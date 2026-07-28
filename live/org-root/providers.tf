provider "aws" {
  region  = var.region
  profile = var.profile

  # Organizations is a management-account API. Running this anywhere else
  # would either fail loudly or, worse, act on a different organization.
  allowed_account_ids = [var.account_id]

  default_tags {
    tags = {
      Project   = var.project
      Stack     = "org-root"
      ManagedBy = "terraform"
      Repo      = "github.com/PontoPe/AwLZ"
    }
  }
}
