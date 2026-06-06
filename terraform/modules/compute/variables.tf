variable "project_id" {
  type        = string
  description = "GCP project hosting the Cloud Run services."
}

variable "region" {
  type        = string
  description = "Region for both Cloud Run services."
}

variable "name_prefix" {
  type        = string
  description = "Prefix for the Cloud Run service names."
}

variable "api_sa_email" {
  type        = string
  description = "API runtime service account email."
}

variable "scanner_sa_email" {
  type        = string
  description = "Scanner runtime service account email."
}

variable "vpc_connector_id" {
  type        = string
  description = "Serverless VPC Access connector ID. Both services use it for outbound."
}

variable "api_image" {
  type        = string
  description = "Container image for the API. The app pipeline owns this — the value is ignored by lifecycle once first applied."
  default     = "us-docker.pkg.dev/cloudrun/container/hello"
}

variable "scanner_image" {
  type        = string
  description = "Container image for the scanner. Same lifecycle handling as api_image."
  default     = "us-docker.pkg.dev/cloudrun/container/hello"
}

variable "api_cpu" {
  type    = string
  default = "1"
}

variable "api_memory" {
  type    = string
  default = "1Gi"
}

variable "api_max_instances" {
  type    = number
  default = 10
}

variable "scanner_cpu" {
  type    = string
  default = "1"
}

variable "scanner_memory" {
  type    = string
  default = "1Gi"
}

variable "scanner_max_instances" {
  type    = number
  default = 5
}

variable "scanner_timeout_seconds" {
  type        = number
  description = "Per-request timeout for the scanner. Sized for slow AV calls; matches Pub/Sub ack_deadline."
  default     = 600
}

# Database wiring
variable "db_host" {
  type        = string
  description = "Private IP of the Cloud SQL instance."
}

variable "db_name" { type = string }
variable "db_user" { type = string }

variable "db_password_secret_short_id" {
  type        = string
  description = "Short secret ID of the DB password (used by secret_key_ref)."
}

variable "av_api_key_secret_short_id" {
  type        = string
  description = "Short secret ID of the AV API key."
}

# Storage wiring
variable "quarantine_bucket_name" { type = string }
variable "clean_bucket_name" { type = string }
