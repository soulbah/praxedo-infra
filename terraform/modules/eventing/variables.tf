variable "project_id" {
  type        = string
  description = "GCP project hosting the topics and subscription."
}

variable "region" {
  type        = string
  description = "Region of the Cloud Run scanner the push subscription targets."
}

variable "quarantine_bucket_name" {
  type        = string
  description = "Name of the quarantine bucket that emits OBJECT_FINALIZE notifications."
}

variable "scanner_service_name" {
  type        = string
  description = "Cloud Run service name of the scanner (invoker IAM target)."
}

variable "scanner_service_uri" {
  type        = string
  description = "HTTPS URI of the scanner service. Used as the Pub/Sub push endpoint and OIDC audience."
}

variable "ack_deadline_seconds" {
  type        = number
  description = "Subscriber ack deadline. Sized for the slow AV call path."
  default     = 600
}

variable "max_delivery_attempts" {
  type        = number
  description = "Pub/Sub retries before dead-lettering."
  default     = 6

  validation {
    condition     = var.max_delivery_attempts >= 5 && var.max_delivery_attempts <= 100
    error_message = "max_delivery_attempts must be between 5 and 100 (Pub/Sub limit)."
  }
}

variable "minimum_backoff" {
  type    = string
  default = "10s"
}

variable "maximum_backoff" {
  type    = string
  default = "600s"
}

variable "message_retention_duration" {
  type        = string
  description = "How long unacked messages are retained on subscriptions and topics."
  default     = "604800s" # 7d
}
