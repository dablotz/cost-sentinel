output "alerts_bucket" {
  value = aws_s3_bucket.alerts.bucket
}

output "sns_topic_arn" {
  value = aws_sns_topic.budget_alerts.arn
}

output "dashboard_website_url" {
  value       = var.dashboard_bucket_name == null ? null : aws_s3_bucket_website_configuration.dashboard[0].website_endpoint
  description = "S3 static website endpoint for the dashboard."
}
