terraform {
  required_version = "~> 1.7.5"
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

  # Dashboard disabled for this test
  dashboard_bucket_name = null
  alert_email           = "testy.mctester@example.com"
}
