variable "project_id" {
  type        = string
  description = "GCP project hosting the infra repo WIF pool + plan/apply SAs."
}

variable "github_owner" {
  type        = string
  description = "GitHub organization or user that owns the infra repository."
}

variable "github_repo" {
  type        = string
  description = "Infra repository name (this repo) allowed to federate."
}

variable "state_bucket_name" {
  type        = string
  description = "GCS bucket holding Terraform remote state. Both SAs get objectAdmin on it (plan still needs to write the lock object)."
}

variable "apply_branch" {
  type        = string
  description = "Branch whose pushes are allowed to impersonate the apply SA. Restricted at the WIF binding so even a leaked workflow on another branch cannot apply."
  default     = "main"
}

variable "wif_pool_id" {
  type        = string
  description = "Workload identity pool ID for the infra repo."
  default     = "infra-github"
}

variable "wif_provider_id" {
  type        = string
  description = "Provider ID inside the pool."
  default     = "github"
}
