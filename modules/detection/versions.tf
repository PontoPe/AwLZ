terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"

      # `aws` is the management account, which is the only place delegation
      # can be registered. `aws.security` is the delegated administrator, where
      # the detectors and the aggregator actually live. `aws.log_archive` owns
      # the Config delivery bucket.
      configuration_aliases = [aws.security, aws.log_archive]
    }
  }
}
