# Architecture — Praxedo File Service on GCP

Reference document. Validated before any Terraform is written. Every later step (modules, IAM, pipelines) flows from here.

Guiding constraint: 3 backend developers, no ops profile, a few hundred users, files up to several hundred MB. Right-sized managed services only. Cloud Run-centric serverless. No GKE, no multi-region.

---

## 1. Decisions

### 1.1 Compute — REST API (Spring Boot)

- **Choice**: **Cloud Run** (service, container).
- **Alternative rejected**: GKE Autopilot.
- **Justification**: Cloud Run runs a Spring Boot container with zero infra to operate (no nodes, no upgrades), scales to zero, integrates natively with WIF, Secret Manager, Cloud SQL connector, and VPC egress. GKE is explicitly excluded by CLAUDE.md and would add unjustified ops burden for a 3-dev team.

### 1.2 Compute — Antivirus scanner worker

- **Choice**: **Cloud Run** service, separate from the API, **sharing the same container image and the same Spring Boot codebase** as the API. The two services are distinguished by `SPRING_PROFILES_ACTIVE` (`api` vs `scanner`), which Cloud Run injects as an env var on each service. The scanner is invoked asynchronously by Pub/Sub push.
- **Alternatives rejected**:
  - Cloud Run *Functions* (2nd gen) on a GCS Eventarc trigger — tighter execution model and less ergonomic Java packaging.
  - **A single Cloud Run service that handles both upload/download and the Pub/Sub push handler** — collapses the two runtimes into one SA, which would have to hold both `storage.objectViewer` on `quarantine` (to stream the file to the AV vendor) **and** the AV vendor API key (mounted from Secret Manager). At that point the §2.3 invariant ("an unscanned file is never downloadable") would rest on application logic, not IAM. We refuse to take that bet for the central security invariant of this service.
  - **Two separate Spring Boot codebases / two separate Docker images** — duplicates the build, the test suite, the dependency upgrades, and the on-call surface. The existing app is a single Spring Boot service; forcing a code split on a 3-dev team is unjustified operational burden.
- **Justification**: A dedicated Cloud Run service gives full control over timeout (up to 60 min, useful when the third-party AV API is slow), retry policy, concurrency, and ingress (`INTERNAL_ONLY` so the scanner URL cannot be hit from the public internet). Reusing the same image as the API keeps the build / test / release loop to a single artefact for the 3-dev team. Splitting only at the runtime / IAM layer is what makes the §2.3 invariant enforceable at the storage IAM boundary (see §2.3).

The application-side responsibility is small: register beans with `@Profile("api")` or `@Profile("scanner")` on the controllers that should only exist on one of the two runtimes. Shared infrastructure beans (JPA, common services) carry no `@Profile` annotation and load in both. Handoff details: `handoff/README.md` §1 + reference workflow.

### 1.3 Compute — Frontend (React SPA)

- **Choice**: **Cloud Storage bucket + external HTTPS Load Balancer + Cloud CDN**.
- **Alternative rejected**: Serving the SPA from the same Cloud Run as the API, or Firebase Hosting.
- **Justification**: Static assets behind Cloud CDN are the cheapest and most reliable pattern, and decouple frontend deploys from API deploys. Cloud Run for static files wastes cold starts and CPU. Firebase Hosting works but introduces a second platform / billing surface for no real gain at this scale.

### 1.4 File storage

- **Choice**: **Cloud Storage**, with **two separate buckets**: `quarantine` (untrusted, post-upload) and `clean` (scan-validated, source for downloads). Uniform bucket-level access, `public_access_prevention = enforced`, versioning on `clean`.
- **Alternative rejected**: Single bucket with an object-metadata flag (`scanned=true`) gating access.
- **Justification**: Two buckets make the invariant enforceable at the **IAM layer**, not at app logic level: the API's service account has zero read permission on `quarantine`, so it physically cannot issue a download URL for an unscanned file even if a bug tries to. A single-bucket design would rely on app code never making a mistake — unacceptable for a security-critical invariant. Filestore / Persistent Disk are over-engineered for blob storage at this scale.

### 1.5 Upload path — large files

- **Choice**: **Direct browser → GCS resumable upload** using a short-lived V4 signed URL minted by the API.
- **Alternative rejected**: Multipart upload proxied through the Cloud Run API.
- **Justification**: Cloud Run has a hard 32 MiB request body limit and is the wrong layer to stream hundreds of MB. Resumable upload natively chunks the file, survives connection drops, and removes CPU/memory load from the API. Detail in §2.1.

### 1.6 Metadata database

- **Choice**: **Cloud SQL for PostgreSQL**, smallest tier (`db-g1-small` or `db-custom-1-3840`), **private IP only**, automated backups, point-in-time recovery enabled.
- **Alternative rejected**: AlloyDB, Firestore.
- **Justification**: Spring Boot teams know JPA/PostgreSQL; metadata is relational (files, owners, scan status, audit). AlloyDB is overkill at this volume and ~5× the cost. Firestore would force a model rewrite and is weaker on the consistency guarantees needed for the scan-status invariant.

### 1.7 Async / event pipeline

- **Choice**: **GCS object-finalize event → Eventarc → Pub/Sub topic `scan-requests` → Cloud Run scanner (push subscription)**, with dead-letter topic `scan-dlq` after N retries and exponential backoff.
- **Alternative rejected**: Cloud Tasks queued from the API after upload completion.
- **Justification**: Triggering on the GCS finalize event removes a class of bugs ("upload finished but API never enqueued the task"). Pub/Sub provides native retry/backoff/DLQ, which is exactly the resilience surface we need for the third-party AV (§2.2). Cloud Tasks would require the API to be the source of truth for enqueueing, adding a failure mode.

### 1.8 Secrets

- **Choice**: **Secret Manager**. Referenced from Cloud Run as mounted secrets or env-var-from-secret. AV API key and DB credentials live there only.
- **Alternative rejected**: Environment variables baked into the Cloud Run revision, or HashiCorp Vault.
- **Justification**: Secret Manager has native Cloud Run integration, audit logs, versioning, IAM. Vault is unjustified ops burden for 3 devs without ops.

### 1.9 Networking

- **Choice**: Dedicated **VPC** with a `/24` subnet, **Serverless VPC Access connector** for Cloud Run → Cloud SQL (private IP), Cloud NAT for outbound to the AV API.
- **Alternative rejected**: Cloud SQL with public IP + authorized networks, or Direct VPC egress without a connector.
- **Justification**: Private IP for the DB is non-negotiable per the security skill. Cloud NAT gives a stable egress IP that can be whitelisted by the third-party AV vendor if needed. Direct VPC egress on Cloud Run is viable but the connector is the more proven default for now.

### 1.10 Container registry

- **Choice**: **Artifact Registry**, one Docker repository per environment (`dev`, `prod`).
- **Alternative rejected**: Container Registry (deprecated).
- **Justification**: Artifact Registry is the current GA product, supports vulnerability scanning, integrates with Cloud Build / GitHub Actions via WIF.

### 1.11 CI/CD authentication (app deployment)

- **Choice**: **Workload Identity Federation** binding the developers' GitHub repo to a deploy service account scoped to push images and update Cloud Run revisions. **This repo provisions the WIF pool/provider and the deploy SA; it does not run the app pipeline.**
- **Alternative rejected**: Exported JSON service account keys stored as GitHub secrets.
- **Justification**: Mandated by CLAUDE.md. Eliminates the long-lived-key exfiltration risk and matches the two-pipeline separation.

### 1.12 Observability

- **Choice**: **Cloud Logging + Cloud Monitoring + Error Reporting + Cloud Trace**, with a small set of SLO alerts (5xx rate, upload-to-scan latency, scan DLQ depth) routed to email/Slack via Notification Channels.
- **Alternative rejected**: Self-hosted Prometheus/Grafana/Loki.
- **Justification**: Excluded by CLAUDE.md, and managed observability covers the SLOs needed at this scale with zero ops.

### 1.13 Environments

- **Choice**: Two GCP projects: `praxedo-file-dev` and `praxedo-file-prod`, identical Terraform code, env-specific tfvars. Shared root for IAM/folders kept minimal.
- **Alternative rejected**: Single project with environment suffixes on resources.
- **Justification**: Project-level isolation is the cleanest GCP blast-radius boundary and aligns IAM cleanly. Cost overhead is negligible at this size.

---

## 2. The three explicit challenges

### 2.1 Uploads up to several hundred MB

Mechanism: **direct-to-GCS resumable upload via short-lived V4 signed URL**.

Flow:
1. Client calls `POST /files` on the API with file metadata (name, size, content-type).
2. The API creates a DB row with `status = PENDING_UPLOAD`, then calls `signBlob` on the GCS object path in the `quarantine` bucket to mint a V4 signed URL for resumable upload (TTL 15 min, restricted to the exact object name and content-type).
3. Client performs the resumable upload directly to GCS, chunked, retryable.
4. GCS object-finalize event fires → Eventarc → Pub/Sub → scanner (see §2.2 and §2.3).

Why this satisfies the constraint: bytes never traverse Cloud Run, so the 32 MiB request limit and the Cloud Run memory budget are irrelevant. Resumable upload natively handles transient network failures across hundreds of MB. The signed URL is scoped to one object and short-lived, so it cannot be reused to upload to another path.

### 2.2 Resilience to the third-party AV API (slowness, outage, unavailability)

Mechanism: **asynchronous pipeline with bounded retries, exponential backoff, dead-letter, and an idempotent worker**.

- The scan is **decoupled** from the upload: the user never waits for the AV API. The upload returns 202 with `status = PENDING_SCAN`.
- The scanner Cloud Run service is invoked from a **Pub/Sub push subscription** with: `ack_deadline = 600s`, `min_backoff = 10s`, `max_backoff = 600s`, max delivery attempts = 6, **dead-letter topic** `scan-dlq`.
- The scanner is **idempotent**: it keys on `(bucket, object, generation)` and a DB advisory lock so duplicate Pub/Sub deliveries are safe.
- The scanner uses a **circuit breaker + timeouts** on the AV HTTP client (connect 5s, read 120s, overall 300s). On 5xx / timeout, it returns a non-ack error → Pub/Sub retries with backoff.
- If a message hits the DLQ, the DB row is flagged `status = SCAN_FAILED` and an alert fires; the object stays in `quarantine`. A small re-drive Cloud Run Job (manual or scheduled) can replay DLQ when the vendor recovers.
- Status state machine in DB: `PENDING_UPLOAD → PENDING_SCAN → SCANNING → CLEAN | INFECTED | SCAN_FAILED`. Only the scanner SA can transition out of `SCANNING`.

Why this satisfies the constraint: AV slowness only grows the queue, never blocks user uploads; AV outage is bounded by retries+DLQ and surfaced via alerts; the system self-heals when the vendor returns.

### 2.3 Invariant — an unscanned file must NEVER be downloadable

Mechanism: **enforced at the IAM and storage layer, not at app-logic layer**.

1. **Two buckets**:
   - `quarantine`: receives all uploads. **The API service account has no read/get-object permission on it.** Only the scanner SA can read.
   - `clean`: only the scanner SA can write to it. The API SA has read-only access.
2. **Promotion is the only path to `clean`**: the scanner, *after* receiving an unambiguous `CLEAN` verdict from the AV API, performs `copy(quarantine → clean)` then `delete(quarantine)` and only then transitions the DB row to `status = CLEAN`. The DB write and the bucket promotion are wrapped in an idempotent flow keyed on object generation; on failure mid-flow, the object stays in `quarantine` and the row is not flipped.
3. **Download endpoint**: `GET /files/{id}/download` checks `status = CLEAN` in DB and, only then, mints a V4 signed read URL **against the `clean` bucket**. The signed URL TTL is short (5 min).
4. **Defense in depth**: even if a bug in the API tries to issue a signed URL for `quarantine`, the API SA lacks `iam.serviceAccounts.signBlob` permission against an identity that has read on `quarantine`, so URL signing physically fails. The IAM boundary is the source of truth.
5. **Lifecycle rule**: `quarantine` has a TTL (e.g. 7 days) deleting any object regardless of status, so an item stuck in `SCAN_FAILED` is eventually purged after triage.

Why this satisfies the constraint: the invariant holds even if app code is buggy, because the API process literally cannot read or sign URLs for unscanned objects.

---

## 3. Hypotheses

Explicit assumptions on which the architecture rests. Each must be confirmed or invalidated before build-out.

1. **Region**: single region `europe-west1`. Latency to French users is acceptable; CLAUDE.md excludes multi-region.
2. **Traffic profile**: peak concurrent users in the low hundreds; sustained throughput well below Cloud Run / Cloud SQL smallest-tier limits.
3. **File size distribution**: long-tail with a few-hundred-MB upper bound, no GB-scale files. Resumable upload covers the upper bound.
4. **End-user authentication**: handled by the application (e.g. Spring Security with an external IdP). Out of scope of this infra repo; the infra exposes the API on HTTPS via the load balancer and trusts the app to authenticate callers.
5. **AV vendor API**: HTTP-based, accepts either a file payload or a temporary signed URL. Has documented retry semantics and an egress IP whitelist option (justifying Cloud NAT).
6. **Database engine**: PostgreSQL 15+, no need for AlloyDB-class throughput.
7. **Two environments only**: `dev` and `prod`. No `staging` for the technical test.
8. **Two repos**: this infra repo and a separate application repo owned by the 3 backend devs. App CI uses the WIF provider this repo exposes.
9. **Backups and DR**: Cloud SQL automated daily backups + 7-day PITR, GCS clean bucket versioning + 30-day retention. No cross-region replication.
10. **Cost ceiling**: implicit but expected to be in the low tens of EUR/month at idle, scaling with usage. Sized accordingly.
11. **Frontend deployment**: SPA built artefact uploaded to a third bucket `frontend-assets` and served via the load balancer; the application repo handles the build/upload step, this repo provisions the bucket + LB + CDN + WIF binding.
12. **No PII/RGPD-specific encryption requirements** beyond default Google-managed encryption at rest. CMEK can be layered in later if requested.
13. **Backend codebase has two Spring profiles, `api` and `scanner`, in the same Maven/Gradle module.** The original Praxedo service is one Spring Boot app; the architecture extends it (not splits it) by activating different `@Profile` beans in the two Cloud Run services. The team owns this small code adjustment — see `handoff/README.md` §1. If the team prefers a different code organization (e.g. separate modules in a Maven multi-module build, or even separate repos), the infra side stays unchanged: Cloud Run still runs two services, each pulls the image identified in its revision, and `SPRING_PROFILES_ACTIVE` is an env var that any layout can interpret.
