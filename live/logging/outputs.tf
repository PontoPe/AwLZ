output "bucket_name" {
  description = "Archive bucket name."
  value       = module.logging.bucket_name
}

output "trail_arn" {
  description = "Organization trail ARN."
  value       = module.logging.trail_arn
}

output "kms_key_arn" {
  description = "CMK protecting the archive, held in the log archive account."
  value       = module.logging.kms_key_arn
}

output "object_lock" {
  description = "Retention in force on every delivered object."
  value       = module.logging.object_lock
}
