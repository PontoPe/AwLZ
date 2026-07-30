# Copy to terraform.tfvars (gitignored) and fill in.
#
#   cp example.tfvars terraform.tfvars
#
# IDs from:
#   cd ../org-root  && terraform output account_ids organization_id
#   cd ../bootstrap && terraform output state_bucket

project = "awlz"
region  = "sa-east-1"
profile = "mgmt"

account_id             = "000000000000" # management account
log_archive_account_id = "000000000000" # awlz-log-archive
organization_id        = "o-xxxxxxxxxx"

account_ids = {
  log-archive = "000000000000"
  security    = "000000000000"
  dev         = "000000000000"
  lab         = "000000000000"
}

state_bucket_arn = "arn:aws:s3:::awlz-tfstate-000000000000"

# COMPLIANCE means nobody — including root — can delete these objects before
# the retention expires, and the bucket cannot be destroyed until then.
object_lock_mode           = "COMPLIANCE"
object_lock_retention_days = 30
