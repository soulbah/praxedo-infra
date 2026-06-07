# AI-assisted workflow

This folder contains every prompt that was given to the assistant during the build of this infrastructure. They are committed on purpose: the technical test asks for the prompts to be stored alongside the artefacts, and reading them in order is the fastest way for anyone (a reviewer, a future maintainer, a teammate picking up the repo) to reconstruct how each piece was decided.

The point of this document is not to claim that AI built the infrastructure. It did not. The method below is what produced something usable; remove any one of the four pieces and the result degrades quickly. The assistant was a *supervised accelerator*, not an autopilot.

---

## 1. The method

Four phases. The same loop every time.

### 1.1 Scope the problem and the constraints first

Before any code, we wrote `CLAUDE.md` at the root of the repo. It is short on purpose. It states the business context, the three non-negotiable challenges from the exercise (large uploads, AV resilience, the §2.3 invariant), the team size and shape (3 backend devs, no ops), the target cloud (GCP), the explicit out-of-scope list (no GKE, no multi-region, no self-hosted observability), and the security floor (WIF only, no JSON keys, ever).

`CLAUDE.md` is loaded on every assistant turn. It is the layer that prevents the model from drifting into "best practice" templates that do not fit a 3-dev no-ops team — every time the assistant proposed something heavier than required, the file is what we pointed to.

A second guardrail lives at `.claude/skills/terraform-gcp/SKILL.md`: the security defaults the assistant must apply on every Terraform write or edit (least privilege, private IPs, bucket controls, no `roles/owner|editor`, no committed SA keys, pinned providers, mandatory `terraform fmt`+`validate`). It is referenced explicitly from the early prompts (see `01-terraform-skill.md`).

### 1.2 Hand the design to the model under explicit guardrails

Once the constraints were written down, the architecture was scoped by the model and reviewed by the human (`02-architecture-scoping.md`). The output is `docs/architecture.md`: one decision per subsection, the alternative considered, the justification. It was deliberately written *before* any Terraform was authored. From that point on, every later prompt could refer to a numbered decision in the architecture rather than re-litigating it.

Two things made this work:

- The guardrails are *named in the prompts themselves*. "Respect the `terraform-gcp` skill", "remember the two-pipeline separation from CLAUDE.md", "no over-engineering, fit for 3 devs no ops". The model is reminded each turn, even though the file is already loaded — the reminder is what triggers the model to re-check itself rather than re-derive.
- The design was scoped, then validated, *before* implementation. The model did not pick the architecture mid-implementation; it picked it, the human read it end to end, and only then did Terraform code start landing.

### 1.3 Validate at each step

Every prompt asks for a single coherent step: foundations, then network + storage, then storage IAM split, then secrets/DB/compute, then events/edge, then CI/CD, etc. After each step the human:

- reads the diff,
- asks for changes ("trim the CODEOWNERS to one team, you're over-engineering", "this prompt is too long", "you used an anglicism in a French file"),
- and only then validates the commit.

`docs/progress.md` is the durable trace of this: one row per step, status, and the substantive notes for what landed. It is the source of truth between sessions — when `/clear` was used to drop chat context, `progress.md` was reloaded to re-prime, not the chat history. The chat is volatile, the docs are not.

Two corrections that this loop caught are worth naming, because they are exactly the kind of mistake an unsupervised model makes:

- **The scanner runtime model** (`07-scanner-runtime-model.md`). The first pass silently assumed the team would split their single Spring Boot codebase into two repos for the api and the scanner. Re-reading the exercise statement caught it. The fix kept the IAM-enforced §2.3 invariant (two services, two SAs) but collapsed back to one codebase, one image, two Spring profiles. This is what supervision is for — the model produced something internally consistent but at odds with the actual constraint.
- **PR-gate scope creep**. A first iteration of the CI/CD added a CODEOWNERS split into security/architecture/* groups and a drift workflow that opened, updated and closed GitHub issues. Reasonable in a larger company; pure over-engineering for 3 devs. The fix trimmed both back to the minimum (`-127`/`+31` lines on that commit). Without `CLAUDE.md` to point at, this drift would have shipped.

### 1.4 Final review in a fresh context

The chat window accumulates assumptions. The clean check is to drop the chat (or open a fresh session) and re-read the full diff, the architecture, the runbook, the handoff, and the dev requirements, with only `CLAUDE.md` and `docs/` as primer. Anything that does not survive that re-read gets rewritten — that is how the runbook's hard line-wraps got unwrapped, how `dev-requirements.md` was sized for a 3-dev no-ops audience rather than a hypothetical reader, and how the architecture's §1.2 was rewritten with the alternatives explicitly rejected once the scanner runtime model changed.

---

## 2. The role of `CLAUDE.md`

`CLAUDE.md` is the contract. Every prompt below is short because the contract is doing the heavy lifting. The prompts say *what* step to take next; `CLAUDE.md` says *what is in and out of bounds* for every step.

What lives there, in short:

- Right-sizing rule ("no over-engineering, when in doubt pick the simpler managed option").
- Operability rule ("must be operable by 3 devs without ops; any decision adding operational burden must be justified").
- The three non-negotiable challenges from the exercise (uploads, AV resilience, §2.3 invariant).
- The two-pipeline separation ("infra lifecycle here, application deployment in the developers' repo — we make their deployment possible, secure and standardized; we do not deploy for them").
- Working method (scope first, validate, commit in Conventional Commits, comment the *why* not the *what*).
- Out-of-scope list (no GKE, no multi-region, no self-hosted monitoring).

When a prompt produced something at odds with one of these, the correction was always to point at the rule, not to re-explain it. The model corrects itself reliably when the rule is named.

---

## 3. What the assistant did, and did not

**Did**:

- Drafted the architecture document and iterated it under review.
- Wrote every Terraform module and the two CI/CD workflows.
- Wrote the runbook, the developer prerequisites, the handoff workflow and its README.
- Caught syntax mistakes, restructured prose on request, kept `docs/progress.md` synchronized.

**Did not**:

- Pick the architecture without the human reading it first.
- Commit anything that the human had not validated.
- Choose what was in scope or out of scope; that lived in `CLAUDE.md` from day one.
- Run anything against a live GCP project. The technical test deliverable is the repo, not a deployed environment.

---

## 4. Prompt index

In execution order:

| # | File | What it produced |
|---|---|---|
| 0 | [`00-init-gitignore.md`](./00-init-gitignore.md) | Initial repo bootstrap (git init, .gitignore for Terraform). |
| 1 | [`01-terraform-skill.md`](./01-terraform-skill.md) | Installed the `terraform-gcp` skill at `.claude/skills/terraform-gcp/SKILL.md` as the per-edit security floor. |
| 2 | [`02-architecture-scoping.md`](./02-architecture-scoping.md) | `docs/architecture.md` — one decision per section, alternatives, justifications, hypotheses. |
| 3 | [`03-terraform-foundations.md`](./03-terraform-foundations.md) | Pinned providers, GCS remote state, project APIs, workspace-per-env (`dev`/`prod`). |
| 4 | [`04-infra-modules.md`](./04-infra-modules.md) | Application modules: network, storage with §2.3 IAM split, secrets, Cloud SQL private-IP, Cloud Run, Pub/Sub, edge LB+CDN, observability. |
| 5 | [`05-infra-cicd.md`](./05-infra-cicd.md) | Infra repo CI/CD: WIF OIDC (no SA keys), plan → GH Environment gate → apply on frozen `tfplan`, drift detection. |
| 6 | [`06-app-deploy-foundations.md`](./06-app-deploy-foundations.md) | Application repo handoff: WIF outputs, reference GitHub Actions workflow, variable map. |
| 7 | [`07-scanner-runtime-model.md`](./07-scanner-runtime-model.md) | Scanner correction: one image, two Spring profiles. Documented as an explicit hypothesis in `architecture.md`. |
| 8 | [`08-dev-prerequisites.md`](./08-dev-prerequisites.md) | `docs/dev-requirements.md`: actionable checklist + reference multi-stage Dockerfile for the backend team. |

---

## 5. If you reproduce this method

Three things that would have made the result worse if removed:

1. **`CLAUDE.md` written before the first prompt.** Without it, every later prompt has to re-state constraints, the model picks defaults that fit a larger company, and the corrections pile up.
2. **One step at a time, validated before commit.** Long multi-step prompts produce diffs that are hard to review and that bury wrong assumptions inside correct code.
3. **A fresh-context re-read at the end.** The chat normalizes whatever has been said before; a clean read against the source documents is the only way to catch the assumptions you stopped questioning halfway through.

The AI part is the accelerator. The supervision is what makes the output trustworthy.
