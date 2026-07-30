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

# Local Security Hub organization configuration auto-enables only accounts that
# join after it is configured. These four accounts already existed, so their
# enablement, membership and CIS subscription are explicit Terraform resources.
#
# Default standards stay off here. The portfolio evidence is CIS v3.0.0; also
# enabling FSBP and CIS v1.2.0 would add checks, cost and a second denominator
# without strengthening the benchmark this project claims.
resource "aws_securityhub_account" "management" {
  enable_default_standards = false
}

resource "aws_securityhub_account" "log_archive" {
  provider = aws.log_archive

  enable_default_standards = false
}

resource "aws_securityhub_account" "dev" {
  provider = aws.dev

  enable_default_standards = false
}

resource "aws_securityhub_account" "lab" {
  provider = aws.lab

  enable_default_standards = false
}

resource "aws_securityhub_member" "existing" {
  provider = aws.security

  for_each = {
    management  = var.account_id
    log_archive = var.account_ids.log-archive
    dev         = var.account_ids.dev
    lab         = var.account_ids.lab
  }

  account_id = each.value
  invite     = false

  depends_on = [
    module.detection,
    aws_securityhub_account.management,
    aws_securityhub_account.log_archive,
    aws_securityhub_account.dev,
    aws_securityhub_account.lab,
  ]
}

resource "aws_securityhub_standards_subscription" "management" {
  for_each = module.detection.security_hub_standards

  standards_arn = each.value

  depends_on = [aws_securityhub_member.existing]
}

resource "aws_securityhub_standards_subscription" "log_archive" {
  provider = aws.log_archive

  for_each = module.detection.security_hub_standards

  standards_arn = each.value

  depends_on = [aws_securityhub_member.existing]
}

resource "aws_securityhub_standards_subscription" "dev" {
  provider = aws.dev

  for_each = module.detection.security_hub_standards

  standards_arn = each.value

  depends_on = [aws_securityhub_member.existing]
}

resource "aws_securityhub_standards_subscription" "lab" {
  provider = aws.lab

  for_each = module.detection.security_hub_standards

  standards_arn = each.value

  depends_on = [aws_securityhub_member.existing]
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
