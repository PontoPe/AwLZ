data "aws_caller_identity" "current" {}

locals {
  # S3 bucket names are globally unique. Suffixing with the account ID avoids
  # collisions without leaking anything an attacker can't already enumerate.
  state_bucket = "${var.project}-tfstate-${data.aws_caller_identity.current.account_id}"
}

# ---------------------------------------------------------------------------
# KMS — customer-managed key for state at rest
#
# SSE-S3 would encrypt too, but a CMK gives an auditable key policy and a
# revocation switch. State holds the full resource graph of the organization.
# ---------------------------------------------------------------------------

resource "aws_kms_key" "state" {
  description             = "Encrypts Terraform state for ${var.project}"
  enable_key_rotation     = true
  deletion_window_in_days = 30

  policy = data.aws_iam_policy_document.state_key.json
}

resource "aws_kms_alias" "state" {
  name          = "alias/${var.project}-tfstate"
  target_key_id = aws_kms_key.state.key_id
}

data "aws_iam_policy_document" "state_key" {
  # checkov:skip=CKV_AWS_109:KMS key policies require an unscoped account-root delegation. Without it the key is orphaned and unrecoverable — AWS documents this statement as mandatory.
  # checkov:skip=CKV_AWS_111:Same. `kms:*` on the account root is the delegation statement, not a grant to any principal; actual access is gated by IAM.
  # checkov:skip=CKV_AWS_356:A key policy's resource is always the key itself. `*` here cannot mean anything else.

  # Without this the key is orphaned — IAM cannot grant access to a key whose
  # policy does not delegate to the account.
  statement {
    sid     = "AllowAccountAdministration"
    effect  = "Allow"
    actions = ["kms:*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }

    resources = ["*"]
  }

  statement {
    sid    = "DenyKeyDeletionByAnyoneButAdmins"
    effect = "Deny"

    actions = [
      "kms:ScheduleKeyDeletion",
      "kms:DisableKey",
    ]

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    resources = ["*"]

    condition {
      test     = "StringNotLike"
      variable = "aws:PrincipalArn"
      values   = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-reserved/sso.amazonaws.com/*AdministratorAccess*"]
    }
  }
}

# ---------------------------------------------------------------------------
# S3 — the state bucket
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "state" {
  # checkov:skip=CKV_AWS_144:Cross-region replication is refused deliberately. Data residency is sa-east-1 (see docs/architecture.md); replicating state elsewhere would move the org's full resource graph out of Brazil. Versioning below is the rollback path.
  # checkov:skip=CKV2_AWS_62:Event notifications on a state bucket have no consumer. State access is audited by the org CloudTrail once modules/logging lands.
  # checkov:skip=CKV_AWS_18:Server access logging stays off. S3 requires the logging target bucket to be owned by the same account as the source, so it could never deliver to awlz-log-archive, and logging into the same account as the audited bucket defeats the point. Access is recorded as CloudTrail S3 data events scoped to this bucket in modules/logging, landing in the object-locked archive. T6b, closed.
  bucket = local.state_bucket

  # Deleting this bucket destroys the ability to manage the entire org.
  lifecycle {
    prevent_destroy = true
  }
}

# Versioning is the rollback path. Without it, a corrupted apply is terminal.
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.state.arn
    }
    # Cuts KMS API calls (and cost) by reusing a data key per request batch.
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    object_ownership = "BucketOwnerEnforced" # disables ACLs entirely
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "expire-superseded-state"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.state_retention_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = data.aws_iam_policy_document.state_bucket.json

  depends_on = [aws_s3_bucket_public_access_block.state]
}

data "aws_iam_policy_document" "state_bucket" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.state.arn,
      "${aws_s3_bucket.state.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  statement {
    sid    = "DenyUnencryptedObjectUploads"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.state.arn}/*"]

    condition {
      test     = "StringNotEquals"
      variable = "s3:x-amz-server-side-encryption"
      values   = ["aws:kms"]
    }
  }
}
