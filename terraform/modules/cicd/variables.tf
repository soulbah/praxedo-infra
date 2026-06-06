variable "project_id" {
  type        = string
  description = "GCP project hosting the WIF pool/provider and deploy SA."
}

variable "region" {
  type        = string
  description = "Region of the Artifact Registry repository the deploy SA pushes to."
}

variable "github_owner" {
  type        = string
  description = "GitHub organization or user that owns the application repository."
}

variable "github_repo" {
  type        = string
  description = "GitHub repository name (without owner/) allowed to federate."
}

variable "artifact_registry_repository_id" {
  type        = string
  description = "Repository ID granted artifactregistry.writer to the deploy SA."
}

variable "api_sa_name" {
  type        = string
  description = "Full resource name of the API runtime SA (the deploy SA must impersonate it to set it on Cloud Run)."
}

variable "scanner_sa_name" {
  type        = string
  description = "Full resource name of the scanner runtime SA."
}

variable "frontend_bucket_name" {
  type        = string
  description = "Name of the frontend bucket the deploy SA uploads the SPA build to."
}

variable "wif_pool_id" {
  type        = string
  description = "Workload identity pool ID."
  default     = "github-actions"
}

variable "wif_provider_id" {
  type        = string
  description = "Workload identity provider ID within the pool."
  default     = "github"
}
