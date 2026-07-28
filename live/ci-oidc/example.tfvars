# Copy to terraform.tfvars (gitignored) and fill in.
#
# ARNs from: cd ../bootstrap && terraform output

project = "awlz"
region  = "sa-east-1"
profile = "mgmt"

account_id = "000000000000"

github_repository = "PontoPe/AwLZ"
apply_environment = "production"

state_bucket_arn  = "arn:aws:s3:::awlz-tfstate-000000000000"
state_kms_key_arn = "arn:aws:kms:sa-east-1:000000000000:key/00000000-0000-0000-0000-000000000000"
