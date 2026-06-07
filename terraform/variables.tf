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

# ----------------------------------------------------------------------------
# Network
# ----------------------------------------------------------------------------

variable "subnet_cidr" {
  type        = string
  description = "CIDR for the primary subnet. A /24 covers the planned scale with room for the Cloud SQL peering and the VPC connector to live in distinct ranges."
  default     = "10.10.0.0/24"

  validation {
    condition     = can(cidrnetmask(var.subnet_cidr))
    error_message = "subnet_cidr must be a valid CIDR block."
  }
}

variable "connector_cidr" {
  type        = string
  description = "CIDR for the Serverless VPC Access connector. Must be a /28 and disjoint from var.subnet_cidr."
  default     = "10.8.0.0/28"

  validation {
    condition     = can(cidrnetmask(var.connector_cidr)) && tonumber(split("/", var.connector_cidr)[1]) == 28
    error_message = "connector_cidr must be a /28 CIDR block."
  }
}

variable "private_services_prefix_length" {
  type        = number
  description = "Prefix length for the private services peering range used by Cloud SQL."
  default     = 16
}

# ----------------------------------------------------------------------------
# Storage
# ----------------------------------------------------------------------------

variable "quarantine_ttl_days" {
  type        = number
  description = "TTL in days applied to every object in the quarantine bucket. Hard safety net against vendor outages leaving objects behind."
  default     = 7
}

variable "clean_noncurrent_ttl_days" {
  type        = number
  description = "Retention in days for noncurrent versions of objects in the clean bucket."
  default     = 30
}

# ----------------------------------------------------------------------------
# Artifact Registry
# ----------------------------------------------------------------------------

variable "registry_tagged_keep_count" {
  type        = number
  description = "Number of most-recent tagged images to retain per package."
  default     = 10
}

variable "registry_untagged_retention_seconds" {
  type        = number
  description = "Age (seconds) above which untagged images are deleted."
  default     = 604800
}

# ----------------------------------------------------------------------------
# Database
# ----------------------------------------------------------------------------

variable "db_tier" {
  type        = string
  description = "Cloud SQL machine tier. Smallest custom tier covers the expected metadata workload."
  default     = "db-custom-1-3840"
}

variable "db_availability_type" {
  type        = string
  description = "ZONAL for dev / cost; REGIONAL for prod HA."
  default     = "ZONAL"
}

variable "db_disk_size_gb" {
  type        = number
  description = "Initial Cloud SQL disk size in GiB. Disk autoresize is enabled."
  default     = 20
}

variable "db_deletion_protection" {
  type        = bool
  description = "Cloud SQL deletion protection. Keep true in prod; can be relaxed in dev tfvars."
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

# ----------------------------------------------------------------------------
# Compute (Cloud Run)
# ----------------------------------------------------------------------------

variable "app_image" {
  type        = string
  description = "Initial container image used by BOTH Cloud Run services. The app pipeline ships a single image that runs in either api or scanner mode via SPRING_PROFILES_ACTIVE (see docs/architecture.md §1.2). Overwritten by the app pipeline at deploy time (ignored by lifecycle)."
  default     = "us-docker.pkg.dev/cloudrun/container/hello"
}

variable "api_max_instances" {
  type    = number
  default = 10
}

variable "scanner_max_instances" {
  type    = number
  default = 5
}

variable "scanner_timeout_seconds" {
  type        = number
  description = "Per-request timeout for the scanner service. Sized for slow AV calls; matches Pub/Sub ack_deadline."
  default     = 600
}

# ----------------------------------------------------------------------------
# Observability
# ----------------------------------------------------------------------------

variable "alert_email" {
  type        = string
  description = "Recipient address for the email notification channel. Empty string leaves alerts wired but silent."
  default     = ""
}

# ----------------------------------------------------------------------------
# Edge (LB + CDN + frontend bucket)
# ----------------------------------------------------------------------------

variable "domains" {
  type        = list(string)
  description = "FQDNs attached to the managed SSL certificate. Must be non-empty; the operator points DNS A records at the LB IP to allow the cert to provision."

  validation {
    condition     = length(var.domains) > 0
    error_message = "domains must contain at least one FQDN."
  }
}

variable "api_path_prefix" {
  type        = string
  description = "Path prefix routed to the API backend service."
  default     = "/api"
}

# ----------------------------------------------------------------------------
# CI/CD (Workload Identity Federation)
# ----------------------------------------------------------------------------

variable "github_owner" {
  type        = string
  description = "GitHub organization or user that owns the application repository."
}

variable "github_repo" {
  type        = string
  description = "GitHub repository name allowed to federate against this pool."
}

# ----------------------------------------------------------------------------
# Infra repo CI/CD (this pipeline)
# ----------------------------------------------------------------------------

variable "infra_github_owner" {
  type        = string
  description = "GitHub owner of the infra repo (this repo). Separate from var.github_owner so the app pipeline cannot impersonate infra identities."
}

variable "infra_github_repo" {
  type        = string
  description = "GitHub repository name of the infra repo (this repo)."
}

variable "infra_apply_branch" {
  type        = string
  description = "Branch whose pushes are allowed to impersonate the infra apply SA. WIF-level branch lock."
  default     = "main"
}
