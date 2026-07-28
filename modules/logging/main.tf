locals {
  bucket_name = "${var.project}-org-trail-${var.log_archive_account_id}"
  trail_name  = "${var.project}-org-trail"

  # Organization trails write under AWSLogs/<org-id>/<account-id>/, not the
  # single-account AWSLogs/<account-id>/ path. Getting this wrong produces a
  # trail that creates cleanly and then silently fails to deliver.
  trail_arn = "arn:aws:cloudtrail:${var.region}:${data.aws_caller_identity.mgmt.account_id}:trail/${local.trail_name}"
}

data "aws_caller_identity" "mgmt" {}

# ---------------------------------------------------------------------------
# KMS — in the log archive account, not the management account
#
# The key and the objects it protects live in the account that the management
# account can be compromised without. CloudTrail encrypts with it at write
# time, so an attacker holding the management account still cannot read the
# archive without also holding a key grant here.
# ---------------------------------------------------------------------------

resource "aws_kms_key" "trail" {
  provider = aws.log_archive

  description             = "Encrypts the ${var.project} organization CloudTrail archive"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.trail_key.json
}

resource "aws_kms_alias" "trail" {
  provider = aws.log_archive

  name          = "alias/${var.project}-org-trail"
  target_key_id = aws_kms_key.trail.key_id
}

data "aws_iam_policy_document" "trail_key" {
  # checkov:skip=CKV_AWS_109:A KMS key policy must delegate to the account root or the key is orphaned and unrecoverable. AWS documents this statement as mandatory.
  # checkov:skip=CKV_AWS_111:Same statement. `kms:*` on the account root is delegation, not a grant to a principal; actual access is gated by IAM in that account.
  # checkov:skip=CKV_AWS_356:A key policy's resource is always the key it is attached to. `*` cannot widen it.

  statement {
    sid     = "AllowAccountAdministration"
    effect  = "Allow"
    actions = ["kms:*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.log_archive_account_id}:root"]
    }

    resources = ["*"]
  }

  # CloudTrail runs in the management account but encrypts into this key.
  #
  # The binding condition is the *encryption context*, not just SourceArn.
  # CloudTrail passes the trail ARN as `aws:cloudtrail:arn` in the encryption
  # context on every GenerateDataKey call, and that is what the key policy has
  # to authorise. A policy with SourceArn alone fails with
  # InsufficientEncryptionPolicyException at CreateTrail — the trail is never
  # created, so there is nothing to debug after the fact.
  statement {
    sid    = "AllowCloudTrailGenerateDataKey"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions   = ["kms:GenerateDataKey*"]
    resources = ["*"]

    condition {
      test     = "StringLike"
      variable = "kms:EncryptionContext:aws:cloudtrail:arn"
      values   = ["arn:aws:cloudtrail:*:${data.aws_caller_identity.mgmt.account_id}:trail/*"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }
  }

  # DescribeKey carries no encryption context, so it needs its own statement.
  # Folding it into the one above would make that condition unsatisfiable.
  statement {
    sid    = "AllowCloudTrailDescribeKey"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions   = ["kms:DescribeKey"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }
  }

  # Without this, objects are written but nobody in the organization can read
  # them back — including an incident responder.
  statement {
    sid    = "AllowOrgRead"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions   = ["kms:Decrypt", "kms:DescribeKey"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalOrgID"
      values   = [var.organization_id]
    }
  }
}

# ---------------------------------------------------------------------------
# The archive bucket
#
# Object Lock must be enabled when the bucket is created. There is no API to
# add it later — that is why this is its own module rather than something
# bolted onto an existing bucket.
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "trail" {
  provider = aws.log_archive

  # checkov:skip=CKV_AWS_144:Cross-region replication would copy the org's complete audit trail out of sa-east-1, against the residency decision in ADR-001. Object Lock plus versioning is the durability control here.
  # checkov:skip=CKV2_AWS_62:Event notifications on the archive have no consumer. Detection subscribes to the CloudWatch Logs stream instead, which is why that delivery exists.
  # checkov:skip=CKV_AWS_18:Server access logging on a log archive means either logging into itself — a delivery loop that bills per object forever — or a second archive with the same question one level up. Access is instead constrained by the bucket policy, the KMS key policy, and org-scoped read. Recorded as residual risk on T4.
  bucket              = local.bucket_name
  object_lock_enabled = true

  lifecycle {
    prevent_destroy = true
  }
}

# Object Lock requires versioning, and enabling Object Lock at creation
# implies it. Declared anyway so the intent survives a future refactor.
resource "aws_s3_bucket_versioning" "trail" {
  provider = aws.log_archive

  bucket = aws_s3_bucket.trail.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_object_lock_configuration" "trail" {
  provider = aws.log_archive

  bucket = aws_s3_bucket.trail.id

  rule {
    default_retention {
      mode = var.object_lock_mode
      days = var.object_lock_retention_days
    }
  }

  depends_on = [aws_s3_bucket_versioning.trail]
}

resource "aws_s3_bucket_server_side_encryption_configuration" "trail" {
  provider = aws.log_archive

  bucket = aws_s3_bucket.trail.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.trail.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "trail" {
  provider = aws.log_archive

  bucket = aws_s3_bucket.trail.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "trail" {
  provider = aws.log_archive

  bucket = aws_s3_bucket.trail.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "trail" {
  provider = aws.log_archive

  bucket = aws_s3_bucket.trail.id

  rule {
    id     = "archive-then-keep"
    status = "Enabled"

    filter {}

    # Object Lock blocks deletion, not storage class transitions. Cold storage
    # is how a long retention stays affordable.
    transition {
      days          = var.glacier_transition_days
      storage_class = "GLACIER_IR"
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.trail]
}

resource "aws_s3_bucket_policy" "trail" {
  provider = aws.log_archive

  bucket = aws_s3_bucket.trail.id
  policy = data.aws_iam_policy_document.trail_bucket.json

  depends_on = [aws_s3_bucket_public_access_block.trail]
}

data "aws_iam_policy_document" "trail_bucket" {
  statement {
    sid    = "AWSCloudTrailAclCheck"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.trail.arn]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }
  }

  statement {
    sid    = "AWSCloudTrailWrite"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions = ["s3:PutObject"]

    # Organization trails write under AWSLogs/<org-id>/, and CloudTrail also
    # probes AWSLogs/<mgmt-account-id>/ during setup. Both prefixes, and
    # nothing wider.
    resources = [
      "${aws_s3_bucket.trail.arn}/AWSLogs/${var.organization_id}/*",
      "${aws_s3_bucket.trail.arn}/AWSLogs/${data.aws_caller_identity.mgmt.account_id}/*",
    ]

    # No s3:x-amz-acl condition. The bucket sets BucketOwnerEnforced, which
    # disables ACLs outright, so CloudTrail does not send that header and a
    # policy requiring it can never match. The AWS-published example predates
    # ACL-disabled buckets; copying it verbatim yields a trail that cannot
    # write and an error naming the bucket rather than the condition.
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
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
    resources = [aws_s3_bucket.trail.arn, "${aws_s3_bucket.trail.arn}/*"]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  # Read access for the organization, so an investigation does not require
  # credentials minted in the log archive account itself.
  statement {
    sid    = "AllowOrgRead"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions   = ["s3:GetObject", "s3:ListBucket"]
    resources = [aws_s3_bucket.trail.arn, "${aws_s3_bucket.trail.arn}/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalOrgID"
      values   = [var.organization_id]
    }
  }
}

# ---------------------------------------------------------------------------
# CloudWatch Logs delivery
#
# S3 is the durable archive; CloudWatch Logs is what anything can subscribe to
# in near real time. CIS requires the pairing, and metric filters and alarms
# on trail events have nowhere to attach without it.
#
# Retention is short by default: this is a live tail for detection, not the
# system of record. The system of record is the object-locked bucket.
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "trail" {
  # checkov:skip=CKV_AWS_338:One-year retention belongs on the system of record, which is the object-locked S3 archive. This is a 14-day tail for alarms and subscriptions; a second year-long copy would double the bill to defend nothing the archive does not already cover.
  # checkov:skip=CKV_AWS_158:A dedicated CMK here would be a third key at ~USD 1/month against a hard USD 20 budget, to protect a transient copy whose durable original is already CMK-encrypted in another account. CloudWatch Logs is encrypted at rest with an AWS-owned key regardless. Revisit when the budget rises or when this group starts carrying data the archive does not — see docs/cost.md.

  name              = "/aws/cloudtrail/${local.trail_name}"
  retention_in_days = var.cloudwatch_retention_days
}

resource "aws_iam_role" "trail_to_cwlogs" {
  name               = "${var.project}-cloudtrail-to-cwlogs"
  assume_role_policy = data.aws_iam_policy_document.trail_assume.json
}

data "aws_iam_policy_document" "trail_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    # Without this, any account able to make CloudTrail call sts on its behalf
    # could assume the role — the confused deputy this condition exists for.
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }
  }
}

resource "aws_iam_role_policy" "trail_to_cwlogs" {
  name   = "${var.project}-cloudtrail-to-cwlogs"
  role   = aws_iam_role.trail_to_cwlogs.id
  policy = data.aws_iam_policy_document.trail_to_cwlogs.json
}

data "aws_iam_policy_document" "trail_to_cwlogs" {
  statement {
    effect = "Allow"

    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    # Scoped to this log group's streams, not logs:* on everything.
    resources = ["${aws_cloudwatch_log_group.trail.arn}:log-stream:*"]
  }
}

# ---------------------------------------------------------------------------
# The trail — created in the management account
# ---------------------------------------------------------------------------

resource "aws_cloudtrail" "org" {
  # checkov:skip=CKV_AWS_252:An SNS topic on trail delivery notifies that a log file landed, which is not detection. Detection subscribes to the CloudWatch Logs stream configured above, and GuardDuty consumes the trail directly. An always-on topic would add cost and no signal.

  name           = local.trail_name
  s3_bucket_name = aws_s3_bucket.trail.id

  is_organization_trail         = true
  is_multi_region_trail         = true
  include_global_service_events = true

  # Detects post-hoc modification of delivered log files. Without it, the
  # archive is trustworthy only as far as S3 permissions are.
  enable_log_file_validation = true

  kms_key_id = aws_kms_key.trail.arn

  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.trail.arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.trail_to_cwlogs.arn

  # Data events, scoped. `advanced_event_selector` is the only form that can
  # name individual buckets; the legacy `event_selector` cannot.
  dynamic "advanced_event_selector" {
    for_each = length(var.data_event_bucket_arns) > 0 ? [1] : []

    content {
      name = "S3 data events for explicitly listed buckets"

      field_selector {
        field  = "eventCategory"
        equals = ["Data"]
      }

      field_selector {
        field  = "resources.type"
        equals = ["AWS::S3::Object"]
      }

      field_selector {
        field       = "resources.ARN"
        starts_with = [for arn in var.data_event_bucket_arns : "${arn}/"]
      }
    }
  }

  # Selecting any advanced selector replaces the default "all management
  # events" behaviour, so management events have to be asked for explicitly
  # once data events are in play.
  dynamic "advanced_event_selector" {
    for_each = length(var.data_event_bucket_arns) > 0 ? [1] : []

    content {
      name = "All management events"

      field_selector {
        field  = "eventCategory"
        equals = ["Management"]
      }
    }
  }

  depends_on = [
    aws_s3_bucket_policy.trail,
    aws_kms_key.trail,
  ]
}
