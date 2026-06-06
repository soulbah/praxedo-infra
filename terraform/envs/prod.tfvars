# Prod environment — applied against project praxedo-file-prod.
# Holds non-secret config only; secrets live in Secret Manager.

# Core
project_id = "praxedo-file-prod"
region     = "europe-west1"
zone       = "europe-west1-b"
owner      = "praxedo-infra"

# Database — HA + protection.
db_availability_type   = "REGIONAL"
db_deletion_protection = true
db_disk_size_gb        = 50

# Compute — higher headroom for prod traffic.
api_max_instances     = 20
scanner_max_instances = 10

# Observability — required in prod.
alert_email = "oncall@praxedo.example"

# Edge.
domains         = ["app.praxedo.example"]
api_path_prefix = "/api"

# App pipeline federation.
github_owner = "praxedo"
github_repo  = "praxedo-app"

# Infra pipeline federation (this repo).
infra_github_owner = "praxedo"
infra_github_repo  = "praxedo-infra"
infra_apply_branch = "main"
