# SCP verification — `awlz-lab`

Date: 2026-07-28. Stack: `live/guardrails`. Target: the `awlz-lab` account, the only attachment at time of writing.

Tests run as `OrganizationAccountAccessRole` assumed from the management account — a principal with `AdministratorAccess`. That is the point: an SCP is the only thing that can deny an account administrator, so a test as anything less privileged would prove nothing.

Session credentials came from `sts:AssumeRole` and were never written to disk.

| Policy | ID | Probe | Result |
|---|---|---|---|
| `deny-unapproved-regions` | `p-6ogkgy2n` | `ec2:DescribeVpcs` in `sa-east-1` | **allowed** — returned `vpc-0aa9ecb2a3f34d277` |
| `deny-unapproved-regions` | `p-6ogkgy2n` | `ec2:DescribeVpcs` in `eu-west-1` | **explicit deny** |
| `protect-security-services` | `p-yxl15m5m` | `cloudtrail:StopLogging` | **explicit deny** |
| `protect-security-services` | `p-yxl15m5m` | `guardduty:DeleteDetector` | **explicit deny** |
| `protect-guardrail-roles` | `p-jd382c9k` | `iam:DeleteRole` on `awlz-does-not-exist` | **explicit deny** |
| `protect-guardrail-roles` | `p-jd382c9k` | `iam:DeleteRole` on `unrelated-does-not-exist` | **`NoSuchEntity`** — not denied |

## Why the probes target things that do not exist

Each denied probe names a resource that was never created — a trail called `no-such-trail`, an all-zero detector ID, a role that does not exist.

If the SCP were missing or misscoped, these calls would come back `TrailNotFound`, `BadRequest`, or `NoSuchEntity`. They come back as an explicit deny instead, which means authorization was evaluated and refused *before* AWS looked for the resource. That distinguishes a working deny from a call that failed for an unrelated reason — and it means nothing had to be created or destroyed to prove it.

## The last row is the important one

`iam:DeleteRole` on an unprotected role name returns `NoSuchEntity`, not a deny. The role protection is scoped to `awlz-*` and `OrganizationAccountAccessRole` as intended, rather than blanket-denying `iam:DeleteRole` across the account.

Without this control, the five rows above are also consistent with an SCP that denies far more than intended — which would look like a pass and behave like an outage.

## Raw output

```
$ aws ec2 describe-vpcs --region eu-west-1
An error occurred (UnauthorizedOperation) when calling the DescribeVpcs operation:
You are not authorized to perform this operation. User:
arn:aws:sts::<lab-account-id>:assumed-role/OrganizationAccountAccessRole/awlz-scp-verify
is not authorized to perform: ec2:DescribeVpcs with an explicit deny in a service
control policy: .../service_control_policy/p-6ogkgy2n

$ aws cloudtrail stop-logging --name no-such-trail --region sa-east-1
An error occurred (AccessDeniedException) when calling the StopLogging operation:
... explicit deny in a service control policy: .../service_control_policy/p-yxl15m5m

$ aws guardduty delete-detector --detector-id 00000000000000000000000000000000 --region sa-east-1
An error occurred (AccessDeniedException) when calling the DeleteDetector operation:
... explicit deny in a service control policy: .../service_control_policy/p-yxl15m5m

$ aws iam delete-role --role-name awlz-does-not-exist
An error occurred (AccessDenied) when calling the DeleteRole operation:
... explicit deny in a service control policy: .../service_control_policy/p-jd382c9k

$ aws iam delete-role --role-name unrelated-does-not-exist
An error occurred (NoSuchEntity) when calling the DeleteRole operation:
The role with name unrelated-does-not-exist cannot be found.
```

## Not yet covered

- Policies are attached to `awlz-lab` only. `awlz-dev`, and the Security OU accounts, are unguarded until `scp_targets` widens.
- `protect-security-services` currently defends nothing real — the org trail does not exist until `modules/logging`. It is in place first so the trail is never briefly unprotected.
- No probe for the Identity Center role gap noted in `policies/scp/README.md`, because that protection is deliberately absent.
