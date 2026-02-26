terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ----------------------------
# S3 buckets (artifacts + tfstate)
# ----------------------------
resource "aws_s3_bucket" "artifacts" {
  bucket        = var.artifact_bucket_name
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket" "tfstate" {
  bucket        = var.tf_state_bucket_name
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_dynamodb_table" "tflock" {
  name         = "${var.name_prefix}-tf-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"
  attribute {
    name = "LockID"
    type = "S"
  }
}

# ----------------------------
# CodeConnections (GitHub)
# ----------------------------
resource "aws_codestarconnections_connection" "github" {
  name          = "${var.name_prefix}-github"
  provider_type = "GitHub"
}

# NOTE: after apply, you must go to AWS Console and "Authorize" this connection once.

# ----------------------------
# IAM: CodeBuild roles
# ----------------------------
resource "aws_iam_role" "codebuild_build_role" {
  name = "${var.name_prefix}-codebuild-build-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "codebuild.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "codebuild_build_policy" {
  name = "${var.name_prefix}-codebuild-build-policy"
  role = aws_iam_role.codebuild_build_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      # Logs
      {
        Effect   = "Allow",
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"],
        Resource = "*"
      },
      # Pipeline artifact bucket (read inputs, write build output)
      {
        Effect = "Allow",
        Action = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"],
        Resource = [
          aws_s3_bucket.artifacts.arn,
          "${aws_s3_bucket.artifacts.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role" "codebuild_deploy_role" {
  name = "${var.name_prefix}-codebuild-deploy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "codebuild.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "codebuild_deploy_policy" {
  name = "${var.name_prefix}-codebuild-deploy-policy"
  role = aws_iam_role.codebuild_deploy_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      # Logs
      {
        Effect   = "Allow",
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"],
        Resource = "*"
      },

      # Pipeline artifacts bucket (read build output, write deploy output like terraform-outputs.json)
      {
        Effect = "Allow",
        Action = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"],
        Resource = [
          aws_s3_bucket.artifacts.arn,
          "${aws_s3_bucket.artifacts.arn}/*"
        ]
      },

      # Terraform remote state bucket
      {
        Effect = "Allow",
        Action = ["s3:GetObject", "s3:PutObject", "s3:ListBucket", "s3:GetBucketLocation"],
        Resource = [
          aws_s3_bucket.tfstate.arn,
          "${aws_s3_bucket.tfstate.arn}/*"
        ]
      },

      # DynamoDB lock table
      {
        Effect   = "Allow",
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem", "dynamodb:DescribeTable"],
        Resource = aws_dynamodb_table.tflock.arn
      },

      {
        Effect = "Allow",
        Action = [
          "kms:CreateKey",
          "kms:PutKeyPolicy",
          "kms:CreateAlias",
          "kms:GetKeyPolicy",
          "kms:GetKeyRotationStatus",
          "kms:UpdateAlias",
          "kms:DeleteAlias",
          "kms:EnableKeyRotation",
          "kms:ListResourceTags",
          "kms:TagResource",
          "kms:UntagResource",
          "kms:DescribeKey",
          "kms:ScheduleKeyDeletion",
          "kms:ListAliases",
          "kms:Encrypt",
          "kms:CreateGrant"
        ],
        Resource = "*"
      },

      # App resources managed by Terraform
      # (You can narrow these later; keep functional first.)
      { Effect = "Allow", Action = ["budgets:*"], Resource = "*" },
      { Effect = "Allow", Action = ["sns:*"], Resource = "*" },
      { Effect = "Allow", Action = ["lambda:*"], Resource = "*" },
      { Effect = "Allow", Action = ["s3:*"], Resource = "*" },

      # IAM needed because Terraform creates roles/policies for Lambda execution.
      { Effect = "Allow", Action = [
        "iam:PassRole",
        "iam:GetRole",
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:PutRolePolicy",
        "iam:DeleteRolePolicy",
        "iam:ListRolePolicies",
        "iam:GetRolePolicy",
        "iam:ListAttachedRolePolicies",
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role" "codebuild_integration_role" {
  name = "${var.name_prefix}-codebuild-integration-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "codebuild.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "codebuild_integration_policy" {
  name = "${var.name_prefix}-codebuild-integration-policy"
  role = aws_iam_role.codebuild_integration_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      # Logs
      {
        Effect   = "Allow",
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"],
        Resource = "*"
      },

      # Pipeline artifacts bucket: read terraform-outputs.json + script from artifact
      {
        Effect = "Allow",
        Action = ["s3:GetObject", "s3:ListBucket"],
        Resource = [
          aws_s3_bucket.artifacts.arn,
          "${aws_s3_bucket.artifacts.arn}/*"
        ]
      },

      # Invoke the ingestor Lambda
      {
        Effect   = "Allow",
        Action   = ["lambda:InvokeFunction"],
        Resource = "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:cost-sentinel-dev-ingestor"
      },

      # Read the dashboard object
      {
        Effect   = "Allow",
        Action   = ["s3:GetObject"],
        Resource = "arn:aws:s3:::${var.dashboard_bucket_name_dev}/latest.json"
      }
    ]
  })
}

# ----------------------------
# CodeBuild Projects
# ----------------------------
resource "aws_codebuild_project" "build" {
  name         = "${var.name_prefix}-build"
  service_role = aws_iam_role.codebuild_build_role.arn

  artifacts { type = "CODEPIPELINE" }

  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/standard:7.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = false
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "infra/bootstrap/buildspec-build.yml"
  }
}

resource "aws_codebuild_project" "deploy_dev" {
  name         = "${var.name_prefix}-deploy-dev"
  service_role = aws_iam_role.codebuild_deploy_role.arn

  artifacts { type = "CODEPIPELINE" }

  environment {
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "aws/codebuild/standard:7.0"
    type         = "LINUX_CONTAINER"

    environment_variable {
      name  = "TF_STATE_BUCKET"
      value = aws_s3_bucket.tfstate.bucket
    }
    environment_variable {
      name  = "TF_STATE_KEY"
      value = "cost-sentinel/dev.tfstate"
    }
    environment_variable {
      name  = "TF_LOCK_TABLE"
      value = aws_dynamodb_table.tflock.name
    }

    # These feed your app env Terraform variables
    environment_variable {
      name  = "ALERTS_BUCKET_NAME_DEV"
      value = var.alerts_bucket_name_dev
    }
    environment_variable {
      name  = "BUDGET_EMAIL"
      value = var.budget_email == null ? "" : var.budget_email
    }
    environment_variable {
      name  = "MONTHLY_BUDGET_USD"
      value = tostring(var.monthly_budget_usd)
    }
    environment_variable {
      name  = "BUDGET_THRESHOLDS"
      value = join(",", [for n in var.budget_thresholds_percent : tostring(n)])
    }
    environment_variable {
      name  = "DASHBOARD_BUCKET_NAME_DEV"
      value = var.dashboard_bucket_name_dev
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "infra/bootstrap/buildspec-deploy-dev.yml"
  }
}

resource "aws_codebuild_project" "integration_dev" {
  name         = "${var.name_prefix}-integration-dev"
  service_role = aws_iam_role.codebuild_integration_role.arn

  artifacts { type = "CODEPIPELINE" }

  environment {
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "aws/codebuild/standard:7.0"
    type         = "LINUX_CONTAINER"
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "infra/bootstrap/buildspec-integration-dev.yml"
  }
}


# ----------------------------
# IAM: CodePipeline role
# ----------------------------
resource "aws_iam_role" "codepipeline_role" {
  name = "${var.name_prefix}-codepipeline-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "codepipeline.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "codepipeline_policy" {
  name = "${var.name_prefix}-codepipeline-policy"
  role = aws_iam_role.codepipeline_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      # Artifacts bucket
      {
        Effect = "Allow",
        Action = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"],
        Resource = [
          aws_s3_bucket.artifacts.arn,
          "${aws_s3_bucket.artifacts.arn}/*"
        ]
      },
      # Start CodeBuild
      {
        Effect = "Allow",
        Action = ["codebuild:StartBuild", "codebuild:BatchGetBuilds"],
        Resource = [
          aws_codebuild_project.build.arn,
          aws_codebuild_project.deploy_dev.arn,
          aws_codebuild_project.integration_dev.arn
        ]
      },
      # Use connection
      {
        Effect = "Allow",
        Action = [
          "codeconnections:UseConnection",
          "codestar-connections:UseConnection"
        ],
        Resource = aws_codestarconnections_connection.github.arn
      },
      # Allow CodePipeline to pass CodeBuild service roles
      {
        Effect = "Allow",
        Action = ["iam:PassRole"],
        Resource = [
          aws_iam_role.codebuild_build_role.arn,
          aws_iam_role.codebuild_deploy_role.arn,
          aws_iam_role.codebuild_integration_role.arn
        ]
      }
    ]
  })
}

# ----------------------------
# CodePipeline
# ----------------------------
resource "aws_codepipeline" "pipeline" {
  name     = "${var.name_prefix}-pipeline"
  role_arn = aws_iam_role.codepipeline_role.arn

  artifact_store {
    location = aws_s3_bucket.artifacts.bucket
    type     = "S3"
  }

  stage {
    name = "Source"
    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source_output"]
      configuration = {
        ConnectionArn    = aws_codestarconnections_connection.github.arn
        FullRepositoryId = var.github_repo
        BranchName       = var.github_branch
        DetectChanges    = "true"
      }
    }
  }

  stage {
    name = "Build"
    action {
      name             = "BuildAndPackage"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["source_output"]
      output_artifacts = ["build_output"]
      configuration = {
        ProjectName = aws_codebuild_project.build.name
      }
    }
  }

  stage {
    name = "DeployDev"
    action {
      name             = "TerraformApplyDev"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["build_output"]
      output_artifacts = ["deploy_dev_output"]
      configuration = {
        ProjectName = aws_codebuild_project.deploy_dev.name
      }
    }
  }

  stage {
    name = "IntegrationDev"
    action {
      name            = "IntegrationTestsDev"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["build_output", "deploy_dev_output"]
      configuration = {
        ProjectName   = aws_codebuild_project.integration_dev.name
        PrimarySource = "build_output"
      }
    }
  }
}
