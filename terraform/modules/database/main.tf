# Fetch the DB password generated in the secrets module. Reading via a data
# source keeps the secret value out of the database module's Terraform
# graph as a literal — it's pulled at plan time and applied to the Cloud
# SQL user resource only.
data "google_secret_manager_secret_version" "db_password" {
  project = var.project_id
  secret  = var.db_password_secret_short_id
}

resource "google_sql_database_instance" "main" {
  project          = var.project_id
  name             = "${var.name_prefix}-db"
  region           = var.region
  database_version = "POSTGRES_15"

  deletion_protection = var.deletion_protection

  settings {
    tier              = var.tier
    availability_type = var.availability_type
    disk_size         = var.disk_size_gb
    disk_autoresize   = true
    disk_type         = "PD_SSD"

    user_labels = var.labels

    # Private IP only — public IP is disabled outright. Access flows through
    # the VPC peering established in the network module.
    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = var.vpc_self_link
      ssl_mode                                      = "ENCRYPTED_ONLY"
      enable_private_path_for_google_cloud_services = true
    }

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
      start_time                     = "02:00"
      transaction_log_retention_days = var.transaction_log_retention_days

      backup_retention_settings {
        retained_backups = var.backup_retention_count
        retention_unit   = "COUNT"
      }
    }

    maintenance_window {
      day          = 7 # Sunday
      hour         = 3
      update_track = "stable"
    }

    insights_config {
      query_insights_enabled  = true
      query_string_length     = 1024
      query_plans_per_minute  = 5
      record_application_tags = true
      record_client_address   = false
    }

    database_flags {
      name  = "cloudsql.iam_authentication"
      value = "off"
    }
  }
}

resource "google_sql_database" "app" {
  project  = var.project_id
  instance = google_sql_database_instance.main.name
  name     = var.db_name
}

# App-level user. The default `postgres` superuser is not exposed; the app
# only ever connects as this least-privilege user with the password held in
# Secret Manager.
resource "google_sql_user" "app" {
  project  = var.project_id
  instance = google_sql_database_instance.main.name
  name     = var.db_user
  password = data.google_secret_manager_secret_version.db_password.secret_data
  type     = "BUILT_IN"
}
