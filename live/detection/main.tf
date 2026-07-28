module "detection" {
  source = "../../modules/detection"

  providers = {
    aws             = aws
    aws.security    = aws.security
    aws.log_archive = aws.log_archive
  }

  project                = var.project
  region                 = var.region
  security_account_id    = var.account_ids.security
  log_archive_account_id = var.account_ids.log-archive
  organization_id        = var.organization_id
  recording_account_ids  = concat([var.account_id], values(var.account_ids))
  config_retention_days  = var.config_retention_days
  auto_enable_standards  = var.auto_enable_standards
}

# One recorder per account. Terraform cannot iterate over providers, so these
# are written out rather than generated — five near-identical blocks is the
# honest shape of the problem, and hiding it behind cleverness would make the
# blast radius of each one harder to see.

module "config_mgmt" {
  source = "../../modules/config-recorder"

  providers = { aws = aws }

  project              = var.project
  delivery_bucket_name = module.detection.config_bucket_name
  delivery_kms_key_arn = module.detection.config_kms_key_arn
}

module "config_security" {
  source = "../../modules/config-recorder"

  providers = { aws = aws.security }

  project              = var.project
  delivery_bucket_name = module.detection.config_bucket_name
  delivery_kms_key_arn = module.detection.config_kms_key_arn
}

module "config_log_archive" {
  source = "../../modules/config-recorder"

  providers = { aws = aws.log_archive }

  project              = var.project
  delivery_bucket_name = module.detection.config_bucket_name
  delivery_kms_key_arn = module.detection.config_kms_key_arn
}

module "config_dev" {
  source = "../../modules/config-recorder"

  providers = { aws = aws.dev }

  project              = var.project
  delivery_bucket_name = module.detection.config_bucket_name
  delivery_kms_key_arn = module.detection.config_kms_key_arn
}

module "config_lab" {
  source = "../../modules/config-recorder"

  providers = { aws = aws.lab }

  project              = var.project
  delivery_bucket_name = module.detection.config_bucket_name
  delivery_kms_key_arn = module.detection.config_kms_key_arn
}

# Each recorder reports the account it actually landed in. If a provider is
# misconfigured, this fails loudly at plan time instead of silently creating
# two recorders in one account and none in another.
check "recorders_landed_in_distinct_accounts" {
  assert {
    condition = length(distinct([
      module.config_mgmt.account_id,
      module.config_security.account_id,
      module.config_log_archive.account_id,
      module.config_dev.account_id,
      module.config_lab.account_id,
    ])) == 5

    error_message = "two Config recorders resolved to the same account — check the provider aliases in providers.tf."
  }
}
