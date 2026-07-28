provider "aws" {
  region  = var.region
  profile = var.profile

  # SCPs can only be managed from the organization's management account.
  allowed_account_ids = [var.account_id]

  default_tags {
    tags = {
      Project   = var.project
      Stack     = "guardrails"
      ManagedBy = "terraform"
      Repo      = "github.com/PontoPe/AwLZ"
    }
  }
}
