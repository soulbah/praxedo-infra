# Runtime identity for the REST API Cloud Run service. All API-side bucket,
# database, and secret access bindings target this SA. Kept distinct from the
# scanner identity so the IAM boundary alone enforces the §2.3 invariant.
resource "google_service_account" "api" {
  project      = var.project_id
  account_id   = "praxedo-api"
  display_name = "Praxedo File Service — API runtime"
  description  = "Cloud Run service account for the Spring Boot REST API."
}

# Runtime identity for the AV scanner Cloud Run worker. Holds the only IAM
# binding that can read from `quarantine` and write to `clean`.
resource "google_service_account" "scanner" {
  project      = var.project_id
  account_id   = "praxedo-scanner"
  display_name = "Praxedo File Service — AV scanner runtime"
  description  = "Cloud Run service account for the antivirus scanner worker."
}

# Self-impersonation: lets the API SA mint V4 signed URLs (signBlob on itself)
# for resumable uploads to `quarantine` and downloads from `clean`. The SA
# never assumes another identity — this binding does not widen its access,
# only enables the signing operation against its own credential.
resource "google_service_account_iam_member" "api_self_sign" {
  service_account_id = google_service_account.api.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:${google_service_account.api.email}"
}
