output "repository_id" {
  value       = google_artifact_registry_repository.docker.repository_id
  description = "Repository ID."
}

output "repository_name" {
  value       = google_artifact_registry_repository.docker.name
  description = "Fully qualified resource name of the repository."
}

output "repository_url" {
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.docker.repository_id}"
  description = "Docker pull/push URL for the repository."
}
