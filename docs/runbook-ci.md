# Cost Sentinel – CI/CD Runbook (AWS CodeSuite)

This document describes how the CI/CD pipeline for Cost Sentinel is deployed, operated, and recovered.

The pipeline uses AWS-native tooling (CodePipeline, CodeBuild, CodeConnections) to package and deploy infrastructure and application code using Terraform.

---

# Architecture Overview

Source of truth:
- GitHub repository (main branch)

Deployment system:
- AWS CodePipeline orchestrates pipeline stages
- AWS CodeBuild runs Terraform and packages Lambda artifacts
- AWS CodeConnections provides secure GitHub integration
- Terraform deploys all application infrastructure

Pipeline stages:

1. Source
   GitHub → CodePipeline via CodeConnections

2. Build
   CodeBuild job:
   - Runs terraform fmt and terraform validate
   - Packages Lambda function into dist/ingestor.zip

3. DeployDev
   CodeBuild job:
   - Runs terraform init with S3 backend and DynamoDB lock
   - Runs terraform plan
   - Runs terraform apply

Terraform manages:

- AWS Budget
- SNS topic and subscriptions
- Lambda function
- S3 bucket for alert artifacts
- IAM roles and policies

---

# One-Time Setup Procedure

## Step 1 – Deploy bootstrap stack

From repo root:

```
cd infra/bootstrap
terraform init
terraform apply
```


This creates:

- CodePipeline
- CodeBuild projects
- Artifact bucket
- Terraform state bucket
- Terraform lock table
- CodeConnections connection (pending authorization)

---

## Step 2 – Authorize GitHub connection

Required manual step:

1. Open AWS Console
2. Navigate to:
   Developer Tools → Settings → Connections
3. Locate connection:
   cost-sentinel-github
4. Click connection
5. Click "Update pending connection"
6. Click "Authorize"
7. Authenticate with GitHub
8. Confirm repository access

Connection status must change to:

AVAILABLE

Pipeline cannot pull source until this step is complete.

---

## Step 3 – Verify pipeline trigger

Make a small commit to main:

```
git commit --allow-empty -m "trigger pipeline"
git push origin main
```


Verify pipeline execution:

AWS Console → CodePipeline → cost-sentinel-pipeline

Expected result:

All stages succeed.

---

# Routine Operations

## Deploy new infrastructure or Lambda changes

Push commit to main branch:

```
git push origin main
```


Pipeline automatically:

- Packages Lambda
- Runs terraform plan
- Applies infrastructure changes

No manual intervention required.

---

## Verify deployment

Check pipeline:

AWS Console → CodePipeline → cost-sentinel-pipeline

Check Lambda:

AWS Console → Lambda → cost-sentinel-dev-ingestor

Check alert bucket:

AWS Console → S3 → <alerts bucket>

---

# Terraform State Management

State stored in:

S3 bucket:
cost-sentinel-tfstate

Lock table:
cost-sentinel-tf-lock

Benefits:

- Prevents concurrent state modification
- Enables pipeline-safe deployments
- Supports future multi-environment deployments

---

# Failure Recovery Procedures

## Pipeline fails in Build stage

Symptoms:
- CodeBuild fails before Terraform deploy

Actions:

1. Open CodeBuild project logs
2. Identify error:
   - Terraform validation error
   - Missing files
   - Syntax error

3. Fix locally
4. Commit fix
5. Push to main

Pipeline automatically retries.

---

## Pipeline fails in Deploy stage

Symptoms:
- Terraform apply fails

Actions:

1. Open CodeBuild logs
2. Identify Terraform error
3. Fix infrastructure code
4. Commit and push

Do NOT manually modify Terraform-managed resources in console.

---

## Terraform state lock stuck

Rare scenario.

Check DynamoDB table:

cost-sentinel-tf-lock

Remove lock only if pipeline is confirmed not running.

---

# Emergency Rollback Procedure

To revert infrastructure:

```
git revert <commit>
git push origin main
```


Pipeline redeploys previous state.

Terraform safely removes new resources.

---

# Security Model

Pipeline uses IAM roles with least privilege:

CodePipeline role:
- Reads GitHub source
- Starts CodeBuild

CodeBuild role:
- Reads/writes Terraform state
- Deploys Lambda, SNS, S3, Budgets

Lambda role:
- Writes alert data to S3
- Writes logs to CloudWatch

No long-lived credentials stored in repository.

---

# Cost Controls

Pipeline designed for low-cost operation:

CodePipeline:
~$1/month when active

CodeBuild:
Free tier: 100 minutes/month

Lambda:
Free tier sufficient for expected usage

S3 storage:
Minimal (alert logs only)

Terraform state:
Minimal cost

---

# Future Enhancements

Planned improvements:

- Separate dev and prod pipelines
- Manual approval stage for production
- Canary Lambda deployments
- Static dashboard hosted on S3
- OIDC-based GitHub integration (if switching back from CodeSuite)
- Fine-grained IAM permissions

---

# Contact / Ownership

System owner:
Cost Sentinel repository owner

All infrastructure defined in:

infra/bootstrap/
infra/envs/
infra/modules/

Manual changes outside Terraform are prohibited.
