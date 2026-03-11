resource "aws_kms_key" "main" {
  description             = "${var.name_prefix} encryption key for Lambda, SNS, and CloudWatch Logs"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = var.common_tags

  lifecycle {
    prevent_destroy = true
  }

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      # Admin access for your account root
      {
        Sid : "AllowRootAdmin",
        Effect : "Allow",
        Principal : { AWS : "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" },
        Action : "kms:*",
        Resource : "*"
      },

      # Allow Lambda service to use the key
      {
        Sid : "AllowLambdaUse",
        Effect : "Allow",
        Principal : { AWS : aws_iam_role.lambda_role.arn },
        Action : [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ],
        Resource : "*",
        Condition : {
          StringEquals = {
            "kms:ViaService"    = "lambda.${data.aws_region.current.id}.amazonaws.com",
            "kms:CallerAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },

      # Allow CloudWatch Logs to use the key
      {
        Sid : "AllowCloudWatchLogs",
        Effect : "Allow",
        Principal : { Service = "logs.${data.aws_region.current.id}.amazonaws.com" },
        Action : [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ],
        Resource : "*",
        Condition : {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.name_prefix}-*"
          }
        }
      },

      # Allow SNS to use the key
      {
        Sid       = "AllowSNSUse",
        Effect    = "Allow",
        Principal = { Service = "sns.amazonaws.com" },
        Action    = ["kms:Decrypt", "kms:GenerateDataKey"],
        Resource  = "*"
      },

      # Allow Budgets to use the key
      {
        Sid       = "AllowBudgetsPublish",
        Effect    = "Allow",
        Principal = { Service = "budgets.amazonaws.com" },
        Action    = ["kms:Decrypt", "kms:GenerateDataKey"],
        Resource  = "*"
      }
    ]
  })
}

resource "aws_kms_alias" "main" {
  name          = "alias/${var.name_prefix}"
  target_key_id = aws_kms_key.main.key_id
}
