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

**Already done once, on 2026-07-28.** This section is the reproduction procedure, not a pending task.

The first pass runs with a local state file, because the bucket does not exist yet. Comment out `backend.tf` for that pass.

```bash
cp example.tfvars terraform.tfvars   # fill in profile + account_id
aws sso login --profile mgmt
terraform init
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```

Then migrate this stack's own state into the bucket it just created:

```bash
cp example.backend.hcl backend.hcl   # values from: terraform output -raw backend_config
terraform init -migrate-state -backend-config=backend.hcl
```

Confirm the prompt with `yes`. After migration, delete the local `terraform.tfstate` and `terraform.tfstate.backup` — they are a plaintext copy of the org's full resource graph sitting outside the encrypted bucket.

Every run after that, and every other stack:

```bash
terraform init -backend-config=backend.hcl
```

`backend.tf` declares an empty `backend "s3" {}` on purpose. The bucket name embeds the account ID, so concrete values stay in `backend.hcl`, gitignored next to `terraform.tfvars`.

## Verify

```bash
aws s3api get-bucket-versioning --bucket awlz-tfstate-<account-id> --profile mgmt
aws s3api get-public-access-block --bucket awlz-tfstate-<account-id> --profile mgmt
aws s3api get-bucket-encryption --bucket awlz-tfstate-<account-id> --profile mgmt
aws kms get-key-rotation-status --key-id <key-id> --profile mgmt --region sa-east-1
```

Confirmed on 2026-07-28: versioning `Enabled`; all four public access flags `true`; SSE `aws:kms` with the CMK and `BucketKeyEnabled`; key rotation on, 365-day period. Bucket policy carries `DenyInsecureTransport` and `DenyUnencryptedObjectUploads`.

## Known gap

S3 server access logging is **not** enabled — the target bucket belongs to the log-archive account, which `live/org-root` has yet to create. Tracked as T6b in [docs/threat-model.md](../../docs/threat-model.md), suppressed with that reference in `.trivyignore` (AWS-0089) and `main.tf` (CKV_AWS_18). Closed by `modules/logging`.

## Cost

Cents per month. S3 storage for a few hundred KB of state, plus KMS at USD 1.00/month for the key and negligible request charges. `bucket_key_enabled` keeps KMS requests near zero.

## Destroying

`prevent_destroy` is set on the bucket on purpose. Tearing this down orphans every other stack. To do it deliberately: remove the lifecycle block, empty the bucket including all versions, then destroy.
