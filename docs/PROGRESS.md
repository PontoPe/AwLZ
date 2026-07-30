# Autonomous completion progress

Last updated: **2026-07-30T13:44:16-03:00**

This is the resumable execution ledger for C1–C7. It contains no concrete
account IDs, ARNs, organization IDs, email addresses, or credentials.

## Current state

- Branch: `codex/awlz-autonomous-owner`
- Active item: **C1 — GuardDuty member enrollment**
- AWS session: management account administrator through IAM Identity Center;
  home region `sa-east-1`; validated without recording identifiers.
- Repository gates: `fmt`, `tflint`, `trivy`, Checkov and `validate` for all six
  live stacks passed on 2026-07-30. After the C1 resource was added, Checkov
  reported 368 passed, 0 failed and 22 justified skips.
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
- Apply and membership creation are pending.

## Roadmap

| Item | State | Proof required |
|---|---|---|
| C1 — GuardDuty | In progress | Four delegated members with `RelationshipStatus: Enabled` |
| C2 — Security Hub cost decision | Pending | Current state, usage and conservative AwLZ + PontoAntiCrack projection |
| C3 — CIS control experiment | Pending | Stable baseline; lab with/without SCP measurements; independently verified reattachment |
| C4 — T5 and T8 | Pending | Applied boundary adoption, Config detection, observed CloudTrail event and alarm |
| C5 — CI least privilege | Pending | Member read-only roles and successful OIDC plans without write permissions |
| C6 — cost actuals | Pending | Closed Cost Explorer window, or an exact earliest retry date |
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
