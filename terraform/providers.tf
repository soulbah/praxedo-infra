provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone

  # Apply the common label set to every resource that supports
  # provider-default labels. Per-resource labels still merge on top.
  default_labels = local.common_labels
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone

  default_labels = local.common_labels
}
