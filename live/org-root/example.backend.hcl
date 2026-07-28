# Copy to backend.hcl (gitignored) and fill in.
#
#   cp example.backend.hcl backend.hcl
#   terraform init -backend-config=backend.hcl
#
# Same bucket and key as every other stack — only `key` differs.
# Values from: cd ../bootstrap && terraform output -raw backend_config

bucket       = "awlz-tfstate-000000000000" # awlz-tfstate-<management account id>
key          = "org-root/terraform.tfstate"
region       = "sa-east-1"
profile      = "mgmt"
encrypt      = true
kms_key_id   = "arn:aws:kms:sa-east-1:000000000000:key/00000000-0000-0000-0000-000000000000"
use_lockfile = true
