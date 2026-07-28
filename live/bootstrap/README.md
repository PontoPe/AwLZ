# bootstrap

Creates the remote state backend that every other stack in this repo uses: an S3 bucket with a customer-managed KMS key, versioning, and TLS-only access.

Run once. Chicken-and-egg by nature — this stack starts with a **local** state file and then migrates its own state into the bucket it just created.

## Why there is no DynamoDB lock table

Terraform 1.10 added native S3 state locking (`use_lockfile = true`): the lock is a `.tflock` object next to the state, using S3 conditional writes. The DynamoDB table is legacy. Fewer resources, no extra bill, one less thing to forget to encrypt.

## Why state lives in the management account

The threat model ([docs/threat-model.md](../../docs/threat-model.md), T6) says state belongs in the security account. That account does not exist yet — this stack runs *before* AWS Organizations creates it. Options were:

1. Bootstrap here, migrate state to the security account later.
2. Bootstrap here, accept it, document it.

**Chosen: 2.** Cross-account state migration costs more operational risk than the residual risk of state living in the management account, which is already the most privileged account in the organization. Anyone who can read state there can already read everything. Recorded as accepted residual risk.

## Run

```bash
cp example.tfvars terraform.tfvars   # fill in profile + account_id
aws sso login --profile mgmt
terraform init
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```

Then migrate this stack's own state into the bucket:

```bash
terraform output -raw backend_config > backend.tf   # set key = "bootstrap/terraform.tfstate"
terraform init -migrate-state
```

Confirm the prompt with `yes`. After migration, delete the local `terraform.tfstate` and `terraform.tfstate.backup`.

## Verify

```bash
aws s3api get-bucket-versioning --bucket $(terraform output -raw state_bucket) --profile mgmt
aws s3api get-public-access-block --bucket $(terraform output -raw state_bucket) --profile mgmt
```

Versioning `Enabled`, all four public access flags `true`.

## Cost

Cents per month. S3 storage for a few hundred KB of state, plus KMS at USD 1.00/month for the key and negligible request charges. `bucket_key_enabled` keeps KMS requests near zero.

## Destroying

`prevent_destroy` is set on the bucket on purpose. Tearing this down orphans every other stack. To do it deliberately: remove the lifecycle block, empty the bucket including all versions, then destroy.
