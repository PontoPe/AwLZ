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

## C3 — the `awlz-lab` control experiment, 2026-07-30

The README promised a before/after comparison that no longer exists: the
guardrails were in place before Security Hub was. The honest replacement is a
control experiment in the throwaway account — measure `awlz-lab` with its SCPs,
remove them from that account only, measure again, put them back.

### Only the lab was ever unprotected

The three SCPs are attached to the **Workloads OU**, which holds `awlz-lab` and
`awlz-dev`. Detaching them from the OU would have stripped `awlz-dev` too, so
the transition was made gapless from `awlz-dev`'s point of view:

1. attach all three directly to `awlz-dev` — it now holds them twice over;
2. detach all three from the OU — `awlz-lab` loses them, `awlz-dev` does not;
3. reattach all three to the OU — `awlz-lab` is protected again;
4. only then remove the temporary direct attachments from `awlz-dev`.

Reattachment ran from a shell trap, so it would have executed even if the
measurement had failed or the run had been interrupted.

```text
Window open:   2026-07-30T15:18:14-03:00
Window closed: 2026-07-30T15:23:34-03:00
Duration:      5m20s, awlz-lab only
```

### Behaviour changed exactly when the policy did

Both probes name resources that do not exist, so nothing was created or
destroyed to produce these results.

| Probe | With SCP | Without SCP | After reattach |
|---|---|---|---|
| `ec2:DescribeVpcs` in `eu-west-1` | explicit deny by SCP | **allowed** | explicit deny by SCP |
| `cloudtrail:StopLogging` on `no-such-trail` | explicit deny by SCP | **`TrailNotFound`** | explicit deny by SCP |

The second row is the sharper one. Without the SCP the call is authorized and
fails only because the trail is absent, which separates "the guardrail is off"
from "the call failed for some other reason".

### The CIS score did not move

| Measurement | Passed | Failed | Unknown | Denominator |
|---|---:|---:|---:|---:|
| `awlz-lab` with SCPs | 24 | 11 | 0 | 35 |
| `awlz-lab` without SCPs | 24 | 11 | 0 | 35 |

Control by control, all 35 are identical. Failing in both: `Account.1`,
`Config.1`, `EC2.6`, `EC2.7`, `IAM.15`, `IAM.16`, `IAM.18`, `IAM.28`, `S3.1`,
`S3.22`, `S3.23`.

The second measurement is not a stale copy of the first. `StartConfigRulesEvaluation`
is rate limited to roughly one rule at a time, so a subset was triggered in each
phase; three rules recorded a successful evaluation inside each phase's boundary:

```text
phase A (SCPs attached)   securityhub-access-keys-rotated          15:11:45
                          securityhub-ec2-ebs-encryption-by-default 15:12:25
                          securityhub-vpc-flow-logs-enabled         15:15:30
phase B (SCPs detached)   securityhub-access-keys-rotated          15:19:18
                          securityhub-ec2-ebs-encryption-by-default 15:19:51
                          securityhub-vpc-flow-logs-enabled         15:22:57
```

### What this proves, and what it does not

**Proves:** the guardrails were genuinely off for `awlz-lab` during the window
and genuinely on either side of it, and a CIS v3.0.0 score is blind to that.
Not one of the 35 controls reads an SCP. A benchmark score is a statement about
resource configuration; a preventive control is a statement about what nobody
can do to that configuration. Reporting the score as evidence that the
guardrails work — which the earlier README implied — was measuring the wrong
thing.

**Does not prove:** that SCPs never affect a CIS score anywhere. A guardrail
that blocks a *remediation* would eventually show up as a failed control. It
also says nothing about the 11 controls that fail: those are real findings in a
sandbox account, unrelated to the experiment.

### Restoration was verified independently

```text
OU Workloads : FullAWSAccess  awlz-deny-unapproved-regions  awlz-protect-guardrail-roles  awlz-protect-security-services
awlz-lab     : FullAWSAccess
awlz-dev     : FullAWSAccess
```

`terraform plan` on `live/guardrails` after the run reports **0 to change, 0 to
destroy**; the only pending actions are the not-yet-applied
`require-permissions-boundary` policy and its two attachments. The out-of-band
detach and reattach left no drift, matching the earlier recovery incident.

## `require-permissions-boundary` — attached 2026-07-30

The fourth SCP is now on both member OUs. It denies `iam:CreateRole` and
`iam:PutRolePermissionsBoundary` unless the request carries the exact account
boundary ARN, and protects the boundary policy itself.

### The exemption was probed; the deny branch cannot be

As `OrganizationAccountAccessRole` in `awlz-lab`, `iam:CreateRole` **without** a
boundary returns `MalformedPolicyDocument`, not a deny — authorization passed
and the deliberately malformed trust document stopped the request before
anything was created. That is the property that matters most here: the recovery
path is still able to build a role when a boundary has locked something out.

The opposite branch has no honest live probe. Exercising it needs a non-exempt
principal that can call `iam:CreateRole`, and every such principal in a member
account would have to be created without a boundary — which is precisely what
this control forbids. A principal *with* the boundary cannot create roles at
all, since the boundary denies `iam:Create*`. Rather than weaken a control to
photograph it, the deny logic is covered by five `cfn-guard` 3.2.0 cases
(boundary present, two legitimate exceptions, boundary absent, wrong boundary)
and by the detective rule below.

### The Config rule found real drift on its first evaluation

`awlz-role-permissions-boundary` in `awlz-lab`:

| Result | Role |
|---|---|
| `COMPLIANT` | `awlz-config-recorder` |
| `COMPLIANT` | `awlz-gha-plan-readonly` |
| `NON_COMPLIANT` | `pac-sg-open-remediation` |
| `NON_COMPLIANT` | `pac-s3-public-remediation` |
| `NON_COMPLIANT` | `pac-iam-key-leak-remediation` |

The three non-compliant roles belong to the sibling PontoAntiCrack deployment
and predate the boundary. They are reported here and left alone: they are
another owner's resources, and the preventive SCP only governs roles created
from now on. This is the split the control was designed around — the SCP stops
new unbounded roles, the Config rule surfaces the ones already there.
