output "instance_name" {
  value       = google_sql_database_instance.main.name
  description = "Cloud SQL instance name."
}

output "instance_connection_name" {
  value       = google_sql_database_instance.main.connection_name
  description = "Cloud SQL instance connection name (project:region:instance), useful for the Cloud SQL Java connector if ever swapped in."
}

output "private_ip" {
  value       = google_sql_database_instance.main.private_ip_address
  description = "Private IP of the Cloud SQL instance, consumed by Cloud Run via JDBC."
}

output "db_name" {
  value       = google_sql_database.app.name
  description = "Application database name."
}

output "db_user" {
  value       = google_sql_user.app.name
  description = "Application database user."
}
