# Copy to envs/prod.tfvars (gitignored) and adjust.
# Used with: terraform apply -var-file=envs/prod.tfvars
# Reminder: select the matching workspace first — `terraform workspace select prod`.

# Core
project_id = "praxedo-file-prod"
region     = "europe-west1"
zone       = "europe-west1-b"
owner      = "praxedo-infra"

# Database — HA + protection for prod.
db_availability_type   = "REGIONAL"
db_deletion_protection = true
db_disk_size_gb        = 50

# Compute — higher headroom.
api_max_instances     = 20
scanner_max_instances = 10

# Observability — required in prod.
alert_email = "oncall@praxedo.example"

# Edge.
domains         = ["app.praxedo.example"]
api_path_prefix = "/api"

# CI/CD.
github_owner = "praxedo"
github_repo  = "praxedo-app"
