# Service control policies

The policy documents. `live/guardrails` creates and attaches them.

They are `templatefile` templates, not plain JSON — `${allowed_regions}` and `${project}` are filled at plan time. That is why they will not parse with a bare `jq`.

Terraform runs each through `jsonencode(jsondecode(...))`, which both validates the JSON and strips whitespace. SCPs have a **5120-byte limit** and pretty-printed JSON burns a surprising amount of it.

## What each one does

### `deny-unapproved-regions.json`

Denies everything outside `sa-east-1` and `us-east-1`, keyed on `aws:RequestedRegion`.

`us-east-1` is in the list because global services report there whether you like it or not — IAM, Organizations, CloudFront, Route 53, and CloudTrail global events. Removing it breaks the organization. This is settled; see the decision table in `AGENTS.md`.

The `NotAction` list covers services with no regional endpoint at all, which would otherwise be denied outright. It is deliberately short: because `us-east-1` is already allowed, most global services are covered without an exemption.

Covers **T3** (actions in an unmonitored region).

### `protect-security-services.json`

Denies the calls that turn off the things that would notice an attack — stopping or deleting a CloudTrail trail, deleting a Config recorder, deleting a GuardDuty detector, disabling Security Hub or an Access Analyzer.

No principal exception. Member accounts have no legitimate reason to touch org-managed detection; the delegated administrator does that from `awlz-security`, which sits outside these targets.

Covers **T2**.

### `protect-guardrail-roles.json`

Denies IAM writes against `${project}-*` roles and `OrganizationAccountAccessRole`.

`OrganizationAccountAccessRole` is the break-glass path into a member account now that centralized root access has removed root credentials. An account that can delete it can lock the organization out of itself.

Identity Center's `aws-reserved/sso.amazonaws.com/*` roles are **not** in scope here. Denying IAM writes on them would break permission-set provisioning, which reprovisions those roles on every change. Protecting them needs a condition that exempts the Identity Center service principal — worth doing, not done yet.

Covers **T5**, partially. Residual risk stays until the permission boundary and its Config rule exist.

## Why there is no blanket root-deny policy

The usual landing zone ships an SCP denying every action where `aws:PrincipalArn` is `arn:aws:iam::*:root`. This one does not, on purpose.

1. `RootCredentialsManagement` has already **deleted** root credentials from every member account. There is no root principal left to deny. See T9.
2. A blanket root deny would also block `RootSessions` — the mechanism that lets the management account perform the handful of genuinely root-only tasks in a member account, audited in CloudTrail. That is the break-glass path. Denying it trades a real recovery capability for a control that is already redundant.

Eliminating the credential beats denying its use. If centralized root access is ever turned off, this decision has to be revisited in the same change.
