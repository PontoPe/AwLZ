# Handoff — AwLZ

State of the project as of **2026-07-28**. Written for a person picking this up cold, including the person who built it.

`CLAUDE.md` is the agent-facing version: rules, conventions, gotchas. This one is the situation report.

---

## What this is

A multi-account AWS landing zone in Terraform — the governance layer an organization sits on, not an application. AWS Organizations, service control policies, an immutable org-wide audit trail, and detection, all as reproducible code.

Built as a portfolio artifact for cloud-security roles. That shapes one thing more than any other:

> **The deliverable is not working infrastructure. It is reproducible infrastructure plus evidence that the controls do what the documentation claims.**

Anyone can apply a Terraform module. The parts worth showing are `docs/evidence/`, where each control is probed and the result recorded — including the ones that failed, and the two occasions a guardrail blocked its own deployment.

Repo is **public**: `github.com/PontoPe/AwLZ`.

## The organization

```
Management account (pegradowski-mgmt)
│  Organizations, SCPs, Identity Center, Terraform state, org trail
│
├── OU: Security
│   ├── awlz-log-archive    object-locked CloudTrail archive + its own CMK
│   └── awlz-security       delegated admin: GuardDuty, Security Hub, Config, Access Analyzer
│
└── OU: Workloads
    ├── awlz-dev
    └── awlz-lab            control group for the CIS experiment; consumed by PontoAntiCrack
```

Home region `sa-east-1` (Brazil data residency). `us-east-1` is also permitted by the region SCP because global services report there regardless — removing it breaks the organization.

**Member accounts have no root credentials.** `RootCredentialsManagement` deleted them. Break-glass is `OrganizationAccountAccessRole`, assumed from the management account.

## What is live

All six stacks applied against real AWS and verified. Everything below was checked, not assumed.

| Stack | State |
|---|---|
| `live/bootstrap` | S3 state + CMK, versioning, TLS-only, native locking |
| `live/org-root` | 2 OUs, 4 accounts ACTIVE, centralized root access on, 8 trusted service principals |
| `live/guardrails` | 3 SCPs attached to both OUs |
| `live/logging` | Org trail → Object Lock COMPLIANCE 30d archive in a separate account; 14-day CloudWatch tail |
| `live/detection` | GuardDuty + Security Hub CIS 3.0.0 + Config ×5 accounts + Access Analyzer, delegated |
| `live/ci-oidc` | OIDC provider, read-only plan role, admin apply role gated by the `production` environment |

**CI is green and enforcing.** `fmt`, `tflint`, `trivy`, `checkov`, `validate` across six stacks, and a real `terraform plan` against AWS via OIDC. `main` requires a pull request *and* passing checks — a red run cannot merge.

Gate baseline: **checkov 376 passed / 0 failed / 21 skipped**, trivy and tflint clean. Every skip carries a written reason inline; several carry a threat-model ID and the stack that closes it.

## What is not done

Three things, and none of them are code.

**1. CIS score — waiting on AWS.** Security Hub is `PENDING` with 37 findings and climbing; controls provision over roughly 24 hours against Config data that only started flowing today. A score captured now would be an artifact of timing.

When it settles, run the experiment in `docs/evidence/detection-verification.md`: detach `awlz-lab`'s SCPs, score it, reattach, score again. That measures what the guardrails buy, on an account that exists to be broken.

> The README originally promised "CIS score **before vs after**". That is no longer obtainable — the guardrails went in before Security Hub did, so there is no un-hardened "before" left organization-wide. The lab control group is the honest replacement, and the docs say so rather than quietly redefining the claim.

**2. Cost actuals — waiting on billing.** Cost Explorer returns `DataUnavailableException` for an organization created today. `docs/cost.md` has estimates with the arithmetic shown and is explicit that they are not measurements.

**3. GuardDuty member enrollment — unconfirmed.** This is the one control that is configured but **not demonstrated**. `AutoEnableOrganizationMembers` is `ALL`, but `list-members` returned 0 for over an hour after apply.

```bash
aws guardduty list-members --detector-id <id> --region sa-east-1
```

Expect four members, `RelationshipStatus: Enabled`. If still empty, existing accounts may need explicit `create-members` despite auto-enable being documented to cover them. Treat it as open until the output says otherwise.

## Budget

**USD 20/month ceiling**, alerts at 85% and 100% actual plus 100% forecast.

Roughly **USD 3/month is fixed** (three CMKs). The variable part is detection, projected **USD 11–36/month total** — which straddles the ceiling.

**Security Hub is the risk.** At `auto_enable_standards = "DEFAULT"` it is projected USD 4–18/month on its own, because per-account CIS scoring is what the evidence needs. The lever is one line in `live/detection/terraform.tfvars`:

```hcl
auto_enable_standards = "NONE"
```

GuardDuty's first 30 days are free, so **August will understate the steady state**. Do not read the first invoice as representative.

## Working on it

```bash
aws sso login --profile mgmt
aws sts get-caller-identity --profile mgmt     # ARN must contain AWSReservedSSO_AdministratorAccess
cd live/<stack>
terraform init -backend-config=backend.hcl
```

Sessions last one hour. Re-login is routine.

`main` is protected, so changes go through a branch and a PR. Concrete IDs live in gitignored `terraform.tfvars` and `backend.hcl`; `example.*` files are the committed templates. To recover the real values:

```bash
cd live/org-root  && terraform output      # account ids, OU ids, org id
cd live/bootstrap && terraform output -raw backend_config
```

Windows toolchain notes — nothing is on `PATH` in a fresh shell, and PowerShell mangles `-var-file=` — are in `CLAUDE.md`.

## Traps this project already hit

Each cost an apply. All are documented where they bite; collected here because they are the reason several design choices look odd.

- **The guardrails blocked their own deployment, twice.** `config:PutConfigurationRecorder` both creates and neuters a recorder; `awlz-config-aggregator` matched the protected `awlz-*` prefix. Both SCPs now separate *destructive* actions (never exempt) from actions deployment also needs (deployment principals exempt). ADR-014.
- **`aws:PrincipalOrgID` does not exist on a service principal.** Config calls as `config.amazonaws.com`; the condition could never match, and S3 reported it as a delivery-policy failure.
- **The AWS-published CloudTrail bucket policy is wrong for ACL-disabled buckets.** It requires `s3:x-amz-acl`, which is never sent when `BucketOwnerEnforced` is set.
- **CloudTrail KMS access keys off the encryption context**, not `aws:SourceArn` alone. `DescribeKey` carries no encryption context and needs its own statement.
- **The GitHub OIDC `sub` is not `repo:owner/name`.** This repo gets immutable subject claims: `repo:PontoPe@96898980/AwLZ@1315312585`. Read yours with `gh api repos/<owner>/<name>/actions/oidc/customization/sub`. Nothing in the STS error hints at it, and the tempting fix — `StringLike` — would match a fork's pull request.
- **S3 server access logging cannot cross accounts.** The original plan for T6b was impossible; CloudTrail data events replaced it and are better.
- **`checkov-action` runs a 2021 Docker image** regardless of which release you pin. It produced three false positives on a bucket that was fine. CI installs checkov from pip at the same version used locally.

## Where to read next

| Question | File |
|---|---|
| Why is it built this way? | `docs/architecture.md` — 15 ADRs |
| What is it defending against? | `docs/threat-model.md` — T1–T9 with residual risk |
| Do the controls actually work? | `docs/evidence/` |
| What will it cost? | `docs/cost.md` |
| How do I not break it? | `CLAUDE.md` |

Each stack also has its own README covering what it creates and what went wrong building it.

## Next session, in order

1. Re-check GuardDuty enrollment. Close it or fix it.
2. Once Security Hub settles, capture the CIS baseline and run the `awlz-lab` control-group experiment.
3. Permission boundaries + a Config rule for T5; a CloudWatch alarm on break-glass role assumption for T8. Both are open items in the threat model.
4. Give CI a read-only role per member account so `live/logging` and `live/detection` can rejoin the plan matrix — they are excluded because planning them currently needs an admin role, and a PR-triggered role must not hold that.
5. Cost actuals after a billing cycle.
6. Demo recording.
