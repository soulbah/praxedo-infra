# Praxedo File Service — Production Infrastructure

## Context
SRE technical test. Deploy an existing file-management service to production following current best practices.

The service: REST API (Java/Spring Boot) + React frontend. Users upload and download files; metadata stored in a database. Antivirus scanning is delegated to a third-party API. A file MUST be scanned clean before it can ever be downloaded.

Scale: a few hundred users, files from a few KB to several hundred MB.
Team: 3 backend developers, NO dedicated ops profile.

## Non-negotiable principles
- Right-size for the described load. No over-engineering. When in doubt, pick the simpler managed option.
- The solution must be operable by 3 developers without ops. Any decision that adds operational burden must be explicitly justified.
- Target cloud: GCP.
- Three challenges must be addressed explicitly, not glossed over: large file uploads, resilience to the third-party antivirus API, and the invariant that an unscanned file is never downloadable.
- App deployment authenticates via Workload Identity Federation (OIDC). No stored service-account keys, ever.
- Two distinct pipelines, never confused: the infra lifecycle (this repo) and the application deployment (the developers' repo). We make their deployment possible, secure and standardized — we do not deploy for them.

## Working method
- Scope the architecture before writing any code. Validate it, then build incrementally, pausing for review between logical steps.
- Durable context lives in CLAUDE.md and docs/, never in chat history.
- Use /clear when switching between project phases, then reload only the relevant doc once (e.g. docs/architecture.md) to re-prime.
- When compacting, always preserve the list of modified files, the validated steps from docs/progress.md, and any pending review items.
- Commit after each validated step using Conventional Commits. Keep commits (no refs to claude or anthropic) atomic and scoped to one logical change.
- Comment the WHY, not the WHAT.

## Out of scope (do not add)
- No GKE / Kubernetes / service mesh.
- No multi-region.
- No self-hosted monitoring stack; managed GCP observability is enough.