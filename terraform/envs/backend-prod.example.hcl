# Partial backend config for the prod workspace.
# Copy to backend-prod.hcl (gitignored) and adjust the bucket name.
# Used with: terraform init -backend-config=envs/backend-prod.hcl
#
# The GCS backend appends the workspace name to `prefix` automatically, so
# the actual state object lives at:
#   gs://<bucket>/<prefix>/<workspace>.tfstate

bucket = "praxedo-file-prod-tfstate"
prefix = "praxedo-infra"
