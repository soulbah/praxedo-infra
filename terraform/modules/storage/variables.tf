variable "project_id" {
  type        = string
  description = "GCP project owning the buckets."
}

variable "location" {
  type        = string
  description = "Bucket location (region — single-region by design)."
}

variable "name_prefix" {
  type        = string
  description = "Prefix used to compose globally unique bucket names (typically the project ID)."
}

variable "api_sa_email" {
  type        = string
  description = "Email of the API runtime SA. Granted write-only on quarantine and read-only on clean."
}

variable "scanner_sa_email" {
  type        = string
  description = "Email of the scanner runtime SA. Granted full object lifecycle on quarantine and write-only on clean."
}

variable "quarantine_ttl_days" {
  type        = number
  description = "Hard TTL on every object in the quarantine bucket regardless of scan status. Safety net so a SCAN_FAILED row eventually purges after triage."
  default     = 7

  validation {
    condition     = var.quarantine_ttl_days >= 1 && var.quarantine_ttl_days <= 90
    error_message = "quarantine_ttl_days must be between 1 and 90."
  }
}

variable "clean_noncurrent_ttl_days" {
  type        = number
  description = "Retention for noncurrent versions in the clean bucket before deletion."
  default     = 30

  validation {
    condition     = var.clean_noncurrent_ttl_days >= 7 && var.clean_noncurrent_ttl_days <= 365
    error_message = "clean_noncurrent_ttl_days must be between 7 and 365."
  }
}
