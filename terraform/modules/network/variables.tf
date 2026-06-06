variable "project_id" {
  type        = string
  description = "GCP project hosting the VPC."
}

variable "region" {
  type        = string
  description = "Region for the subnet, router/NAT, and VPC connector."
}

variable "env" {
  type        = string
  description = "Environment slug (dev|prod), used in resource descriptions."
}

variable "name_prefix" {
  type        = string
  description = "Resource name prefix (typically the project ID)."
}

variable "subnet_cidr" {
  type        = string
  description = "Primary subnet CIDR. A /24 is enough at this scale."

  validation {
    condition     = can(cidrnetmask(var.subnet_cidr))
    error_message = "subnet_cidr must be a valid CIDR block."
  }
}

variable "connector_cidr" {
  type        = string
  description = "Serverless VPC Access connector CIDR. Must be a /28."

  validation {
    condition     = can(cidrnetmask(var.connector_cidr)) && tonumber(split("/", var.connector_cidr)[1]) == 28
    error_message = "connector_cidr must be a /28 CIDR block."
  }
}

variable "private_services_prefix_length" {
  type        = number
  description = "Prefix length for the Cloud SQL private services peering range."
  default     = 16

  validation {
    condition     = var.private_services_prefix_length >= 16 && var.private_services_prefix_length <= 24
    error_message = "private_services_prefix_length must be between 16 and 24."
  }
}
