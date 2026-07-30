# Copy to terraform.tfvars (gitignored) and fill in.
#
# IDs from: cd ../org-root && terraform output account_ids organization_id

project = "awlz"
region  = "sa-east-1"
profile = "mgmt"

account_id      = "000000000000" # management account
organization_id = "o-xxxxxxxxxx"

account_ids = {
  log-archive = "000000000000"
  security    = "000000000000"
  dev         = "000000000000"
  lab         = "000000000000"
}

config_retention_days = 90

# Applies only to future accounts. Existing accounts and the CIS v3.0.0
# benchmark used by docs/evidence/ are explicit Terraform resources.
# DEFAULT enables AWS's FSBP and CIS v1.2.0 defaults; NONE avoids those extra
# checks.
auto_enable_standards = "NONE"

# The C3 experiment is captured; the four member subscriptions are off for cost.
member_standards_enabled = false
