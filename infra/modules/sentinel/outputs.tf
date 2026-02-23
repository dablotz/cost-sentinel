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

output "dashboard_bucket_name" {
  value = local.dashboard_enabled ? null : aws_s3_bucket.dashboard[0].bucket
}

output "dashboard_status_object" {
  value = local.dashboard_enabled ? null : "s3://${aws_s3_bucket.dashboard[0].bucket}/latest.json"
}
