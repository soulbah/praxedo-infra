# Praxedo File Service — Production Infrastructure

GCP infrastructure-as-code for an existing Java/Spring Boot REST API + React SPA that lets users upload, scan, and download files. Antivirus scanning is delegated to a third-party HTTP API. **A file must be scanned clean before it can ever be downloaded.**

This repo provisions the platform. It does **not** deploy the application: the developer team owns that pipeline in a separate repo and authenticates to GCP via Workload Identity Federation (no service-account keys, ever). The boundary is enforced by IAM — see `handoff/` for what the application pipeline gets and what it can and cannot do.

This README is the entry point. Read it first, then drill into the supporting docs:

| Document | Purpose |
|---|---|
| `docs/architecture.md` | Detailed decisions, alternatives rejected, the three explicit challenges |
| `docs/runbook.md` | Day-to-day operations, bootstrap, recovery paths |
| `docs/dev-requirements.md` | What the application team owns (Dockerfile, Spring profiles, probes, env vars) |
| `docs/progress.md` | Phase-by-phase build log |
| `handoff/README.md` | Drop-in application-pipeline starter kit (workflow + variable map) |
| `terraform/README.md` | Module layout, bootstrap commands, conventions |
| `prompts/README.md` | AI-assisted workflow disclosure |

---

## 1. Context and constraints

| Dimension | Value |
|---|---|
| Workload | REST API (Spring Boot) + React SPA, file upload / scan / download |
| Scale | A few hundred users, files from a few KB to several hundred MB |
| Team | 3 backend developers, **no dedicated ops profile** |
| Target cloud | GCP |
| Environments | `dev`, `prod` (two distinct GCP projects) |
| Excluded | GKE / Kubernetes / service mesh, multi-region, self-hosted monitoring |

Two non-negotiable principles drive every decision:

1. **Operability by 3 developers without ops.** Any choice that adds ops burden must be explicitly justified. When in doubt, pick the simpler managed option.
2. **Right-sizing.** No premature scale-out, no premium SKUs without a stated reason. The target is "low tens of EUR/month at idle, scaling with usage".

Two pipelines, never confused:

- **Infra lifecycle** (this repo). Terraform, owned by the platform.
- **Application deployment** (a separate developer repo). Owned by the 3 devs. We make their pipeline possible, secure, and standardised; we do not deploy for them.

---

## 2. Solution at a glance

```
                ┌──────────────┐    ┌──────────────┐
   Browser ───► │ HTTPS LB +   │───►│ Cloud Run    │  (Spring profile: api)
                │ Cloud CDN    │    │ API service  │
                └──────┬───────┘    └──────┬───────┘
                       │                   │
                       │ static SPA        │ V4 signed URL (resumable)
                       ▼                   ▼
                ┌──────────────┐    ┌──────────────┐
                │ frontend     │    │ quarantine   │  (no public read,
                │ bucket       │    │ bucket       │   API SA: write-only)
                └──────────────┘    └──────┬───────┘
                                           │ OBJECT_FINALIZE
                                           ▼
                                    ┌──────────────┐
                                    │ Pub/Sub      │──► DLQ (scan-dlq)
                                    │ scan-requests│
                                    └──────┬───────┘
                                           │ push (OIDC)
                                           ▼
                                    ┌──────────────┐    ┌──────────────┐
                                    │ Cloud Run    │───►│ 3rd-party AV │
                                    │ scanner svc  │    │ HTTP API     │
                                    └──────┬───────┘    └──────────────┘
                                           │ on CLEAN: copy + delete
                                           ▼
                                    ┌──────────────┐
                                    │ clean bucket │  (API SA: read-only,
                                    │              │   scanner SA: write-only)
                                    └──────────────┘
                                           ▲
                                           │ V4 signed read URL (5 min)
                                    download from API after status=CLEAN
```

Metadata sits in Cloud SQL for PostgreSQL on a private IP, reached from Cloud Run via a Serverless VPC Access connector. Secrets (DB password, AV API key) live in Secret Manager. Outbound traffic to the AV vendor leaves via Cloud NAT with a static IP so the vendor can allowlist a single address. Observability is fully managed: Cloud Logging, Monitoring, Error Reporting, Trace.

---

## 3. Architecture choices and trade-offs

Every important decision is recorded in `docs/architecture.md` with the alternative that was rejected and why. The section below is a faithful condensation, including the trade-offs we accept.

### 3.1 Compute — Cloud Run for both API and scanner

**Chosen.** Two Cloud Run services, **same container image**, distinguished by `SPRING_PROFILES_ACTIVE` (`api` vs `scanner`). API ingress is `INTERNAL_LOAD_BALANCER`; scanner ingress is `INTERNAL_ONLY` and is invoked via Pub/Sub push.

- **Rejected — GKE Autopilot.** Explicitly forbidden by the brief, and would add unjustified ops burden (node upgrades, cluster maintenance) for a 3-dev team with no ops.
- **Rejected — One Cloud Run service handling both upload/download and Pub/Sub push.** That collapses the two runtimes into a single SA, which would have to hold both `storage.objectViewer` on `quarantine` (to stream the file to the AV vendor) **and** the AV vendor API key. The §2.3 invariant ("an unscanned file is never downloadable") would then rest on application logic alone. We refuse to take that bet for the central security invariant of this service.
- **Rejected — Two separate Spring Boot codebases / two Docker images.** Duplicates the build, test suite, dependency upgrades, and on-call surface. The existing service is one Spring Boot app; forcing a code split on three developers is unjustified.

**Trade-off accepted.** Both Cloud Run revisions pull the same image — a vulnerability in any shared bean appears in both runtimes. The mitigation is the IAM split: even if the API process were exploited, it has no read access to `quarantine` and no access to the AV key, so the §2.3 invariant still holds.

### 3.2 File storage — two buckets, IAM-enforced separation

**Chosen.** Cloud Storage with `quarantine` and `clean` buckets. Uniform bucket-level access, `public_access_prevention = enforced`, versioning on `clean`. The API SA cannot read `quarantine`; the scanner SA cannot write to it after the promotion step (it can read and delete). Only the scanner SA can write to `clean`; the API SA reads from `clean`.

- **Rejected — Single bucket with a metadata flag (`scanned=true`).** Makes the invariant a property of application code, not of IAM. One buggy branch in the download handler could leak unscanned files. With two buckets, the API SA literally lacks the permission to sign a URL for `quarantine` — the invariant is enforceable at the storage layer.

**Trade-off accepted.** Two buckets cost slightly more in metadata operations and require a copy at promotion. Acceptable in exchange for an IAM-grounded security invariant.

### 3.3 Large uploads — direct browser → GCS via signed URL

**Chosen.** The API mints a short-lived V4 signed URL (15 min, scoped to the exact object name + content-type) and the browser performs a resumable upload **directly to GCS**. The API never sees the bytes.

- **Rejected — Multipart upload proxied through the API.** Cloud Run has a 32 MiB request body limit and is the wrong layer to stream hundreds of MB. Also wastes CPU/memory budget on byte shovelling.

**Trade-off accepted.** The signed URL is a credential. We compensate with very short TTL, exact-object scoping, and content-type pinning. Frontend code must handle resumable upload semantics (chunking, retries) — this is a standard GCS SDK affair.

### 3.4 Async pipeline — GCS event → Pub/Sub → scanner

**Chosen.** GCS `OBJECT_FINALIZE` notification → Pub/Sub topic `scan-requests` → Cloud Run scanner via push subscription. Ack deadline 600 s, backoff 10 s → 600 s, max 6 attempts, dead-letter topic `scan-dlq`.

- **Rejected — Cloud Tasks queued from the API after upload completion.** Would make the API the source of truth for enqueueing, adding a failure mode: "upload finished, API forgot to enqueue".
- **Variance from `docs/architecture.md` §1.7.** That section described Eventarc; the implementation uses a direct GCS notification feeding the same Pub/Sub topic. Semantics are identical; the direct notification lets Terraform own the subscription knobs cleanly. Logged in `docs/progress.md` step 8.

**Trade-off accepted.** A failed AV scan ages in the DLQ until an operator replays it. We mitigate with an alert on `num_undelivered_messages > 0` and a documented replay procedure in the runbook.

### 3.5 Database — Cloud SQL for PostgreSQL, smallest tier, private IP

**Chosen.** PG 15 on `db-custom-1-3840`, private IP only (`ipv4_enabled = false`), SSL `ENCRYPTED_ONLY`, automated backups (7 retained) + 7-day PITR. Prod uses REGIONAL HA; dev is ZONAL with `deletion_protection = false`.

- **Rejected — AlloyDB.** Overkill at this volume and roughly 5× the cost.
- **Rejected — Firestore.** Would force a data-model rewrite and weaken the consistency guarantees needed by the scan-status state machine.

**Trade-off accepted.** Prod HA is regional, not multi-region. CLAUDE.md excludes multi-region, and the cost / complexity is not justified by the stated scale.

### 3.6 CI/CD — Workload Identity Federation, two distinct pools

**Chosen.** Two WIF pools, completely separate: one for this infra repo (`infra-github`), one for the application repo (`github-actions`). The infra pool federates two SAs — `infra-plan` (read-only, federable from any branch / PR) and `infra-apply` (admin, federable **only** from `refs/heads/main`). Branch lock is enforced inside the WIF binding via `attribute.repository_ref`, so even a leaked workflow secret cannot mint an apply token from a non-main branch.

- **Rejected — Exported JSON service-account keys.** Forbidden by the brief, and the standard exfiltration vector.
- **Rejected — One shared WIF pool for both repos.** A compromise of the application repo would put the infra apply SA within reach. Two pools = surgical blast radius.

**Trade-off accepted.** Two WIF pools to maintain instead of one. The duplication is mechanical (Terraform), and the isolation is worth it.

### 3.7 Apply gating — plan → manual approval → apply on a frozen plan

**Chosen.** On every push to `main`, the workflow plans per env, uploads the plan artifact, then waits on a **GitHub Environment approval gate**. The apply job consumes the **frozen `tfplan`** (no var-file, no re-plan), so what was approved is exactly what executes. `apply-prod` requires `apply-dev` to have succeeded first.

- **Rejected — Auto-apply on merge.** Too easy to deploy a surprise. The team has no ops; a 30-second human review of the plan is cheap insurance.
- **Rejected — Re-plan inside the apply job.** Reintroduces drift between what was approved and what runs.

**Trade-off accepted.** Adds a manual click. We consider that a feature, not a bug.

### 3.8 Edge — external HTTPS LB + Cloud CDN + GCS for the SPA

**Chosen.** Global IP + Google-managed cert. URL map routes `/api/*` to a Serverless NEG fronting the Cloud Run API, default to a CDN-fronted backend bucket holding the SPA. HTTP redirects to HTTPS. The Cloud Run API has `allUsers` invoker but ingress is `INTERNAL_LOAD_BALANCER`, so it is reachable only via the LB.

- **Rejected — Firebase Hosting.** Introduces a second platform / billing surface for no real gain.
- **Rejected — Serving the SPA from Cloud Run.** Wastes cold starts and CPU for static files.

**Trade-off accepted — frontend bucket exception.** The frontend bucket has `public_access_prevention = inherited` and `allUsers:objectViewer`, scoped so the LB origin can fetch SPA assets anonymously. This is the only public-read object in the project; `quarantine` and `clean` both keep `PAP = enforced`. Documented as a scoped exception in the runbook.

### 3.9 Observability — managed only

**Chosen.** Cloud Logging, Monitoring, Error Reporting, Trace. Three alerts: API 5xx rate, scan-requests oldest unacked age (>15 min), `scan-dlq-sub.num_undelivered_messages > 0`. Optional email notification channel.

- **Rejected — Self-hosted Prometheus/Grafana/Loki.** Excluded by the brief, and unjustified ops burden.

**Trade-off accepted.** No custom dashboards out of the box. The three alerts cover the failure modes the architecture explicitly plans for; deeper observability can be added on demand.

### 3.10 Networking — single region, NAT static IP, STANDARD tier

**Chosen.** One VPC, one `/24` subnet in `europe-west1`. Serverless VPC connector bridges Cloud Run to Cloud SQL on private IP. Cloud NAT egress with a manually allocated **STANDARD-tier** static IP (regional NAT does not need PREMIUM global routing — STANDARD is cheaper and equivalent here).

**Trade-off accepted.** Single region. CLAUDE.md excludes multi-region; we do not pay for what we do not need.

### 3.11 Least-privilege admin role list

**Chosen.** The `infra-apply` SA holds an **explicit list of admin roles** covering each Google service Terraform touches, instead of `roles/owner` or `roles/editor` (both forbidden by the terraform-gcp skill). Adding a new managed service (e.g. Cloud DNS) means appending its admin role here.

**Trade-off accepted.** This is real maintenance cost — the alternative (`roles/editor`) is one IAM mistake away from owning the project. The cost is documented and accepted.

---

## 4. The three explicit challenges

The brief calls out three things the solution must address explicitly. They are detailed in `docs/architecture.md` §2; the summary:

1. **Uploads up to several hundred MB.** Direct browser → GCS resumable upload via short-lived V4 signed URL. Bytes never traverse Cloud Run. The 32 MiB request limit and Cloud Run memory budget are irrelevant.
2. **Resilience to the third-party AV API.** Decoupled async pipeline. The user never waits for the AV. Pub/Sub provides bounded retries with exponential backoff and a DLQ. The scanner is idempotent (keyed on `(bucket, object, generation)` + a PostgreSQL advisory lock). AV slowness only grows the queue; AV outage is bounded and alerted; the system self-heals.
3. **Invariant: an unscanned file is never downloadable.** Enforced at the IAM and storage layer. The API SA has no read on `quarantine` and cannot mint signed URLs against it. The scanner is the only path to `clean`, and only after an unambiguous `CLEAN` verdict. Defense in depth: a buggy API request signer literally cannot produce a `quarantine` URL because the SA lacks the permission.

---

## 5. Repository layout

```
.
├── README.md                 # this file
├── CLAUDE.md                 # project guardrails (AI-assisted workflow)
├── Makefile                  # init / fmt / validate / plan / apply per env
├── .terraform-version        # CLI version pin
├── .pre-commit-config.yaml   # fmt + validate + tflint + Trivy + hygiene
├── docs/
│   ├── architecture.md       # decisions, alternatives, the three challenges
│   ├── runbook.md            # ops manual: bootstrap, daily flow, recovery
│   ├── dev-requirements.md   # app-team checklist + reference Dockerfile
│   └── progress.md           # phase-by-phase build log
├── handoff/                  # drop-in starter kit for the application repo
│   ├── README.md
│   └── .github/workflows/deploy.yml
├── terraform/
│   ├── envs/                 # *.example.tfvars + backend-*.example.hcl
│   ├── modules/
│   │   ├── network/          # VPC, subnet, Cloud NAT, VPC connector
│   │   ├── service-accounts/ # praxedo-api + praxedo-scanner SAs
│   │   ├── artifact-registry/
│   │   ├── storage/          # quarantine + clean buckets, IAM split
│   │   ├── database/         # Cloud SQL (private IP, backups, PITR)
│   │   ├── secrets/          # DB password + AV API key
│   │   ├── compute/          # both Cloud Run services
│   │   ├── eventing/         # GCS notification → Pub/Sub + DLQ + push sub
│   │   ├── edge/             # external HTTPS LB + CDN + managed cert
│   │   ├── observability/    # alerts + notification channels
│   │   ├── cicd/             # app pipeline WIF pool + deploy SA
│   │   └── infra-cicd/       # infra pipeline WIF pool + plan + apply SAs
│   └── (root: versions, providers, backend, locals, apis, outputs)
├── .github/
│   ├── CODEOWNERS
│   ├── actions/tf-setup/     # composite action: install + WIF + init
│   └── workflows/
│       ├── terraform-checks.yml   # PR: fmt + validate + tflint + Trivy + plan
│       ├── terraform-deploy.yml   # main: plan → approval gate → apply
│       ├── terraform-drift.yml    # daily drift detection on main
│       └── pr-title.yml           # Conventional Commits lint
└── prompts/                  # AI-assisted workflow disclosure (FR)
```

---

## 6. Getting started

Day-to-day commands live in `docs/runbook.md`; the short version:

```sh
# One-time per env — provision the GCS state bucket (see runbook §2).

# Daily flow.
make init  ENV=dev
make plan  ENV=dev
make apply ENV=dev
```

Workspace must match the env; the `default` workspace is rejected by a `check` block in `terraform/locals.tf`. The first apply must be performed by a human owner (bootstrap of the infra WIF pool itself); subsequent applies go through the CI gate.

---

## 7. Hypotheses

The architecture rests on the following explicit assumptions. Each must be confirmed or invalidated by the evaluator / the team before any production go-live.

1. **Region**: single region `europe-west1`. Latency to French users is acceptable; CLAUDE.md excludes multi-region.
2. **Traffic profile**: peak concurrent users in the low hundreds; sustained throughput well below Cloud Run / Cloud SQL smallest-tier limits.
3. **File size distribution**: long-tail with a few-hundred-MB upper bound, no GB-scale files. Resumable upload covers the upper bound.
4. **End-user authentication**: handled by the application (e.g. Spring Security with an external IdP). Out of scope of this infra repo. The infra exposes the API on HTTPS via the load balancer and trusts the app to authenticate callers.
5. **AV vendor API**: HTTP-based, accepts either a file payload or a temporary signed URL. Documented retry semantics. Supports egress-IP allowlisting (justifying the Cloud NAT static IP).
6. **Database engine**: PostgreSQL 15+. No need for AlloyDB-class throughput.
7. **Environments**: `dev` and `prod` only for this technical test. No `staging`.
8. **Two repos**: this infra repo and a separate application repo owned by the 3 backend devs. App CI uses the WIF provider this repo exposes.
9. **Backup / DR**: Cloud SQL automated daily backups + 7-day PITR; GCS `clean` bucket versioning + 30-day non-current retention. No cross-region replication.
10. **Cost ceiling**: expected to be in the low tens of EUR/month at idle, scaling with usage. Sized accordingly.
11. **Frontend deployment**: SPA build artefact uploaded to the `frontend-assets` bucket and served via the load balancer. The application repo handles the build/upload step; this repo provisions the bucket + LB + CDN + WIF binding.
12. **PII / RGPD**: no specific encryption requirements beyond default Google-managed encryption at rest. CMEK can be layered in later if requested.
13. **Backend codebase**: two Spring profiles, `api` and `scanner`, in the same module. The original service is one Spring Boot app; the architecture extends it (not splits it) by activating different `@Profile` beans in the two Cloud Run services. If the team prefers a different code organisation, the infra side is unchanged: Cloud Run still runs two services and `SPRING_PROFILES_ACTIVE` is just an env var any layout can interpret.

---

## 8. What this repo deliberately does **not** do

- No GKE, no Kubernetes, no service mesh. Cloud Run is enough at this scale.
- No multi-region. Out of scope per the brief.
- No self-hosted monitoring stack. Managed GCP observability covers the SLOs.
- No application deployment. The 3-dev team owns that pipeline; `handoff/` is the starter kit.
- No service-account keys, exported or otherwise. WIF + OIDC, end to end.
- No silent `roles/owner` or `roles/editor`. The admin SA holds an explicit role list.

---

## 9. AI-assisted workflow

This project was built with human-supervised AI assistance. The methodology, prompts, and reasoning trail are documented in `prompts/README.md`. Every decision was reviewed; nothing was merged without a human signing off. The `CLAUDE.md` file at the repo root holds the durable guardrails that scoped every working session.
