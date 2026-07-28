# Copy to backend.hcl (gitignored) and fill in.
# Values from: cd ../bootstrap && terraform output -raw backend_config

bucket       = "awlz-tfstate-000000000000"
key          = "detection/terraform.tfstate"
region       = "sa-east-1"
profile      = "mgmt"
encrypt      = true
kms_key_id   = "arn:aws:kms:sa-east-1:000000000000:key/00000000-0000-0000-0000-000000000000"
use_lockfile = true
