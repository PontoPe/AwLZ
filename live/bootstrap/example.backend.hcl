# Copy to backend.hcl (gitignored) and fill in.
#
#   cp example.backend.hcl backend.hcl
#   terraform init -backend-config=backend.hcl
#
# Values come from `terraform output -raw backend_config` on this stack.
# Other stacks reuse the same bucket and key ARN — only `key` changes.

bucket       = "awlz-tfstate-000000000000" # awlz-tfstate-<management account id>
key          = "bootstrap/terraform.tfstate"
region       = "sa-east-1"
profile      = "mgmt"
encrypt      = true
kms_key_id   = "arn:aws:kms:sa-east-1:000000000000:key/00000000-0000-0000-0000-000000000000"
use_lockfile = true
