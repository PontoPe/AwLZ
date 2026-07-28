output "plan_role_arn" {
  description = "Put this in .github/workflows/ci.yml as role-to-assume for the plan job."
  value       = module.oidc.plan_role_arn
}

output "apply_role_arn" {
  description = "Assumable only from the gated GitHub Environment."
  value       = module.oidc.apply_role_arn
}

output "trusted_subjects" {
  description = "Exact sub claims accepted."
  value       = module.oidc.trusted_subjects
}
