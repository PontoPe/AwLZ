# AwLZ — context for coding agents

Read this before touching anything. It is the handoff between sessions.

## What this is

A multi-account AWS landing zone in Terraform, built as a portfolio artifact for cloud-security roles (targeting AWS SAA + Terraform Associate, then Security Specialty). The deliverable is not "working infra" — it is **reproducible infra plus compliance evidence**. A CIS score before/after and a cost table matter as much as the code.

Owner: Pedro (GitHub `PontoPe`). Repo: `github.com/PontoPe/AwLZ`, **public**.

Three sibling repos exist under `C:\Users\Pedro\Documents\Coding\` and cross-reference this one: `ProvenancePipeline`, `KateClusters`, `PontoAntiCrack`. `PontoAntiCrack` consumes the org trail and lab account this repo creates.

## Where things stand

Done:

- Repo scaffolded: README with architecture diagram + threat model, `docs/threat-model.md`, `docs/architecture.md` (ADR skeleton), `docs/cost.md`, `docs/toolchain.md`, CI workflow, Makefile.
- AWS management account created: name `pegradowski-mgmt`, root email `pedro.gradowski+aws-mgmt@gmail.com`.
- Management account root MFA **done** — two devices, deliberately **not** in the same vault as the root password.
- Billing: IAM access to billing activated, monthly cost budget USD 20 with alerts at 85%/100% actual and 100% forecasted, to `pedro.gradowski+aws-budgeting@gmail.com`.
- AWS Organizations created, **all features**, Service control policies **enabled**. Org root id `r-ptjo`.
- IAM Identity Center enabled in **sa-east-1**. Portal `https://pegradowski.awsapps.com/start`, user `pegradowski-iam_ic`, permission set `AdministratorAccess` with a 1-hour session, assigned to `pegradowski-mgmt`.
- Local CLI profile **`mgmt`** configured via `aws configure sso` — SSO session `pegradowski`, region `sa-east-1`, no static credentials on disk.
- **`live/bootstrap` applied, 2026-07-28.** 9 resources. State bucket `awlz-tfstate-<mgmt-account-id>` with a CMK (alias `alias/awlz-tfstate`), rotation on. State at `bootstrap/terraform.tfstate`; local state files deleted. Verified controls listed in `live/bootstrap/README.md`.
- **`live/org-root` applied, 2026-07-28.** 1 imported, 7 added, 1 changed. OUs Security and Workloads; accounts `awlz-log-archive` + `awlz-security` under Security, `awlz-dev` + `awlz-lab` under Workloads, all ACTIVE. Trusted access enabled for 8 principals. **Centralized root access is on** — member accounts have no root credentials.
- **`live/guardrails` applied, 2026-07-28.** 3 SCPs — region allow-list, detection-service protection, guardrail-role protection — attached to the **Security and Workloads OUs**, so all four member accounts. Documents in `policies/scp/`. Verified from inside the account with an assumed admin role; results in `docs/evidence/scp-verification.md`, including a negative control proving the role policy is scoped rather than blanket.
- Gate baseline across the whole repo: tflint 0, trivy 0, checkov **376 passed / 0 failed / 21 skipped**. Every skip carries a written reason. Do not add a bare suppression to this repo — the justification is part of the deliverable.

The manual console phase is finished. Everything from here is Terraform.

Session start, every time:

```
aws sso login --profile mgmt
aws sts get-caller-identity --profile mgmt
```

ARN must contain `AWSReservedSSO_AdministratorAccess`. Sessions expire in 1 hour; re-login is routine, not a bug. Then in any applied stack: `terraform init -backend-config=backend.hcl`.

**Concrete IDs are not in this file on purpose** — account IDs, the org ID, the state bucket name and the KMS key ID live in gitignored `terraform.tfvars` / `backend.hcl`, and the repo goes public. To get them:

```
cd live/org-root && terraform output          # account ids, OU ids, org id
cd live/bootstrap && terraform output -raw backend_config
```

- **`live/logging` applied, 2026-07-28.** Org trail in mgmt, object-locked archive + CMK in `awlz-log-archive`. COMPLIANCE 30 days. CloudWatch tail, 14 days. Data events scoped to the state bucket, which closes T6b. Verified delivering — `docs/evidence/logging-verification.md`.
- **`live/detection` applied, 2026-07-28.** GuardDuty, Security Hub (CIS 3.0.0), Config and Access Analyzer, all delegated to `awlz-security`. Config recorders in all five accounts, all `recording: true` / `SUCCESS`. Config bucket + its own CMK in `awlz-log-archive`.
- **`live/ci-oidc` applied, 2026-07-28.** GitHub OIDC provider, `awlz-gha-plan` (read-only, denied state writes) and `awlz-gha-apply` (admin, gated by the `production` environment). CI runs a real `terraform plan` against AWS on every PR.
- GitHub: repo is **public**. Ruleset on `main` requires a PR and passing status checks. Repo variables carry the IDs; `TF_MEMBER_ACCOUNTS` is a secret because it holds root emails.

Open, in rough priority order:

1. **GuardDuty member enrollment is unconfirmed.** `AutoEnableOrganizationMembers` is `ALL` but `list-members` was still empty ~40 minutes after apply. Re-check; if still empty, existing accounts may need explicit `create-members` despite the auto-enable setting.
2. **CIS score not captured.** Security Hub was still `INCOMPLETE` and had zero findings. Needs ~24h. Then run the `awlz-lab` control-group experiment described in `docs/evidence/detection-verification.md` — detach its SCPs, score, reattach, score.
3. **Cost actuals.** Cost Explorer had no data for a same-day organization. Fill `docs/cost.md` after a billing cycle. **Security Hub is the budget risk** — projected USD 4–18/month against a USD 20 ceiling; the lever is `auto_enable_standards = "NONE"`.
4. `live/logging` and `live/detection` are **excluded from the CI plan matrix** on purpose: planning them needs `OrganizationAccountAccessRole`, which is admin, and a PR-triggered role must not hold that. Fix is a read-only role per member account plus lifting the assumed role name to a variable.
5. Permission boundaries + Config rule for T5; alarm on break-glass assumption for T8.
6. Demo recording.

Superseded, kept because the traps are still live:

- **S3 server access logging cannot cross accounts.** The target bucket must be owned by the source bucket's account, so T6b was closed with CloudTrail S3 data events instead. The bootstrap suppressions stay, with rewritten reasons.
- **`repo:PontoPe/AwLZ:*` is not the sub claim.** GitHub issues immutable subject claims here: `repo:PontoPe@96898980/AwLZ@1315312585`. Read it with `gh api repos/<owner>/<name>/actions/oidc/customization/sub`. Nothing in the STS error says so.
- Guardrails collided with detection twice. Both SCPs now split destructive actions (no exemption) from actions deployment also needs (deployment principals exempt). ADR-014.

History was scrubbed of concrete IDs before the repo went public, and force-push is now blocked on `main` — so a second scrub is not available. Keep IDs out of committed files.

## Decisions already made — do not relitigate

| Decision | Rationale |
|---|---|
| Home region `sa-east-1` | Data residency in Brazil. Costs ~30-50% more than us-east-1; accepted, documented in `docs/cost.md`. |
| SCP region allow-list = `sa-east-1` + `us-east-1` | Global services (IAM, Organizations, CloudFront, CloudTrail global events) report to us-east-1 regardless. Excluding it breaks the org. |
| No static AWS access keys, anywhere | Local auth via IAM Identity Center SSO; CI via GitHub OIDC. This is a stated selling point of the repo — never introduce an access key, not even temporarily. |
| Terraform state in the **management** account | The security account does not exist until `org-root` runs. Cross-account state migration was judged riskier than the residual exposure. Accepted, documented in `live/bootstrap/README.md` and threat model T6. |
| Native S3 state locking (`use_lockfile`), no DynamoDB table | Terraform 1.10+ feature. Fewer resources, no extra cost. |
| Partial backend config — `backend "s3" {}` plus gitignored `backend.hcl` | The bucket name embeds the account ID, and the repo already keeps account IDs out of git. `example.backend.hcl` is the committed template. |
| `.terraform.lock.hcl` **is** committed | Was gitignored by mistake. Without it a clone resolves providers fresh and can plan against a different provider version than the evidence was produced with. |
| No cross-region replication on the state bucket | Would move the org's full resource graph out of sa-east-1, against the residency decision. Versioning is the rollback path. |
| `trivy config` instead of `tfsec` | tfsec is end-of-life; Aqua folded it into Trivy. |
| Management account hosts no workloads | Governance only. |
| Alternate contact (Security) set to `+aws-security@` | AWS abuse and compromise notices route there. |
| Identity Center home region `sa-east-1` | Cannot be changed without deleting the instance. Locked in. |
| `AdministratorAccess` permission set capped at a 1-hour session | Default is 12 hours. A security portfolio should not ship a 12-hour admin session. |

| Centralized root access on, via Terraform | `aws_iam_organizations_features` with `RootCredentialsManagement` + `RootSessions`. Member accounts have no root credentials. Break-glass is `OrganizationAccountAccessRole` assumed from the management account. Threat model T9. |
| Organization adopted by `import` block, managed not read | Makes trusted access declarative — a new service is one line in `var.service_access_principals`. Consequence: `aws_organizations_organization` is global and singular, so only `live/org-root` may manage it. |
| Member accounts: `close_on_deletion = false`, `prevent_destroy` everywhere | Closing an account starts a 90-day suspension that burns its root email. A destroy should detach, never close. |
| No blanket root-deny SCP | Root credentials are already deleted from member accounts, so there is nothing to deny, and a root deny would block `RootSessions` — the break-glass path. Reasoning in `policies/scp/README.md`; revisit only if centralized root access is disabled. |
| SCPs attach to accounts/OUs, never the org root | The management account is exempt from SCPs regardless, and root attachment makes the blast radius harder to reason about. Root exemption is the only recovery path from a bad policy — it must stay unbroken. |
| SCP documents in `policies/scp/*.json`, applied from `live/guardrails` | Root modules live under `live/` by convention; `policies/` holds documents. Separate from `org-root` so an SCP rollback does not share a plan with account creation. |

## Conventions

- `live/<stack>/` are root modules, one per account/stage. `modules/` are reusable. Never `terraform apply` from `modules/`.
- Every stack pins `required_version` and provider versions.
- Every stack sets `allowed_account_ids` on the provider — a wrong profile must fail, not apply.
- `terraform.tfvars` is gitignored and holds the account ID and profile name; `example.tfvars` is the committed template. Same pattern for `backend.hcl` / `example.backend.hcl`.
- Scanner suppressions carry the reason inline (`# checkov:skip=ID:why`, commented `.trivyignore` entries) and, when the finding is real rather than a false positive, a threat-model ID and the stack that closes it. A bare suppression is worse than the finding.
- Resource names prefixed with `var.project` (`awlz`).
- Docs are part of the deliverable. A change that alters the threat surface updates `docs/threat-model.md` in the same commit.
- Commits: Conventional Commits, author `heavensnipe@gmail.com` (registered on the GitHub account, so attribution links).

## Environment gotchas

The user is on Windows 11 with PowerShell 7. These have already cost time:

- **Nothing is on `PATH` in a fresh shell.** Winget installs to per-package directories and creates no shims here. Prepend these before running anything:

  ```powershell
  $wg = "$env:LOCALAPPDATA\Microsoft\WinGet\Packages"
  $env:PATH = "$wg\Hashicorp.Terraform_Microsoft.Winget.Source_8wekyb3d8bbwe;" +
              "$wg\AquaSecurity.Trivy_Microsoft.Winget.Source_8wekyb3d8bbwe;" +
              "$wg\TerraformLinters.tflint_Microsoft.Winget.Source_8wekyb3d8bbwe;" +
              "C:\Program Files\Amazon\AWSCLIV2;" +
              "$env:LOCALAPPDATA\Python\pythoncore-3.14-64\Scripts;$env:PATH"
  ```

- `python -m checkov` **does not work** — checkov is a package with no `__main__`. Use `checkov.cmd` from the Scripts directory above.
- PowerShell mangles native-CLI arguments containing `=`. `terraform plan -var-file=x -out=y` fails with `Too many command line arguments`. Build an array and splat it: `& terraform @("plan","-var-file=terraform.tfvars","-out=tfplan")`.
- `trivy config` rejects `--no-color`. Bare `trivy config .` works.
- PowerShell `&&` short-circuits — a chained version check stops at the first failure and the rest silently never run.
- `terraform -chdir=$var` does not expand the variable in PowerShell. Use `Set-Location` instead.
- Makefiles here assume a POSIX shell. Run them from Git Bash or WSL.
- Installed: terraform 1.15.8, tflint 0.64.0, trivy 0.72.0, checkov 3.3.8, aws-cli 2.36.9. Provider pinned at `hashicorp/aws` 6.56.0 via the committed lock file.

## Working style the user expects

- Terse. No preamble, no restating the question. Fragments are fine.
- Security warnings and multi-step console procedures get written out clearly, not compressed.
- Verify before claiming: run `terraform fmt`, `validate`, and the linters rather than asserting the code is fine.
- When a recommendation turns out wrong, correct it in one line and move on.
- Do not create AWS accounts, enter payment details, or perform console actions on the user's behalf — hand over exact steps instead.
