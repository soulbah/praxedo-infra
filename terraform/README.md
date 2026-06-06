# Terraform — Praxedo File Service infra

Root stack for the GCP infrastructure described in `docs/architecture.md`.
A single root module is reused across environments via Terraform workspaces
(`dev`, `prod`). Each workspace targets a dedicated GCP project.

## Layout

```
terraform/
├── versions.tf       # required_version + pinned providers
├── backend.tf        # GCS remote state (partial config)
├── providers.tf      # google / google-beta provider config
├── variables.tf      # project_id, region, zone, owner, extra_labels
├── locals.tf         # workspace→env mapping, common labels, API set
├── apis.tf           # project-level API enablement
├── outputs.tf        # surface for downstream modules / pipelines
└── envs/
    ├── dev.example.tfvars
    ├── prod.example.tfvars
    ├── backend-dev.example.hcl
    └── backend-prod.example.hcl
```

## Bootstrap (one-time per environment)

The GCS state bucket is a chicken/egg dependency — it must exist *before*
`terraform init` can configure the remote backend. Provision it manually
once per environment:

```sh
PROJECT_ID=praxedo-file-dev
gcloud storage buckets create "gs://${PROJECT_ID}-tfstate" \
  --project="${PROJECT_ID}" \
  --location=europe-west1 \
  --uniform-bucket-level-access \
  --public-access-prevention
gcloud storage buckets update "gs://${PROJECT_ID}-tfstate" \
  --versioning
```

Then create the local config from the examples:

```sh
cp envs/dev.example.tfvars         envs/dev.tfvars
cp envs/backend-dev.example.hcl    envs/backend-dev.hcl
```

`*.tfvars` and `backend-*.hcl` (non-example) are gitignored.

## Daily flow

```sh
# 1. Init with the env-specific backend.
terraform init -backend-config=envs/backend-dev.hcl

# 2. Select / create the matching workspace.
terraform workspace select dev || terraform workspace new dev

# 3. Plan & apply against the env tfvars.
terraform plan  -var-file=envs/dev.tfvars
terraform apply -var-file=envs/dev.tfvars
```

For prod, substitute `prod` everywhere. Workspace must match the env
(`default` is rejected by a `check` block in `locals.tf`).

## Conventions enforced here

* `terraform.workspace` is the source of truth for the env slug — the
  workspace, not the tfvars file, controls which environment is touched.
* Every labelable resource inherits `env`, `owner`, `managed_by=terraform`
  via the provider's `default_labels`.
* All project IDs, regions, zones, and labels are variables — no magic
  strings in resource bodies.
* `google_project_service` resources never disable APIs on destroy.

## Validation locally

```sh
terraform fmt -recursive
terraform init -backend=false        # offline validate
terraform validate
```
