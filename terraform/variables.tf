variable "project_id" {
  type        = string
  description = "GCP project ID for the active environment (e.g. praxedo-file-dev)."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be 6-30 chars, lowercase letters/digits/hyphens, start with a letter, not end with a hyphen."
  }
}

variable "region" {
  type        = string
  description = "Primary GCP region. Single-region by design (see CLAUDE.md)."
  default     = "europe-west1"

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]$", var.region))
    error_message = "region must look like a GCP region slug, e.g. europe-west1."
  }
}

variable "zone" {
  type        = string
  description = "Primary zone within var.region. Used as the provider default."
  default     = "europe-west1-b"

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]-[a-z]$", var.zone))
    error_message = "zone must look like a GCP zone slug, e.g. europe-west1-b."
  }
}

variable "owner" {
  type        = string
  description = "Team or person accountable for the stack. Applied as the `owner` label."
  default     = "praxedo-infra"
}

variable "extra_labels" {
  type        = map(string)
  description = "Optional labels merged on top of the common label set. Keys/values must respect GCP label syntax."
  default     = {}

  validation {
    condition = alltrue([
      for k, v in var.extra_labels :
      can(regex("^[a-z][a-z0-9_-]{0,62}$", k)) && can(regex("^[a-z0-9_-]{0,63}$", v))
    ])
    error_message = "Label keys/values must be lowercase alphanumeric, dashes or underscores; keys must start with a letter; max 63 chars."
  }
}
