output "workload_identity_provider" {
  value       = "projects/${google_iam_workload_identity_pool.infra.project}/locations/global/workloadIdentityPools/${google_iam_workload_identity_pool.infra.workload_identity_pool_id}/providers/${google_iam_workload_identity_pool_provider.github.workload_identity_pool_provider_id}"
  description = "Fully-qualified WIF provider name. Set as a per-env GitHub Actions variable (TF_WIF_PROVIDER_DEV / TF_WIF_PROVIDER_PROD)."
}

output "plan_sa_email" {
  value       = google_service_account.plan.email
  description = "Email of the plan SA. Per-env GitHub variable TF_PLAN_SA_DEV / TF_PLAN_SA_PROD."
}

output "apply_sa_email" {
  value       = google_service_account.apply.email
  description = "Email of the apply SA. Per-env GitHub variable TF_APPLY_SA_DEV / TF_APPLY_SA_PROD."
}
