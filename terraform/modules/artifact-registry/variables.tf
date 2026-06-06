variable "project_id" {
  type        = string
  description = "GCP project hosting the registry."
}

variable "region" {
  type        = string
  description = "Region for the Docker repository."
}

variable "repository_id" {
  type        = string
  description = "Repository ID (must be lowercase, hyphen-separated)."
  default     = "praxedo-docker"
}

variable "consumer_sa_emails" {
  type        = list(string)
  description = "Service accounts granted pull access (Cloud Run runtime identities)."
  default     = []
}

variable "untagged_retention_seconds" {
  type        = number
  description = "Age above which untagged images are auto-deleted."
  default     = 604800 # 7 days
}

variable "tagged_keep_count" {
  type        = number
  description = "Number of most-recent tagged versions to retain."
  default     = 10
}
