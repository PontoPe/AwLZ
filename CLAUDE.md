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
- Root MFA in progress — two devices, deliberately **not** in the same vault as the root password.
- Billing: IAM access to billing activated, monthly cost budget USD 20 with alerts at 85%/100% actual and 100% forecasted, to `pedro.gradowski+aws-budgeting@gmail.com`.
- AWS Organizations created, **all features**, Service control policies **enabled**. Org root id `r-ptjo`.
- `live/bootstrap` written and `terraform validate`-clean. **Not applied yet.**

Blocked on (manual, console, user does this):

- IAM Identity Center not yet enabled. Must be enabled in **sa-east-1** — the home region cannot be changed later without deleting the instance.
- Until `aws sso login` works, nothing can be applied.

Next after that, in order:

1. Apply `live/bootstrap`, migrate its state into the bucket it creates.
2. `live/org-root` — OUs (Security, Workloads), member accounts (log-archive, security, dev, lab).
3. `policies/scp` — region deny, CloudTrail protection, root deny.
4. `modules/logging` — org trail → S3 in the log-archive account, KMS + Object Lock.
5. `modules/iam-oidc` — GitHub OIDC provider + roles scoped to `repo:PontoPe/AwLZ:*`.
6. `modules/detection` — GuardDuty, Config, Security Hub + CIS.
7. Evidence: CIS score before vs after, cost actuals, demo GIF.

## Decisions already made — do not relitigate

| Decision | Rationale |
|---|---|
| Home region `sa-east-1` | Data residency in Brazil. Costs ~30-50% more than us-east-1; accepted, documented in `docs/cost.md`. |
| SCP region allow-list = `sa-east-1` + `us-east-1` | Global services (IAM, Organizations, CloudFront, CloudTrail global events) report to us-east-1 regardless. Excluding it breaks the org. |
| No static AWS access keys, anywhere | Local auth via IAM Identity Center SSO; CI via GitHub OIDC. This is a stated selling point of the repo — never introduce an access key, not even temporarily. |
| Terraform state in the **management** account | The security account does not exist until `org-root` runs. Cross-account state migration was judged riskier than the residual exposure. Accepted, documented in `live/bootstrap/README.md` and threat model T6. |
| Native S3 state locking (`use_lockfile`), no DynamoDB table | Terraform 1.10+ feature. Fewer resources, no extra cost. |
| `trivy config` instead of `tfsec` | tfsec is end-of-life; Aqua folded it into Trivy. |
| Management account hosts no workloads | Governance only. |
| Alternate contact (Security) set to `+aws-security@` | AWS abuse and compromise notices route there. |

## Conventions

- `live/<stack>/` are root modules, one per account/stage. `modules/` are reusable. Never `terraform apply` from `modules/`.
- Every stack pins `required_version` and provider versions.
- Every stack sets `allowed_account_ids` on the provider — a wrong profile must fail, not apply.
- `terraform.tfvars` is gitignored and holds the account ID and profile name; `example.tfvars` is the committed template.
- Resource names prefixed with `var.project` (`awlz`).
- Docs are part of the deliverable. A change that alters the threat surface updates `docs/threat-model.md` in the same commit.
- Commits: Conventional Commits, author `heavensnipe@gmail.com` (registered on the GitHub account, so attribution links).

## Environment gotchas

The user is on Windows 11 with PowerShell 7. These have already cost time:

- `terraform` lives at `C:\Users\Pedro\AppData\Local\Microsoft\WinGet\Packages\Hashicorp.Terraform_Microsoft.Winget.Source_8wekyb3d8bbwe\terraform.exe`. A shell opened before the install will not have it on `PATH`.
- `checkov` is installed but its Scripts directory may not be on `PATH`: `C:\Users\Pedro\AppData\Local\Python\pythoncore-3.14-64\Scripts`. `python -m checkov` always works.
- PowerShell `&&` short-circuits — a chained version check stops at the first failure and the rest silently never run.
- `terraform -chdir=$var` does not expand the variable in PowerShell. Use `Set-Location` instead.
- Makefiles here assume a POSIX shell. Run them from Git Bash or WSL.
- Installed: terraform 1.15.8, tflint 0.64.0, trivy 0.72.0, checkov 3.3.8, aws-cli 2.36.9.

## Working style the user expects

- Terse. No preamble, no restating the question. Fragments are fine.
- Security warnings and multi-step console procedures get written out clearly, not compressed.
- Verify before claiming: run `terraform fmt`, `validate`, and the linters rather than asserting the code is fine.
- When a recommendation turns out wrong, correct it in one line and move on.
- Do not create AWS accounts, enter payment details, or perform console actions on the user's behalf — hand over exact steps instead.
