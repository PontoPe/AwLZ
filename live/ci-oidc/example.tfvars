# Copy to terraform.tfvars (gitignored) and fill in.
#
# ARNs from: cd ../bootstrap && terraform output

project = "awlz"
region  = "sa-east-1"
profile = "mgmt"

account_id = "000000000000"

account_ids = {
  log-archive = "000000000000"
  security    = "000000000000"
  dev         = "000000000000"
  lab         = "000000000000"
}

github_repository = "PontoPe/AwLZ"
apply_environment = "production"

state_bucket_arn  = "arn:aws:s3:::awlz-tfstate-000000000000"
state_kms_key_arn = "arn:aws:kms:sa-east-1:000000000000:key/00000000-0000-0000-0000-000000000000"

# GitHub may issue immutable subject claims, where the sub prefix embeds
# numeric owner and repo IDs. Read yours with:
#   gh api repos/<owner>/<name>/actions/oidc/customization/sub
# and put the sub_claim_prefix here. Leave empty if it is the plain form.
additional_subject_prefixes = []
