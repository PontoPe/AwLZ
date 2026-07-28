# Copy to terraform.tfvars (gitignored) and fill in.
#
#   cp example.tfvars terraform.tfvars

project = "awlz"
region  = "sa-east-1"
profile = "mgmt"

account_id      = "000000000000" # management account ID, 12 digits
organization_id = "o-xxxxxxxxxx" # aws organizations describe-organization

# Emails are permanent in practice — closing an account starts a 90-day
# suspension and the address cannot be reused until it ends. Check them twice.
member_accounts = {
  log-archive = { email = "you+aws-log-archive@example.com", ou = "Security" }
  security    = { email = "you+aws-security@example.com", ou = "Security" }
  dev         = { email = "you+aws-dev@example.com", ou = "Workloads" }
  lab         = { email = "you+aws-lab@example.com", ou = "Workloads" }
}
