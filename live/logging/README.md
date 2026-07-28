# logging

The organization CloudTrail trail and its archive. Spans two accounts: the trail is created in the **management** account, the bucket and its key live in **`awlz-log-archive`**.

Wraps [`modules/logging`](../../modules/logging). Depends on `live/org-root` for the account and organization IDs, and on `live/bootstrap` for the state bucket ARN it records data events against.

## Two accounts, no static credentials

The default provider is the management account. A second provider, aliased `log_archive`, assumes `OrganizationAccountAccessRole` in the archive account:

```hcl
provider "aws" {
  alias = "log_archive"
  assume_role {
    role_arn = "arn:aws:iam::<log-archive>:role/OrganizationAccountAccessRole"
  }
}
```

That is the same role that serves as break-glass, and the one `protect-guardrail-roles` defends from deletion. No access key is involved, consistent with ADR-003.

Both providers set `allowed_account_ids`, so a wrong profile fails instead of writing the audit trail into the wrong account.

## What is created

| Where | What |
|---|---|
| `awlz-log-archive` | S3 bucket, Object Lock **COMPLIANCE** 30 days, versioning, CMK, Glacier IR at 90 days, org-scoped read |
| `awlz-log-archive` | KMS CMK with rotation, usable by CloudTrail and readable org-wide |
| management | Organization trail: multi-region, global service events, log file validation, CMK-encrypted |
| management | CloudWatch log group (14 days) + scoped role, so alarms and subscriptions have something to attach to |

## Object Lock is a commitment, not a checkbox

COMPLIANCE mode means **no principal can delete these objects before retention expires** — not the account root, not AWS Support. That is precisely the property that makes the archive worth having: it survives compromise of the management account.

The cost of that property is symmetrical. Until every object's 30 days elapse:

- the bucket cannot be emptied
- the bucket cannot be destroyed
- `terraform destroy` on this stack will fail, and `prevent_destroy` stops it earlier anyway

Retention is deliberately short. A production archive would use years and budget for it; this is a portfolio organization on a hard USD 20/month ceiling, and honesty about that is better than a number chosen to look impressive.

## Data events, deliberately narrow

Management events are free for the first copy. Data events bill per event and are how an organization trail quietly becomes the largest line on the bill.

So `data_event_bucket_arns` is an allow-list, and it currently holds exactly one bucket: the Terraform state bucket. Reads and writes of state are otherwise invisible — that is threat T6b.

**This replaced the original plan.** T6b was going to be closed with S3 server access logging on the state bucket, pointed at the archive. That is not possible: S3 requires a server access logging target to be owned by the same account as the source bucket, and the archive is deliberately in a different account. Data events are the better answer regardless, because they land in the object-locked archive instead of a bucket sitting in the same account as the thing being audited.

## Two policy traps worth knowing

Both produced the same unhelpful error — `InsufficientEncryptionPolicyException: Insufficient permissions to access S3 bucket ... or KMS key ...` — which names the resources and not the mistake.

**The bucket policy must not require `s3:x-amz-acl`.** The AWS-published example includes `"s3:x-amz-acl": "bucket-owner-full-control"`. This bucket sets `BucketOwnerEnforced`, which disables ACLs entirely, so CloudTrail never sends that header and the condition can never match. The published example predates ACL-disabled buckets.

**The key policy must authorise the encryption context.** CloudTrail passes the trail ARN as `kms:EncryptionContext:aws:cloudtrail:arn` on every `GenerateDataKey` call, and that is what has to be allowed. `aws:SourceArn` alone is not sufficient. `kms:DescribeKey` carries no encryption context, so it needs a separate statement — folding it in makes the condition unsatisfiable.

## Run

```bash
cp example.tfvars terraform.tfvars
cp example.backend.hcl backend.hcl
aws sso login --profile mgmt
terraform init -backend-config=backend.hcl
terraform plan -var-file=terraform.tfvars -out=tfplan
terraform apply tfplan
```

## Verify

```bash
aws cloudtrail get-trail-status --name awlz-org-trail --profile mgmt --region sa-east-1
aws cloudtrail describe-trails --trail-name-list awlz-org-trail --profile mgmt --region sa-east-1
aws cloudtrail get-event-selectors --trail-name awlz-org-trail --profile mgmt --region sa-east-1
```

`IsLogging: true`, no `LatestDeliveryError`, `IsOrganizationTrail: true`, `LogFileValidationEnabled: true`.

First delivery takes roughly 5–15 minutes. `LatestDeliveryTime: null` immediately after apply is expected, not a fault.

Results recorded in [docs/evidence/logging-verification.md](../../docs/evidence/logging-verification.md).
