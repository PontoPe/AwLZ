# Copy to terraform.tfvars (gitignored) and fill in.
#
#   cp example.tfvars terraform.tfvars

project    = "awlz"
region     = "sa-east-1"
profile    = "mgmt"         # the SSO profile from `aws configure sso`
account_id = "000000000000" # management account ID, 12 digits
