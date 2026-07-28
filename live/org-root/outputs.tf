output "organization_id" {
  description = "Organization ID. SCP conditions and cross-account bucket policies key off this."
  value       = aws_organizations_organization.this.id
}

output "organization_arn" {
  description = "Organization ARN, for aws:PrincipalOrgID-style conditions."
  value       = aws_organizations_organization.this.arn
}

output "root_id" {
  description = "Organization root ID. SCPs attach here or to an OU below it."
  value       = aws_organizations_organization.this.roots[0].id
}

output "organizational_unit_ids" {
  description = "OU name -> ID. policies/scp attaches to these."
  value       = { for k, v in aws_organizations_organizational_unit.this : k => v.id }
}

output "account_ids" {
  description = "Member account short name -> account ID. Later stacks assume roles into these."
  value       = { for k, v in aws_organizations_account.this : k => v.id }
}

output "account_arns" {
  description = "Member account short name -> account ARN."
  value       = { for k, v in aws_organizations_account.this : k => v.arn }
}

output "member_account_access_role_arns" {
  description = "Break-glass path into each member account, assumed from the management account. The only way in once centralized root access removes member root credentials."
  value       = { for k, v in aws_organizations_account.this : k => "arn:aws:iam::${v.id}:role/OrganizationAccountAccessRole" }
}
