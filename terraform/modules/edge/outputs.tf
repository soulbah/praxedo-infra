output "lb_ip_address" {
  value       = google_compute_global_address.lb.address
  description = "Global IP. Point each domain's DNS A record at this address."
}

output "frontend_bucket_name" {
  value       = google_storage_bucket.frontend.name
  description = "Frontend assets bucket name. App pipeline uploads the built SPA here."
}

output "frontend_bucket_url" {
  value       = google_storage_bucket.frontend.url
  description = "gs:// URL of the frontend bucket."
}

output "managed_ssl_certificate_name" {
  value       = google_compute_managed_ssl_certificate.main.name
  description = "Name of the managed SSL certificate. Provisioning state visible in the GCP console."
}

output "https_forwarding_rule" {
  value       = google_compute_global_forwarding_rule.https.name
  description = "Name of the HTTPS forwarding rule."
}
