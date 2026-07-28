# detection

GuardDuty, Security Hub, AWS Config and Access Analyzer, delegated to **`awlz-security`**. Runs from the management account, which registers the delegation and then owns almost none of the result.

Depends on `live/org-root` for account IDs and on `live/guardrails` — see the collision below, which is not optional reading.

## Delegated, not centralised in management

The management account registers delegation and holds nothing else. Detectors, the Security Hub administrator, the Config aggregator and the Access Analyzer all live in `awlz-security`.

If the management account is compromised, the findings that would reveal it should not be in the same blast radius. That is the entire argument, and it is why `modules/detection` needs three providers.

## Five providers, written out longhand

GuardDuty and Security Hub have organization-wide auto-enable. **AWS Config does not.** A configuration recorder is a per-account, per-region resource, so `modules/config-recorder` is instantiated once per account with a different provider each time.

Terraform cannot iterate over providers, so the five blocks are written out rather than generated. That is the honest shape of the problem; hiding it behind cleverness would make each one's blast radius harder to see.

A `check` block asserts the five recorders resolved to five *distinct* accounts. A copy-pasted provider alias would otherwise create two recorders in one account and none in another, and nothing would complain.

Without a recorder, an account scores "no data" against CIS rather than "non-compliant" — worse than failing, because a summary makes it look fine.

## The guardrail blocked its own deployment

`protect-guardrail-roles` denied `iam:AttachRolePolicy` on `awlz-*` roles. The Config aggregator role is `awlz-config-aggregator`. The apply failed on our own SCP.

This is the second time detection collided with a guardrail written before it existed, and the fix follows the same shape as the first:

| Statement | Scope | Exemption |
|---|---|---|
| `ProtectBreakGlassRoleAbsolutely` | `OrganizationAccountAccessRole` | **none** |
| `ProtectGuardrailRolesExceptDeployers` | `awlz-*` | `var.deployment_principal_arns` |

The break-glass role keeps its unconditional protection — that one is the recovery path and nothing legitimately edits it. Roles the landing zone creates for itself have to be manageable by the thing that creates them, or the guardrail simply prevents the landing zone from existing.

The exemption is worth naming honestly: a principal able to create a role matching `awlz-*` inherits it. That is bounded by the same statement denying IAM writes on that prefix to everyone else.

## Four failures worth recording

Each produced an error naming a resource rather than the mistake.

**`InsufficientDeliveryPolicyException` … `provided kms key is 'null'`.** When the delivery bucket defaults to SSE-KMS, `aws_config_delivery_channel` must name the key explicitly. Config validates write access at channel-creation time and will not infer the bucket default.

**The same exception with the key present.** The bucket policy conditioned Config's access on `aws:PrincipalOrgID`. Config calls as the service principal `config.amazonaws.com`, and **a service principal carries no `PrincipalOrgID`** — that key describes IAM principals. The condition could never match. `aws:SourceAccount` against the list of recording accounts is the correct scoping.

**Access Analyzer 409: "Service Linked Role is not in the organizational management account".** An ORGANIZATION-scope analyzer created from the delegated administrator still needs Access Analyzer's service-linked role in the *management* account, because that account reads the org tree. Registering delegation does not create it; `aws_iam_service_linked_role` does.

**The SCP collision above.**

## Cost

This stack is the entire recurring bill.

| Service | Driver |
|---|---|
| GuardDuty | events analysed; 30-day trial hides the real number until month two |
| Config | configuration items recorded, plus rule evaluations |
| Security Hub | control evaluations per account per month |
| KMS | one CMK for the Config bucket |

`auto_enable_standards = "DEFAULT"` gives every member account its own CIS score, which is what the evidence is measured from. `"NONE"` is cheaper and leaves member accounts unscored.

Config history expires after 90 days. CloudTrail is the immutable record of *who changed what*; Config snapshots are inputs to rule evaluation and lose value once superseded.

## Verify

```bash
# per account
aws configservice describe-configuration-recorder-status --region sa-east-1

# in awlz-security
aws guardduty describe-organization-configuration --detector-id <id> --region sa-east-1
aws securityhub get-enabled-standards --region sa-east-1
```

All five recorders `recording: true` / `lastStatus: SUCCESS`, GuardDuty `AutoEnableOrganizationMembers: ALL`, CIS subscribed.

Security Hub reports `StandardsStatus: INCOMPLETE` for a while after enabling, and GuardDuty member enrollment lags the API call. Neither is an error.

Results in [docs/evidence/detection-verification.md](../../docs/evidence/detection-verification.md).
