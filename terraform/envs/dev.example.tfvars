# Copy to dev.tfvars (gitignored) and adjust to your project.
# Used with: terraform apply -var-file=envs/dev.tfvars
# Reminder: select the matching workspace first — `terraform workspace select dev`.

project_id = "praxedo-file-dev"
region     = "europe-west1"
zone       = "europe-west1-b"
owner      = "praxedo-infra"
