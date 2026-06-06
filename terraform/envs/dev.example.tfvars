# Copy to envs/dev.tfvars (gitignored) and adjust to your project.
# Used with: terraform apply -var-file=envs/dev.tfvars
# Reminder: select the matching workspace first — `terraform workspace select dev`.

# Core
project_id = "praxedo-file-dev"
region     = "europe-west1"
zone       = "europe-west1-b"
owner      = "praxedo-infra"

# Database — relaxed in dev for cost.
db_availability_type   = "ZONAL"
db_deletion_protection = false

# Observability — leave empty in dev to keep alerts silent until a recipient
# is decided.
alert_email = ""

# Edge — operator must own this domain and point its DNS A record at the LB
# IP (terraform output lb_ip_address) before the managed cert can provision.
domains         = ["dev.praxedo.example"]
api_path_prefix = "/api"

# CI/CD — GitHub repository allowed to federate.
github_owner = "praxedo"
github_repo  = "praxedo-app"
