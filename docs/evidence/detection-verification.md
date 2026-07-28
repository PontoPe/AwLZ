# Detection verification

Stack: `live/detection`. Date: 2026-07-28, within an hour of apply.

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
| Security Hub | `get-enabled-standards` | CIS v3.0.0 subscribed |
| Access Analyzer | ORGANIZATION-scope analyzer | created in `awlz-security` |
| Provider placement | `check` block on five recorder account IDs | five distinct accounts |

`lastStatus: SUCCESS` on all five recorders is the load-bearing result. Config validates delivery when the channel is created and again on each write, so SUCCESS means the whole cross-account path works: a recorder in one account, writing through a bucket policy scoped by `aws:SourceAccount`, into a bucket in a second account, encrypted with a CMK in that second account whose key policy grants the recorder role a data key.

That path had three separate defects before it worked. They are recorded in `live/detection/README.md` rather than here, because they are properties of the code, not of the deployment.

## Not yet verified — pending, not passing

Both of these are time-dependent. Recording them as open rather than waiting and backfilling a claim.

**GuardDuty member enrollment.** `list-members` returns empty. `AutoEnableOrganizationMembers` is `ALL`, which covers existing accounts as well as future ones, but enrollment is asynchronous and had not completed at the time of writing. Re-check:

```bash
aws guardduty list-members --detector-id <id> --region sa-east-1
```

Four members expected, `RelationshipStatus: Enabled`. If they are still absent after a few hours, existing accounts may need explicit `create-members` — auto-enable is documented to cover them, so that would be worth confirming before writing it up.

**CIS score.** `StandardsStatus` is `INCOMPLETE` and `get-findings` returns zero. Security Hub provisions controls over roughly 24 hours and evaluates against Config data that does not exist yet — the recorders started minutes ago. A score captured now would read as 0% and mean nothing.

## The baseline problem

The README promises "CIS score before vs after". That framing no longer survives contact with what was built.

The guardrails went in **before** Security Hub did: SCPs, deleted member root credentials, an object-locked audit trail. Any score captured now is already post-hardening. There is no honest "before" left to measure in the organization as a whole.

Two replacements, both defensible, neither of which is the original claim:

1. **Baseline vs remediated.** Capture the first score once controls provision, fix what it flags, capture again. Real delta, real work, but it measures remediation rather than the landing zone.
2. **`awlz-lab` as a control group.** Detach its SCPs, score it, reattach, score again. This directly measures what the guardrails buy, on an account that exists to be broken.

Option 2 is the stronger artifact and is the one this project should ship. It needs the CIS controls provisioned first, so it is queued behind the item above.

The README has been corrected to describe this rather than the original promise.

## Cost note

This stack is the entire recurring bill. Security Hub with `auto_enable_standards = "DEFAULT"` is projected at USD 4–18/month against a USD 20 budget — the single largest line and the one most likely to force a decision. See `docs/cost.md` for the arithmetic and the one-line lever that reduces it.
