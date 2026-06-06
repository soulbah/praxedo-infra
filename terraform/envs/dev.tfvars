# Dev environment — applied against project praxedo-file-dev.
# Holds non-secret config only; secrets (DB password, AV vendor key) live
# in Secret Manager and are not Terraform-managed values.

# Core
project_id = "praxedo-file-dev"
region     = "europe-west1"
zone       = "europe-west1-b"
owner      = "praxedo-infra"

# Database — relaxed in dev for cost.
db_availability_type   = "ZONAL"
db_deletion_protection = false

# Observability — silent in dev until a recipient is decided.
alert_email = ""

# Edge — operator must own this domain and point its DNS A record at the LB
# IP (`terraform output lb_ip_address`) before the managed cert provisions.
domains         = ["dev.praxedo.example"]
api_path_prefix = "/api"

# App pipeline federation.
github_owner = "praxedo"
github_repo  = "praxedo-app"

# Infra pipeline federation (this repo).
infra_github_owner = "praxedo"
infra_github_repo  = "praxedo-infra"
infra_apply_branch = "main"
