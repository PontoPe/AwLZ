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
