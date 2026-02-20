terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_s3_bucket" "alerts" {
  bucket        = var.alerts_bucket_name
  force_destroy = var.force_destroy_bucket
}

resource "aws_s3_bucket_versioning" "alerts" {
  bucket = aws_s3_bucket.alerts.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "alerts" {
  bucket                  = aws_s3_bucket.alerts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "alerts" {
  bucket = aws_s3_bucket.alerts.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_sns_topic" "budget_alerts" {
  name = var.sns_topic_name
}

# Optional email subscription (nice for early testing)
resource "aws_sns_topic_subscription" "email" {
  count     = var.alert_email == null || trim(var.alert_email, " ") == "" ? 0 : 1
  topic_arn = aws_sns_topic.budget_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# IAM for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "${var.name_prefix}-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "lambda.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.name_prefix}-lambda-policy"
  role = aws_iam_role.lambda_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      # Write alert artifacts
      {
        Effect = "Allow",
        Action = ["s3:PutObject", "s3:AbortMultipartUpload", "s3:ListBucket", "s3:GetBucketLocation"],
        Resource = [
          aws_s3_bucket.alerts.arn,
          "${aws_s3_bucket.alerts.arn}/*"
        ]
      },
      # Log to CloudWatch
      {
        Effect   = "Allow",
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"],
        Resource = "*"
      }
    ]
  })
}

# Lambda (zip is built by your workflow and referenced here)
resource "aws_lambda_function" "ingestor" {
  function_name = "${var.name_prefix}-ingestor"
  role          = aws_iam_role.lambda_role.arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.11"
  timeout       = 10
  memory_size   = 128

  filename         = var.lambda_zip_path
  source_code_hash = filebase64sha256(var.lambda_zip_path)

  environment {
    variables = {
      ALERTS_BUCKET = aws_s3_bucket.alerts.bucket
      KEY_PREFIX    = "alerts"
      WRITE_LATEST  = var.write_latest ? "true" : "false"
    }
  }
}

# Allow SNS -> Lambda
resource "aws_lambda_permission" "allow_sns" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ingestor.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.budget_alerts.arn
}

resource "aws_sns_topic_subscription" "lambda" {
  topic_arn = aws_sns_topic.budget_alerts.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.ingestor.arn
}

# Budget: keep it simple, monthly cost budget
resource "aws_budgets_budget" "monthly_cost" {
  name         = var.budget_name
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  # Alert at threshold % of budget
  dynamic "notification" {
    for_each = var.budget_thresholds_percent
    content {
      comparison_operator = "GREATER_THAN"
      threshold           = notification.value
      threshold_type      = "PERCENTAGE"
      notification_type   = "ACTUAL"

      subscriber_sns_topic_arns = [aws_sns_topic.budget_alerts.arn]
    }
  }
}
