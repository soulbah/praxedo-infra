output "api_service_name" {
  value       = google_cloud_run_v2_service.api.name
  description = "Cloud Run service name for the API."
}

output "api_service_uri" {
  value       = google_cloud_run_v2_service.api.uri
  description = "HTTPS URI of the API service (load balancer fronts this later)."
}

output "scanner_service_name" {
  value       = google_cloud_run_v2_service.scanner.name
  description = "Cloud Run service name for the scanner."
}

output "scanner_service_uri" {
  value       = google_cloud_run_v2_service.scanner.uri
  description = "HTTPS URI of the scanner service. Used as the Pub/Sub push endpoint."
}
