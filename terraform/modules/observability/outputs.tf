output "notification_channel_ids" {
  value       = local.notification_channel_ids
  description = "IDs of the notification channels created here (empty if alert_email is unset)."
}

output "alert_policy_ids" {
  value = [
    google_monitoring_alert_policy.api_5xx.id,
    google_monitoring_alert_policy.scan_lag.id,
    google_monitoring_alert_policy.scan_dlq_nonempty.id,
  ]
  description = "IDs of all alert policies provisioned by this module."
}
