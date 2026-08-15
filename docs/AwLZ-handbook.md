# Handoff — AwLZ

State of the project as of **2026-08-15**; cost measured 2026-08-04. Written for a person picking this up cold, including the person who built it.

`AGENTS.md` is the agent-facing version: rules, conventions, gotchas. This one is the situation report.

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
| `live/guardrails` | 4 SCPs attached to both OUs, including the boundary requirement |
| `live/logging` | Org trail → Object Lock COMPLIANCE 30d archive in a separate account; 14-day CloudWatch tail; T8 break-glass alarm on a CMK-encrypted topic |
| `live/detection` | GuardDuty ×5 + Security Hub CIS 3.0.0 in the delegated administrator + Config ×5 + Access Analyzer + T5 permission boundaries and their Config rule |
| `live/ci-oidc` | OIDC provider, read-only plan role, `awlz-gha-plan-readonly` per member account, admin apply role gated by the `production` environment |

**CI is green and enforcing.** `fmt`, `tflint`, `trivy`, `checkov`, `validate` across six stacks, and a real `terraform plan` against AWS via OIDC for **all six** — `logging`, `detection` and `ci-oidc` rejoined the plan matrix once the member read-only roles existed, so CI holds administrator nowhere. `main` requires a pull request *and* passing checks — a red run cannot merge.

Gate baseline: **checkov 477 passed / 0 failed / 69 skipped**, trivy and tflint clean. Every skip carries a written reason inline; several carry a threat-model ID and the stack that closes it.

## What is not done

**Nothing is open on a deadline.** C1–C7 are complete: cost actuals closed on
2026-08-04 against the first billable window.

One measurement is still ahead rather than overdue. GuardDuty and Security Hub
are inside their trials until late August, and July was fully covered by
credits, so **September 2026 is the first month whose invoice represents what
this organization actually costs.** Both distortions are named in `docs/cost.md`
beside the numbers they affect.

The maintenance list — what goes stale, where, and what refreshes it — is in
[TrustStack/docs/ROADMAP.md](../../TrustStack/docs/ROADMAP.md).

Everything that was open on 2026-07-28 is closed:
Everything else that was open on 2026-07-28 is closed:

**CIS score — done, and the result is negative.** `awlz-lab` was measured with
its SCPs, without them, and after reattachment. All 35 controls are identical in
both states, because no CIS v3.0.0 control reads an SCP. A benchmark score
describes resource configuration; it cannot describe a preventive guardrail. The
behavioural probes — denied, allowed, denied again — are what show the SCPs
working. Full write-up in `docs/evidence/scp-verification.md`.

> The README originally promised "CIS score **before vs after**". That was not obtainable — the guardrails went in before Security Hub did, so there is no un-hardened "before" left organization-wide. The lab control group replaced it, and it returned a null result that is published as one.

**GuardDuty member enrollment — closed.** The management account had no regional
detector, and the delegated administrator cannot create one through
`CreateMembers`. The detector is Terraform-managed now and all four members are
`Enabled`, verified from both directions.

**T5 and T8 — live.** Permission boundaries in four accounts with a Config rule
that detects any customer role without one, an SCP requiring the boundary on new
roles, and a CloudWatch alarm on assumption of the four recovery-role ARNs. The
alarm reached `ALARM` on real assumptions rather than a synthetic metric.

**Least-privilege CI — live.** `awlz-gha-plan-readonly` per member account,
trusting only the management plan role, holding `ReadOnlyAccess` and the T5
boundary.

## Budget

**USD 20/month ceiling**, alerts at 85% and 100% actual plus 100% forecast.

**USD 4.05/month is fixed** — four CMKs: Terraform state, the CloudTrail
archive, the Config delivery bucket, and the break-glass alarm topic. The fourth
was added on 2026-07-30 because `alias/aws/sns` accepts no key policy, and an
alert announcing recovery-role use is exactly what an attacker would want to
read or suppress.

The cost lever was decided and applied rather than left as a note. Five CIS
subscriptions projected **USD 24.77/month** jointly with PontoAntiCrack, over
the ceiling. CIS v3.0.0 is now retained in `awlz-security` only, with
future-account auto-enable at `NONE`:

```hcl
auto_enable_standards    = "NONE"
member_standards_enabled = false
```

That projects **USD 13.73/month**, leaving USD 6.27 of headroom. What is lost is
the live per-account score; the timestamped C3 artifact remains. GuardDuty's
first 30 days are free, so **August will understate the steady state**. Do not
read the first invoice as representative.

## Working on it

```bash
aws sso login --profile mgmt
aws sts get-caller-identity --profile mgmt     # ARN must contain AWSReservedSSO_AdministratorAccess
cd live/<stack>
terraform init -backend-config=backend.hcl
```

Sessions last twelve hours. Log out explicitly when the work is finished.

`main` is protected, so changes go through a branch and a PR. Concrete IDs live in gitignored `terraform.tfvars` and `backend.hcl`; `example.*` files are the committed templates. To recover the real values:

```bash
cd live/org-root  && terraform output      # account ids, OU ids, org id
cd live/bootstrap && terraform output -raw backend_config
```

Windows toolchain notes — nothing is on `PATH` in a fresh shell, and PowerShell mangles `-var-file=` — are in `AGENTS.md`.

## Traps this project already hit

Each cost an apply. All are documented where they bite; collected here because they are the reason several design choices look odd.

- **The guardrails blocked their own deployment, twice.** `config:PutConfigurationRecorder` both creates and neuters a recorder; `awlz-config-aggregator` matched the protected `awlz-*` prefix. Both SCPs now separate *destructive* actions (never exempt) from actions deployment also needs (deployment principals exempt). ADR-014.
- **`aws:PrincipalOrgID` does not exist on a service principal.** Config calls as `config.amazonaws.com`; the condition could never match, and S3 reported it as a delivery-policy failure.
- **The AWS-published CloudTrail bucket policy is wrong for ACL-disabled buckets.** It requires `s3:x-amz-acl`, which is never sent when `BucketOwnerEnforced` is set.
- **CloudTrail KMS access keys off the encryption context**, not `aws:SourceArn` alone. `DescribeKey` carries no encryption context and needs its own statement.
- **The GitHub OIDC `sub` is not `repo:owner/name`.** This repo gets immutable subject claims: `repo:PontoPe@96898980/AwLZ@1315312585`. Read yours with `gh api repos/<owner>/<name>/actions/oidc/customization/sub`. Nothing in the STS error hints at it, and the tempting fix — `StringLike` — would match a fork's pull request.
- **S3 server access logging cannot cross accounts.** The original plan for T6b was impossible; CloudTrail data events replaced it and are better.
- **`checkov-action` runs a 2021 Docker image** regardless of which release you pin. It produced three false positives on a bucket that was fine. CI installs checkov from pip at the same version used locally.
- **SNS rejects `sns:*` in a topic policy.** `SetTopicAttributes` fails the whole call with "Policy statement action out of service scope", so the topic is created and left with no policy at all while the alarm never gets attached. The owner statement has to name the topic-scoped actions.
- **`alias/aws/sns` cannot carry a key policy.** Which is why the break-glass topic has its own CMK: nothing else bounds who decrypts an alert announcing recovery-role use, and the grant cannot be revoked independently of SNS.
- **`iam list-roles` does not return `PermissionsBoundary`.** Adoption has to be read with `get-role`, one role at a time. A boundary that silently failed to attach looks identical to one that worked if you check with `list-roles`.
- **`StartConfigRulesEvaluation` is rate limited to roughly one rule at a time.** Firing a batch returns `LimitExceededException` after the first success or two. Pace it and retry, or accept a subset and say which.
- **Git Bash rewrites arguments that look like paths.** `--log-group-name /aws/lambda/x` reaches `aws.exe` as `C:/...` and comes back as a regex validation error that says nothing about path conversion. `MSYS_NO_PATHCONV=1` fixes it; the same class of bug makes `file://` parameters fail on Windows CLI builds.
- **A quota is per account, not per organization.** The Lambda concurrency increase had to be requested inside `awlz-lab`, not in management — the management value was irrelevant to a function deployed in the member account.

## Where to read next

| Question | File |
|---|---|
| Why is it built this way? | `docs/architecture.md` — 19 ADRs |
| What is it defending against? | `docs/threat-model.md` — T1–T9 with residual risk |
| Do the controls actually work? | `docs/evidence/` |
| What will it cost? | `docs/cost.md` |
| How do I not break it? | `AGENTS.md` |

Each stack also has its own README covering what it creates and what went wrong building it.

## Next session, in order

Items 1–4 and 6 of the previous list are done and merged in
[PR #11](https://github.com/PontoPe/AwLZ/pull/11). What remains:

1. **Re-measure cost after 2026-09-01.** July was credit-covered and both
   detection services were inside their trials, so August is the first
   uncredited month and September the first fully representative one. Use the
   query in `docs/cost.md` **with its `RECORD_TYPE` filter** — without it,
   credits net usage to zero and a healthy Config recorder reads as USD 0.
2. **Hand the boundary finding to PontoAntiCrack.** The T5 Config rule reports
   `pac-sg-open-remediation`, `pac-s3-public-remediation` and
   `pac-iam-key-leak-remediation` in `awlz-lab` as `NON_COMPLIANT`; they predate
   the boundary. That is the sibling owner's call — adopt the boundary or record
   an exception. Do not modify another project's roles from here.
