# Partial backend configuration — see live/bootstrap/backend.tf for why.
#
#   cp example.backend.hcl backend.hcl
#   terraform init -backend-config=backend.hcl
terraform {
  backend "s3" {}
}
