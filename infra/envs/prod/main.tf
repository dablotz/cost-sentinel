provider "aws" {
  region = var.aws_region
}

module "sentinel" {
  source = "../../modules/sentinel"

  name_prefix = local.name_prefix
  common_tags = local.common_tags

  alerts_bucket_name = var.alerts_bucket_name
  # Prod buckets are protected; never auto-destroy non-empty buckets.
  force_destroy_bucket = false

  lambda_s3_bucket = var.lambda_s3_bucket
  lambda_s3_key    = var.lambda_s3_key

  alert_email = var.alert_email

  # Prod owns the single account-wide budget (see post-mortem-5). Dev runs
  # silently with enable_budget = false to avoid duplicate alerts.
  enable_budget             = true
  monthly_budget_usd        = var.monthly_budget_usd
  budget_thresholds_percent = var.budget_thresholds_percent

  dashboard_bucket_name = var.dashboard_bucket_name
  dashboard_web_dir     = "../../../web"

  write_latest = true
}
