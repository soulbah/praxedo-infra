locals {
  notification_channel_ids = google_monitoring_notification_channel.email[*].id
}

# Email channel is optional in dev. count=0 leaves the alerts wired but
# silent until a recipient is configured.
resource "google_monitoring_notification_channel" "email" {
  count = var.alert_email == "" ? 0 : 1

  project      = var.project_id
  display_name = "Praxedo file service — email alerts"
  type         = "email"

  labels = {
    email_address = var.alert_email
  }
}

# ----------------------------------------------------------------------------
# API 5xx rate
# ----------------------------------------------------------------------------
resource "google_monitoring_alert_policy" "api_5xx" {
  project      = var.project_id
  display_name = "API 5xx rate above threshold"
  combiner     = "OR"

  conditions {
    display_name = "5xx response rate"

    condition_threshold {
      filter = join(" AND ", [
        "resource.type=\"cloud_run_revision\"",
        "resource.labels.service_name=\"${var.api_service_name}\"",
        "metric.type=\"run.googleapis.com/request_count\"",
        "metric.labels.response_code_class=\"5xx\"",
      ])

      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = var.api_5xx_threshold_rps

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  notification_channels = local.notification_channel_ids

  documentation {
    content   = "API 5xx rate above ${var.api_5xx_threshold_rps} req/s for 5 minutes. Check Cloud Run logs for the API service and recent deploys."
    mime_type = "text/markdown"
  }
}

# ----------------------------------------------------------------------------
# Scan pipeline lag — oldest unacked message age on scan-requests
# ----------------------------------------------------------------------------
resource "google_monitoring_alert_policy" "scan_lag" {
  project      = var.project_id
  display_name = "Scan pipeline lag above threshold"
  combiner     = "OR"

  conditions {
    display_name = "oldest unacked message age"

    condition_threshold {
      filter = join(" AND ", [
        "resource.type=\"pubsub_subscription\"",
        "resource.labels.subscription_id=\"${var.scan_requests_subscription_name}\"",
        "metric.type=\"pubsub.googleapis.com/subscription/oldest_unacked_message_age\"",
      ])

      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = var.scan_lag_threshold_seconds

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MAX"
      }
    }
  }

  notification_channels = local.notification_channel_ids

  documentation {
    content   = "Scanner has not drained scan-requests within ${var.scan_lag_threshold_seconds}s. Likely causes: AV vendor slowness, scanner cold-starting under load, or a stuck instance."
    mime_type = "text/markdown"
  }
}

# ----------------------------------------------------------------------------
# DLQ depth — any message in scan-dlq is by definition an operator concern.
# ----------------------------------------------------------------------------
resource "google_monitoring_alert_policy" "scan_dlq_nonempty" {
  project      = var.project_id
  display_name = "Scan DLQ is not empty"
  combiner     = "OR"

  conditions {
    display_name = "undelivered messages on scan-dlq-sub"

    condition_threshold {
      filter = join(" AND ", [
        "resource.type=\"pubsub_subscription\"",
        "resource.labels.subscription_id=\"${var.scan_dlq_subscription_name}\"",
        "metric.type=\"pubsub.googleapis.com/subscription/num_undelivered_messages\"",
      ])

      duration        = "0s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MAX"
      }
    }
  }

  notification_channels = local.notification_channel_ids

  documentation {
    content   = "One or more scans dead-lettered. Inspect scan-dlq-sub, identify the offending object, and re-drive once the vendor is healthy."
    mime_type = "text/markdown"
  }
}
