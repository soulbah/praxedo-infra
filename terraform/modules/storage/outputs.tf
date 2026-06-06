output "quarantine_bucket_name" {
  value       = google_storage_bucket.quarantine.name
  description = "Name of the quarantine bucket."
}

output "quarantine_bucket_url" {
  value       = google_storage_bucket.quarantine.url
  description = "gs:// URL of the quarantine bucket."
}

output "clean_bucket_name" {
  value       = google_storage_bucket.clean.name
  description = "Name of the clean bucket."
}

output "clean_bucket_url" {
  value       = google_storage_bucket.clean.url
  description = "gs:// URL of the clean bucket."
}
