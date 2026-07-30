provider "aws" {
  region              = var.region
  profile             = var.profile != "" ? var.profile : null
  allowed_account_ids = [var.account_id]

  default_tags {
    tags = {
      Project   = var.project
      Stack     = "ci-oidc"
      ManagedBy = "terraform"
      Repo      = "github.com/PontoPe/AwLZ"
    }
  }
}

provider "aws" {
  alias               = "security"
  region              = var.region
  profile             = var.profile != "" ? var.profile : null
  allowed_account_ids = [var.account_ids.security]

  assume_role {
    role_arn     = "arn:aws:iam::${var.account_ids.security}:role/${var.member_role_name}"
    session_name = "${var.project}-ci-oidc"
  }
}

provider "aws" {
  alias               = "log_archive"
  region              = var.region
  profile             = var.profile != "" ? var.profile : null
  allowed_account_ids = [var.account_ids.log-archive]

  assume_role {
    role_arn     = "arn:aws:iam::${var.account_ids.log-archive}:role/${var.member_role_name}"
    session_name = "${var.project}-ci-oidc"
  }
}

provider "aws" {
  alias               = "dev"
  region              = var.region
  profile             = var.profile != "" ? var.profile : null
  allowed_account_ids = [var.account_ids.dev]

  assume_role {
    role_arn     = "arn:aws:iam::${var.account_ids.dev}:role/${var.member_role_name}"
    session_name = "${var.project}-ci-oidc"
  }
}

provider "aws" {
  alias               = "lab"
  region              = var.region
  profile             = var.profile != "" ? var.profile : null
  allowed_account_ids = [var.account_ids.lab]

  assume_role {
    role_arn     = "arn:aws:iam::${var.account_ids.lab}:role/${var.member_role_name}"
    session_name = "${var.project}-ci-oidc"
  }
}
