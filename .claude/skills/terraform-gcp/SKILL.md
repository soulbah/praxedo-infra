---
name: terraform-gcp
description: Use whenever writing or editing Terraform code targeting Google Cloud Platform (.tf / .tfvars / module changes). Enforces security defaults (least-privilege service accounts, Secret Manager, private networking, Workload Identity Federation) and quality rules (fmt/validate, pinned providers, typed variables, explicit outputs, consistent labels, no hardcoded values).
---

# Terraform on GCP — defaults

Apply these rules on every Terraform write or edit. No exceptions without explicit user override.

## Security defaults

- **Service accounts**: one dedicated SA per component. Bind only the IAM roles needed for that component's resources. Never grant `roles/owner` or `roles/editor`. Prefer predefined narrow roles (`roles/storage.objectAdmin` on a single bucket, `roles/cloudsql.client` on a single instance) or custom roles. Scope bindings to the resource, not the project, when possible.
- **Secrets**: store in Secret Manager. Reference via `data "google_secret_manager_secret_version"` or resource-level secret references. Never put secret values, API keys, tokens, or passwords in `.tf` or committed `.tfvars`. Pass sensitive inputs as `variable { sensitive = true }`.
- **Databases**: Cloud SQL / AlloyDB / Memorystore on **private IP only**. No public IP. Access via VPC + Private Service Connect or VPC peering. Require SSL. Disable default user; create least-privilege users via Secret Manager.
- **Buckets**: `uniform_bucket_level_access = true`. `public_access_prevention = "enforced"`. No `allUsers` / `allAuthenticatedUsers` IAM. Enable versioning + retention where relevant.
- **CI auth (GitHub Actions)**: Workload Identity Federation only. Bind the GitHub OIDC provider to a deploy SA scoped to the target project. **Never** export or commit JSON SA keys. No `GOOGLE_APPLICATION_CREDENTIALS` file in CI.

## Quality rules

- `terraform fmt -recursive` and `terraform validate` must pass before any commit. Run them; do not commit failing code.
- **Pin provider versions**: `required_providers { google = { source = "hashicorp/google", version = "~> X.Y" } }` and `required_version = ">= 1.x"`. No floating `latest`.
- **Variables**: every `variable` block has explicit `type`, a `description`, and a `default` when safe. Use `validation` blocks for enums / formats. Mark sensitive vars `sensitive = true`.
- **Outputs**: declare explicit `output` blocks for anything another module or pipeline consumes. Include `description`. Mark `sensitive = true` when relevant.
- **Labels**: every labelable resource gets a consistent label set (`env`, `component`, `owner`, `managed_by = "terraform"`). Derive from a shared `local.labels` or `var.labels`.
- **No hardcoded values**: project IDs, regions, zones, bucket names, SA emails, CIDRs, image tags — all via variables or locals. No magic strings in resource bodies.

## Workflow

1. Read existing module structure before adding resources.
2. Run `terraform fmt` + `terraform validate` after edits.
3. Surface any rule you had to bend and why in the response.
