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

# DEFAULT gives every member account its own CIS score, which is what the
# evidence in docs/evidence/ is measured from. NONE is cheaper and leaves
# member accounts unscored.
auto_enable_standards = "DEFAULT"
