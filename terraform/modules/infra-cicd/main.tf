# ============================================================================
# Infra repo CI/CD identities — distinct from the application pipeline.
#
# Two SAs:
#   * infra-plan  — read-only, impersonable from any branch / pull request
#                   (so PR checks can run `terraform plan`).
#   * infra-apply — admin, impersonable ONLY from a push to the named branch
#                   (main), restricted at the WIF binding level.
#
# Both SAs federate via a dedicated WIF pool. Sharing nothing with the
# application pipeline's pool keeps blast radius surgical: a compromise of
# the app repo cannot reach the infra apply SA, and vice-versa.
# ============================================================================

# ----------------------------------------------------------------------------
# Roles
#
# The terraform-gcp skill forbids roles/owner and roles/editor. For the
# apply identity that means an explicit list of admin roles covering every
# Google service this Terraform code touches. Adding a new managed service
# (e.g. Cloud DNS) requires appending its admin role here — that is the
# accepted maintenance cost of avoiding owner/editor.
# ----------------------------------------------------------------------------
locals {
  plan_roles = toset([
    "roles/viewer",
    "roles/iam.securityReviewer",
    "roles/secretmanager.viewer",
  ])

  apply_roles = toset([
    "roles/serviceusage.serviceUsageAdmin",
    "roles/resourcemanager.projectIamAdmin",
    "roles/iam.serviceAccountAdmin",
    "roles/iam.workloadIdentityPoolAdmin",
    "roles/compute.networkAdmin",
    "roles/compute.securityAdmin",
    "roles/compute.loadBalancerAdmin",
    "roles/compute.instanceAdmin.v1",
    "roles/vpcaccess.admin",
    "roles/servicenetworking.networksAdmin",
    "roles/storage.admin",
    "roles/cloudsql.admin",
    "roles/secretmanager.admin",
    "roles/run.admin",
    "roles/pubsub.admin",
    "roles/artifactregistry.admin",
    "roles/monitoring.admin",
    "roles/logging.admin",
    "roles/certificatemanager.editor",
  ])

  repo_principal = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.infra.name}/attribute.repository/${var.github_owner}/${var.github_repo}"

  apply_principal = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.infra.name}/attribute.repository_ref/${var.github_owner}/${var.github_repo}@refs/heads/${var.apply_branch}"
}

# ----------------------------------------------------------------------------
# WIF pool + GitHub OIDC provider.
# ----------------------------------------------------------------------------
resource "google_iam_workload_identity_pool" "infra" {
  project                   = var.project_id
  workload_identity_pool_id = var.wif_pool_id
  display_name              = "GitHub Actions — infra repo"
  description               = "Federation pool for the Praxedo infra repo CI/CD."
}

resource "google_iam_workload_identity_pool_provider" "github" {
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.infra.workload_identity_pool_id
  workload_identity_pool_provider_id = var.wif_provider_id
  display_name                       = "GitHub OIDC"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }

  # Synthesise a `repository@ref` attribute so the apply SA's WIF binding
  # can require both repo identity AND branch in a single principalSet.
  attribute_mapping = {
    "google.subject"           = "assertion.sub"
    "attribute.repository"     = "assertion.repository"
    "attribute.ref"            = "assertion.ref"
    "attribute.repository_ref" = "assertion.repository + \"@\" + assertion.ref"
    "attribute.event_name"     = "assertion.event_name"
    "attribute.actor"          = "assertion.actor"
  }

  # Hard-cap federation to the infra repo. Without this, any GitHub repo
  # could in principle try to exchange a token against this pool.
  attribute_condition = "assertion.repository == \"${var.github_owner}/${var.github_repo}\""
}

# ----------------------------------------------------------------------------
# Plan SA — read-only. Used by PR checks to run `terraform plan`.
# ----------------------------------------------------------------------------
resource "google_service_account" "plan" {
  project      = var.project_id
  account_id   = "infra-plan"
  display_name = "Praxedo infra — terraform plan (read-only)"
  description  = "Impersonated by PR checks via WIF. Read-only roles."
}

resource "google_service_account_iam_member" "plan_wif" {
  service_account_id = google_service_account.plan.name
  role               = "roles/iam.workloadIdentityUser"
  # Any workflow from the repo can impersonate the plan SA. Plan is
  # read-only, so PR branches and reopened PRs both need it.
  member = local.repo_principal
}

resource "google_project_iam_member" "plan_roles" {
  for_each = local.plan_roles

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.plan.email}"
}

# ----------------------------------------------------------------------------
# Apply SA — admin. Only impersonable from a push to var.apply_branch.
# ----------------------------------------------------------------------------
resource "google_service_account" "apply" {
  project      = var.project_id
  account_id   = "infra-apply"
  display_name = "Praxedo infra — terraform apply (admin)"
  description  = "Impersonated by main-branch pushes via WIF. Holds the admin role list."
}

resource "google_service_account_iam_member" "apply_wif" {
  service_account_id = google_service_account.apply.name
  role               = "roles/iam.workloadIdentityUser"
  # WIF-level branch lock: even a workflow that holds the apply secret name
  # cannot mint a token unless its OIDC claim says it ran on var.apply_branch.
  member = local.apply_principal
}

resource "google_project_iam_member" "apply_roles" {
  for_each = local.apply_roles

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.apply.email}"
}

# ----------------------------------------------------------------------------
# State bucket access for both SAs.
#
# Terraform plan acquires a lock object in the GCS backend, so even the
# plan path needs object write — granted at the bucket scope, not project.
# ----------------------------------------------------------------------------
resource "google_storage_bucket_iam_member" "plan_state" {
  bucket = var.state_bucket_name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.plan.email}"
}

resource "google_storage_bucket_iam_member" "apply_state" {
  bucket = var.state_bucket_name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.apply.email}"
}
