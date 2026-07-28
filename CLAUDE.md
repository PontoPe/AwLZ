# AwLZ — context for Claude Code

Read this before touching anything. It is the handoff between sessions.

## What this is

A multi-account AWS landing zone in Terraform, built as a portfolio artifact for cloud-security roles (targeting AWS SAA + Terraform Associate, then Security Specialty). The deliverable is not "working infra" — it is **reproducible infra plus compliance evidence**. A CIS score before/after and a cost table matter as much as the code.

Owner: Pedro (GitHub `PontoPe`). Repo: `github.com/PontoPe/AwLZ`, private for now, goes public at the first real milestone.

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
- **`live/guardrails` applied, 2026-07-28.** 3 SCPs — region allow-list, detection-service protection, guardrail-role protection — attached to `awlz-lab` **only**. Documents in `policies/scp/`. Verified from inside the account with an assumed admin role; results in `docs/evidence/scp-verification.md`, including a negative control proving the role policy is scoped rather than blanket.
- Gate baseline: `live/bootstrap` tflint 0 / trivy 0 / checkov 0 failed, 6 skipped with written reasons. `live/org-root` and `live/guardrails` clean on all three, no suppressions. Do not add a bare suppression to this repo — the justification is part of the deliverable.

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

Immediate next step — `modules/logging`, currently an empty directory:

1. Org-wide CloudTrail trail in the management account, delivering to S3 in `awlz-log-archive`. Trusted access for `cloudtrail.amazonaws.com` is already enabled.
2. Bucket in the log archive account: KMS CMK, Object Lock in compliance mode, no delete path. Object Lock **must** be enabled at bucket creation — it cannot be added later.
3. Also wire S3 server access logging for the state bucket into this archive. That closes **T6b** and lets the suppressions in `live/bootstrap/.trivyignore` and `main.tf` be deleted.
4. Cross-account: this stack writes into `awlz-log-archive`, so it needs a second provider aliased onto `OrganizationAccountAccessRole` in that account. There are no static credentials — assume the role via `assume_role` in the provider block.

Then, in order:

5. Widen `scp_targets` in `live/guardrails` from `awlz-lab` to the Workloads OU, then Security. Re-run the probes in `docs/evidence/scp-verification.md` after each step.
6. `modules/iam-oidc` — GitHub OIDC provider + roles scoped to `repo:PontoPe/AwLZ:*`. CI (`.github/workflows/ci.yml`) has the plan job stubbed out waiting on this.
7. `modules/detection` — GuardDuty, Config, Security Hub + CIS. Delegate admin to `awlz-security`, not the management account.
8. Evidence: CIS score before vs after, cost actuals, demo GIF.

Before the repo goes public: commit `51ce5c0` put the management account ID in this file, and it is already pushed. Either scrub it from history or accept it as low-sensitivity. Nothing after that commit adds concrete IDs.

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
