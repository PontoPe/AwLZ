# Detection verification

Stack: `live/detection`. Initial verification: 2026-07-28, within an hour of
apply. GuardDuty membership reverified: 2026-07-30T13:47:05-03:00.

Account IDs redacted. Delegated administrator is `awlz-security`.

## Verified

| Control | Check | Result |
|---|---|---|
| Config recorder — mgmt | `describe-configuration-recorder-status` | `recording: true`, `lastStatus: SUCCESS` |
| Config recorder — security | same | `recording: true`, `SUCCESS` |
| Config recorder — log-archive | same | `recording: true`, `SUCCESS` |
| Config recorder — dev | same | `recording: true`, `SUCCESS` |
| Config recorder — lab | same | `recording: true`, `SUCCESS` |
| Config aggregator | created in `awlz-security` | org-wide, all regions |
| GuardDuty | `describe-organization-configuration` | `AutoEnableOrganizationMembers: ALL` |
| GuardDuty members | delegated `list-members --only-associated` | four of four `Enabled` |
| Security Hub | `get-enabled-standards` | CIS v3.0.0 subscribed |
| Access Analyzer | ORGANIZATION-scope analyzer | created in `awlz-security` |
| Provider placement | `check` block on five recorder account IDs | five distinct accounts |

`lastStatus: SUCCESS` on all five recorders is the load-bearing result. Config validates delivery when the channel is created and again on each write, so SUCCESS means the whole cross-account path works: a recorder in one account, writing through a bucket policy scoped by `aws:SourceAccount`, into a bucket in a second account, encrypted with a CMK in that second account whose key policy grants the recorder role a data key.

That path had three separate defects before it worked. They are recorded in `live/detection/README.md` rather than here, because they are properties of the code, not of the deployment.

## GuardDuty membership — closed 2026-07-30

The delegated detector initially listed three enabled members: log archive, dev
and lab. The management account was the only missing organization account even
though auto-enable was `ALL`.

The management account had no regional detector. This is a GuardDuty special
case: the delegated administrator cannot enable that detector through
`CreateMembers`; it must already exist before association. The detector is now
Terraform-managed. After applying the reviewed one-resource plan, an
idempotent `CreateMembers` call was made only for the still-missing management
account.

Sanitized delegated-administrator query:

```text
Timestamp: 2026-07-30T13:47:05-03:00
Query: list-members --only-associated
AutoEnableOrganizationMembers: ALL
management: Enabled
log-archive: Enabled
dev: Enabled
lab: Enabled
UnexpectedMembers: 0
```

Independent reverse check from the management account:

```text
ManagementDetectorCount: 1
AdministratorMatchesSecurity: PASS
ManagementRelationshipStatus: Enabled
DelegatedMembersEnabled: 4/4
PostApplyTerraformPlan: NO_CHANGES
```

The management exception and `CreateMembers` behavior are documented in the
[GuardDuty API reference](https://docs.aws.amazon.com/guardduty/latest/APIReference/API_CreateMembers.html).

## Security Hub existing-account enrollment

Organization auto-enable did not retroactively enroll the four accounts that
already existed. Terraform now enables Security Hub with default standards off
in management, log archive, dev and lab, associates those accounts to the
delegated administrator, and explicitly subscribes each of the five accounts
to CIS v3.0.0.

The first reviewed apply completed the four account enablements and three
member associations, then stopped because the new management subscription had
not yet propagated to the delegated administrator. No standard subscription
or SCP changed in that failed request. Independent checks found the management
hub enabled, three members `Enabled`, and management as the only missing
member. A second saved plan contained exactly that membership and the four
missing CIS subscriptions; it applied 5 added, 0 changed and 0 destroyed.

Sanitized post-recovery state:

```text
management: CIS v3.0.0 READY, controls READY_FOR_UPDATES
security: CIS v3.0.0 READY, controls READY_FOR_UPDATES
log-archive: CIS v3.0.0 READY, controls READY_FOR_UPDATES
dev: CIS v3.0.0 READY, controls READY_FOR_UPDATES
lab: CIS v3.0.0 READY, controls READY_FOR_UPDATES
Unexpected standard subscriptions: 0
```

## Not yet verified — pending, not passing

The CIS score is time-dependent. Recording it as open rather than backfilling a
claim.

At `2026-07-30T14:11:12-03:00`, every subscription was ready, but the four
accounts enabled today had evaluated only 17–20 of 36 enabled controls. The
older security account had evaluated 35. The partial scores are deliberately
excluded from the baseline. The experiment starts only after the denominator
is stable and the exact query, timestamp and denominator are recorded.

## The baseline problem

The README promises "CIS score before vs after". That framing no longer survives contact with what was built.

The guardrails went in **before** Security Hub did: SCPs, deleted member root credentials, an object-locked audit trail. Any score captured now is already post-hardening. There is no honest "before" left to measure in the organization as a whole.

Two replacements, both defensible, neither of which is the original claim:

1. **Baseline vs remediated.** Capture the first score once controls provision, fix what it flags, capture again. Real delta, real work, but it measures remediation rather than the landing zone.
2. **`awlz-lab` as a control group.** Detach its SCPs, score it, reattach, score again. This directly measures what the guardrails buy, on an account that exists to be broken.

Option 2 is the stronger artifact and is the one this project should ship. It needs the CIS controls provisioned first, so it is queued behind the item above.

The README has been corrected to describe this rather than the original promise.

## Cost note

The measured-input conservative joint projection is USD 23.77/month with CIS
in all five accounts and USD 12.73 with CIS retained only in the delegated
security account. All five subscriptions stay live until this experiment is
valid; the cheaper configuration is applied immediately afterwards. See
`docs/cost.md` for the arithmetic, measurement timestamps and evidence loss.
