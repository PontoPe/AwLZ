output "policy_ids" {
  description = "Policy name -> SCP ID."
  value       = { for k, v in aws_organizations_policy.this : k => v.id }
}

output "policy_sizes" {
  description = "Policy name -> rendered size in bytes. The SCP limit is 5120; this is the headroom left before a policy has to be split."
  value       = { for k, v in local.policies : k => length(v) }
}

output "attachments" {
  description = "Which policy is attached to which target. The blast radius of this stack, in one place."
  value       = { for k, v in local.attachments : v.policy => v.target... }
}
