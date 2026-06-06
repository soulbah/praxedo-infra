locals {
  # Single source for resource naming. Project IDs are already env-scoped
  # (praxedo-file-dev / praxedo-file-prod), so reusing them here keeps every
  # downstream resource name distinct across environments without an extra
  # suffix.
  name_prefix = var.project_id
}

module "network" {
  source = "./modules/network"

  project_id                     = var.project_id
  region                         = var.region
  env                            = local.env
  name_prefix                    = local.name_prefix
  subnet_cidr                    = var.subnet_cidr
  connector_cidr                 = var.connector_cidr
  private_services_prefix_length = var.private_services_prefix_length

  # Networking APIs (compute, vpcaccess, servicenetworking) must be enabled
  # before the underlying resources can be created.
  depends_on = [google_project_service.enabled]
}

module "service_accounts" {
  source = "./modules/service-accounts"

  project_id = var.project_id

  depends_on = [google_project_service.enabled]
}

module "artifact_registry" {
  source = "./modules/artifact-registry"

  project_id = var.project_id
  region     = var.region
  consumer_sa_emails = [
    module.service_accounts.api_sa_email,
    module.service_accounts.scanner_sa_email,
  ]
  tagged_keep_count          = var.registry_tagged_keep_count
  untagged_retention_seconds = var.registry_untagged_retention_seconds

  depends_on = [google_project_service.enabled]
}

module "storage" {
  source = "./modules/storage"

  project_id                = var.project_id
  location                  = var.region
  name_prefix               = local.name_prefix
  api_sa_email              = module.service_accounts.api_sa_email
  scanner_sa_email          = module.service_accounts.scanner_sa_email
  quarantine_ttl_days       = var.quarantine_ttl_days
  clean_noncurrent_ttl_days = var.clean_noncurrent_ttl_days

  depends_on = [google_project_service.enabled]
}
