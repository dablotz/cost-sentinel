provider "aws" {
  region = var.aws_region
}

module "sentinel" {
  source = "../../modules/sentinel"

  name_prefix          = local.name_prefix
  common_tags          = local.common_tags
  alerts_bucket_name   = var.alerts_bucket_name
  force_destroy_bucket = true

  lambda_s3_bucket = var.lambda_s3_bucket
  lambda_s3_key    = var.lambda_s3_key

  alert_email = var.alert_email

  # Budget/name default to "<name_prefix>-*" in the module.
  # Keep dev's budget ON until prod owns the account-wide alert, then flip
  # this to false so dev runs the stack silently (no duplicate alerts).
  enable_budget             = true
  monthly_budget_usd        = var.monthly_budget_usd
  budget_thresholds_percent = var.budget_thresholds_percent

  dashboard_bucket_name = var.dashboard_bucket_name
  dashboard_web_dir     = "../../../web"

  write_latest = true
}
