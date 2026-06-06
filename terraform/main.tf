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

module "secrets" {
  source = "./modules/secrets"

  project_id = var.project_id
  region     = var.region

  db_password_accessor_emails = [
    module.service_accounts.api_sa_email,
    module.service_accounts.scanner_sa_email,
  ]

  # Only the scanner ever calls the AV API. The API SA must not be able to
  # read the vendor key — least-privilege isolation between the two
  # runtimes.
  av_api_key_accessor_emails = [
    module.service_accounts.scanner_sa_email,
  ]

  depends_on = [google_project_service.enabled]
}

module "database" {
  source = "./modules/database"

  project_id                  = var.project_id
  region                      = var.region
  name_prefix                 = local.name_prefix
  vpc_self_link               = module.network.vpc_self_link
  db_password_secret_short_id = module.secrets.db_password_secret_short_id
  tier                        = var.db_tier
  availability_type           = var.db_availability_type
  disk_size_gb                = var.db_disk_size_gb
  deletion_protection         = var.db_deletion_protection
  db_name                     = var.db_name
  db_user                     = var.db_user
  labels                      = local.common_labels

  # The Cloud SQL instance peers via the servicenetworking connection that
  # lives inside module.network; the module-level depends_on covers it. The
  # secret version must also exist before the SQL user can be created.
  depends_on = [
    module.network,
    module.secrets,
    google_project_service.enabled,
  ]
}

module "compute" {
  source = "./modules/compute"

  project_id       = var.project_id
  region           = var.region
  name_prefix      = local.name_prefix
  api_sa_email     = module.service_accounts.api_sa_email
  scanner_sa_email = module.service_accounts.scanner_sa_email
  vpc_connector_id = module.network.vpc_connector_id

  api_image     = var.api_image
  scanner_image = var.scanner_image

  api_max_instances       = var.api_max_instances
  scanner_max_instances   = var.scanner_max_instances
  scanner_timeout_seconds = var.scanner_timeout_seconds

  db_host                     = module.database.private_ip
  db_name                     = module.database.db_name
  db_user                     = module.database.db_user
  db_password_secret_short_id = module.secrets.db_password_secret_short_id
  av_api_key_secret_short_id  = module.secrets.av_api_key_secret_short_id

  quarantine_bucket_name = module.storage.quarantine_bucket_name
  clean_bucket_name      = module.storage.clean_bucket_name

  depends_on = [google_project_service.enabled]
}

module "eventing" {
  source = "./modules/eventing"

  project_id             = var.project_id
  region                 = var.region
  quarantine_bucket_name = module.storage.quarantine_bucket_name
  scanner_service_name   = module.compute.scanner_service_name
  scanner_service_uri    = module.compute.scanner_service_uri

  depends_on = [google_project_service.enabled]
}

module "observability" {
  source = "./modules/observability"

  project_id                      = var.project_id
  alert_email                     = var.alert_email
  api_service_name                = module.compute.api_service_name
  scan_requests_subscription_name = module.eventing.scan_requests_subscription_name
  scan_dlq_subscription_name      = module.eventing.scan_dlq_subscription_name

  depends_on = [google_project_service.enabled]
}

module "edge" {
  source = "./modules/edge"

  project_id       = var.project_id
  region           = var.region
  name_prefix      = local.name_prefix
  api_service_name = module.compute.api_service_name
  domains          = var.domains
  api_path_prefix  = var.api_path_prefix

  depends_on = [google_project_service.enabled]
}

module "cicd" {
  source = "./modules/cicd"

  project_id                      = var.project_id
  region                          = var.region
  github_owner                    = var.github_owner
  github_repo                     = var.github_repo
  artifact_registry_repository_id = module.artifact_registry.repository_id
  api_sa_name                     = module.service_accounts.api_sa_name
  scanner_sa_name                 = module.service_accounts.scanner_sa_name
  frontend_bucket_name            = module.edge.frontend_bucket_name

  depends_on = [google_project_service.enabled]
}
