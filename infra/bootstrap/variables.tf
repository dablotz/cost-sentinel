variable "common_tags" {
  type = map(string)
  default = {
    Project     = "cost-sentinel"
    ManagedBy   = "terraform"
    Environment = "dev"
  }
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "name_prefix" {
  type    = string
  default = "cost-sentinel"
}

variable "github_repo" {
  type        = string
  description = "GitHub repo in owner/name format, e.g. mygitrepo/cost-sentinel"
}

variable "github_branch" {
  type    = string
  default = "main"
}

variable "alerts_bucket_name_dev" {
  type        = string
  description = "Globally unique bucket name for app alerts bucket (dev)."
}

variable "tf_state_bucket_name" {
  type        = string
  description = "Globally unique bucket name for Terraform remote state."
}

variable "artifact_bucket_name" {
  type        = string
  description = "Globally unique bucket name for CodePipeline artifacts."
}

variable "budget_email" {
  type        = string
  default     = null
  description = "Optional email to subscribe to SNS (dev)."
}

variable "monthly_budget_usd" {
  type    = number
  default = 10
}

variable "budget_thresholds_percent" {
  type    = list(number)
  default = [10, 50, 80, 100]
}

variable "dashboard_bucket_name_dev" {
  type        = string
  description = "Globally unique bucket name for the public dashboard site bucket (dev)."
}
