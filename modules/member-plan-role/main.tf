data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [var.management_plan_role_arn]
    }

    # The principal is already exact. Keeping the condition makes a future
    # trust-policy refactor fail closed if the Principal is ever widened.
    condition {
      test     = "ArnEquals"
      variable = "aws:PrincipalArn"
      values   = [var.management_plan_role_arn]
    }
  }
}

resource "aws_iam_role" "this" {
  name                 = "${var.project}-gha-plan-readonly"
  description          = "Read-only cross-account Terraform refresh for GitHub OIDC plans"
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  permissions_boundary = var.permissions_boundary_arn
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "readonly" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/ReadOnlyAccess"
}
