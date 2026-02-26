---

## Postmortem: KMS, Integration Pipeline, and CI Hardening

Project: Cost Sentinel (AWS Budget → SNS → Lambda → S3 Dashboard)
Date: 2026-02-25
Status: Resolved – Full deploy + integration test successful

---

## Summary

During expansion of the Cost Sentinel project to include:
 * A customer-managed KMS key for Lambda environment variables
 * A new Integration stage in CodePipeline
 * Automated Terraform output propagation between pipeline stages
 * Runtime Lambda invocation testing

We encountered and resolved multiple classes of issues:
 * Artifact propagation failures
 * Terraform output wiring mistakes
 * IAM role permission gaps
 * KMS authorization failures (both AWS-managed and CMK)
 * Deploy role capability drift during bootstrap refactor
 * Test failures only observable in CI environment

Final state:
 * End-to-end pipeline (Source → Build → DeployDev → IntegrationDev) succeeds.
 * Lambda invocation and S3 dashboard validation run in CI.
 * KMS CMK is explicitly managed with least-privilege policies.
 * IAM roles are split by responsibility (build, deploy, integration, lambda).

---

## Major Incidents and Resolutions
Incident A – Terraform Outputs Not Reaching Integration Stage
Symptom

Integration stage failed to find terraform-outputs.json.

```
Skipping invalid file path terraform-outputs.json
```

Root Cause

Deploy stage generated the file, but:
 * It was written to the wrong relative path.
 * Secondary artifacts were not searched correctly in Integration stage.
 * CodeBuild multi-artifact layout (s3/00, s3/01) was misunderstood.

Resolution
 * Wrote outputs to $CODEBUILD_SRC_DIR explicitly:
```bash
terraform output -json > "$CODEBUILD_SRC_DIR/terraform-outputs.json"
```
* Verified file existence before artifact upload.
* Updated Integration stage to search sibling artifact directories:
```bash
find "$CODEBUILD_SRC_DIR/.." -maxdepth 5 -name terraform-outputs.json
```

Lesson

CodePipeline multi-artifact builds:
 * Primary source is mounted under s3/00
 * Secondary artifacts are mounted under sibling directories (s3/01, etc.)
 * Never assume . contains everything.

---

Incident B – Lambda KMSAccessDenied (AWS-Managed Key)

Symptom
Lambda invocation failed during integration:
```
KMSAccessDeniedException: no resource-based policy allows kms:Decrypt
```

Investigation
 * KMSKeyArn was null (using AWS-managed key)
 * IAM simulation returned implicitDeny
 * No SCPs or org policies involved

Root Cause

Lambda execution role had no effective IAM allow for KMS decrypt, and AWS-managed key path was insufficient under this account configuration.

Decision

Rather than fighting AWS-managed key behavior, migrate to explicit CMK.

---

Incident C – Customer-Managed KMS Key Permission Gaps

After adding a CMK for Lambda env encryption, Terraform deploy failed iteratively:

Missing permissions encountered during terraform apply:
 * kms:GetKeyRotationStatus
 * kms:ScheduleKeyDeletion
 * kms:ListAliases
 * kms:Encrypt
 * kms:CreateGrant

Root Cause

Deploy CodeBuild role did not have sufficient permissions to fully manage KMS lifecycle.

Terraform KMS behavior requires:
 * Create
 * Alias management
 * Rotation status polling
 * Grant creation
 * Policy updates
 * Key deletion scheduling

Resolution

Expanded deploy role KMS policy to include:
```hcl
kms:CreateKey
kms:PutKeyPolicy
kms:CreateAlias
kms:UpdateAlias
kms:DeleteAlias
kms:EnableKeyRotation
kms:GetKeyRotationStatus
kms:DescribeKey
kms:TagResource
kms:UntagResource
kms:ListResourceTags
kms:ListAliases
kms:ScheduleKeyDeletion
kms:CreateGrant
kms:Encrypt
```

Lesson

Terraform’s KMS provider behavior includes read-after-write polling and implicit grant operations.
Design deploy roles for full lifecycle control, not just creation.

---

Incident D – Role Responsibility Separation

Originally:
 * Single broad CodeBuild role handled build + deploy + integration.

Refactor introduced:
 * codebuild_build_role
 * codebuild_deploy_role
 * codebuild_integration_role
 * lambda_execution_role

Result
 * Principle of least privilege enforced.
 * KMS permissions isolated to deploy + lambda roles.
 * Integration stage only allowed:
   * lambda:InvokeFunction
   * s3:GetObject on dashboard bucket

Lesson

Separating roles early reduces cascading IAM debugging later.

---

## Improvements Added Since Last Postmortem

Pre-commit Hardening
 * Terraform fmt
 * Terraform validate
 * Terraform test
 * Python linting
 * CI simulation target in Makefile

Terraform Testing
 * basic.tftest.hcl
 * nodashboard.tftest.hcl
 * Mock provider usage

CI Simulation
 * make ci-simulate replicates CodeBuild locally
 * make clean removes .terraform and locks

Integration Testing
 * Lambda invoked with test SNS payload
 * Dashboard bucket verified
 * latest.json validated
 * Failure causes pipeline stage failure

---

## This project now demonstrates:

CI/CD Platform Engineering
 * Multi-stage CodePipeline
 * Artifact passing between stages
 * Separate CodeBuild projects
 * Terraform state remote backend

IAM Design
 * Role separation by responsibility
 * Inline vs managed policies
 * Simulation-driven debugging
 * KMS grant + key policy awareness

Infrastructure as Code Maturity
 * Module reuse
 * Conditional resources
 * Test coverage
 * Deterministic outputs

Security
 * Customer-managed CMK
 * Key policy scoping
 * kms:ViaService condition usage
 * Explicit least privilege

Observability
 * Integration stage catches runtime permission failures
 * Environment drift detected automatically

---

## Architectural Outcome

Final Flow:
```
GitHub Push
    ↓
CodePipeline
    ↓
Build (package lambda + validate terraform)
    ↓
DeployDev (terraform apply + export outputs)
    ↓
IntegrationDev
    ↓
- Invoke Lambda
- Verify S3 write
- Validate dashboard JSON
```
All automated.

---

## What Would Be Improved Next

 * Add prevent_destroy to stateful buckets
 * Add Terraform lifecycle rules where appropriate
 * Narrow KMS permissions further using tags + conditions
 * Add contract test for SNS → Lambda mapping
 * Add smoke test against S3 website endpoint
 * Add CloudWatch log validation in integration stage
 * Add cost guardrail alerts on CMK creation

---

## Final State

 * Full pipeline deploy successful.
 * Integration test successful.
 * Lambda env vars encrypted with CMK.
 * IAM roles separated and hardened.
 * Terraform outputs reliably propagated.
 * CI failures now meaningful and actionable.
