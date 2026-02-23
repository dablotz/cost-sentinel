output "alerts_bucket" {
  value = module.sentinel.alerts_bucket
}

output "sns_topic_arn" {
  value = module.sentinel.sns_topic_arn
}

output "dashboard_url" {
  value       = module.sentinel.dashboard_website_url
  description = "S3 static website endpoint for the dashboard."
}
