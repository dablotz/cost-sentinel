---

## Postmortem: Adding pre-commit, Terraform tests, and the dashboard MVP

# Postmortem: DevEx + Testing + Dashboard MVP Hardening

Date range: 2026-02-20 to 2026-02-23
Systems: Terraform modules, AWS CodeBuild/CodePipeline, pre-commit tooling, S3 dashboard (static site)
Status: Resolved / implemented

---

## Summary

After the initial Cost Sentinel pipeline became functional, we prioritized hardening the developer experience and making changes safer and more repeatable. We implemented:

- Local pre-commit hooks for formatting, linting, and hygiene checks
- Terraform module tests using `terraform test` (mocked AWS provider)
- A minimal S3-hosted dashboard that displays `latest.json`, deployed via Terraform
- A `latest.json` placeholder to eliminate first-run onboarding friction

During implementation, several issues surfaced primarily in CI (CodeBuild) that did not always reproduce locally. These were resolved by making module code null-safe, eliminating brittle filesystem assumptions, and aligning local tooling with CI execution behavior.

---

## Impact

- **Positive:** Faster feedback loops locally, fewer pipeline failures due to formatting/syntax errors, and a working public dashboard with deterministic behavior on first load.
- **Negative:** Multiple CI iterations were required due to discrepancies between local runs and CodeBuild, particularly around Terraform evaluation of `null` and filesystem paths.

No production impact (project is in personal MVP stage).

---

## What changed

### 1) Pre-commit hooks added

**Goal:** Catch common issues before CI (Terraform formatting drift, YAML whitespace, Python lint, secrets, etc.)

**Implemented:**
- `pre-commit` with a standard set of hooks
- YAML linting for buildspec and config files
- Terraform formatting/validation hooks
- Python lint/format tooling (ruff)
- Optional secret scanning (detect-secrets baseline)

**Outcome:**
- Prevented repeated CI failures caused by minor syntax issues (e.g., missing whitespace or malformed YAML).

---

### 2) Terraform module tests added (`terraform test`)

**Goal:** Validate module behavior quickly and without AWS calls/cost.

**Implemented:**
- `infra/modules/sentinel/tests/basic`: dashboard enabled path
- `infra/modules/sentinel/tests/nodashboard`: dashboard disabled path (critical for conditional logic regressions)
- Mocked AWS provider during tests

**Outcome:**
- Caught multiple conditional/edge-case regressions early (dashboard disabled path, null-safe string handling, asset upload gating).

---

### 3) Dashboard MVP implemented (S3 static website)

**Goal:** Provide a functional “view” of the latest alert without adding server components.

**Implemented:**
- Public S3 bucket for the dashboard site assets (`index.html`, `app.js`) managed by Terraform
- Dashboard fetches `latest.json` and displays its contents
- Lambda writes `latest.json` when budget events occur (future/ongoing), while Terraform uploads a placeholder object for first-run usability

**Outcome:**
- Working dashboard that is immediately usable after deployment (no 403/404 confusion on first load).

---

## Incidents encountered and resolutions

### Incident A: CI failures due to `trimspace(null)` and non-short-circuit evaluation

**Symptoms (CI):**
- `Invalid function argument ... trimspace(str) ... argument must not be null`
- Appeared in resource `count` expressions, IAM policy conditionals, and outputs.

**Root cause:**
- Terraform does not guarantee short-circuit evaluation for `||` / `&&`.
- `trimspace()` cannot accept `null`.

**Resolution:**
- Normalize nullable strings using `try(trimspace(var.x), "")` and drive all conditionals from locals:
  - `dashboard_enabled`
  - `email_enabled`
- Update all outputs and conditionals to use the normalized values rather than re-trimming raw variables.

---

### Incident B: Module tried to locate repo root (filesystem brittleness)

**Symptoms:**
- `filemd5` / `open ... no such file or directory` during `terraform test`
- Worked in pipeline/local env but failed in module test contexts.

**Root cause:**
- Module attempted to compute repo root internally.
- `path.root` differs depending on invocation context (env apply vs test harness).

**Resolution:**
- Stop “guessing” repo structure inside the module.
- Treat `dashboard_web_dir` as **relative to the root module**, passed in by:
  - `infra/envs/dev` (CI apply context)
  - module tests (test harness context)
- Gate dashboard asset uploads so the disabled dashboard test does not evaluate `filemd5()` on non-existent files.

---

### Incident C: Public policy blocked for dashboard bucket (S3 Block Public Access)

**Symptoms:**
- `AccessDenied ... because public policies are prevented by BlockPublicPolicy`

**Root cause:**
- Bucket-level Public Access Block settings needed to allow public bucket policies, and/or apply ordering needed to ensure settings were applied before the policy.

**Resolution:**
- Ensure dashboard bucket `aws_s3_bucket_public_access_block` explicitly sets:
  - `block_public_policy = false`
  - `restrict_public_buckets = false`
- Ensure the bucket policy depends on the public access block resource (apply ordering).
- Proceeded with the minimal S3 website approach for MVP.

---

### Incident D: Dashboard showed `HTTP 403` for `latest.json` on first run

**Symptoms:**
- Dashboard loaded, but `fetch('./latest.json')` failed with `HTTP 403`.
- Alerts bucket initially empty.

**Root cause:**
- `latest.json` didn’t exist yet (no events ingested).
- First-run UX was confusing without a baseline object.

**Resolution:**
- Terraform uploads a placeholder `latest.json` during provisioning so the UI is deterministic on day one.
- Lambda overwrites it later when budget events occur.

---

## Why CI behaved differently than local

Primary reasons:
- Terraform evaluation paths exposed `null` handling issues only under specific tests (nodashboard).
- Different working directories (`path.root`) across env apply vs test harness.
- Local caches (`.terraform/`) can mask certain behaviors.
- Local Terraform version drift can change evaluation and diagnostics.

---

## Preventative actions implemented

- Pinned Terraform version (CI parity) and documented setup using `tfenv` + `.terraform-version`.
- Added `make ci-test` style target to:
  - wipe test `.terraform` caches
  - run tests directory-by-directory (CI-like)
- Standardized null/empty string normalization in module locals.
- Standardized how filesystem paths are provided to the module (`dashboard_web_dir`).
- Added placeholder `latest.json` for deterministic onboarding.

---

## Current status

- Pre-commit checks are installed and running locally.
- Terraform tests pass locally and in CI.
- Dashboard bucket exists, assets are deployed by Terraform, and dashboard loads reliably on first run.
