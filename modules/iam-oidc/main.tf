data "aws_partition" "current" {}

# ---------------------------------------------------------------------------
# The OIDC provider
#
# GitHub presents a short-lived JWT; AWS exchanges it for temporary
# credentials. No access key is ever created, which is the point — a stolen
# GitHub token cannot be replayed against AWS outside a running workflow, and
# there is nothing in the repo or the runner to leak.
#
# No thumbprint_list. AWS now validates token.actions.githubusercontent.com
# against its own trust store, and a pinned thumbprint is a rotation footgun:
# when GitHub rotates its certificate, a stale thumbprint breaks every
# workflow at once.
# ---------------------------------------------------------------------------

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

locals {
  oidc = aws_iam_openid_connect_provider.github.arn

  # The `sub` claim is the whole security boundary. Anything looser — a
  # wildcard on the repository, or omitting the condition — lets any repository
  # on GitHub assume the role. That is T1, and it is a one-character mistake.
  plan_subs = [
    "repo:${var.github_repository}:pull_request",
    "repo:${var.github_repository}:ref:refs/heads/${var.plan_branch}",
  ]

  apply_subs = [
    "repo:${var.github_repository}:environment:${var.apply_environment}",
  ]
}

data "aws_iam_policy_document" "trust" {
  for_each = {
    plan  = local.plan_subs
    apply = local.apply_subs
  }

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc]
    }

    # Without this, a token issued for any audience would be accepted.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # StringEquals, not StringLike. `repo:owner/name:*` would also match
    # `pull_request` from a fork, which is the exact path that must never hold
    # credentials.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = each.value
    }
  }
}

# ---------------------------------------------------------------------------
# Plan role — read-only
#
# Runs on pull requests, including those a reviewer has not read yet. It must
# not be able to change anything, and it must not be able to read secrets that
# would show up in a plan diff.
# ---------------------------------------------------------------------------

resource "aws_iam_role" "plan" {
  name                 = "${var.project}-gha-plan"
  assume_role_policy   = data.aws_iam_policy_document.trust["plan"].json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "plan_readonly" {
  role       = aws_iam_role.plan.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_role_policy" "plan_state" {
  name   = "${var.project}-gha-plan-state"
  role   = aws_iam_role.plan.id
  policy = data.aws_iam_policy_document.plan_state.json
}

data "aws_iam_policy_document" "plan_state" {
  statement {
    sid       = "ReadState"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:ListBucket"]
    resources = [var.state_bucket_arn, "${var.state_bucket_arn}/*"]
  }

  statement {
    sid       = "DecryptState"
    effect    = "Allow"
    actions   = ["kms:Decrypt", "kms:DescribeKey"]
    resources = [var.state_kms_key_arn]
  }

  # A plan run must not take the state lock. Terraform is told to skip locking
  # for plan-only runs; denying the write here means a misconfigured workflow
  # fails instead of blocking every other run until someone force-unlocks.
  statement {
    sid       = "DenyStateWrites"
    effect    = "Deny"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${var.state_bucket_arn}/*"]
  }
}

# ---------------------------------------------------------------------------
# Apply role — write, gated by the GitHub Environment
#
# Deliberately AdministratorAccess. This role manages organizations, SCPs, KMS
# key policies and cross-account roles; an accurate least-privilege policy for
# that is close to administrator with extra steps and a false sense of
# containment. The real control is the trust policy — only a workflow that
# passed the environment gate can assume it — plus a one-hour session and a
# full CloudTrail record of everything it does.
# ---------------------------------------------------------------------------

resource "aws_iam_role" "apply" {
  name                 = "${var.project}-gha-apply"
  assume_role_policy   = data.aws_iam_policy_document.trust["apply"].json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "apply_admin" {
  role       = aws_iam_role.apply.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AdministratorAccess"
}
