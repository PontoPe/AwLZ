terraform {
  # 1.10+ required: S3 native state locking (use_lockfile) replaces the
  # DynamoDB lock table. One less resource, one less thing to pay for.
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
