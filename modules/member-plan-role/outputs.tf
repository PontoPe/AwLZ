output "arn" {
  description = "Member-account read-only plan role ARN."
  value       = aws_iam_role.this.arn
}

output "name" {
  description = "Stable role name used by cross-account providers."
  value       = aws_iam_role.this.name
}

output "account_id" {
  description = "Account that received the role."
  value       = data.aws_caller_identity.current.account_id
}
