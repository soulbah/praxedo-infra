terraform {
  # Remote state on GCS. Partial config: bucket + prefix supplied via
  # `terraform init -backend-config=envs/backend-<env>.hcl`. The GCS backend
  # appends the active workspace name to `prefix` automatically, so dev and
  # prod state files live side-by-side in the same bucket without collision.
  #
  # The state bucket itself is provisioned out-of-band (chicken/egg) — see
  # terraform/README.md for the bootstrap procedure.
  backend "gcs" {}
}
