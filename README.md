# Architecture

## High-Level Architecture

                        ┌────────────────────┐
                        │      GitHub        │
                        │  Source Repository │
                        └─────────┬──────────┘
                                  │
                                  │ CodeConnections
                                  ▼
                        ┌────────────────────┐
                        │    CodePipeline    │
                        │  CI/CD Orchestration
                        └─────────┬──────────┘
                                  │
                 ┌────────────────┴────────────────┐
                 │                                 │
                 ▼                                 ▼
        ┌──────────────────┐              ┌──────────────────┐
        │   CodeBuild      │              │   CodeBuild      │
        │  Build Stage     │              │  Deploy Stage    │
        │                  │              │                  │
        │ - Validate TF    │              │ - terraform init │
        │ - Package Lambda │              │ - terraform plan │
        │                  │              │ - terraform apply│
        └─────────┬────────┘              └─────────┬────────┘
                  │                                 │
                  │ Artifact                       │ Deploys
                  ▼                                 ▼
            ┌─────────────┐               ┌─────────────────────┐
            │   S3        │               │  AWS Infrastructure │
            │ Artifacts   │               │  (Terraform)        │
            └─────────────┘               └─────────┬───────────┘
                                                    │
                                                    │ creates
                                                    ▼
                                      ┌──────────────────────────┐
                                      │      AWS Budget          │
                                      │ Cost Threshold Monitoring│
                                      └──────────┬───────────────┘
                                                 │
                                                 │ triggers
                                                 ▼
                                        ┌─────────────────┐
                                        │      SNS        │
                                        │ Alert Topic     │
                                        └────────┬────────┘
                                                 │
                                                 │ invokes
                                                 ▼
                                        ┌─────────────────┐
                                        │     Lambda      │
                                        │ Alert Ingestor  │
                                        └────────┬────────┘
                                                 │
                                                 │ writes alert records
                                                 ▼
                                        ┌─────────────────┐
                                        │       S3        │
                                        │ Alert Storage   │
                                        │ alerts/*.json   │
                                        └─────────────────┘



# CI/CD Pipeline

Cost Sentinel uses AWS-native CI/CD tooling (CodePipeline, CodeBuild, CodeConnections)

This keeps all compute, logging, and deployment activity contained within AWS for:

- predictable billing
- easier cost monitoring
- consistent IAM-based security
- reduced external dependencies

---

# Pipeline Architecture

GitHub → CodeConnections → CodePipeline → CodeBuild → Terraform → AWS Resources

Pipeline stages:

1. Source
   Pulls code from GitHub

2. Build
   Packages Lambda function
   Validates Terraform

3. DeployDev
   Applies Terraform to deploy infrastructure

---

# Deployment Model

Infrastructure is fully defined using Terraform.

Pipeline deploys:

- AWS Budgets
- SNS alert topic
- Lambda ingestor
- S3 alert storage bucket
- IAM roles and policies

Terraform state stored remotely in S3 with DynamoDB locking.

---

# Deployment Trigger

Deployment occurs automatically on push to main branch.

No manual deployment required.

---

# Lambda Artifact Build

Pipeline packages Lambda function:

app/ingestor/handler.py → dist/ingestor.zip

Terraform references this artifact during deployment.

---

# First-Time Setup

See:

docs/runbook-ci.md

For connection authorization and bootstrap instructions.

## Development Setup

Requirements:
- Python 3.11+
- Terraform 1.7.5+

Setup:

```bash
./bootstrap-dev.sh
```

---

# Security

No AWS credentials stored in repository.

Pipeline uses IAM roles:

- CodePipeline role
- CodeBuild role
- Lambda execution role

All permissions defined in Terraform.

---

# Cost Profile

Typical monthly cost:

CodePipeline: ~$1
CodeBuild: $0–$2
Lambda: $0 (free tier)
S3: negligible

Total expected cost: <$5/month

---

# Why AWS CodeSuite Instead of GitHub Actions

Benefits:

- centralized billing
- IAM-native permissions
- fewer external integrations
- predictable cost model
- aligns with enterprise AWS deployment patterns

---

# Future Improvements

- production pipeline
- deployment approval stages
- dashboard frontend hosted on S3
- anomaly detection integration
- automated rollback safeguards
