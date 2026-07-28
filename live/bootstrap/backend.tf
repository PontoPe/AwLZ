# Partial backend configuration. The bucket name embeds the account ID, so the
# concrete values live in backend.hcl (gitignored) alongside terraform.tfvars —
# same reasoning, same convention.
#
#   terraform init -backend-config=backend.hcl
#
# `terraform output -raw backend_config` on this stack prints the block for any
# other stack; change only the `key`.
terraform {
  backend "s3" {}
}
