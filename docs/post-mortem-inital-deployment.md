# Postmortem: Cost Sentinel Initial Deployment Pipeline Failures

Date range: 2026-02-20  
Environment: AWS (CodePipeline, CodeBuild, Terraform, Lambda, SNS, S3, Budgets)  
Impact: Delayed successful deployment of initial infrastructure and application components.

---

# Summary

Initial deployment of the Cost Sentinel platform encountered multiple failures across CI/CD configuration, IAM permissions, artifact handling, and Terraform runtime behavior.

These issues were resolved through incremental debugging, IAM policy corrections, artifact path normalization, and pipeline configuration updates.

Final outcome: successful end-to-end deployment using fully automated AWS-native CI/CD.

---

# Impact

Duration: ~several pipeline iterations  
Severity: Deployment blocked, no production impact  
Scope: Infrastructure provisioning only (no customer-facing services)

No runtime service degradation occurred because this was an initial deployment.

---

# Root Causes and Resolutions

## Issue 1: CodePipeline could not use CodeConnections GitHub integration

### Symptom

Pipeline failed with:

```
Unable to use Connection: arn:aws:codeconnections:...
The provided role does not have sufficient permissions.
```


### Root Cause

CodePipeline IAM role lacked required permission:

```
codeconnections:UseConnection
```


AWS recently renamed CodeStar Connections → CodeConnections, and the IAM action prefix changed accordingly.

### Resolution

Updated CodePipeline IAM role policy:

```
codeconnections:UseConnection
codestar-connections:UseConnection
```


Re-applied bootstrap Terraform.

---

## Issue 2: CodeBuild continued using outdated buildspec

### Symptom

Deploy stage still executed deprecated terraform init command.

### Root Cause

CodeBuild project stored buildspec inline via Terraform:

```
buildspec = file("${path.module}/buildspec-deploy-dev.yml")
```


Re-applied bootstrap Terraform.

This allowed CodeBuild to read buildspec from repository instead of embedded content.

---

## Issue 3: Terraform could not find Lambda artifact

### Symptom

Terraform plan failed:

```
filebase64sha256 failed: no such file ../../dist/ingestor.zip
```


### Root Cause

CodePipeline artifact extraction directory structure did not match expected relative path.

Deploy stage working directory differed from build stage output assumptions.

### Resolution

Updated deploy buildspec to copy artifact into environment-local path:

```
infra/envs/dev/dist/ingestor.zip
```


Updated Terraform variable:

```
lambda_zip_path = "./dist/ingestor.zip"
```


Ensured artifact location consistency.

---

## Issue 4: SNS subscription creation failed

### Symptom

Terraform apply failed:

Invalid parameter: Endpoint


### Root Cause

Empty string passed for alert_email variable.

Terraform resource count logic treated empty string as valid endpoint.

### Resolution

Updated Terraform condition:

```
count = var.alert_email == null || trim(var.alert_email, " ") == "" ? 0 : 1
```


Prevented creation of invalid subscription.

---

## Issue 5: CodeBuild IAM role missing required read permissions

### Symptom

Terraform failed with IAM AccessDenied errors:

```
iam:ListRolePolicies
iam:ListAttachedRolePolicies
```


### Root Cause

Terraform requires read permissions to inspect IAM role state during plan/apply.

CodeBuild IAM role only had partial IAM permissions.

### Resolution

Expanded CodeBuild IAM role policy:

```
iam:GetRole
iam:CreateRole
iam:DeleteRole
iam:PutRolePolicy
iam:DeleteRolePolicy
iam:ListRolePolicies
iam:GetRolePolicy
iam:ListAttachedRolePolicies
iam:GetPolicy
iam:GetPolicyVersion
iam:ListPolicyVersions
iam:ListInstanceProfilesForRole
```


Re-applied bootstrap Terraform.

---

## Issue 6: YAML syntax and whitespace errors in buildspec

### Symptom

Pipeline execution failed due to malformed command syntax.

### Root Cause

Missing whitespace and improper YAML command formatting.

No linting step present locally.

### Resolution

Corrected YAML syntax and validated via pipeline.

Lesson learned: CI validation is effective safeguard.

---

# Contributing Factors

- Lack of initial IAM read permissions for Terraform execution role
- Artifact path assumptions between pipeline stages
- Terraform module behavior requiring artifact presence at plan time
- AWS service naming transition (CodeStar Connections → CodeConnections)
- No pre-commit linting or validation locally

---

# What Went Well

- Failures were isolated and surfaced clearly in CodeBuild logs
- Terraform state management remained consistent and uncorrupted
- Incremental fixes were safely deployable
- CI/CD pipeline successfully enforced configuration correctness
- Infrastructure remained fully declarative and reproducible

---

# What Could Be Improved

## 1. Pre-commit validation

Add local validation tools:

```
terraform fmt -check
terraform validate
yamllint
```


## 2. Pipeline IAM permissions baseline

Pre-define Terraform IAM read permissions for CI roles.

## 3. Artifact handling standardization

Standardize artifact paths relative to Terraform working directory.

## 4. Bootstrap / pipeline separation

Maintain clear distinction between pipeline infrastructure and application infrastructure.

---

# Preventative Actions

Completed:

- Corrected IAM permissions
- Standardized artifact location
- Fixed Terraform variable handling
- Updated CodeBuild buildspec sourcing

Recommended future improvements:

- Add pre-commit hooks
- Add Terraform validate stage before apply
- Add staging environment
- Add manual approval gate for production deployments

---

# Lessons Learned

CI/CD pipelines surface infrastructure correctness early.

Terraform execution roles require both write and read permissions.

Artifact handling must be explicit and deterministic.

AWS IAM permissions must account for provider read operations.

Buildspecs embedded via Terraform must be managed carefully or referenced externally.

---

# Current Status

Deployment pipeline fully operational.

Infrastructure successfully deployed via CodePipeline and Terraform.

System ready for application feature expansion.
