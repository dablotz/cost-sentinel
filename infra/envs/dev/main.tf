terraform {
  required_version = ">= 1.6.0"
  backend "s3" {}
}

provider "aws" {
  region = var.aws_region
}

module "sentinel" {
  source = "../../modules/sentinel"

  name_prefix          = var.name_prefix
  alerts_bucket_name   = var.alerts_bucket_name
  force_destroy_bucket = true

  lambda_zip_path = var.lambda_zip_path

  alert_email = var.alert_email

  budget_name               = "${var.name_prefix}-monthly-cost"
  monthly_budget_usd        = var.monthly_budget_usd
  budget_thresholds_percent = var.budget_thresholds_percent

  dashboard_bucket_name = var.dashboard_bucket_name
  dashboard_web_dir     = "../../../web"

  write_latest = true
}
