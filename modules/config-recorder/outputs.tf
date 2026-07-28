output "recorder_name" {
  description = "Configuration recorder name."
  value       = aws_config_configuration_recorder.this.name
}

output "role_arn" {
  description = "Role the recorder assumes."
  value       = aws_iam_role.config.arn
}

output "account_id" {
  description = "Account this recorder was created in — useful for asserting the provider landed where intended."
  value       = data.aws_caller_identity.current.account_id
}
