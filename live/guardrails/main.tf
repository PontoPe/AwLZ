locals {
  # The policy documents live in policies/scp as templates so they stay
  # readable and reviewable on their own. Rendering happens here.
  policy_documents = {
    deny-unapproved-regions = templatefile("${path.module}/../../policies/scp/deny-unapproved-regions.json", {
      allowed_regions = jsonencode(var.allowed_regions)
    })

    protect-security-services = templatefile("${path.module}/../../policies/scp/protect-security-services.json", {
      deployment_principal_arns = jsonencode(var.deployment_principal_arns)
    })

    protect-guardrail-roles = templatefile("${path.module}/../../policies/scp/protect-guardrail-roles.json", {
      project                   = var.project
      deployment_principal_arns = jsonencode(var.deployment_principal_arns)
    })

    require-permissions-boundary = templatefile("${path.module}/../../policies/scp/require-permissions-boundary.json", {
      project = var.project
    })
  }

  # jsondecode then jsonencode does two jobs: it fails the plan on malformed
  # JSON instead of at the AWS API, and it strips the whitespace that a
  # pretty-printed document wastes against the 5120-byte SCP limit.
  policies = { for name, doc in local.policy_documents : name => jsonencode(jsondecode(doc)) }

  # The boundary policy must cover every member OU already protected by the
  # other guardrails. Deriving the target set preserves existing private
  # tfvars while preventing the new policy from being created unattached.
  effective_scp_targets = merge(var.scp_targets, {
    require-permissions-boundary = distinct(flatten(values(var.scp_targets)))
  })

  # Flattened so each attachment is its own addressable resource. Detaching
  # one target is then a one-line edit, which matters when a policy is
  # blocking something it should not.
  attachments = merge([
    for name, targets in local.effective_scp_targets : {
      for target in targets : "${name}/${target}" => {
        policy = name
        target = target
      }
    }
  ]...)
}

# A policy over the limit is rejected by the API after the plan looks fine.
# Catching it here keeps the failure at plan time.
check "policy_size" {
  assert {
    condition     = alltrue([for name, doc in local.policies : length(doc) <= 5120])
    error_message = "an SCP exceeds the 5120-byte limit: ${jsonencode({ for name, doc in local.policies : name => length(doc) })}"
  }
}

resource "aws_organizations_policy" "this" {
  for_each = local.policies

  name        = "${var.project}-${each.key}"
  description = "${var.project} guardrail — see policies/scp/README.md"
  type        = "SERVICE_CONTROL_POLICY"
  content     = each.value
}

resource "aws_organizations_policy_attachment" "this" {
  for_each = local.attachments

  policy_id = aws_organizations_policy.this[each.value.policy].id
  target_id = each.value.target
}
