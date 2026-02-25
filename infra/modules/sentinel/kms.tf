resource "aws_kms_key" "lambda_env" {
  description             = "${var.name_prefix} Lambda env var encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

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

      # Allow Lambda service to use the key for this function's execution role
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
      }
    ]
  })
}

resource "aws_kms_alias" "lambda_env" {
  name          = "alias/${var.name_prefix}-lambda-env"
  target_key_id = aws_kms_key.lambda_env.key_id
}
