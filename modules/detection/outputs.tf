output "config_bucket_name" {
  description = "Config delivery bucket. Every recorder writes here."
  value       = aws_s3_bucket.config.id
}

output "config_kms_key_arn" {
  description = "CMK protecting the Config delivery bucket. Recorders need a grant on it."
  value       = aws_kms_key.config.arn
}

output "guardduty_detector_id" {
  description = "Detector in the delegated administrator account."
  value       = aws_guardduty_detector.security.id
}

output "security_hub_standards" {
  description = "Standards subscribed in the administrator account."
  value       = { for k, v in aws_securityhub_standards_subscription.this : k => v.standards_arn }
}

output "config_aggregator_arn" {
  description = "Organization-wide Config aggregator."
  value       = aws_config_configuration_aggregator.org.arn
}

output "access_analyzer_arn" {
  description = "Organization-scope Access Analyzer."
  value       = aws_accessanalyzer_analyzer.org.arn
}
