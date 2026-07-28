# SCP verification

Stack: `live/guardrails`. Date: 2026-07-28.

Account IDs are redacted as `<mgmt>`, `<dev>`, `<lab>`. The repo keeps them out of git; nothing about the result depends on the digits.

Tests run as `OrganizationAccountAccessRole`, assumed from the management account — a principal holding `AdministratorAccess`. That is the point: an SCP is the only thing that can deny an account administrator, so a test as anything less privileged would prove nothing. Session credentials came from `sts:AssumeRole` and were never written to disk.

## Round 1 — attached to `awlz-lab` only

| Policy | Probe | Result |
|---|---|---|
| `deny-unapproved-regions` | `ec2:DescribeVpcs` in `sa-east-1` | **allowed** |
| `deny-unapproved-regions` | `ec2:DescribeVpcs` in `eu-west-1` | **explicit deny** |
| `protect-security-services` | `cloudtrail:StopLogging` | **explicit deny** |
| `protect-security-services` | `guardduty:DeleteDetector` | **explicit deny** |
| `protect-guardrail-roles` | `iam:DeleteRole` on `awlz-does-not-exist` | **explicit deny** |
| `protect-guardrail-roles` | `iam:DeleteRole` on `unrelated-does-not-exist` | **`NoSuchEntity`** — not denied |

### Why the probes name things that do not exist

Every denied probe targets a resource that was never created — a trail called `no-such-trail`, an all-zero detector ID, a missing role.

If the policy were absent or misscoped, those calls return `TrailNotFound`, `BadRequest`, or `NoSuchEntity`. They return an explicit deny instead, so authorization was evaluated and refused *before* AWS looked for the resource. That separates a working deny from a call that failed for an unrelated reason, and nothing had to be created or destroyed to show it.

### The last row is the one that matters

`iam:DeleteRole` on an unprotected name returns `NoSuchEntity`, not a deny. The role protection is scoped to `awlz-*` and `OrganizationAccountAccessRole` as intended, rather than blanket-denying `iam:DeleteRole`.

Without that control, the five rows above are equally consistent with a policy that denies far more than intended — which looks like a pass and behaves like an outage.

## Round 2 — widened to the Security and Workloads OUs

`protect-security-services` was split before widening. Attaching the original version to the Security OU would have broken `modules/detection` before it was written: the delegated administrator lives in `awlz-security`, and `config:PutConfigurationRecorder` is both how a recorder is created and how an existing one is neutered.

The policy now has two statements:

- **`DenyDestroyingDetection`** — delete, stop, disable, disassociate. No exemption, applies to everyone.
- **`DenyWeakeningDetectionExceptDeployers`** — reconfiguration calls, exempting `OrganizationAccountAccessRole` and `awlz-*` roles via `ArnNotLike`.

Verified against `awlz-dev`, which had no policy attached during round 1:

| Probe | Expected | Result |
|---|---|---|
| `ec2:DescribeVpcs` in `eu-west-1` | deny | **explicit deny** |
| `cloudtrail:StopLogging` — destructive, no exemption | deny | **explicit deny** |
| `config:PutConfigurationRecorder` — weakening, exempt principal | **not** denied | **succeeded** |

## Incident: the third probe was a mutating call

`config:PutConfigurationRecorder` is not a read. It succeeded, which proved the exemption works — and created a real configuration recorder named `awlz-probe` in `awlz-dev`, pointing at a nonexistent role.

Deleting it needed `config:DeleteConfigurationRecorder`, which is in the destructive statement with **no exemption**. The guardrail worked exactly as designed and blocked the cleanup.

Recovery, from the management account:

1. `organizations detach-policy` — `protect-security-services` off the Workloads OU
2. `configservice delete-configuration-recorder` in `awlz-dev`
3. `organizations attach-policy` — reattach
4. `terraform plan` — no drift; the out-of-band detach and reattach produced the same attachment ID

Three things this is worth recording:

- **The recovery path is real and was exercised.** Detaching an SCP requires the management account, which is exempt from SCPs. That exemption is the only reason a bad policy is survivable, and it now has a worked example rather than an assertion.
- **The probe was badly chosen.** Testing an *allow* by making a mutating call leaves state behind. `describe-configuration-recorders` would have proved nothing about write authorization, so the honest alternative is a mutating call in a throwaway account — `awlz-lab`, not `awlz-dev`.
- **A guardrail that blocks cleanup is working, not broken.** The recorder was created with `recordingScope: PAID` but never started (`recording: false`), so it cost nothing. Had it been recording, the SCP would have stood between the org and an unwanted bill until someone detached it.

## Not yet covered

- `protect-security-services` currently defends nothing real — the org trail does not exist until `modules/logging`. It is in place first so the trail is never briefly unprotected.
- No probe for the Identity Center role gap in `policies/scp/README.md`; that protection is deliberately absent.
- The exemption is only as narrow as the role names. Anything that can create a role matching `awlz-*` inherits it — which is why `protect-guardrail-roles` denies IAM writes on that same prefix.
