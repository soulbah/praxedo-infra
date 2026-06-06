locals {
  api_member     = "serviceAccount:${var.api_sa_email}"
  scanner_member = "serviceAccount:${var.scanner_sa_email}"
}

# Quarantine bucket — receives every direct-to-GCS upload. Until the scanner
# emits a CLEAN verdict and copies to `clean`, an object here is untrusted.
# The §2.3 invariant relies on the IAM split below, not on app logic.
resource "google_storage_bucket" "quarantine" {
  project  = var.project_id
  name     = "${var.name_prefix}-quarantine"
  location = var.location

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  # Refuse destroy if non-empty: an accidental `terraform destroy` must not
  # silently drop user data still awaiting scan.
  force_destroy = false

  versioning {
    enabled = false
  }

  # Safety net: any object — including SCAN_FAILED stragglers — eventually
  # purges, so a vendor outage cannot leave a growing pile of unscanned
  # objects forever.
  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age = var.quarantine_ttl_days
    }
  }
}

# Clean bucket — sole source for downloads. Versioning gives a recovery
# window against an accidental delete or a buggy scanner.
resource "google_storage_bucket" "clean" {
  project  = var.project_id
  name     = "${var.name_prefix}-clean"
  location = var.location

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  force_destroy = false

  versioning {
    enabled = true
  }

  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      with_state                 = "ARCHIVED"
      days_since_noncurrent_time = var.clean_noncurrent_ttl_days
    }
  }
}

# ----------------------------------------------------------------------------
# IAM — enforces the §2.3 invariant at the storage layer.
#
# API SA on quarantine: objectCreator only. The API mints V4 signed upload
# URLs; signed URLs derive permissions from the signer, so write is needed
# but read is deliberately withheld. The API physically cannot mint a
# signed download URL for an unscanned object.
#
# API SA on clean: objectViewer. Lets the API mint a short-lived signed
# download URL once the DB row reads `status = CLEAN`.
#
# Scanner SA on quarantine: objectAdmin. Needs read (to send to AV) and
# delete (after promote). objectAdmin is bucket-scoped, so the broader
# permission set never reaches `clean`.
#
# Scanner SA on clean: objectCreator. Promotion is copy(quarantine→clean);
# scanner does not need read on clean.
# ----------------------------------------------------------------------------

resource "google_storage_bucket_iam_member" "api_quarantine_write_only" {
  bucket = google_storage_bucket.quarantine.name
  role   = "roles/storage.objectCreator"
  member = local.api_member
}

resource "google_storage_bucket_iam_member" "api_clean_read_only" {
  bucket = google_storage_bucket.clean.name
  role   = "roles/storage.objectViewer"
  member = local.api_member
}

resource "google_storage_bucket_iam_member" "scanner_quarantine_object_admin" {
  bucket = google_storage_bucket.quarantine.name
  role   = "roles/storage.objectAdmin"
  member = local.scanner_member
}

resource "google_storage_bucket_iam_member" "scanner_clean_write_only" {
  bucket = google_storage_bucket.clean.name
  role   = "roles/storage.objectCreator"
  member = local.scanner_member
}
