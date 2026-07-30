# Maximum permissions for customer-managed roles in member accounts.
#
# A permissions boundary never grants an action. The role still needs an
# identity policy that allows it; this policy only caps how far that identity
# policy can go.
data "aws_iam_policy_document" "this" {
  # checkov:skip=CKV_AWS_1:A permissions boundary grants nothing by itself. The broad allow keeps arbitrary workload services usable while explicit denies cap escalation and control-plane tampering.
  # checkov:skip=CKV_AWS_49:The wildcard is the allow half of a permissions boundary, not an identity grant. The attached identity policy remains the only source of permissions.
  # checkov:skip=CKV_AWS_107:No credentials permission is granted by this boundary. Effective access is the intersection with a separately scoped identity policy.
  # checkov:skip=CKV_AWS_108:No data permission is granted by this boundary. Effective access is the intersection with a separately scoped identity policy.
  # checkov:skip=CKV_AWS_109:Identity and Organizations mutations are explicitly denied; the scanner does not model boundary intersection semantics.
  # checkov:skip=CKV_AWS_110:IAM writes, PassRole and AssumeRole are explicitly denied to prevent escalation; the scanner evaluates the allow statement in isolation.
  # checkov:skip=CKV_AWS_111:The boundary must work across unknown workload resources and grants no write itself; resource scope belongs to each attached identity policy.
  # checkov:skip=CKV_AWS_356:The boundary is reusable across arbitrary workload resources and grants nothing; attached identity policies provide resource-level allows.
  # checkov:skip=CKV2_AWS_40:Full IAM privileges are explicitly denied. Checkov does not model the deny statements or permissions-boundary intersection.
  statement {
    sid       = "AllowSubjectToExplicitGuardrails"
    effect    = "Allow"
    actions   = ["*"]
    resources = ["*"]
  }

  statement {
    sid    = "DenyIdentityAndOrganizationEscalation"
    effect = "Deny"

    actions = [
      "iam:Add*",
      "iam:Attach*",
      "iam:Create*",
      "iam:DeactivateMFADevice",
      "iam:Delete*",
      "iam:Detach*",
      "iam:EnableMFADevice",
      "iam:PassRole",
      "iam:Put*",
      "iam:Remove*",
      "iam:Reset*",
      "iam:Resync*",
      "iam:Set*",
      "iam:Tag*",
      "iam:Untag*",
      "iam:Update*",
      "iam:Upload*",
      "organizations:Accept*",
      "organizations:AttachPolicy",
      "organizations:Cancel*",
      "organizations:CloseAccount",
      "organizations:Create*",
      "organizations:Decline*",
      "organizations:Delete*",
      "organizations:Deregister*",
      "organizations:DetachPolicy",
      "organizations:Disable*",
      "organizations:Enable*",
      "organizations:Invite*",
      "organizations:LeaveOrganization",
      "organizations:MoveAccount",
      "organizations:Put*",
      "organizations:Register*",
      "organizations:Remove*",
      "organizations:TagResource",
      "organizations:UntagResource",
      "organizations:Update*",
      "sso:*",
      "sso-admin:*",
      "identitystore:*",
      "sts:AssumeRole",
    ]

    resources = ["*"]
  }

  statement {
    sid    = "DenyAuditAndDetectionTampering"
    effect = "Deny"

    actions = [
      "cloudtrail:DeleteTrail",
      "cloudtrail:PutEventSelectors",
      "cloudtrail:PutInsightSelectors",
      "cloudtrail:StopLogging",
      "cloudtrail:UpdateTrail",
      "config:Delete*",
      "config:PutConfigurationRecorder",
      "config:PutDeliveryChannel",
      "config:StopConfigurationRecorder",
      "guardduty:DeleteDetector",
      "guardduty:DeleteMembers",
      "guardduty:Disassociate*",
      "guardduty:StopMonitoringMembers",
      "guardduty:UpdateDetector",
      "securityhub:BatchDisableStandards",
      "securityhub:DeleteMembers",
      "securityhub:DisableSecurityHub",
      "securityhub:Disassociate*",
      "securityhub:UpdateStandardsControl",
    ]

    resources = ["*"]
  }

  statement {
    sid    = "DenyKeyDestruction"
    effect = "Deny"

    actions = [
      "kms:DisableKey",
      "kms:PutKeyPolicy",
      "kms:ScheduleKeyDeletion",
    ]

    resources = ["*"]
  }
}

resource "aws_iam_policy" "this" {
  # checkov:skip=CKV_AWS_289:The wildcard is the allow half of a permissions boundary, which grants nothing by itself. Explicit denies cap escalation, detection tampering and key destruction.
  # checkov:skip=CKV_AWS_355:The boundary must be reusable across arbitrary workload resources. It grants nothing; attached identity policies still provide the resource-level allow.
  name        = "${var.project}-permissions-boundary"
  description = "Maximum permissions for customer-managed member-account roles"
  policy      = data.aws_iam_policy_document.this.json
}
