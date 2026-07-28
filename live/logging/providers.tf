provider "aws" {
  region  = var.region
  profile = var.profile

  allowed_account_ids = [var.account_id]

  default_tags {
    tags = local.tags
  }
}

# The archive bucket lives in a different account. There are no static
# credentials anywhere in this repo, so the second provider gets there by
# assuming the role Organizations creates in every member account — the same
# role that is the break-glass path, and the one protect-guardrail-roles
# defends against deletion.
provider "aws" {
  alias   = "log_archive"
  region  = var.region
  profile = var.profile

  allowed_account_ids = [var.log_archive_account_id]

  assume_role {
    role_arn     = "arn:aws:iam::${var.log_archive_account_id}:role/OrganizationAccountAccessRole"
    session_name = "${var.project}-logging"
  }

  default_tags {
    tags = local.tags
  }
}
