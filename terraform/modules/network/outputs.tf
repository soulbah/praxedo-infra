output "vpc_id" {
  value       = google_compute_network.vpc.id
  description = "Resource ID of the VPC."
}

output "vpc_self_link" {
  value       = google_compute_network.vpc.self_link
  description = "Self-link of the VPC, consumed by Cloud Run / Cloud SQL modules."
}

output "vpc_name" {
  value       = google_compute_network.vpc.name
  description = "Name of the VPC."
}

output "subnet_id" {
  value       = google_compute_subnetwork.primary.id
  description = "Resource ID of the primary subnet."
}

output "subnet_self_link" {
  value       = google_compute_subnetwork.primary.self_link
  description = "Self-link of the primary subnet."
}

output "vpc_connector_id" {
  value       = google_vpc_access_connector.main.id
  description = "ID of the Serverless VPC Access connector, referenced by Cloud Run services."
}

output "vpc_connector_name" {
  value       = google_vpc_access_connector.main.name
  description = "Name of the Serverless VPC Access connector."
}

output "nat_egress_ip" {
  value       = google_compute_address.nat.address
  description = "Stable egress IP for outbound traffic from Cloud Run via the connector. Share with the AV vendor for whitelisting."
}

output "private_services_range_name" {
  value       = google_compute_global_address.private_services.name
  description = "Name of the reserved range used by Cloud SQL via private services."
}

output "private_services_connection_id" {
  value       = google_service_networking_connection.private_services.id
  description = "ID of the servicenetworking connection. Cloud SQL must depend on it."
}
