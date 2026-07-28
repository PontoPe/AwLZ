terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"

      # This module spans two accounts. `aws` is the management account, where
      # the organization trail lives; `aws.log_archive` is the account that
      # holds the bucket. The caller supplies both.
      configuration_aliases = [aws.log_archive]
    }
  }
}
