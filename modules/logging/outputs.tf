output "bucket_name" {
  description = "Archive bucket name."
  value       = aws_s3_bucket.trail.id
}

output "bucket_arn" {
  description = "Archive bucket ARN."
  value       = aws_s3_bucket.trail.arn
}

output "kms_key_arn" {
  description = "CMK protecting the archive. Lives in the log archive account, not the management account."
  value       = aws_kms_key.trail.arn
}

output "trail_arn" {
  description = "Organization trail ARN."
  value       = aws_cloudtrail.org.arn
}

output "trail_name" {
  description = "Organization trail name."
  value       = aws_cloudtrail.org.name
}

output "object_lock" {
  description = "Retention actually in force. COMPLIANCE means these objects cannot be deleted by anyone, including root, until the period expires."
  value = {
    mode = var.object_lock_mode
    days = var.object_lock_retention_days
  }
}
