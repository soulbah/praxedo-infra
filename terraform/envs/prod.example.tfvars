# Copy to prod.tfvars (gitignored) and adjust to your project.
# Used with: terraform apply -var-file=envs/prod.tfvars
# Reminder: select the matching workspace first — `terraform workspace select prod`.

project_id = "praxedo-file-prod"
region     = "europe-west1"
zone       = "europe-west1-b"
owner      = "praxedo-infra"
