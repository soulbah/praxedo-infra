# Project Progress

Tracks the state of each phase. Source of truth — updated after every validated step.

Statuses: `todo` · `in-progress` · `blocked` · `done`

| # | Step | Status | Notes |
|---|------|--------|-------|
| 0 | Repo bootstrap (git init, .gitignore, terraform-gcp skill) | done | commit `1283fcd`, skill at `.claude/skills/terraform-gcp/SKILL.md` |
| 1 | Architecture scoping (`docs/architecture.md`) | done | validated, used as source of truth for §2 |
| 2 | Terraform layout & module skeleton (providers, backend, env stacks, root locals/labels) | done | root `terraform/` stack: pinned providers (`google` ~> 6.10, `google-beta` ~> 6.10, `random` ~> 3.6), GCS partial backend, workspace→env mapping (`dev`/`prod`) with `check` guardrail, common labels via provider `default_labels`, project-level API enablement, `envs/*.example.tfvars` + `envs/backend-*.example.hcl`, README with bootstrap + daily flow. `terraform fmt` clean, `terraform validate` passes |
| 3 | Foundation module — VPC, subnet, Cloud NAT, Serverless VPC connector, Artifact Registry | todo | |
| 4 | Storage module — `quarantine` + `clean` + `frontend-assets` buckets, IAM split, lifecycle rules | todo | enforces invariant §2.3 |
| 5 | Database module — Cloud SQL PostgreSQL private IP, backups, PITR, users via Secret Manager | todo | |
| 6 | Secrets module — Secret Manager entries + IAM bindings per consumer SA | todo | |
| 7 | Compute module — Cloud Run API service + scanner service, dedicated SAs, least-privilege IAM | todo | |
| 8 | Eventing module — Eventarc on GCS finalize → Pub/Sub `scan-requests` + `scan-dlq` + scanner subscription | todo | resilience §2.2 |
| 9 | Edge module — external HTTPS Load Balancer + Cloud CDN + managed cert for frontend bucket and API | todo | |
| 10 | Observability module — log sinks, uptime checks, SLO alerts (5xx, scan latency, DLQ depth), notification channels | todo | |
| 11 | CI/CD enablement — Workload Identity Federation pool/provider, deploy SA, IAM bindings for app repo | todo | no SA keys, ever |
| 12 | Environment wiring — `dev` and `prod` stacks consuming the modules with env tfvars | todo | |
| 13 | Pre-commit & repo hygiene — terraform fmt/validate hooks, tflint/tfsec, README per module | todo | |
| 14 | End-to-end validation — `terraform plan` per env, manual smoke checklist, document operational runbook | todo | |
