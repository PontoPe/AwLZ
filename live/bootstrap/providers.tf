provider "aws" {
  region  = var.region
  profile = var.profile != "" ? var.profile : null

  # Refuse to run against the wrong account. The bootstrap stack creates the
  # thing every other stack trusts — a typo'd profile here is expensive.
  allowed_account_ids = [var.account_id]

  default_tags {
    tags = {
      Project   = var.project
      Stack     = "bootstrap"
      ManagedBy = "terraform"
      Repo      = "github.com/PontoPe/AwLZ"
    }
  }
}
