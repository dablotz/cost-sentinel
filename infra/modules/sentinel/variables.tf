variable "common_tags" {
  type = map(string)
  default = {
    Project     = "cost-sentinel"
    ManagedBy   = "terraform"
    Environment = "dev"
  }
}

variable "name_prefix" {
  type        = string
  description = "Prefix for naming AWS resources."
}

variable "alerts_bucket_name" {
  type        = string
  description = "S3 bucket to store alert artifacts."
}

variable "force_destroy_bucket" {
  type        = bool
  default     = false
  description = "If true, bucket will be destroyed even if non-empty (dev only)."
}

variable "sns_topic_name" {
  type        = string
  default     = "cost-sentinel-budget-alerts"
  description = "SNS topic name for budget alerts."
}

variable "alert_email" {
  type        = string
  default     = null
  description = "Optional email to subscribe to SNS for testing."
}

variable "lambda_s3_bucket" {
  type        = string
  description = "S3 bucket containing Lambda zip."
}

variable "lambda_s3_key" {
  type        = string
  description = "S3 key for Lambda zip."
}

variable "budget_name" {
  type        = string
  default     = "cost-sentinel-monthly-cost"
  description = "AWS Budget name."
}

variable "monthly_budget_usd" {
  type        = number
  default     = 10
  description = "Monthly budget amount in USD."
}

variable "budget_thresholds_percent" {
  type        = list(number)
  default     = [10, 50, 80, 100]
  description = "Threshold percentages that trigger ACTUAL spend alerts."
}

variable "write_latest" {
  type        = bool
  default     = true
  description = "Whether to also write alerts/latest.json for quick viewing."
}

variable "dashboard_bucket_name" {
  type        = string
  default     = null
  description = "If set, create a public S3 bucket for the static dashboard and write latest.json to it."
}

variable "dashboard_web_dir" {
  type        = string
  default     = "web"
  description = "Path (relative to the repo root) containing dashboard web assets."
}
