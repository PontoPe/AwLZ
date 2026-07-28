output "oidc_provider_arn" {
  description = "GitHub OIDC provider."
  value       = aws_iam_openid_connect_provider.github.arn
}

output "plan_role_arn" {
  description = "Read-only role for plan-on-PR. Goes in the workflow as role-to-assume."
  value       = aws_iam_role.plan.arn
}

output "apply_role_arn" {
  description = "Write role, assumable only from the gated GitHub Environment."
  value       = aws_iam_role.apply.arn
}

output "trusted_subjects" {
  description = "Exact sub claims accepted. Anything not listed here cannot assume these roles."
  value = {
    plan  = local.plan_subs
    apply = local.apply_subs
  }
}
