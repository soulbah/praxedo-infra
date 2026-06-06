data "google_project" "this" {
  project_id = var.project_id
}

# GCS service account that publishes object notifications. Granting it
# publisher on the topic is the prerequisite for google_storage_notification
# to work — the notification call fails closed otherwise.
data "google_storage_project_service_account" "gcs" {
  project = var.project_id
}

locals {
  pubsub_service_agent = "serviceAccount:service-${data.google_project.this.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

# ----------------------------------------------------------------------------
# Topics — scan-requests (main) and scan-dlq (dead-letter).
# ----------------------------------------------------------------------------
resource "google_pubsub_topic" "scan_requests" {
  project = var.project_id
  name    = "scan-requests"

  message_retention_duration = var.message_retention_duration
}

resource "google_pubsub_topic" "scan_dlq" {
  project = var.project_id
  name    = "scan-dlq"

  message_retention_duration = var.message_retention_duration
}

# ----------------------------------------------------------------------------
# GCS notification — OBJECT_FINALIZE on the quarantine bucket publishes to
# scan-requests. Architecture §1.7 named Eventarc; using a direct GCS→
# Pub/Sub notification keeps the wire identical while letting us own the
# subscription (retry / DLQ knobs) explicitly.
# ----------------------------------------------------------------------------
resource "google_pubsub_topic_iam_member" "gcs_publisher" {
  project = google_pubsub_topic.scan_requests.project
  topic   = google_pubsub_topic.scan_requests.name
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${data.google_storage_project_service_account.gcs.email_address}"
}

resource "google_storage_notification" "quarantine_finalize" {
  bucket         = var.quarantine_bucket_name
  topic          = google_pubsub_topic.scan_requests.id
  payload_format = "JSON_API_V1"
  event_types    = ["OBJECT_FINALIZE"]

  depends_on = [google_pubsub_topic_iam_member.gcs_publisher]
}

# ----------------------------------------------------------------------------
# Push invoker identity — Pub/Sub pushes to the scanner with an OIDC token
# minted as this SA. Kept distinct from the scanner's own runtime SA so the
# scanner can never accidentally re-invoke itself with elevated permissions.
# ----------------------------------------------------------------------------
resource "google_service_account" "pubsub_invoker" {
  project      = var.project_id
  account_id   = "praxedo-pubsub-inv"
  display_name = "Pub/Sub push invoker for the scanner"
}

resource "google_cloud_run_v2_service_iam_member" "scanner_invoker" {
  project  = var.project_id
  location = var.region
  name     = var.scanner_service_name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.pubsub_invoker.email}"
}

# The Pub/Sub service agent must be allowed to mint OIDC tokens as the
# invoker SA, otherwise the push subscription cannot authenticate to Cloud
# Run.
resource "google_service_account_iam_member" "pubsub_agent_token_creator" {
  service_account_id = google_service_account.pubsub_invoker.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = local.pubsub_service_agent
}

# DLQ wiring: the Pub/Sub service agent needs publisher on the DLQ topic and
# subscriber on the source subscription (Google requirement when
# dead_letter_policy is set).
resource "google_pubsub_topic_iam_member" "pubsub_agent_dlq_publisher" {
  project = google_pubsub_topic.scan_dlq.project
  topic   = google_pubsub_topic.scan_dlq.name
  role    = "roles/pubsub.publisher"
  member  = local.pubsub_service_agent
}

# ----------------------------------------------------------------------------
# scan-requests subscription — push to scanner.
# ----------------------------------------------------------------------------
resource "google_pubsub_subscription" "scan_requests" {
  project = var.project_id
  name    = "scan-requests-sub"
  topic   = google_pubsub_topic.scan_requests.id

  ack_deadline_seconds       = var.ack_deadline_seconds
  message_retention_duration = var.message_retention_duration

  retry_policy {
    minimum_backoff = var.minimum_backoff
    maximum_backoff = var.maximum_backoff
  }

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.scan_dlq.id
    max_delivery_attempts = var.max_delivery_attempts
  }

  push_config {
    push_endpoint = var.scanner_service_uri

    oidc_token {
      service_account_email = google_service_account.pubsub_invoker.email
      audience              = var.scanner_service_uri
    }
  }

  depends_on = [
    google_cloud_run_v2_service_iam_member.scanner_invoker,
    google_service_account_iam_member.pubsub_agent_token_creator,
    google_pubsub_topic_iam_member.pubsub_agent_dlq_publisher,
  ]
}

resource "google_pubsub_subscription_iam_member" "pubsub_agent_subscriber" {
  project      = google_pubsub_subscription.scan_requests.project
  subscription = google_pubsub_subscription.scan_requests.name
  role         = "roles/pubsub.subscriber"
  member       = local.pubsub_service_agent
}

# ----------------------------------------------------------------------------
# DLQ subscription — pull-only. Operators inspect / re-drive from here, and
# Observability alerts on its num_undelivered_messages.
# ----------------------------------------------------------------------------
resource "google_pubsub_subscription" "scan_dlq" {
  project = var.project_id
  name    = "scan-dlq-sub"
  topic   = google_pubsub_topic.scan_dlq.id

  ack_deadline_seconds       = 60
  message_retention_duration = var.message_retention_duration
}
