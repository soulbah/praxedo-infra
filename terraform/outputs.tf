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
