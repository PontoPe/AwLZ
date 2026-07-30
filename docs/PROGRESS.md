# Autonomous completion progress

Last updated: **2026-07-30T15:31:39-03:00**

This is the resumable execution ledger for C1–C7. It contains no concrete
account IDs, ARNs, organization IDs, email addresses, or credentials.

## Current state

- Branch: `codex/awlz-autonomous-owner`
- Active item: **C2 cost apply, then C4 and C5 remote work**
- AWS session: management account administrator through IAM Identity Center;
  home region `sa-east-1`; validated without recording identifiers.
- Repository gates: `fmt`, `tflint`, `trivy`, Checkov and `validate` for all six
  live stacks passed on 2026-07-30. With the staged C4, C5 and C7 work,
  Checkov reported 465 passed, 0 failed and 66 justified skips.
- Lab state: the PontoAntiCrack owner reported the lab released with no live
  operation. No lab-targeted plan, apply or SCP experiment was started here.

## Execution log

### C1 — GuardDuty

- Observed organization auto-enable `ALL`.
- Delegated membership was `Enabled` for log archive, dev and lab, but the
  management account was absent.
- Root cause: the management account had no regional detector. GuardDuty
  requires that detector to exist before `CreateMembers`; delegated auto-enable
  cannot create it for this special account.
- Added one Terraform-managed management detector. Saved plan digest prefix
  `9CFBD2E41AF2` contains exactly one create:
  `module.detection.aws_guardduty_detector.management`. No update, replacement
  or destroy; frequency remains `FIFTEEN_MINUTES`.
- Applied exactly that saved plan: 1 added, 0 changed, 0 destroyed.
- Ran `CreateMembers` only for the still-missing management account.
- Independent verification proved one management detector associated with the
  delegated security administrator, all four delegated members `Enabled`, no
  unexpected member and a no-change Terraform plan. Public output is in
  `docs/evidence/detection-verification.md`.

### C2/C3 — Security Hub state and enrollment

- State query found only `awlz-security` subscribed to Security Hub. Its CIS
  v3.0.0 subscription is `READY` and controls are `READY_FOR_UPDATES`.
- Management, log archive, dev and lab were not subscribed. Local organization
  auto-enable does not retroactively cover accounts that already existed.
- ADR-016 makes the existing-account topology explicit: enable Security Hub
  with default standards off, associate the four accounts to the delegated
  administrator, and subscribe all five accounts to CIS v3.0.0 only.
- Reviewed saved plan digest prefix `63D0C52928B4`: 12 creates, 0 updates,
  0 destroys. The creates are four account enablements, four organization
  memberships and four CIS v3.0.0 subscriptions. Every account has
  `enable_default_standards = false`; every member has `invite = false`.
- PontoAntiCrack remained idle with the lab released before planning.
- The reviewed apply enabled the four accounts and associated log archive, dev
  and lab, then stopped safely because Security Hub had not yet propagated the
  management account enablement to the delegated administrator. No standard
  subscription or SCP was changed by the failed request.
- Independent recovery checks proved the management hub enabled, the three
  completed memberships `Enabled`, and management the only missing member.
  Recovery plan digest prefix `6EEAD3F4A491` contained exactly the missing
  management membership and four CIS subscriptions: 5 creates, 0 updates,
  0 destroys. Applying that exact plan completed successfully.
- All five accounts now have exactly one CIS v3.0.0 subscription, each `READY`,
  and no default-standard subscription. The delegated administrator receives
  findings for all four members.
- Stabilization is still open. At `2026-07-30T14:11:12-03:00`, the long-running
  security account had evaluated 35 controls, while accounts enabled today had
  evaluated only 17–20 of 36. Those partial scores are not an admissible
  baseline and will not be used for the control experiment.
- At `2026-07-30T14:33:00-03:00`, lab reached denominator 35 and log archive
  reached 36. Dev remained at 18 and management at 21, so the baseline is
  still inadmissible. PontoAntiCrack was independently idle and reported the
  lab released with no AWS or Stratus process.
- At `2026-07-30T14:43:26-03:00`, dev reached denominator 35. Management
  remained at 21; all other accounts were at 35 or 36. The experiment remains
  blocked only on management-account control evaluation and no SCP attachment
  has changed.
- At `2026-07-30T14:57:45-03:00` the baseline became admissible: every account
  reports denominator 35 or 36, management included. `scripts/export-cis-score.sh`
  now produces this table on demand and writes `docs/evidence/cis-score.txt`.
  The Makefile had referenced that script since before it existed.

### C3 — control experiment executed and reversed

- Ran `2026-07-30T15:11:01-03:00` to `15:26:46-03:00`; `awlz-lab` was without
  its SCPs for `15:18:14` to `15:23:34`, 5m20s.
- The three SCPs sit on the Workloads OU, which also holds `awlz-dev`. They were
  attached directly to `awlz-dev` before leaving the OU and removed from it only
  after returning, so `awlz-dev`'s effective policy never changed. Only
  `awlz-lab` was ever unprotected. Reattachment ran from a shell trap.
- Probes flipped with the policy and back: `ec2:DescribeVpcs` in `eu-west-1` and
  `cloudtrail:StopLogging` on a nonexistent trail were denied by SCP, then
  allowed (the second returning `TrailNotFound`), then denied again. Neither
  probe creates or destroys anything.
- CIS v3.0.0 for `awlz-lab` was 24 passed / 11 failed / 0 unknown out of 35 in
  both states, identical control by control. Three Config rules recorded a
  successful evaluation inside each phase, so the second reading is fresh rather
  than a stale copy.
- Conclusion: no CIS v3.0.0 control reads an SCP, so the benchmark score cannot
  measure a preventive guardrail. The behavioural probes are the evidence that
  the guardrail works; the score is evidence about resource configuration.
- Restoration verified by independent read of all three targets and by
  `terraform plan` on `live/guardrails`: 0 to change, 0 to destroy, with only
  the staged `require-permissions-boundary` policy and its two attachments
  pending. Full write-up in `docs/evidence/scp-verification.md`.

### CI gate — break-glass topic encryption

- The first PR run failed on Trivy `AVD-AWS-0136`: the T8 SNS topic used
  `alias/aws/sns`. An AWS-managed key carries no key policy, so nothing bounds
  which principal decrypts an alert that announces recovery-role use.
- Replaced with a dedicated rotating CMK whose policy grants CloudWatch
  `GenerateDataKey*`/`Decrypt` only for this account and this alarm ARN. Cost
  rises ~USD 1/month; the conservative joint steady state is now USD 13.73
  against the USD 20 ceiling.
- `fmt`, `tflint`, Trivy, Checkov (477 passed, 0 failed, 69 skipped) and all six
  `validate` stacks pass locally; the pushed commit is green on every required
  check.

### C2 — cost decision

- Cost Explorer for 2026-07-28 through 2026-07-30 remains estimated; net
  unblended cost is USD 0 and is not labelled an actual.
- Measured inputs: 33 Config items on the latest estimated day, GuardDuty
  accrued usage USD 0.002667, and 46 active CIS findings across 35 evaluated
  controls in the mature security account.
- The conservative joint projection is USD 24.77/month with CIS in all five
  accounts, including PontoAntiCrack's documented USD 2.35 at-rest footprint.
  This can exceed the USD 20 ceiling.
- Decision: preserve all five standards until C3 is valid, then retain CIS only
  in `awlz-security`, remove four explicit subscriptions and set future
  auto-enable to `NONE`. Conservative joint result: USD 13.73/month, leaving
  USD 6.27 buffer. The lost live per-account evidence is explicit in
  `docs/cost.md`.
- C6 is time-bound rather than fabricated. Earliest closed-window retry:
  `2026-08-02T12:00:00-03:00` for the July 28–August 1 window, and only if
  Cost Explorer returns `Estimated: false`.

### C4 — T5 implementation staged, not applied

- Added an account-local permissions boundary for each of the four member
  accounts, adoption by AwLZ-managed Config roles, and a Guard custom policy
  rule that checks the exact boundary ARN.
- Added a fourth SCP that requires the boundary on new roles and protects both
  the attachment and policy. `OrganizationAccountAccessRole` is the sole
  recovery exception.
- The Guard rule passed local positive, negative, service-linked and
  break-glass test cases with official `cfn-guard` 3.2.0.
- Terraform validation, tflint, Trivy and Checkov pass. Checkov reports 384
  passed, 0 failed and 66 justified skips; boundary false positives carry an
  individual inline reason.
- Remote planning and apply remain pending behind C3. No boundary, Config rule
  or SCP change has reached AWS from this staged implementation.

### C4 — T8 implementation staged, not applied

- Added an exact-ARN CloudTrail metric filter for all four
  `OrganizationAccountAccessRole` roles, a one-minute CloudWatch alarm and an
  encrypted SNS target with SourceAccount and SourceArn constraints.
- No endpoint or address is hardcoded. The alarm exists independently of
  notification-channel ownership.
- Terraform validation, tflint, Trivy and Checkov pass; Checkov reports 397
  passed, 0 failed and 66 justified skips.
- Remote plan, apply, harmless observed role assumption and `ALARM` transition
  remain pending. No logging resource has changed in AWS from this staged
  implementation.

### C5 — read-only member plan roles staged, not applied

- Added one `awlz-gha-plan-readonly` role per member account. Trust is limited
  to the exact management OIDC plan role; each role has AWS `ReadOnlyAccess`
  and the T5 permissions boundary.
- The management plan role can assume only the four computed member role ARNs.
  Logging, detection and CI provider role names now default to break-glass for
  local apply and accept the read-only role name for CI.
- `live/ci-oidc` is temporarily removed from this branch's plan matrix because
  it cannot assume roles that do not exist yet. Main is unaffected. It must
  return with logging and detection before merge.
- Terraform validation, tflint, Trivy and Checkov pass; Checkov reports 465
  passed, 0 failed and 66 justified skips.
- Remote plan/apply and real OIDC plan proof remain pending.

### C7 — deterministic recording path staged

- Read the ProvenancePipeline recording guide and reusable runner read-only.
- Added a deterministic local driver that strictly validates the sanitized C5
  IAM simulation evidence and displays one allowed Config read and one
  explicitly denied Config write. The driver performs no AWS call.
- The recorder writes an uncapped raw asciinema cast, self-tests its AWS deny
  patterns with a fake ARN, audits before promotion, renders with `agg`, and
  extracts a frame for pixel inspection.
- WSL dependencies: asciinema 2.4.0 and Pillow from Ubuntu packages; official
  `agg` 1.9.0 release verified against its published SHA-256 before install.
- Recording remains pending on the applied C5 simulation evidence. No
  placeholder cast or GIF will be committed.

## Roadmap

| Item | State | Proof required |
|---|---|---|
| C1 — GuardDuty | **Proved** | Four delegated members with `RelationshipStatus: Enabled` |
| C2 — Security Hub cost decision | **Decided; apply next** | USD 24.77 five-account vs USD 13.73 security-only joint projection |
| C3 — CIS control experiment | **Proved** | Lab measured with and without SCPs, probes flipped both ways, reattachment verified independently and by plan |
| C4 — T5 and T8 | Pending | Applied boundary adoption, Config detection, observed CloudTrail event and alarm |
| C5 — CI least privilege | Pending | Member read-only roles and successful OIDC plans without write permissions |
| C6 — cost actuals | **Time-bound** | Earliest retry 2026-08-02T12:00:00-03:00; require `Estimated: false` |
| C7 — demo | Pending | Audited raw cast and rendered GIF showing one deny and one allowed read |

## Recovery invariants

- `awlz-lab` must never be left without its expected SCPs.
- If an experiment fails, reattachment and independent verification take
  precedence over documentation.
- No account, payment, root, Identity Center or static credential operation is
  authorized.
- The monthly conservative projection must not exceed USD 20.
- Terraform state protection, scanner gates and protected-branch controls must
  not be weakened.

## TODO for the next owner

- [ ] Resume the first item above that is not marked proved.
- [ ] Before any lab SCP experiment or lab apply, confirm PontoAntiCrack is not
      in a live phase.
- [ ] After every remote change, record the plan/apply result, independent
      verification and rollback state here.
- [ ] Keep commits small, push the branch, wait for every required check and
      merge through a protected pull request.
- [ ] At the end, log out of SSO, verify every expected SCP attachment, and
      leave the repository tree clean.
