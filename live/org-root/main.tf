# ---------------------------------------------------------------------------
# The organization itself
#
# Created in the console before this repo had a Terraform stack. Adopted here
# rather than recreated — an organization cannot be created twice, and the
# management account is already its root.
#
# Managing it (instead of reading it through a data source) is what makes
# trusted access declarative. Every service that later needs to act org-wide —
# the CloudTrail org trail, GuardDuty, Config — is enabled by adding a
# principal to var.service_access_principals, reviewable in a diff.
# ---------------------------------------------------------------------------

import {
  to = aws_organizations_organization.this
  id = var.organization_id
}

resource "aws_organizations_organization" "this" {
  feature_set = "ALL"

  aws_service_access_principals = var.service_access_principals

  enabled_policy_types = [
    "SERVICE_CONTROL_POLICY",
  ]

  # Destroying the organization would orphan every member account and is not
  # something an apply should ever be one typo away from.
  lifecycle {
    prevent_destroy = true
  }
}

# ---------------------------------------------------------------------------
# Organizational units
#
# Security holds accounts that must never run workloads: the immutable log
# archive and the security tooling account. Workloads holds everything else.
# The split is what SCPs attach to — a policy on Security can be far stricter
# than anything that would be tolerable on a dev account.
# ---------------------------------------------------------------------------

resource "aws_organizations_organizational_unit" "this" {
  for_each = var.organizational_units

  name      = each.value
  parent_id = aws_organizations_organization.this.roots[0].id

  lifecycle {
    prevent_destroy = true
  }
}

# ---------------------------------------------------------------------------
# Member accounts
#
# Slow to create (minutes each, serialized by AWS) and effectively permanent:
# closing one starts a 90-day suspension during which its root email cannot be
# reused. Treated as immutable infrastructure.
# ---------------------------------------------------------------------------

resource "aws_organizations_account" "this" {
  for_each = var.member_accounts

  name      = "${var.project}-${each.key}"
  email     = each.value.email
  parent_id = aws_organizations_organizational_unit.this[each.value.ou].id

  # The role the management account assumes to get into a fresh member
  # account. This is the break-glass path once centralized root access removes
  # member root credentials.
  role_name = "OrganizationAccountAccessRole"

  # Lets IAM and Identity Center principals in the account read its billing
  # data. Without it only the account root can, which defeats the point of
  # having no root credentials.
  iam_user_access_to_billing = "ALLOW"

  # A `terraform destroy` should detach the account, never close it. Closing
  # burns the email address for 90 days.
  close_on_deletion = false

  lifecycle {
    prevent_destroy = true

    # AWS does not return these after creation, so they read as perpetual
    # drift. Changing either one in place is not a thing Organizations
    # supports anyway — it would mean a new account.
    ignore_changes = [role_name, iam_user_access_to_billing]
  }
}

# ---------------------------------------------------------------------------
# Centralized root access
#
# RootCredentialsManagement deletes the root user credentials from every
# member account. RootSessions allows the management account to perform the
# few tasks that genuinely require member root (deleting an S3 bucket policy
# that locks everyone out, for example) as a short-lived privileged session,
# audited in CloudTrail.
#
# This eliminates the standing-root-credential threat rather than mitigating
# it — see T5 in docs/threat-model.md. The management account root is out of
# scope and still needs its hardware MFA.
# ---------------------------------------------------------------------------

resource "aws_iam_organizations_features" "this" {
  count = var.enable_centralized_root_access ? 1 : 0

  enabled_features = [
    "RootCredentialsManagement",
    "RootSessions",
  ]

  # Trusted access for iam.amazonaws.com is a prerequisite, and the feature is
  # only meaningful once there are member accounts to strip credentials from.
  depends_on = [
    aws_organizations_organization.this,
    aws_organizations_account.this,
  ]
}
