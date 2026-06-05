variable "common_tags" {
  type        = map(string)
  description = "Tags applied to all resources. Callers should pass an env-specific map; the default is a neutral fallback for module tests."
  default = {
    Project   = "cost-sentinel"
    ManagedBy = "terraform"
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
  default     = null
  description = "SNS topic name for budget alerts. Defaults to \"<name_prefix>-budget-alerts\" when unset."
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
  default     = null
  description = "AWS Budget name. Defaults to \"<name_prefix>-monthly-cost\" when unset."
}

variable "enable_budget" {
  type        = bool
  default     = true
  description = "Whether to create the AWS Budget. Set false for a non-alerting environment (e.g. dev) so it does not duplicate the account-wide budget owned by prod."
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
