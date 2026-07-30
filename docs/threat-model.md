# Threat model — AwLZ

## Scope

The AWS Organization and its guardrails: management account, security/log-archive account, workload accounts, the Terraform that manages them, and the CI identity that applies it. Application workloads inside member accounts are **out of scope**.

## Assets

| Asset | Why it matters |
|-------|----------------|
| Organization management account | Full control over every member account |
| CloudTrail org trail + log archive bucket | The only record of what happened; forensic ground truth |
| KMS CMK protecting logs | Compromise = read or destroy the record |
| Terraform state | Contains ARNs, account IDs, resource graph; write access = infra takeover |
| GitHub OIDC role | Applies infrastructure changes |
| SCPs | The enforcement boundary itself |

## Trust boundaries

1. GitHub Actions runner → AWS (crossed by OIDC federation, short-lived credentials)
2. Management account → member accounts (crossed by SCPs and org-level roles)
3. Workload accounts → security account (crossed by one-way log delivery)
4. Human operator → AWS console/API

## Threats (STRIDE)

| # | STRIDE | Threat | Likelihood | Impact | Control | Residual risk |
|---|--------|--------|-----------|--------|---------|---------------|
| T1 | Spoofing | Another repo assumes our CI role | Med | High | Trust policy conditions on `token.actions.githubusercontent.com:sub` = exact `repo:owner/name:ref` | Fork-PR path must never be given the role |
| T2 | Tampering | `cloudtrail:StopLogging` / `DeleteTrail` in a member account | Med | High | SCP deny; S3 Object Lock compliance mode | Management account itself is not covered by SCPs |
| T3 | Repudiation | Actions taken in an unmonitored region | Med | Med | SCP deny outside allowed regions; global services pinned to `us-east-1` | Region allow-list must be reviewed when adding services |
| T4 | Info disclosure | Log archive bucket read by a member account | Low | High | Dedicated account, bucket policy + KMS key policy deny cross-account read | — |
| T5 | Elevation | Member account creates a role that bypasses guardrails | Med | High | SCP denies IAM changes to `awlz-*` roles; permission boundary required for role creation | Boundary enforcement needs a Config rule to catch drift |
| T6 | Info disclosure | Terraform state read from a public/misconfigured bucket | Low | High | Private bucket, SSE-KMS with a CMK, Block Public Access, ACLs disabled, bucket policy denying non-TLS and unencrypted puts | State lives in the management account, not the security account — accepted, see `live/bootstrap/README.md` |
| T6b | Repudiation | State object read or overwritten without a trace | Low | Med | **Closed** by CloudTrail S3 **data events** scoped to the state bucket, delivered to the org trail in the log-archive account. `modules/logging`. | Not closed the way originally planned. S3 server access logging requires the target bucket to be owned by the *same account* as the source, so state-bucket access logs could never have been delivered cross-account to `awlz-log-archive`. Data events are the stronger control anyway — they land in the object-locked archive rather than a bucket in the same account as the thing being audited. Scanner findings AWS-0089 / CKV_AWS_18 remain suppressed, since server access logging is still literally off. |
| T7 | Tampering | Malicious Terraform merged | Med | High | Required review, `trivy config`/`checkov`/`tflint` gates, plan-only on PR, apply gated by environment approval | Reviewer fatigue |
| T8 | DoS | Guardrails lock out legitimate emergency access | Low | Med | Documented break-glass role + procedure, alarmed on use | Break-glass must be tested, not just documented |
| T9 | Elevation | Member account root used to act outside Identity Center | Med | High | **Eliminated.** `RootCredentialsManagement` deletes root credentials from every member account; `RootSessions` routes the few root-only operations through the management account, audited in CloudTrail. `live/org-root`. | Management account root is out of scope and remains a standing credential — hardware MFA, two devices, password in a separate vault. |

## Detection mapping

Anything here that cannot be *prevented* must be *detected* — those go to [PontoAntiCrack](../../PontoAntiCrack).

| Threat | Detection |
|--------|-----------|
| T2 | GuardDuty `Stealth:IAMUser/CloudTrailLoggingDisabled` |
| T5 | Config rule on role creation without boundary |
| T8 | CloudWatch alarm on break-glass role assumption |

## Assumptions

- The **management** account root is held by the operator with hardware MFA on two devices, password stored apart from them, and is never used for automation. Member accounts have no root credentials at all — see T9.
- Identity Center is the only interactive path in. If it fails, the recovery path is management account root → `OrganizationAccountAccessRole`. That chain has not been rehearsed; T8's residual risk covers it.
- GitHub organization has 2FA enforced and branch protection on `main`.
- Security Hub CIS v3.0.0 coverage is explicit in all five existing accounts;
  organization auto-enable alone is not treated as evidence for accounts that
  predate `live/detection`. Security Hub is compliance evidence and detection
  aggregation, not a substitute for the preventive SCPs.

## Out of scope

Workload application security, endpoint security of the operator's workstation, AWS's own control-plane integrity.

---

_Revisit whenever a new account, region, or CI identity is added._
