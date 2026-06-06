# ----------------------------------------------------------------------------
# Global IP for the HTTPS load balancer.
# ----------------------------------------------------------------------------
resource "google_compute_global_address" "lb" {
  project = var.project_id
  name    = "${var.name_prefix}-lb-ip"
}

# ----------------------------------------------------------------------------
# Frontend bucket — backs the static SPA served via Cloud CDN.
#
# IMPORTANT — SCOPED SECURITY EXCEPTION:
# Per the terraform-gcp skill, buckets should never grant allUsers IAM. The
# architecture (§1.3) deliberately chose GCS + LB + Cloud CDN for the SPA,
# and the standard pattern requires anonymous LB origin reads. We therefore
# grant allUsers objectViewer on THIS bucket ONLY. To allow that, PAP must
# be `inherited` instead of `enforced`. Mitigations:
#   - This bucket holds nothing but the built SPA artefacts (no PII, no
#     secrets, no scanned/quarantined user files).
#   - The quarantine + clean buckets keep PAP=enforced and zero public IAM.
#   - Versioning + retention give a rollback path against accidental
#     publish of a broken or malicious build.
# ----------------------------------------------------------------------------
resource "google_storage_bucket" "frontend" {
  project  = var.project_id
  name     = "${var.name_prefix}-frontend"
  location = var.region

  uniform_bucket_level_access = true
  # SCOPED EXCEPTION: see the block-level comment above.
  public_access_prevention = "inherited"

  force_destroy = false

  versioning {
    enabled = true
  }

  website {
    main_page_suffix = var.frontend_index_file
    # SPA client-side routing fallback — any 404 returns the SPA shell so
    # the React router can resolve the path in-browser.
    not_found_page = var.frontend_not_found_file
  }

  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      with_state                 = "ARCHIVED"
      days_since_noncurrent_time = var.frontend_versioning_keep_days
    }
  }

  cors {
    origin          = ["*"]
    method          = ["GET", "HEAD", "OPTIONS"]
    response_header = ["Content-Type", "Cache-Control"]
    max_age_seconds = 3600
  }
}

resource "google_storage_bucket_iam_member" "frontend_public_read" {
  bucket = google_storage_bucket.frontend.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}

# ----------------------------------------------------------------------------
# CDN-fronted backend bucket pointing at the frontend bucket.
# ----------------------------------------------------------------------------
resource "google_compute_backend_bucket" "frontend" {
  project     = var.project_id
  name        = "${var.name_prefix}-frontend-be"
  bucket_name = google_storage_bucket.frontend.name
  enable_cdn  = true

  cdn_policy {
    cache_mode        = "CACHE_ALL_STATIC"
    default_ttl       = var.cdn_default_ttl_seconds
    max_ttl           = var.cdn_max_ttl_seconds
    client_ttl        = var.cdn_default_ttl_seconds
    negative_caching  = true
    serve_while_stale = 86400
  }
}

# ----------------------------------------------------------------------------
# Serverless NEG + backend service for the Cloud Run API.
# ----------------------------------------------------------------------------
resource "google_compute_region_network_endpoint_group" "api" {
  project               = var.project_id
  name                  = "${var.name_prefix}-api-neg"
  region                = var.region
  network_endpoint_type = "SERVERLESS"

  cloud_run {
    service = var.api_service_name
  }
}

resource "google_compute_backend_service" "api" {
  project               = var.project_id
  name                  = "${var.name_prefix}-api-be"
  protocol              = "HTTPS"
  load_balancing_scheme = "EXTERNAL_MANAGED"

  backend {
    group = google_compute_region_network_endpoint_group.api.id
  }

  log_config {
    enable      = true
    sample_rate = 1.0
  }
}

# The Cloud Run API has ingress=INTERNAL_LOAD_BALANCER, so only the LB can
# reach it from outside the project — but the LB needs the API to accept its
# requests. allUsers is the standard pattern when the LB enforces the front
# door: ingress restricts the network reach, IAM lets the LB through.
resource "google_cloud_run_v2_service_iam_member" "api_lb_invoker" {
  project  = var.project_id
  location = var.region
  name     = var.api_service_name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# ----------------------------------------------------------------------------
# Managed SSL certificate. Operator must point each FQDN's DNS A record at
# google_compute_global_address.lb.address before the cert leaves
# PROVISIONING.
# ----------------------------------------------------------------------------
resource "google_compute_managed_ssl_certificate" "main" {
  project = var.project_id
  name    = "${var.name_prefix}-cert"

  managed {
    domains = var.domains
  }
}

# ----------------------------------------------------------------------------
# URL map — /api/* → backend service, everything else → frontend bucket.
# ----------------------------------------------------------------------------
resource "google_compute_url_map" "https" {
  project         = var.project_id
  name            = "${var.name_prefix}-https-urlmap"
  default_service = google_compute_backend_bucket.frontend.id

  host_rule {
    hosts        = var.domains
    path_matcher = "main"
  }

  path_matcher {
    name            = "main"
    default_service = google_compute_backend_bucket.frontend.id

    path_rule {
      paths   = ["${var.api_path_prefix}", "${var.api_path_prefix}/*"]
      service = google_compute_backend_service.api.id
    }
  }
}

resource "google_compute_target_https_proxy" "main" {
  project          = var.project_id
  name             = "${var.name_prefix}-https-proxy"
  url_map          = google_compute_url_map.https.id
  ssl_certificates = [google_compute_managed_ssl_certificate.main.id]
}

resource "google_compute_global_forwarding_rule" "https" {
  project               = var.project_id
  name                  = "${var.name_prefix}-https"
  target                = google_compute_target_https_proxy.main.id
  port_range            = "443"
  ip_address            = google_compute_global_address.lb.address
  load_balancing_scheme = "EXTERNAL_MANAGED"
}

# ----------------------------------------------------------------------------
# HTTP → HTTPS redirect.
# ----------------------------------------------------------------------------
resource "google_compute_url_map" "http_redirect" {
  project = var.project_id
  name    = "${var.name_prefix}-http-redirect"

  default_url_redirect {
    https_redirect         = true
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
    strip_query            = false
  }
}

resource "google_compute_target_http_proxy" "redirect" {
  project = var.project_id
  name    = "${var.name_prefix}-http-proxy"
  url_map = google_compute_url_map.http_redirect.id
}

resource "google_compute_global_forwarding_rule" "http" {
  project               = var.project_id
  name                  = "${var.name_prefix}-http"
  target                = google_compute_target_http_proxy.redirect.id
  port_range            = "80"
  ip_address            = google_compute_global_address.lb.address
  load_balancing_scheme = "EXTERNAL_MANAGED"
}
