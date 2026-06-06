# ----------------------------------------------------------------------------
# Workload Identity Federation pool + GitHub OIDC provider.
#
# The provider's attribute_condition is the second line of defence: even if
# an IAM binding ever accidentally widens, no GitHub workflow outside the
# named owner/repo can mint a token against this pool.
# ----------------------------------------------------------------------------
resource "google_iam_workload_identity_pool" "github" {
  project                   = var.project_id
  workload_identity_pool_id = var.wif_pool_id
  display_name              = "GitHub Actions"
  description               = "Federation pool for the Praxedo application repo CI/CD."
}

resource "google_iam_workload_identity_pool_provider" "github" {
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = var.wif_provider_id
  display_name                       = "GitHub OIDC"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
    "attribute.actor"      = "assertion.actor"
  }

  # Hard-cap federation to the named repo. Without this, any GitHub repo
  # could in principle exchange a token against this pool.
  attribute_condition = "assertion.repository == \"${var.github_owner}/${var.github_repo}\""
}

# ----------------------------------------------------------------------------
# Deploy SA — impersonated by GitHub Actions via WIF. Owns just enough to
# push images and roll Cloud Run revisions; explicitly cannot edit IAM,
# read secrets, or touch the buckets that hold user files.
# ----------------------------------------------------------------------------
resource "google_service_account" "app_deploy" {
  project      = var.project_id
  account_id   = "praxedo-app-deploy"
  display_name = "Praxedo — application pipeline deploy SA"
  description  = "Impersonated by the application repo's GitHub Actions via WIF. No stored key."
}

# Federation binding: principal = any workload from the named GitHub repo.
resource "google_service_account_iam_member" "deploy_wif" {
  service_account_id = google_service_account.app_deploy.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_owner}/${var.github_repo}"
}

# Push images to the Docker repo — scoped to the repo, not project-wide.
resource "google_artifact_registry_repository_iam_member" "deploy_writer" {
  project    = var.project_id
  location   = var.region
  repository = var.artifact_registry_repository_id
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${google_service_account.app_deploy.email}"
}

# Update Cloud Run revisions. roles/run.developer is the narrow role for
# deploys; does NOT grant invoker, IAM admin, or service create/destroy.
resource "google_project_iam_member" "deploy_run_developer" {
  project = var.project_id
  role    = "roles/run.developer"
  member  = "serviceAccount:${google_service_account.app_deploy.email}"
}

# To set a Cloud Run service's runAs identity, the deployer must be able to
# impersonate that identity. Scoped to the two specific runtime SAs.
resource "google_service_account_iam_member" "deploy_act_as_api" {
  service_account_id = var.api_sa_name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.app_deploy.email}"
}

resource "google_service_account_iam_member" "deploy_act_as_scanner" {
  service_account_id = var.scanner_sa_name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.app_deploy.email}"
}

# Upload the SPA build to the frontend bucket.
resource "google_storage_bucket_iam_member" "deploy_frontend_writer" {
  bucket = var.frontend_bucket_name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.app_deploy.email}"
}
