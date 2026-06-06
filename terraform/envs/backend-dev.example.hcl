# Partial backend config for the dev workspace.
# Copy to backend-dev.hcl (gitignored) and adjust the bucket name.
# Used with: terraform init -backend-config=envs/backend-dev.hcl
#
# The GCS backend appends the workspace name to `prefix` automatically, so
# the actual state object lives at:
#   gs://<bucket>/<prefix>/<workspace>.tfstate

bucket = "praxedo-file-dev-tfstate"
prefix = "praxedo-infra"
