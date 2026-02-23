terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

module "sut" {
  source = "../../"

  # Required inputs for your module (adjust to match your real variables)
  name_prefix               = "example-cost-sentinel-test"
  alerts_bucket_name        = "example-cost-sentinel-app-alerts-test"
  monthly_budget_usd        = 10
  budget_thresholds_percent = [50, 80, 100]
  lambda_zip_path           = "${path.module}/fixtures/ingestor.zip"

  # Dashboard enabled for this test (exercise those resources)
  dashboard_bucket_name = "example-cost-sentinel-dashboard-site-test"
  dashboard_web_dir     = "../../../../../web"
  alert_email           = "testy.mctester@example.com"
}
