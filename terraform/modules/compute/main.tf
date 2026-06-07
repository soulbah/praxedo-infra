locals {
  jdbc_url = "jdbc:postgresql://${var.db_host}:5432/${var.db_name}"
}

# ----------------------------------------------------------------------------
# API — REST API exposed (later) behind the external HTTPS load balancer.
# Ingress is restricted to internal + load balancer; no allUsers binding.
# ----------------------------------------------------------------------------
resource "google_cloud_run_v2_service" "api" {
  project  = var.project_id
  name     = "${var.name_prefix}-api"
  location = var.region

  ingress             = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"
  deletion_protection = false

  template {
    service_account = var.api_sa_email

    scaling {
      min_instance_count = 0
      max_instance_count = var.api_max_instances
    }

    # Egress via the VPC connector so the API can reach Cloud SQL on its
    # private IP. PRIVATE_RANGES_ONLY keeps public-internet egress on the
    # cheaper default Cloud Run path.
    vpc_access {
      connector = var.vpc_connector_id
      egress    = "PRIVATE_RANGES_ONLY"
    }

    containers {
      image = var.app_image

      ports {
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = var.api_cpu
          memory = var.api_memory
        }
      }

      # Single codebase, two runtime profiles. The image itself is the same
      # as the scanner service below; only the profile differs, which lets
      # Spring activate the api endpoints + beans and ignore the scanner
      # ones. See docs/architecture.md §1.2.
      env {
        name  = "SPRING_PROFILES_ACTIVE"
        value = var.api_profile
      }

      env {
        name  = "SPRING_DATASOURCE_URL"
        value = local.jdbc_url
      }

      env {
        name  = "SPRING_DATASOURCE_USERNAME"
        value = var.db_user
      }

      env {
        name = "SPRING_DATASOURCE_PASSWORD"
        value_source {
          secret_key_ref {
            secret  = var.db_password_secret_short_id
            version = "latest"
          }
        }
      }

      env {
        name  = "QUARANTINE_BUCKET"
        value = var.quarantine_bucket_name
      }

      env {
        name  = "CLEAN_BUCKET"
        value = var.clean_bucket_name
      }
    }
  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }

  # The app pipeline (separate repo) owns image promotion. Terraform sets
  # the initial placeholder image, then steps out of the way so a deploy
  # does not show up as drift on the next `terraform plan`.
  lifecycle {
    ignore_changes = [
      template[0].containers[0].image,
      client,
      client_version,
    ]
  }
}

# ----------------------------------------------------------------------------
# Scanner — invoked by Pub/Sub push only. Ingress is internal-only so the
# service URL cannot be hit from the public internet, even if the OIDC
# invoker binding were ever revoked. Outbound egress goes through the
# Cloud NAT static IP so the AV vendor sees a stable address.
# ----------------------------------------------------------------------------
resource "google_cloud_run_v2_service" "scanner" {
  project  = var.project_id
  name     = "${var.name_prefix}-scanner"
  location = var.region

  ingress             = "INGRESS_TRAFFIC_INTERNAL_ONLY"
  deletion_protection = false

  template {
    service_account = var.scanner_sa_email

    timeout = "${var.scanner_timeout_seconds}s"

    scaling {
      min_instance_count = 0
      max_instance_count = var.scanner_max_instances
    }

    # ALL_TRAFFIC required so AV outbound calls leave via Cloud NAT with
    # the static whitelisted IP, not via the random Cloud Run egress pool.
    vpc_access {
      connector = var.vpc_connector_id
      egress    = "ALL_TRAFFIC"
    }

    containers {
      image = var.app_image

      resources {
        limits = {
          cpu    = var.scanner_cpu
          memory = var.scanner_memory
        }
      }

      # Same image as the api service above; the profile is what switches
      # the runtime to Pub/Sub push handler mode.
      env {
        name  = "SPRING_PROFILES_ACTIVE"
        value = var.scanner_profile
      }

      env {
        name = "AV_API_KEY"
        value_source {
          secret_key_ref {
            secret  = var.av_api_key_secret_short_id
            version = "latest"
          }
        }
      }

      env {
        name  = "SPRING_DATASOURCE_URL"
        value = local.jdbc_url
      }

      env {
        name  = "SPRING_DATASOURCE_USERNAME"
        value = var.db_user
      }

      env {
        name = "SPRING_DATASOURCE_PASSWORD"
        value_source {
          secret_key_ref {
            secret  = var.db_password_secret_short_id
            version = "latest"
          }
        }
      }

      env {
        name  = "QUARANTINE_BUCKET"
        value = var.quarantine_bucket_name
      }

      env {
        name  = "CLEAN_BUCKET"
        value = var.clean_bucket_name
      }
    }
  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }

  lifecycle {
    ignore_changes = [
      template[0].containers[0].image,
      client,
      client_version,
    ]
  }
}
