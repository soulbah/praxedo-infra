variable "project_id" {
  type        = string
  description = "GCP project hosting the Cloud SQL instance."
}

variable "region" {
  type        = string
  description = "Region for the Cloud SQL instance."
}

variable "name_prefix" {
  type        = string
  description = "Resource name prefix."
}

variable "vpc_self_link" {
  type        = string
  description = "Self-link of the VPC the instance peers into for private IP access."
}

variable "db_password_secret_short_id" {
  type        = string
  description = "Short secret ID (no project prefix) of the secret holding the app DB password."
}

variable "tier" {
  type        = string
  description = "Cloud SQL machine tier."
  default     = "db-custom-1-3840"
}

variable "availability_type" {
  type        = string
  description = "REGIONAL for HA, ZONAL for single-zone."
  default     = "ZONAL"

  validation {
    condition     = contains(["ZONAL", "REGIONAL"], var.availability_type)
    error_message = "availability_type must be ZONAL or REGIONAL."
  }
}

variable "disk_size_gb" {
  type        = number
  description = "Initial disk size in GiB. Disk autoresize is enabled."
  default     = 20
}

variable "deletion_protection" {
  type        = bool
  description = "Cloud SQL deletion protection. Forced on in prod, may be relaxed in dev."
  default     = true
}

variable "db_name" {
  type        = string
  description = "Application database name."
  default     = "praxedo"
}

variable "db_user" {
  type        = string
  description = "Application database user."
  default     = "praxedo_app"
}

variable "labels" {
  type        = map(string)
  description = "Labels to set as Cloud SQL settings.user_labels. provider default_labels does not cover this nested field."
  default     = {}
}

variable "backup_retention_count" {
  type        = number
  description = "Number of automated backups retained."
  default     = 7
}

variable "transaction_log_retention_days" {
  type        = number
  description = "PITR transaction log retention window (days)."
  default     = 7
}
