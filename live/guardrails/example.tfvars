# Copy to terraform.tfvars (gitignored) and fill in.
#
#   cp example.tfvars terraform.tfvars

project = "awlz"
region  = "sa-east-1"
profile = "mgmt"

account_id = "000000000000" # management account ID, 12 digits

allowed_regions = ["sa-east-1", "us-east-1"]

# Start with the lab account only. Verify, then widen to OUs.
# IDs from: cd ../org-root && terraform output
scp_targets = {
  deny-unapproved-regions   = ["000000000000"] # lab account id
  protect-security-services = ["000000000000"]
  protect-guardrail-roles   = ["000000000000"]
}

# Once verified, the target rollout is:
#   lab account -> Workloads OU (ou-xxxx-xxxxxxxx) -> Security OU
# Never the org root: the management account is exempt from SCPs anyway, and
# attaching at the root makes the blast radius harder to reason about.
