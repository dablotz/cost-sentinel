# Runbook: Prod Environment Cutover

Operational steps to stand up the `prod` Cost Sentinel environment and make it
the authoritative budget monitor, retiring dev's alerting role.

## Background

- AWS Budgets is **account-scoped**: a dev budget and a prod budget in the same
  account both watch the same spend. To avoid duplicate alerts, **prod owns the
  single budget**; dev runs the stack silently (`enable_budget = false`) once
  prod is live.
- The human-facing **email subscription is managed manually** in the Console
  (kept out of Terraform); only the Lambda subscription is Terraform-managed.
- Promotion model is **"promote current dev state"**: a manual approval gate in
  the existing pipeline. Prod gets dev's latest-vetted commit at approval time.

## Key principle: no monitoring gap

The dev budget is **not** disabled in the same change that introduces prod.
Doing so would remove dev's budget at `DeployDev`, then leave the pipeline
paused at the manual approval gate (arbitrarily long) with nothing monitoring
the account. Cutover is therefore **two pipeline runs**:

1. Run 1 introduces prod with dev still enabled (brief, acceptable duplicate
   alerts).
2. Run 2 disables dev's budget after prod is verified live.

---

## Stage 0 — Implement & review (branch `infra-env-prod`)

- Prod env root `infra/envs/prod/` (done).
- Bootstrap: `deploy_prod` + `integration_prod` CodeBuild projects, their
  buildspecs, `Approval` + `DeployProd` + `IntegrationProd` pipeline stages,
  `codepipeline_role` `StartBuild` grant, and the integration-role ARN-scope fix.
- New bootstrap vars: `alerts_bucket_name_prod`, `dashboard_bucket_name_prod`
  (globally unique, must contain `cost-sentinel`).
- **Not in this change:** the dev `enable_budget = false` flip (that is Run 2).

Optional pre-flight (no apply): `terraform -chdir=infra/envs/prod plan` with a
throwaway `terraform.tfvars` + `backend.hcl` (state key `cost-sentinel/prod.tfstate`)
and an existing artifact (e.g. `lambda-builds/ingestor-70.zip`). Expect a clean
~27-resource create plan, all `cost-sentinel-prod-*`.

## Stage 1 — Apply bootstrap from the terminal (adds prod pipeline stages)

A pipeline cannot add its own stages, so the bootstrap change is applied
out-of-band with admin (SSO) credentials:

```
terraform -chdir=infra/bootstrap init
terraform -chdir=infra/bootstrap apply   # supply alerts_bucket_name_prod, dashboard_bucket_name_prod
```

After apply, the pipeline shows the new `Approval` → `DeployProd` →
`IntegrationProd` stages.

## Stage 2 — Merge to main; let CodePipeline stand up prod

- Merge `infra-env-prod` → `main`. The pipeline runs
  `Build → DeployDev → IntegrationDev` automatically, then **pauses at Approval**.
- Approve the manual action. `DeployProd` runs `terraform apply` for
  `infra/envs/prod` using the **scoped deploy role** (creates the 27 prod
  resources). `IntegrationProd` validates the prod ingestor/dashboard.

> First prod apply runs through the pipeline (not the terminal) so the scoped
> `cost-sentinel-*` deploy role is exercised on prod resources.

## Stage 3 — Subscribe the alert email (manual, Console)

- SNS → Topics → `cost-sentinel-prod-budget-alerts` → Create subscription →
  Protocol `Email`, Endpoint = personal email.
- Confirm via the link AWS emails.

## Stage 4 — Verify prod alerting

- Budget `cost-sentinel-prod-monthly-cost` exists with FORECASTED notifications
  at [10, 50, 80, 100]% pointing at `cost-sentinel-prod-budget-alerts`.
- Topic has both the Lambda subscription (Terraform) and the email subscription
  (manual, confirmed).
- Optionally publish a test message to the topic to confirm email + Lambda fire.

**At this point dev and prod budgets both exist** — expect temporary duplicate
alerts until Run 2.

## Stage 5 — Run 2: disable the dev budget

- Separate commit: set `enable_budget = false` in `infra/envs/dev/main.tf`.
- Merge to main → `DeployDev` removes the dev budget
  (`cost-sentinel-dev-monthly-cost`). Prod is already monitoring, so no gap.

## Stage 6 — Remove the manual dev email subscription

- SNS → `cost-sentinel-dev-budget-alerts` → delete the manual email
  subscription (it now receives nothing).

## Stage 7 — Post-cutover verification

- Only `cost-sentinel-prod-monthly-cost` budget remains.
- Only the prod topic has an email subscription.
- Dev stack still deployed (silent canary): topic + Lambda present, no budget.

---

## Verification snippets

```
# Budgets present
aws budgets describe-budgets --account-id <ACCOUNT_ID> \
  --query 'Budgets[].BudgetName'

# Prod topic subscriptions (expect lambda + email)
aws sns list-subscriptions-by-topic \
  --topic-arn arn:aws:sns:us-east-1:<ACCOUNT_ID>:cost-sentinel-prod-budget-alerts \
  --query 'Subscriptions[].{Protocol:Protocol,Endpoint:Endpoint}'
```

## Rollback

- Prod stateful resources use `prevent_destroy`; do not `terraform destroy` prod
  casually.
- If Run 2 caused a problem, re-enable dev by reverting `enable_budget` to `true`
  and re-running the pipeline; dev's budget is recreated.
- If the first prod apply fails mid-way (e.g. an unforeseen IAM gap), fix the
  deploy-role scope in bootstrap, re-apply bootstrap from the terminal, and
  re-run the `DeployProd` stage; prod state lives at `cost-sentinel/prod.tfstate`.
