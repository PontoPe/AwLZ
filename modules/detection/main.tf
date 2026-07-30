data "aws_partition" "current" {}

locals {
  config_bucket = "${var.project}-config-${var.log_archive_account_id}"
}

# ---------------------------------------------------------------------------
# Delegated administration
#
# Every one of these is registered from the management account and then does
# its actual work in awlz-security. The management account deliberately runs
# no workloads and holds no detection state — if it is compromised, the
# findings that would show it should not be in the same blast radius.
# ---------------------------------------------------------------------------

resource "aws_guardduty_organization_admin_account" "this" {
  admin_account_id = var.security_account_id
}

# GuardDuty treats the Organizations management account as a special member:
# CreateMembers cannot enable its detector. The detector must already exist
# before the delegated administrator can associate that account.
resource "aws_guardduty_detector" "management" {
  # checkov:skip=CKV2_AWS_3:The management detector is enrolled under the delegated security detector; only the administrator detector owns organization configuration. C1 proves the association.
  enable                       = true
  finding_publishing_frequency = var.guardduty_finding_frequency
}

resource "aws_securityhub_organization_admin_account" "this" {
  admin_account_id = var.security_account_id

  depends_on = [aws_securityhub_account.security]
}

# Config and Access Analyzer delegate through Organizations directly rather
# than through a service-specific resource.
resource "aws_organizations_delegated_administrator" "config" {
  account_id        = var.security_account_id
  service_principal = "config.amazonaws.com"
}

resource "aws_organizations_delegated_administrator" "access_analyzer" {
  account_id        = var.security_account_id
  service_principal = "access-analyzer.amazonaws.com"
}

# ---------------------------------------------------------------------------
# GuardDuty
# ---------------------------------------------------------------------------

resource "aws_guardduty_detector" "security" {
  provider = aws.security

  enable                       = true
  finding_publishing_frequency = var.guardduty_finding_frequency
}

resource "aws_guardduty_organization_configuration" "this" {
  provider = aws.security

  detector_id = aws_guardduty_detector.security.id

  # ALL means accounts added to the organization later are covered without
  # anyone remembering. A new account is the account most likely to be
  # misconfigured, and the one least likely to be on a checklist.
  auto_enable_organization_members = "ALL"

  depends_on = [aws_guardduty_organization_admin_account.this]
}

# ---------------------------------------------------------------------------
# Security Hub
# ---------------------------------------------------------------------------

resource "aws_securityhub_account" "security" {
  provider = aws.security

  enable_default_standards = false
}

resource "aws_securityhub_organization_configuration" "this" {
  provider = aws.security

  auto_enable           = true
  auto_enable_standards = var.auto_enable_standards

  depends_on = [aws_securityhub_organization_admin_account.this]
}

resource "aws_securityhub_standards_subscription" "this" {
  provider = aws.security

  for_each = var.security_standards

  standards_arn = "arn:${data.aws_partition.current.partition}:securityhub:${var.region}::${each.value}"

  depends_on = [aws_securityhub_account.security]
}

# ---------------------------------------------------------------------------
# Access Analyzer — organization scope
#
# Finds resources shared outside the organization: a bucket policy, a role
# trust policy, a KMS grant. Free, and it catches exactly the class of mistake
# an SCP cannot, because sharing a resource is a legitimate action.
# ---------------------------------------------------------------------------


# An ORGANIZATION-scope analyzer created from the delegated administrator
# still requires Access Analyzer's service-linked role to exist in the
# *management* account — it is the management account that reads the org tree.
# Without it, CreateAnalyzer fails with a 409 whose message says the SLR "is
# not in the organizational management account" and nothing about how to fix
# it. Registering delegation does not create the role.
resource "aws_iam_service_linked_role" "access_analyzer" {
  aws_service_name = "access-analyzer.amazonaws.com"
}

resource "aws_accessanalyzer_analyzer" "org" {
  provider = aws.security

  analyzer_name = "${var.project}-org"
  type          = "ORGANIZATION"

  depends_on = [
    aws_organizations_delegated_administrator.access_analyzer,
    aws_iam_service_linked_role.access_analyzer,
  ]
}

# ---------------------------------------------------------------------------
# Config delivery bucket, in the log archive account
#
# Separate from the CloudTrail archive on purpose. That bucket is Object Lock
# COMPLIANCE — anything written there is undeletable for the retention period.
# Config snapshots are high-volume and low-value once superseded, so locking
# them would buy nothing and bill for it indefinitely.
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "config" {
  provider = aws.log_archive

  # checkov:skip=CKV_AWS_144:Cross-region replication would move data out of sa-east-1, against ADR-001. Config snapshots are reproducible from the live account; the irreplaceable record is the CloudTrail archive.
  # checkov:skip=CKV2_AWS_62:No consumer for event notifications. Findings are consumed from Security Hub, not from bucket events.
  # checkov:skip=CKV_AWS_18:Access logging on a log bucket recurses. Access is constrained by the bucket policy and org-scoped conditions; the same reasoning as the CloudTrail archive, recorded on T4.
  bucket = local.config_bucket

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "config" {
  provider = aws.log_archive

  bucket = aws_s3_bucket.config.id

  versioning_configuration {
    status = "Enabled"
  }
}

# A dedicated CMK, not SSE-S3.
#
# The first draft used SSE-S3 to avoid a fourth key at ~USD 1/month. Both
# scanners flagged it HIGH and both were right: this bucket holds a
# configuration snapshot of every account in the organization — resource
# inventory, IAM shape, network layout. That is reconnaissance material, and
# unlike Config's own history it is not cheap to un-leak. A key policy also
# gives a revocation switch the bucket policy alone does not.
resource "aws_kms_key" "config" {
  provider = aws.log_archive

  description             = "Encrypts the ${var.project} AWS Config delivery bucket"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.config_key.json
}

resource "aws_kms_alias" "config" {
  provider = aws.log_archive

  name          = "alias/${var.project}-config"
  target_key_id = aws_kms_key.config.key_id
}

data "aws_iam_policy_document" "config_key" {
  # checkov:skip=CKV_AWS_109:A KMS key policy must delegate to the account root or the key is orphaned. Mandatory per AWS.
  # checkov:skip=CKV_AWS_111:Same statement — delegation to the owning account, not a grant to a principal.
  # checkov:skip=CKV_AWS_356:A key policy's resource is always the key it is attached to.

  statement {
    sid     = "AllowAccountAdministration"
    effect  = "Allow"
    actions = ["kms:*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${var.log_archive_account_id}:root"]
    }

    resources = ["*"]
  }

  # Config writes on behalf of each recording account, so the grant is scoped
  # by source account rather than to a single principal.
  statement {
    sid    = "AllowConfigDelivery"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }

    actions = [
      "kms:GenerateDataKey*",
      "kms:Decrypt",
      "kms:DescribeKey",
    ]

    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = var.recording_account_ids
    }
  }

  # The recorder roles in each account put objects directly, so they need the
  # data key too. Scoped to the organization.
  statement {
    sid    = "AllowOrgRecorders"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions = [
      "kms:GenerateDataKey*",
      "kms:Decrypt",
      "kms:DescribeKey",
    ]

    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalOrgID"
      values   = [var.organization_id]
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "config" {
  provider = aws.log_archive

  bucket = aws_s3_bucket.config.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.config.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "config" {
  provider = aws.log_archive

  bucket = aws_s3_bucket.config.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "config" {
  provider = aws.log_archive

  bucket = aws_s3_bucket.config.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "config" {
  provider = aws.log_archive

  bucket = aws_s3_bucket.config.id

  rule {
    id     = "expire-config-history"
    status = "Enabled"

    filter {}

    expiration {
      days = var.config_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.config]
}

resource "aws_s3_bucket_policy" "config" {
  provider = aws.log_archive

  bucket = aws_s3_bucket.config.id
  policy = data.aws_iam_policy_document.config_bucket.json

  depends_on = [aws_s3_bucket_public_access_block.config]
}

data "aws_iam_policy_document" "config_bucket" {
  statement {
    sid    = "AWSConfigBucketPermissionsCheck"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }

    actions   = ["s3:GetBucketAcl", "s3:ListBucket"]
    resources = [aws_s3_bucket.config.arn]

    # aws:SourceAccount, not aws:PrincipalOrgID. Config calls as the service
    # principal config.amazonaws.com, and a service principal carries no
    # PrincipalOrgID — that key describes IAM principals. A policy conditioned
    # on it can never match, and S3 reports the result as
    # InsufficientDeliveryPolicyException with no mention of the condition.
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = var.recording_account_ids
    }
  }

  statement {
    sid    = "AWSConfigBucketDelivery"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.config.arn}/AWSLogs/*"]

    # No s3:x-amz-acl condition. This bucket is BucketOwnerEnforced, so ACLs
    # are disabled and the header is never sent — the same trap that stopped
    # CloudTrail from writing to the archive bucket. See live/logging/README.md.
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = var.recording_account_ids
    }
  }

  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions   = ["s3:*"]
    resources = [aws_s3_bucket.config.arn, "${aws_s3_bucket.config.arn}/*"]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

# ---------------------------------------------------------------------------
# Organization-wide Config aggregator
#
# Recorders are per account; this is the single pane that reads all of them.
# ---------------------------------------------------------------------------

resource "aws_iam_role" "aggregator" {
  provider = aws.security

  name                 = "${var.project}-config-aggregator"
  assume_role_policy   = data.aws_iam_policy_document.aggregator_assume.json
  permissions_boundary = var.security_permissions_boundary_arn
}

data "aws_iam_policy_document" "aggregator_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "aggregator" {
  provider = aws.security

  role       = aws_iam_role.aggregator.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSConfigRoleForOrganizations"
}

resource "aws_config_configuration_aggregator" "org" {
  provider = aws.security

  name = "${var.project}-org"

  organization_aggregation_source {
    all_regions = true
    role_arn    = aws_iam_role.aggregator.arn
  }

  depends_on = [
    aws_organizations_delegated_administrator.config,
    aws_iam_role_policy_attachment.aggregator,
  ]
}
