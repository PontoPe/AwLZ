output "arn" {
  description = "Account-local permissions boundary ARN."
  value       = aws_iam_policy.this.arn
}

output "name" {
  description = "Stable policy name used by the SCP and Config rule."
  value       = aws_iam_policy.this.name
}
