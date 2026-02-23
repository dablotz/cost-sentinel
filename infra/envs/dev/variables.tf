variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "name_prefix" {
  type    = string
  default = "cost-sentinel-dev"
}

variable "alerts_bucket_name" {
  type        = string
  description = "Must be globally unique."
}

variable "lambda_zip_path" {
  type        = string
  description = "Built lambda zip path, e.g. ../../dist/ingestor.zip"
}

variable "alert_email" {
  type        = string
  default     = null
  description = "Optional email subscriber (you must confirm subscription)."
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
  description = "Globally unique bucket name for the public dashboard site."
}
