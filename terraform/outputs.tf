output "project_id" {
  value       = var.project_id
  description = "GCP project ID the stack is bound to."
}

output "region" {
  value       = var.region
  description = "Primary GCP region for the stack."
}

output "zone" {
  value       = var.zone
  description = "Primary zone for the stack."
}

output "env" {
  value       = local.env
  description = "Environment slug derived from the active Terraform workspace."
}

output "common_labels" {
  value       = local.common_labels
  description = "Label set applied to every labelable resource by default."
}

output "enabled_apis" {
  value       = sort(tolist(local.enabled_apis))
  description = "Project-level APIs enabled by this stack."
}

# ----------------------------------------------------------------------------
# Network
# ----------------------------------------------------------------------------

output "vpc_self_link" {
  value       = module.network.vpc_self_link
  description = "Self-link of the VPC."
}

output "subnet_self_link" {
  value       = module.network.subnet_self_link
  description = "Self-link of the primary subnet."
}

output "vpc_connector_id" {
  value       = module.network.vpc_connector_id
  description = "Serverless VPC Access connector ID, consumed by Cloud Run services."
}

output "nat_egress_ip" {
  value       = module.network.nat_egress_ip
  description = "Stable egress IP. Share with the AV vendor for whitelisting."
}

output "private_services_range_name" {
  value       = module.network.private_services_range_name
  description = "Reserved range used by Cloud SQL via private services."
}

# ----------------------------------------------------------------------------
# Service accounts
# ----------------------------------------------------------------------------

output "api_sa_email" {
  value       = module.service_accounts.api_sa_email
  description = "Email of the API runtime SA."
}

output "scanner_sa_email" {
  value       = module.service_accounts.scanner_sa_email
  description = "Email of the scanner runtime SA."
}

# ----------------------------------------------------------------------------
# Artifact Registry
# ----------------------------------------------------------------------------

output "artifact_registry_repository_url" {
  value       = module.artifact_registry.repository_url
  description = "Docker pull/push URL for the registry."
}

# ----------------------------------------------------------------------------
# Storage
# ----------------------------------------------------------------------------

output "quarantine_bucket_name" {
  value       = module.storage.quarantine_bucket_name
  description = "Quarantine bucket name."
}

output "clean_bucket_name" {
  value       = module.storage.clean_bucket_name
  description = "Clean bucket name."
}

# ----------------------------------------------------------------------------
# Secrets
# ----------------------------------------------------------------------------

output "db_password_secret_id" {
  value       = module.secrets.db_password_secret_id
  description = "Resource ID of the DB password secret."
}

output "av_api_key_secret_id" {
  value       = module.secrets.av_api_key_secret_id
  description = "Resource ID of the AV API key secret. Populate the value out of band with `gcloud secrets versions add`."
}

# ----------------------------------------------------------------------------
# Database
# ----------------------------------------------------------------------------

output "db_instance_name" {
  value       = module.database.instance_name
  description = "Cloud SQL instance name."
}

output "db_instance_connection_name" {
  value       = module.database.instance_connection_name
  description = "Cloud SQL connection name (project:region:instance)."
}

output "db_private_ip" {
  value       = module.database.private_ip
  description = "Private IP of the Cloud SQL instance (consumed by Cloud Run env vars)."
}

# ----------------------------------------------------------------------------
# Compute
# ----------------------------------------------------------------------------

output "api_service_name" {
  value       = module.compute.api_service_name
  description = "Cloud Run service name for the API."
}

output "api_service_uri" {
  value       = module.compute.api_service_uri
  description = "Cloud Run URI for the API service."
}

output "scanner_service_name" {
  value       = module.compute.scanner_service_name
  description = "Cloud Run service name for the scanner."
}

output "scanner_service_uri" {
  value       = module.compute.scanner_service_uri
  description = "Cloud Run URI for the scanner service (Pub/Sub push target)."
}

# ----------------------------------------------------------------------------
# Eventing
# ----------------------------------------------------------------------------

output "scan_requests_topic_name" {
  value       = module.eventing.scan_requests_topic_name
  description = "Main Pub/Sub topic for scan requests."
}

output "scan_dlq_topic_name" {
  value       = module.eventing.scan_dlq_topic_name
  description = "Dead-letter topic for failed scans."
}

output "scan_requests_subscription_name" {
  value       = module.eventing.scan_requests_subscription_name
  description = "Push subscription targeting the scanner."
}

output "scan_dlq_subscription_name" {
  value       = module.eventing.scan_dlq_subscription_name
  description = "Pull subscription on the DLQ for operator triage."
}
