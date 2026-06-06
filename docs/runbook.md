# Operational runbook — Praxedo file service infra

Day-to-day commands and the recovery paths for the failure modes the
architecture explicitly plans for. Companion to `docs/architecture.md`
(the design) and `docs/progress.md` (the build state).

---

## 1. Daily flow

Every action below is per-environment. The workspace is the source of
truth for which environment is touched — selecting the wrong workspace is
caught by a `check` block in `terraform/locals.tf`.

```sh
# 1. Init with the env-specific backend (only after the bootstrap step).
make init ENV=dev

# 2. Plan / apply.
make plan  ENV=dev
make apply ENV=dev
```

Substitute `prod` everywhere when working on prod. `default` workspace is
rejected at plan time.

---

## 2. One-time bootstrap

The state bucket is the chicken/egg dependency. Provision it once per
project, then `terraform init`.

```sh
PROJECT=praxedo-file-dev
gcloud storage buckets create gs://${PROJECT}-tfstate \
  --project=${PROJECT} \
  --location=europe-west1 \
  --uniform-bucket-level-access \
  --public-access-prevention
gcloud storage buckets update gs://${PROJECT}-tfstate --versioning
```

Then copy and adjust the example configs:

```sh
cp terraform/envs/dev.example.tfvars      terraform/envs/dev.tfvars
cp terraform/envs/backend-dev.example.hcl terraform/envs/backend-dev.hcl
```

`*.tfvars` and `backend-*.hcl` (non-example) are gitignored.

---

## 3. Seeding the AV vendor API key

The secret container `praxedo-av-api-key` is created by Terraform, but the
value is **not** Terraform-managed (vendor-issued, rotated out of band).

```sh
gcloud secrets versions add praxedo-av-api-key \
  --project=praxedo-file-dev \
  --data-file=/path/to/vendor-key.txt
```

Rotate by adding a new version. The scanner Cloud Run reads `latest`, so
a redeploy or a SIGHUP picks it up.

---

## 4. Domain + managed SSL provisioning

Once `terraform apply` finishes, the LB IP is in the output:

```sh
terraform output lb_ip_address
```

Point each FQDN in `var.domains` at that IP (A record). Google managed
certs only leave `PROVISIONING` after DNS resolves and they can
successfully serve an ACME challenge — typically 15-60 min.

Check progress:

```sh
gcloud compute ssl-certificates describe \
  $(terraform output -raw managed_ssl_certificate_name) \
  --global \
  --format='value(managed.status,managed.domainStatus)'
```

---

## 5. Application pipeline handoff

The infra repo provisions but does **not** deploy. The app repo's GitHub
Actions authenticates via WIF. Two outputs feed the auth step:

```sh
terraform output workload_identity_provider
terraform output app_deploy_sa_email
```

App repo workflow example:

```yaml
- uses: google-github-actions/auth@v2
  with:
    workload_identity_provider: ${{ steps.tf.outputs.workload_identity_provider }}
    service_account:            ${{ steps.tf.outputs.app_deploy_sa_email }}
```

No JSON keys are exported, ever — only OIDC token exchange.

---

## 6. Recovery — the three failure modes the architecture plans for

### 6.1 AV vendor is slow

Symptom: `Scan pipeline lag above threshold` alert fires. Pub/Sub
subscription oldest-unacked age climbs past 15 min.

What's happening: the scan is decoupled from the upload. Queue grows; no
user-facing impact because the API returns 202 immediately after upload.

Action: usually none — the system self-drains when the vendor recovers.
If lag exceeds 1h, check `gcloud monitoring metrics list` for the
scanner request count vs. the topic publish rate. If the scanner is
saturated, raise `scanner_max_instances` in tfvars.

### 6.2 AV vendor is down

Symptom: scans hit the retry ceiling and land in `scan-dlq`. `Scan DLQ is
not empty` alert fires.

What's happening: Pub/Sub retried each message up to `max_delivery_attempts`
(6 by default) with exponential backoff (10s → 600s), then dead-lettered.

Action:
1. Confirm vendor outage. If yes, no action needed yet — quarantine
   objects remain in `quarantine`, DB rows remain in `SCAN_FAILED`.
2. Once vendor recovers, re-drive DLQ:

```sh
# Pull a message ID from scan-dlq-sub, republish to scan-requests.
gcloud pubsub subscriptions pull scan-dlq-sub \
  --auto-ack \
  --limit=100 \
  --format=json |
  jq -r '.[].message.data' |
  while read -r data; do
    gcloud pubsub topics publish scan-requests --message="$(echo $data | base64 -d)"
  done
```

A small Cloud Run Job to automate this is on the backlog (progress §10
next iteration). For now, the manual command above is the documented
path.

### 6.3 An unscanned file must never be downloadable (§2.3 invariant)

This is enforced at the IAM layer, not at app logic. The invariant holds
even if the API process is buggy:

- The API SA has no `storage.objects.get` on the `quarantine` bucket.
  Period. It physically cannot mint a signed download URL for an
  unscanned object.
- The `clean` bucket is only writable by the scanner SA. The promotion
  copy(quarantine → clean) is the only path.

Verify after each apply:

```sh
PROJECT=praxedo-file-dev
gcloud storage buckets get-iam-policy gs://${PROJECT}-quarantine \
  --format=json | jq '.bindings[] | select(.role=="roles/storage.objectViewer")'
# Expected: nothing referencing the API SA. Only the scanner SA should
# appear under objectAdmin.
```

If a future change ever tries to add `objectViewer` for the API SA on
`quarantine`, that diff is a hard reject in code review.

---

## 7. Common operator commands

```sh
# Re-drive a specific object that's stuck in SCAN_FAILED.
gcloud pubsub topics publish scan-requests \
  --message="$(jq -nc --arg b "$BUCKET" --arg o "$OBJECT" '{kind:"storage#object",bucket:$b,name:$o}')"

# Tail scanner logs.
gcloud logging tail \
  'resource.type="cloud_run_revision" AND resource.labels.service_name="praxedo-file-dev-scanner"'

# Inspect Cloud SQL through the private VPC (requires bastion or SSH+iap).
gcloud sql instances describe praxedo-file-dev-db --format='value(ipAddresses)'
```

---

## 8. Pre-commit + CI

```sh
pip install pre-commit
pre-commit install
pre-commit run --all-files
```

Hooks: `terraform_fmt`, `terraform_validate`, `terraform_tflint`,
`terraform_trivy` (HIGH/CRITICAL only). Failures block the commit.

### 8.1 Infra CI pipeline (.github/workflows/)

Two workflows manage this repo's lifecycle. **Distinct from the app
pipeline** (CLAUDE.md): they manage infrastructure only, never deploy
application code.

| Workflow | Trigger | Pattern |
|---|---|---|
| `terraform-checks.yml` | `pull_request`, `workflow_dispatch` | fmt + validate + tflint + Trivy (HIGH/CRITICAL) → plan dev/prod in parallel → sticky PR comment + Job Summary with full diff + uploaded `tfplan` artifact |
| `terraform-deploy.yml` | `push` to main, `workflow_dispatch` | per env: plan job → **GH Environment gate (manual approval)** → apply job that consumes the *frozen* `tfplan` artifact. Prod waits on dev apply success (strict promotion) |

Shared boilerplate lives in `.github/actions/tf-setup` (composite action):
install Terraform from `.terraform-version`, federate to GCP via WIF
(plan SA or apply SA), `terraform init` with the env-specific state
bucket, select the workspace.

Fork PRs are excluded from any job that requires an OIDC token
(`if: head.repo == repo`).

#### Plan-then-approve-then-apply

The deploy workflow uploads the binary `tfplan` between the plan and
apply jobs. Apply consumes `terraform apply tfplan` — no `-var-file`,
no `-auto-approve` flag — so the reviewer approves the exact diff that
runs. State cannot drift between approval and execution.

The reviewer sees the full plan diff in the **Job Summary** of the
plan job before approving the apply job. The approval gate is the GH
Environment configured on the apply job (`environment: dev` /
`environment: prod`).

Configure on the GitHub side (Settings → Environments):
- `dev`: optional reviewers, no wait timer, deployment branches = `main`.
- `prod`: **required reviewers (≥1)**, optional wait timer, deployment
  branches = `main`.

#### `detailed-exitcode` short-circuit

`terraform plan -detailed-exitcode` returns 0 (no changes), 1 (error),
2 (changes). The apply job has `if: needs.plan.outputs.exitcode == '2'`
so a no-op plan skips apply entirely — saves CI minutes and produces
a cleaner audit trail when there's nothing to do.

#### Permissions per job

Workflow-level permissions = `contents: read`. Each job widens only
what it needs:
- plan jobs: `id-token: write` (WIF token)
- PR plan comment step: `pull-requests: write`
- apply jobs: `id-token: write` only

No job ever gets `write-all` or anything broader than the action
actually performs.

### 8.2 Bootstrap (one-time per project)

The infra CI pipeline is created **by Terraform itself** — chicken/egg.
First apply must run from a human with project owner / equivalent
permissions:

```sh
# Authenticate locally as an account that holds project owner on
# praxedo-file-<env>.
gcloud auth application-default login
gcloud config set project praxedo-file-dev

# Create the state bucket (see §2).
# Then run the very first apply locally.
make init   ENV=dev
make apply  ENV=dev
```

After this first apply, the `infra_workload_identity_provider`,
`infra_plan_sa_email`, `infra_apply_sa_email`, and `state_bucket_name`
outputs identify everything the CI workflows need. Configure these as
**GitHub repository / organization variables** (Settings → Secrets and
variables → Actions → Variables):

| GitHub variable | Source | Used by |
|---|---|---|
| `TF_PROJECT_ID_DEV` | literal `praxedo-file-dev` | all infra workflows |
| `TF_PROJECT_ID_PROD` | literal `praxedo-file-prod` | all infra workflows |
| `TF_WIF_PROVIDER_DEV` | `terraform output infra_workload_identity_provider` (dev workspace) | checks + apply-dev |
| `TF_WIF_PROVIDER_PROD` | same, prod workspace | checks + apply-prod |
| `TF_PLAN_SA_DEV` | `terraform output infra_plan_sa_email` (dev) | checks |
| `TF_PLAN_SA_PROD` | same, prod | checks |
| `TF_APPLY_SA_DEV` | `terraform output infra_apply_sa_email` (dev) | apply-dev |
| `TF_APPLY_SA_PROD` | same, prod | apply-prod |

After variables are set, push to main triggers `apply-dev` and the CI
pipeline takes over. Subsequent local `terraform apply` is reserved for
emergencies; the GitHub-side audit trail beats it.

### 8.3 Prod safeguards

Four independent gates before a prod apply executes — defence-in-depth,
so a single misconfiguration cannot bypass the rest:

1. **Frozen plan**: apply consumes the binary `tfplan` artifact uploaded
   by the prod plan job. The reviewer approves a specific diff, not a
   re-plan that could drift between approval and execution.
2. **GitHub Environment `prod`**: required reviewers configured on the
   environment must approve the apply job. The plan diff is rendered in
   the plan job's Job Summary so the reviewer sees the exact change
   before approving.
3. **Strict promotion**: `apply-prod` declares
   `needs: [plan-prod, apply-dev]`. Prod cannot run until dev apply
   succeeded (or was skipped because dev had no changes).
4. **WIF branch lock**: the apply SA's `workloadIdentityUser` binding
   only accepts OIDC tokens whose `assertion.ref == refs/heads/main`.
   Even if all GitHub-side gates were bypassed, a checkout from a
   non-main ref fails authentication.

### 8.4 What to do when CI breaks

| Symptom | Likely cause | Fix |
|---|---|---|
| `Permission denied` on `terraform init` | State bucket IAM not yet propagated, or the SA was rotated | wait 30s and retry; or re-run after `terraform apply` of `modules/infra-cicd` |
| `Unable to fetch the OIDC token` | `id-token: write` missing on the job, or fork PR | check job permissions, ensure PR is from same repo |
| Plan job posts plan but apply job stays pending | Awaiting GH Environment reviewer approval | reviewer goes to Actions → workflow run → click "Review deployments" |
| Apply fails with `state lock` | Previous apply crashed without releasing the lock | `terraform force-unlock <LOCK_ID>` from a local checkout (record the LOCK_ID from the error; never blindly unlock without confirming the previous run actually died) |

### 8.5 Branch protection (configure once on the GitHub side)

The workflows are designed assuming the `main` branch is protected with:

- **Require a pull request before merging**: on.
- **Required reviews**: 1 (or more for sensitive paths via CODEOWNERS).
- **Require status checks to pass before merging**:
  - `Static checks`
  - `plan (dev)`
  - `plan (prod)`
  - `lint PR title`
- **Require branches to be up to date before merging**: on.
- **Require conversation resolution before merging**: on.
- **Restrict who can push to matching branches**: empty (no direct
  pushes; everything via PR).
- **Allow force pushes**: off.
- **Allow deletions**: off.

`.github/CODEOWNERS` layers per-path review requirements on top of the
base review count (storage / secrets / SAs / CI-CD all require the
security group; architecture docs require the architecture group).

### 8.6 Scheduled drift detection

`.github/workflows/terraform-drift.yml` runs `terraform plan` daily at
04:30 UTC against `main` for each environment, using the read-only plan
SA. On a non-zero diff (exit code 2), it opens — or updates — a
sticky issue `Terraform drift — <env>` with a link to the run. The
issue closes when the next clean run reports no drift; reopen manually
if a regression returns.

### 8.7 Local emergency apply

When CI is down and a change is urgent:

```sh
# Authenticate locally as a human with sufficient roles (project owner or
# the same role list held by the apply SA).
gcloud auth application-default login
gcloud config set project praxedo-file-<env>

make apply ENV=<env>
```

Every emergency apply must be backfilled with a PR + normal CI run to
restore the audit trail.

---

## 9. Known scoped exceptions

| Skill rule | Where | Reason |
|---|---|---|
| Buckets: no `allUsers` IAM | `modules/edge` frontend-assets bucket only | LB+CDN serving a public SPA requires anonymous origin reads. quarantine + clean buckets keep PAP=enforced and zero public IAM, so the §2.3 invariant is unaffected. |
| Buckets: PAP=enforced | `modules/edge` frontend bucket only (PAP=`inherited`) | Same reason as above — PAP=enforced would block the allUsers binding required for SPA serving. |
| `roles/storage.objectAdmin` is broader than read+delete | `modules/storage` scanner SA on quarantine | Custom role for read+delete only adds cost > benefit at this scope (single SA on single bucket). |
