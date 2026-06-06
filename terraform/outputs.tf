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
