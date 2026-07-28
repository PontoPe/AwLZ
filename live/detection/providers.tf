# Five providers, one per account. AWS Config has no organization-wide
# auto-enable, so a recorder has to be created in each account individually —
# there is no way around naming them all.
#
# Every one assumes OrganizationAccountAccessRole. No static credentials.

provider "aws" {
  region              = var.region
  profile             = var.profile
  allowed_account_ids = [var.account_id]

  default_tags {
    tags = local.tags
  }
}

provider "aws" {
  alias               = "security"
  region              = var.region
  profile             = var.profile
  allowed_account_ids = [var.account_ids.security]

  assume_role {
    role_arn     = "arn:aws:iam::${var.account_ids.security}:role/OrganizationAccountAccessRole"
    session_name = "${var.project}-detection"
  }

  default_tags {
    tags = local.tags
  }
}

provider "aws" {
  alias               = "log_archive"
  region              = var.region
  profile             = var.profile
  allowed_account_ids = [var.account_ids.log-archive]

  assume_role {
    role_arn     = "arn:aws:iam::${var.account_ids.log-archive}:role/OrganizationAccountAccessRole"
    session_name = "${var.project}-detection"
  }

  default_tags {
    tags = local.tags
  }
}

provider "aws" {
  alias               = "dev"
  region              = var.region
  profile             = var.profile
  allowed_account_ids = [var.account_ids.dev]

  assume_role {
    role_arn     = "arn:aws:iam::${var.account_ids.dev}:role/OrganizationAccountAccessRole"
    session_name = "${var.project}-detection"
  }

  default_tags {
    tags = local.tags
  }
}

provider "aws" {
  alias               = "lab"
  region              = var.region
  profile             = var.profile
  allowed_account_ids = [var.account_ids.lab]

  assume_role {
    role_arn     = "arn:aws:iam::${var.account_ids.lab}:role/OrganizationAccountAccessRole"
    session_name = "${var.project}-detection"
  }

  default_tags {
    tags = local.tags
  }
}
