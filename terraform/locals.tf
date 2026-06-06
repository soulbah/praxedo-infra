locals {
  # The active Terraform workspace is the single source of truth for the
  # environment slug. tfvars files are env-specific but env identity itself
  # lives in the workspace name so a forgotten `-var-file` can never silently
  # apply prod values to the dev workspace.
  env = terraform.workspace

  common_labels = merge(
    {
      env        = local.env
      owner      = var.owner
      managed_by = "terraform"
    },
    var.extra_labels,
  )

  # Project-level APIs required by the architecture (docs/architecture.md).
  # Enabled centrally so individual modules can assume their backing service
  # exists. Kept as a single set — adding a service later means appending one
  # line, not threading another resource through modules.
  enabled_apis = toset([
    # Foundation
    "cloudresourcemanager.googleapis.com",
    "serviceusage.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com", # signBlob for signed URLs, WIF token exchange
    "sts.googleapis.com",            # Workload Identity Federation
    # Networking
    "compute.googleapis.com",
    "vpcaccess.googleapis.com",         # Serverless VPC Access connector
    "servicenetworking.googleapis.com", # Private services access for Cloud SQL
    "dns.googleapis.com",
    "certificatemanager.googleapis.com",
    # Compute & registry
    "run.googleapis.com",
    "artifactregistry.googleapis.com",
    # Data
    "sqladmin.googleapis.com",
    "secretmanager.googleapis.com",
    "storage.googleapis.com",
    # Eventing
    "pubsub.googleapis.com",
    "eventarc.googleapis.com",
    # Observability
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "cloudtrace.googleapis.com",
    "clouderrorreporting.googleapis.com",
  ])
}

# Guardrail: the `default` workspace must never be used to apply real
# infrastructure. Each environment is one workspace, mapped 1:1 to a GCP
# project. Fails plan/apply early with a clear message if violated.
check "workspace_is_valid_env" {
  assert {
    condition     = contains(["dev", "prod"], terraform.workspace)
    error_message = "Active workspace '${terraform.workspace}' is not a valid environment. Run: terraform workspace select dev   (or prod)."
  }
}
