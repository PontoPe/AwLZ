provider "aws" {
  region  = var.region
  profile = var.profile != "" ? var.profile : null

  allowed_account_ids = [var.account_id]

  default_tags {
    tags = local.tags
  }
}

# The archive bucket lives in a different account. There are no static
# credentials anywhere in this repo, so the second provider gets there by
# assuming a named member role. Local apply uses the Organizations break-glass
# role; CI overrides the name with the dedicated read-only plan role.
provider "aws" {
  alias   = "log_archive"
  region  = var.region
  profile = var.profile != "" ? var.profile : null

  allowed_account_ids = [var.log_archive_account_id]

  assume_role {
    role_arn     = "arn:aws:iam::${var.log_archive_account_id}:role/${var.member_role_name}"
    session_name = "${var.project}-logging"
  }

  default_tags {
    tags = local.tags
  }
}
