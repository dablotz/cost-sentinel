output "alerts_bucket" {
  value = module.sentinel.alerts_bucket
}

output "sns_topic_arn" {
  value = module.sentinel.sns_topic_arn
}
