output "scan_requests_topic_name" {
  value       = google_pubsub_topic.scan_requests.name
  description = "Main topic name."
}

output "scan_dlq_topic_name" {
  value       = google_pubsub_topic.scan_dlq.name
  description = "Dead-letter topic name."
}

output "scan_requests_subscription_name" {
  value       = google_pubsub_subscription.scan_requests.name
  description = "Push subscription delivering events to the scanner."
}

output "scan_dlq_subscription_name" {
  value       = google_pubsub_subscription.scan_dlq.name
  description = "Pull subscription used by operators and by observability alerts."
}

output "pubsub_invoker_sa_email" {
  value       = google_service_account.pubsub_invoker.email
  description = "Email of the SA used by Pub/Sub to push to the scanner."
}
