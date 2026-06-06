output "workload_identity_pool_id" {
  value       = google_iam_workload_identity_pool.github.workload_identity_pool_id
  description = "WIF pool short ID."
}

output "workload_identity_provider" {
  value       = "projects/${google_iam_workload_identity_pool.github.project}/locations/global/workloadIdentityPools/${google_iam_workload_identity_pool.github.workload_identity_pool_id}/providers/${google_iam_workload_identity_pool_provider.github.workload_identity_pool_provider_id}"
  description = "Fully-qualified provider name. Use as `workload_identity_provider:` input to google-github-actions/auth in the app repo."
}

output "deploy_sa_email" {
  value       = google_service_account.app_deploy.email
  description = "Deploy SA the app pipeline impersonates. Use as `service_account:` input to google-github-actions/auth."
}
