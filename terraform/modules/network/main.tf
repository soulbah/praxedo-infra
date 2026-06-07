resource "google_compute_network" "vpc" {
  project = var.project_id
  name    = "${var.name_prefix}-vpc"

  description = "Praxedo file service VPC (${var.env})."

  auto_create_subnetworks         = false
  routing_mode                    = "REGIONAL"
  delete_default_routes_on_create = false
}

resource "google_compute_subnetwork" "primary" {
  project = var.project_id
  name    = "${var.name_prefix}-subnet"
  region  = var.region
  network = google_compute_network.vpc.self_link

  ip_cidr_range = var.subnet_cidr

  # Required so Cloud Run via the connector can reach Google APIs (Secret
  # Manager, Cloud SQL admin) over Google-managed private routing without
  # leaving the VPC.
  private_ip_google_access = true

  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

resource "google_compute_router" "nat" {
  project = var.project_id
  name    = "${var.name_prefix}-nat-router"
  region  = var.region
  network = google_compute_network.vpc.self_link
}

# Static egress IP so the AV vendor can whitelist a single address. Manual
# allocation pins it across NAT recreations. STANDARD tier is sufficient for
# regional NAT egress and cheaper than PREMIUM (no global routing needed).
resource "google_compute_address" "nat" {
  project = var.project_id
  name    = "${var.name_prefix}-nat-ip"
  region  = var.region

  address_type = "EXTERNAL"
  network_tier = "STANDARD"
}

resource "google_compute_router_nat" "nat" {
  project = var.project_id
  name    = "${var.name_prefix}-nat"
  router  = google_compute_router.nat.name
  region  = var.region

  nat_ip_allocate_option             = "MANUAL_ONLY"
  nat_ips                            = [google_compute_address.nat.self_link]
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# Serverless VPC Access connector — bridge from Cloud Run (serverless world)
# to the VPC, used to reach Cloud SQL on its private IP and to egress through
# Cloud NAT to the AV API with a stable source IP.
resource "google_vpc_access_connector" "main" {
  project = var.project_id
  name    = "${var.name_prefix}-conn"
  region  = var.region

  ip_cidr_range = var.connector_cidr
  network       = google_compute_network.vpc.name

  min_instances = 2
  max_instances = 3
  machine_type  = "e2-micro"
}

# Reserved range for private services (Cloud SQL via VPC peering with
# servicenetworking). The Cloud SQL instance allocates from this range.
resource "google_compute_global_address" "private_services" {
  project = var.project_id
  name    = "${var.name_prefix}-priv-services"

  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = var.private_services_prefix_length
  network       = google_compute_network.vpc.self_link
}

resource "google_service_networking_connection" "private_services" {
  network                 = google_compute_network.vpc.self_link
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_services.name]
}
