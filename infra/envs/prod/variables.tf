variable "project" {
  type        = string
  default     = "cost-sentinel"
  description = "Project name, used in resource naming and tagging."
}

variable "environment" {
  type        = string
  default     = "prod"
  description = "Deployment environment. Drives name_prefix and tags."
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "alerts_bucket_name" {
  type        = string
  description = "Globally unique S3 bucket for alert artifacts (prod). Must differ from dev."
}

variable "lambda_s3_bucket" {
  type        = string
  description = "S3 bucket containing the Lambda zip."
}

variable "lambda_s3_key" {
  type        = string
  description = "S3 key for the Lambda zip."
}

variable "alert_email" {
  type    = string
  default = null
  # Intentionally left unset: the human-facing email subscription is managed
  # manually via the AWS Console (kept out of Terraform/state), so this stays
  # null. The Lambda subscription remains Terraform-managed.
  description = "Optional Terraform-managed email subscriber. Normally null for this project; email alerts are subscribed manually in the Console."
}

variable "monthly_budget_usd" {
  type    = number
  default = 10
}

variable "budget_thresholds_percent" {
  type    = list(number)
  default = [10, 50, 80, 100]
}

variable "dashboard_bucket_name" {
  type        = string
  description = "Globally unique bucket name for the public dashboard site (prod). Must differ from dev."
}
