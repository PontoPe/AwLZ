# One AWS Config recorder, for one account.
#
# Config has no organization-wide auto-enable the way GuardDuty and Security
# Hub do — a recorder is a per-account, per-region resource. So this module is
# instantiated once per account with a different provider each time, which is
# also why it takes no provider alias of its own: the caller decides where it
# lands.
#
# Most CIS controls are evaluated from Config data. Without a recorder in an
# account, that account scores as "no data" rather than "compliant", which is
# worse than failing because it looks fine on a summary.

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

resource "aws_iam_role" "config" {
  name               = "${var.project}-config-recorder"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

data "aws_iam_policy_document" "assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

# The AWS-managed policy for Config. Read-only across the account plus the
# describe/list calls the recorder needs; it does not grant delivery.
resource "aws_iam_role_policy_attachment" "config" {
  role       = aws_iam_role.config.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWS_ConfigRole"
}

# Delivery is granted separately and scoped to this account's prefix in the
# shared bucket, so a recorder cannot write over another account's history.
resource "aws_iam_role_policy" "delivery" {
  name   = "${var.project}-config-delivery"
  role   = aws_iam_role.config.id
  policy = data.aws_iam_policy_document.delivery.json
}

data "aws_iam_policy_document" "delivery" {
  statement {
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["arn:${data.aws_partition.current.partition}:s3:::${var.delivery_bucket_name}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]
  }

  statement {
    effect    = "Allow"
    actions   = ["s3:GetBucketAcl", "s3:ListBucket"]
    resources = ["arn:${data.aws_partition.current.partition}:s3:::${var.delivery_bucket_name}"]
  }

  # The delivery bucket defaults to SSE-KMS, so writing an object requires a
  # data key. Without this the recorder is created, reports healthy, and
  # delivery fails — Config surfaces that only in the delivery channel status,
  # not as an error on anything Terraform touched.
  statement {
    effect = "Allow"

    actions = [
      "kms:GenerateDataKey",
      "kms:GenerateDataKey*",
      "kms:Decrypt",
      "kms:DescribeKey",
    ]

    resources = [var.delivery_kms_key_arn]
  }
}

resource "aws_config_configuration_recorder" "this" {
  name     = "${var.project}-recorder"
  role_arn = aws_iam_role.config.arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = var.record_global_resource_types
  }
}

resource "aws_config_delivery_channel" "this" {
  name           = "${var.project}-delivery"
  s3_bucket_name = var.delivery_bucket_name

  # Required when the bucket defaults to SSE-KMS. Config validates that it can
  # write *at channel creation time* and refuses with
  # InsufficientDeliveryPolicyException if the key is not named here — even
  # though the bucket would have applied it by default. The error text spells
  # out `provided kms key is 'null'`, which is the only clue.
  s3_kms_key_arn = var.delivery_kms_key_arn

  depends_on = [aws_config_configuration_recorder.this]
}

# A recorder that exists but is not recording is the failure mode this module
# is most likely to leave behind — it looks configured and produces nothing.
resource "aws_config_configuration_recorder_status" "this" {
  name       = aws_config_configuration_recorder.this.name
  is_enabled = true

  depends_on = [aws_config_delivery_channel.this]
}
