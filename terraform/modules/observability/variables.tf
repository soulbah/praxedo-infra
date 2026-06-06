variable "project_id" {
  type        = string
  description = "GCP project."
}

variable "alert_email" {
  type        = string
  description = "Recipient address for the email notification channel. Empty string disables notifications."
  default     = ""
}

variable "api_service_name" {
  type        = string
  description = "Cloud Run service name for the API (filter target for the 5xx policy)."
}

variable "scan_requests_subscription_name" {
  type        = string
  description = "Name of the main scan-requests subscription. Used to alert on pipeline lag."
}

variable "scan_dlq_subscription_name" {
  type        = string
  description = "Name of the DLQ subscription. Any undelivered messages here fire an alert."
}

variable "api_5xx_threshold_rps" {
  type        = number
  description = "Threshold (req/s) above which the API 5xx rate alert fires."
  default     = 0.2
}

variable "scan_lag_threshold_seconds" {
  type        = number
  description = "Oldest unacked message age (seconds) above which the lag alert fires."
  default     = 900
}
