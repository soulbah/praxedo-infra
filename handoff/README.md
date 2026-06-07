# Application repo handoff — Praxedo file service

What infrastructure provisions for the developer team, and the reference GitHub Actions workflow that consumes it.

The infra repo (this one) is responsible for the *foundations* the application pipeline needs: a federated identity to GCP, a deploy service account scoped to the minimum, an Artifact Registry repo, two Cloud Run services, a frontend bucket. It does **not** deploy the application. The application repo owns its own pipeline; `deploy.yml` below is a ready-to-use starting point the team can drop into their repo and adjust.

---

## 1. What the application pipeline gets

Provisioned by Terraform on the infra side, exposed as outputs:

| Output | Meaning | Used as |
|---|---|---|
| `workload_identity_provider` | Fully-qualified WIF provider resource name | `workload_identity_provider:` input to `google-github-actions/auth` |
| `app_deploy_sa_email` | Email of the deploy SA the GitHub workflow impersonates | `service_account:` input to `google-github-actions/auth` |
| `artifact_registry_repository_url` | `region-docker.pkg.dev/project/repo` URL | Docker image tag prefix for build/push |
| `api_service_name` | Cloud Run API service name | `service:` input to `deploy-cloudrun` |
| `scanner_service_name` | Cloud Run scanner service name | Same |
| `frontend_bucket_name` | Bucket name behind the CDN | `gsutil rsync` / `gcloud storage rsync` target |

What the deploy SA can do (and only this — `roles/owner|editor` is explicitly forbidden by the infra skill):

- Push images to the `praxedo-docker` Artifact Registry repo.
- Roll new revisions on the two existing Cloud Run services (`roles/run.developer`). It **cannot** create or delete services, edit IAM, change env vars, mount different secrets, or alter ingress settings — those are Terraform-owned.
- Impersonate the two runtime SAs (`api`, `scanner`) only as required to set the `runAs` identity on a Cloud Run revision.
- Upload SPA assets to the frontend bucket.

Anything outside that surface (DB schema migrations, secret rotation, infra changes) goes through the infra repo or out-of-band runbook procedures.

---

## 2. One-time GitHub configuration in the app repo

The reference workflow expects a small set of GitHub *variables* (not secrets — none of these are sensitive). All eight identifiers come from `terraform output` on the infra repo.

In the application repo, go to **Settings → Secrets and variables → Actions → Variables** and create:

| Variable | Source | Example |
|---|---|---|
| `GCP_PROJECT_ID_DEV` | literal | `praxedo-file-dev` |
| `GCP_PROJECT_ID_PROD` | literal | `praxedo-file-prod` |
| `GCP_REGION` | literal | `europe-west1` |
| `WIF_PROVIDER_DEV` | `terraform output workload_identity_provider` (dev workspace) | `projects/123.../providers/github` |
| `WIF_PROVIDER_PROD` | same, prod workspace | |
| `DEPLOY_SA_DEV` | `terraform output app_deploy_sa_email` (dev) | `praxedo-app-deploy@praxedo-file-dev.iam.gserviceaccount.com` |
| `DEPLOY_SA_PROD` | same, prod | |
| `ARTIFACT_REGISTRY_DEV` | `terraform output artifact_registry_repository_url` (dev) | `europe-west1-docker.pkg.dev/praxedo-file-dev/praxedo-docker` |
| `ARTIFACT_REGISTRY_PROD` | same, prod | |
| `API_SERVICE_DEV` | `terraform output api_service_name` (dev) | `praxedo-file-dev-api` |
| `API_SERVICE_PROD` | same, prod | |
| `SCANNER_SERVICE_DEV` | `terraform output scanner_service_name` (dev) | `praxedo-file-dev-scanner` |
| `SCANNER_SERVICE_PROD` | same, prod | |
| `FRONTEND_BUCKET_DEV` | `terraform output frontend_bucket_name` (dev) | `praxedo-file-dev-frontend` |
| `FRONTEND_BUCKET_PROD` | same, prod | |

GitHub **Environments** (Settings → Environments): create `dev` and `prod`.
- `dev`: no required reviewers, deployment branches restricted to `main`.
- `prod`: **≥1 required reviewer**, deployment branches restricted to `main`.

The Environment is what gates the prod rollout — the deploy SA itself does not enforce a branch lock the way the infra apply SA does, so the GitHub-side gate is the control plane.

---

## 3. Reference workflow

The file is at `.github/workflows/deploy.yml` in this directory. Copy it into the application repo at the same path. The header of the workflow lists every variable it expects and the repo layout it assumes (`backend/api/`, `backend/scanner/`, `frontend/`). Adjust the four `working-directory` / `context` values if your repo layout differs — nothing else inside the workflow should need editing.

Key design choices in the reference workflow, mirroring the infra-side pipeline conventions:

- **WIF only**, no JSON keys. Each job that hits GCP declares `permissions: { id-token: write }` and nothing else broader than needed.
- **Per-env config resolution in one `config` job**. Downstream jobs read from `needs.config.outputs.*` so there is no `${{ env == 'prod' && ... || ... }}` ladder repeated three times.
- **Image tag = first 12 chars of the commit SHA** (`${GITHUB_SHA::12}`). Stable, traceable, no monotonic counter to maintain. A floating `latest` tag is also pushed for ergonomics but the deployed revision always references the SHA tag.
- **Three parallel jobs** (`api`, `scanner`, `frontend`) — none of them blocks the others; a frontend-only change only re-uploads the SPA.
- **Cloud Run config is not touched on deploy.** No `--update-env-vars`, no `--set-secrets`, no `--ingress`. The deploy SA does not hold permissions to change those, and the Terraform `lifecycle.ignore_changes` block on the Cloud Run resource means new images do not cause TF drift either.
- **`concurrency` group keyed per env** so two pushes to main do not race their own apply on the same environment, while dev and prod can still proceed independently.

---

## 4. First deploy checklist (developer side)

1. Push the workflow file to the app repo.
2. Populate the GitHub variables above.
3. Create the `dev` and `prod` GitHub Environments with the reviewer + branch rules from §2.
4. Push to `main` → `dev` deploy runs automatically.
5. To deploy to prod, either push to `main` (`prod` job waits on reviewer approval) or use `workflow_dispatch` and pick `prod`.

If a step fails, the workflow run log is the first stop. Common patterns:

| Symptom | Root cause | Fix |
|---|---|---|
| `Permission denied` on `docker push` | Wrong `ARTIFACT_REGISTRY_*` variable, or AR repo not created yet | re-run `terraform output artifact_registry_repository_url` and update the variable |
| `Could not get the GCS object` or similar 403 on the deploy step | `DEPLOY_SA_*` variable wrong, or AR pull-through not yet propagated | wait 30s and retry; verify the variable matches the infra output |
| `iam.serviceAccounts.actAs` error on `deploy-cloudrun` | Mismatch between the runtime SA Cloud Run expects and what infra granted impersonation on | check `terraform output api_sa_email` matches the SA actually attached to the service |
| `Unable to fetch the OIDC token` | `id-token: write` missing on the job, or fork PR | check job permissions; fork PRs cannot federate |

---

## 5. What stays in the infra repo (not the app repo)

To avoid the two pipelines bleeding into each other:

- Cloud Run **service definitions** (ingress, VPC connector, env vars, secret mounts, runAs identity, max instances) — infra repo only.
- IAM bindings, Secret Manager, Cloud SQL, Pub/Sub, buckets, LB, WAF — infra repo only.
- Container **images and revisions** — app repo only.
- Frontend bucket **contents** — app repo only.
- DB **schema migrations** — app repo, but the migration job runs against the private-IP DB via the same VPC connector the API uses; the app pipeline does not provision migration infrastructure.

If a change needs both repos (e.g. a new env var that maps to a new Secret Manager secret), open the infra PR first, merge it, then the app PR. The runbook §5 documents this flow on the infra side.
