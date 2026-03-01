terraform {
  required_version = "~> 1.7.5"
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

# Create a mock S3 bucket for Lambda zip storage
resource "aws_s3_bucket" "lambda_test" {
  bucket = "test-lambda-bucket"
}

resource "aws_s3_object" "lambda_zip_test" {
  bucket = aws_s3_bucket.lambda_test.id
  key    = "lambda-builds/ingestor-test.zip"
  source = "${path.module}/fixtures/ingestor.zip"
}

module "sut" {
  source = "../../"

  # Required inputs for your module (adjust to match your real variables)
  name_prefix               = "example-cost-sentinel-test"
  alerts_bucket_name        = "example-cost-sentinel-app-alerts-test"
  monthly_budget_usd        = 10
  budget_thresholds_percent = [50, 80, 100]
  lambda_s3_bucket          = aws_s3_bucket.lambda_test.id
  lambda_s3_key             = aws_s3_object.lambda_zip_test.key

  # Dashboard enabled for this test (exercise those resources)
  dashboard_bucket_name = "example-cost-sentinel-dashboard-site-test"
  dashboard_web_dir     = "../../../../../web"
  alert_email           = "testy.mctester@example.com"
}
