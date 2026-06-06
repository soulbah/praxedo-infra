output "api_sa_email" {
  value       = google_service_account.api.email
  description = "Email of the API runtime service account."
}

output "api_sa_name" {
  value       = google_service_account.api.name
  description = "Fully qualified resource name of the API runtime service account."
}

output "api_sa_member" {
  value       = "serviceAccount:${google_service_account.api.email}"
  description = "IAM member string for the API runtime SA."
}

output "scanner_sa_email" {
  value       = google_service_account.scanner.email
  description = "Email of the scanner runtime service account."
}

output "scanner_sa_name" {
  value       = google_service_account.scanner.name
  description = "Fully qualified resource name of the scanner runtime service account."
}

output "scanner_sa_member" {
  value       = "serviceAccount:${google_service_account.scanner.email}"
  description = "IAM member string for the scanner runtime SA."
}
