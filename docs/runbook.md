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

---

## 9. Known scoped exceptions

| Skill rule | Where | Reason |
|---|---|---|
| Buckets: no `allUsers` IAM | `modules/edge` frontend-assets bucket only | LB+CDN serving a public SPA requires anonymous origin reads. quarantine + clean buckets keep PAP=enforced and zero public IAM, so the §2.3 invariant is unaffected. |
| Buckets: PAP=enforced | `modules/edge` frontend bucket only (PAP=`inherited`) | Same reason as above — PAP=enforced would block the allUsers binding required for SPA serving. |
| `roles/storage.objectAdmin` is broader than read+delete | `modules/storage` scanner SA on quarantine | Custom role for read+delete only adds cost > benefit at this scope (single SA on single bucket). |
