terraform {
  required_version = "~> 1.7.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  dashboard_web_assets = local.dashboard_enabled ? {
    "index.html" = {
      path         = "${abspath(path.root)}/${var.dashboard_web_dir}/index.html"
      content_type = "text/html; charset=utf-8"
    }
    "app.js" = {
      path         = "${abspath(path.root)}/${var.dashboard_web_dir}/app.js"
      content_type = "application/javascript; charset=utf-8"
    }
  } : {}

  dashboard_bucket_name_norm = try(trimspace(var.dashboard_bucket_name), "")
  alert_email_norm           = try(trimspace(var.alert_email), "")

  dashboard_enabled = length(local.dashboard_bucket_name_norm) > 0
  email_enabled     = length(local.alert_email_norm) > 0
}

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

resource "aws_s3_bucket" "dashboard" {
  count         = var.dashboard_bucket_name == null || local.dashboard_enabled ? 1 : 0
  bucket        = var.dashboard_bucket_name
  force_destroy = var.force_destroy_bucket
}

# NOTE: For a public static website, we must allow a public bucket policy.
resource "aws_s3_bucket_public_access_block" "dashboard" {
  count                   = var.dashboard_bucket_name == null || local.dashboard_enabled ? 1 : 0
  bucket                  = aws_s3_bucket.dashboard[0].id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_versioning" "dashboard" {
  count  = var.dashboard_bucket_name == null || local.dashboard_enabled ? 1 : 0
  bucket = aws_s3_bucket.dashboard[0].id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "dashboard" {
  count  = var.dashboard_bucket_name == null || local.dashboard_enabled ? 1 : 0
  bucket = aws_s3_bucket.dashboard[0].id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_website_configuration" "dashboard" {
  count  = var.dashboard_bucket_name == null || local.dashboard_enabled ? 1 : 0
  bucket = aws_s3_bucket.dashboard[0].id

  index_document { suffix = "index.html" }
  error_document { key = "index.html" }
}

# Allow public reads of dashboard site assets + latest.json only
resource "aws_s3_bucket_policy" "dashboard_public_read" {
  count  = var.dashboard_bucket_name == null || local.dashboard_enabled ? 1 : 0
  bucket = aws_s3_bucket.dashboard[0].id

  # Ensure BPA settings are applied before policy is put
  depends_on = [
    aws_s3_bucket_public_access_block.dashboard
  ]

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid : "PublicReadDashboard",
        Effect : "Allow",
        Principal : "*",
        Action : ["s3:GetObject"],
        Resource : [
          "${aws_s3_bucket.dashboard[0].arn}/index.html",
          "${aws_s3_bucket.dashboard[0].arn}/app.js",
          "${aws_s3_bucket.dashboard[0].arn}/latest.json"
        ]
      }
    ]
  })
}

resource "aws_s3_object" "dashboard_asset" {
  for_each = local.dashboard_web_assets

  bucket = aws_s3_bucket.dashboard[0].bucket
  key    = each.key

  source       = each.value.path
  etag         = filemd5(each.value.path)
  content_type = each.value.content_type

  server_side_encryption = "AES256"
  cache_control          = "no-store"
}


resource "aws_s3_object" "dashboard_version" {
  count                  = var.dashboard_bucket_name == null || local.dashboard_enabled ? 1 : 0
  bucket                 = aws_s3_bucket.dashboard[0].bucket
  key                    = "version.txt"
  content                = "deployed_at=${timestamp()}\n"
  content_type           = "text/plain; charset=utf-8"
  server_side_encryption = "AES256"
  cache_control          = "no-store"
}

resource "aws_s3_object" "dashboard_latest_placeholder" {
  count = var.dashboard_bucket_name == null || local.dashboard_enabled ? 1 : 0

  bucket = aws_s3_bucket.dashboard[0].bucket
  key    = "latest.json"

  content_type = "application/json; charset=utf-8"
  content = jsonencode({
    status  = "no_alerts_yet"
    message = "No alerts have been ingested yet."
    updated = timestamp()
  })

  server_side_encryption = "AES256"
  cache_control          = "no-store"

  # Optional: avoid updating on every apply due to timestamp()
  lifecycle {
    ignore_changes = [content]
  }
}

resource "aws_sns_topic" "budget_alerts" {
  name = var.sns_topic_name
}

# Optional email subscription (nice for early testing)
resource "aws_sns_topic_subscription" "email" {
  count     = var.alert_email == null || local.email_enabled ? 1 : 0
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
    Statement = concat(
      [
        {
          Effect = "Allow",
          Action = ["s3:PutObject", "s3:AbortMultipartUpload", "s3:ListBucket", "s3:GetBucketLocation"],
          Resource = [
            aws_s3_bucket.alerts.arn,
            "${aws_s3_bucket.alerts.arn}/*"
          ]
        },
        {
          Effect   = "Allow",
          Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"],
          Resource = "*"
        }
      ],
      (local.dashboard_enabled) ? [
        {
          Effect   = "Allow",
          Action   = ["s3:PutObject"],
          Resource = ["${aws_s3_bucket.dashboard[0].arn}/latest.json"]
        }
      ] : []
    )
  })
}


# Lambda (zip is built by your workflow and referenced here)
resource "aws_lambda_function" "ingestor" {
  function_name = "${var.name_prefix}-ingestor"
  role          = aws_iam_role.lambda_role.arn
  kms_key_arn   = aws_kms_key.lambda_env.arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.11"
  timeout       = 10
  memory_size   = 128

  filename         = var.lambda_zip_path
  source_code_hash = filebase64sha256(var.lambda_zip_path)

  environment {
    variables = {
      ALERTS_BUCKET    = aws_s3_bucket.alerts.bucket
      KEY_PREFIX       = "alerts"
      WRITE_LATEST     = var.write_latest ? "true" : "false",
      DASHBOARD_BUCKET = var.dashboard_bucket_name == null ? "" : aws_s3_bucket.dashboard[0].bucket
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
