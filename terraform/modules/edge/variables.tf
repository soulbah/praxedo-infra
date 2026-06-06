variable "project_id" {
  type        = string
  description = "GCP project hosting the LB / CDN / frontend bucket."
}

variable "region" {
  type        = string
  description = "Region of the Cloud Run API service the LB fronts. Used for the Serverless NEG."
}

variable "name_prefix" {
  type        = string
  description = "Resource name prefix."
}

variable "api_service_name" {
  type        = string
  description = "Cloud Run service name backing the API path matcher."
}

variable "domains" {
  type        = list(string)
  description = "FQDNs to attach to the managed SSL certificate. Operator must point DNS A records at the LB IP before the cert can provision."

  validation {
    condition     = length(var.domains) > 0
    error_message = "domains must contain at least one FQDN."
  }
}

variable "api_path_prefix" {
  type        = string
  description = "Path prefix routed to the API backend service. All other paths fall through to the frontend bucket."
  default     = "/api"
}

variable "frontend_index_file" {
  type        = string
  description = "Main page suffix for the frontend bucket website config."
  default     = "index.html"
}

variable "frontend_not_found_file" {
  type        = string
  description = "404 file for the frontend bucket. Set to index.html for SPA client-side routing fallback."
  default     = "index.html"
}

variable "frontend_versioning_keep_days" {
  type        = number
  description = "Noncurrent version retention on the frontend bucket."
  default     = 30
}

variable "cdn_default_ttl_seconds" {
  type    = number
  default = 3600
}

variable "cdn_max_ttl_seconds" {
  type    = number
  default = 86400
}
