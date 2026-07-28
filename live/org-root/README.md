# org-root

The organization tree: OUs, member accounts, trusted access, and centralized root access. Runs in the **management account** with the `mgmt` profile.

Depends on `live/bootstrap` for its state backend. Everything after it depends on the account IDs this stack outputs.

## Layout

```
Root (r-ptjo)
├── Security
│   ├── awlz-log-archive     immutable log destination, no workloads ever
│   └── awlz-security        detection tooling, delegated admin for GuardDuty/Config/Security Hub
└── Workloads
    ├── awlz-dev
    └── awlz-lab             consumed by the PontoAntiCrack repo
```

The split exists so SCPs have something to attach to. A policy that is correct for `Security` — deny everything that is not logging or detection — would be unusable on `dev`.

## The organization is imported, not created

It was created in the console before this stack existed, and an organization cannot be created twice. `main.tf` carries an `import` block keyed on `var.organization_id`, so a fresh clone adopts the existing org instead of erroring.

Managing the resource rather than reading it through a data source is deliberate: it makes `aws_service_access_principals` declarative. Every service that later needs to act across the org — the CloudTrail org trail, GuardDuty, Config — gets enabled by adding one line to `var.service_access_principals` and shows up in a plan diff.

**Consequence:** `aws_organizations_organization` is a single global resource, so no other stack may manage it. A later stack needing trusted access edits the variable here.

## Centralized root access

`aws_iam_organizations_features` enables `RootCredentialsManagement` and `RootSessions`.

- Root user credentials are **deleted** from every member account. Not disabled — removed.
- The management account root is untouched and still needs its hardware MFA.
- Way in afterwards: assume `OrganizationAccountAccessRole` from the management account. That role is created with each account and is the break-glass path.
- The handful of operations that genuinely require member root (an S3 bucket policy that locks out every principal, for instance) run as short-lived root sessions initiated from the management account and land in CloudTrail.
- Reversible. Disable the feature and root credentials can be recovered through the normal password-reset flow.

This eliminates T5 at the source instead of mitigating it. Set `enable_centralized_root_access = false` to skip.

## Run

```bash
cp example.tfvars terraform.tfvars       # account_id, organization_id, member emails
cp example.backend.hcl backend.hcl       # key = "org-root/terraform.tfstate"
aws sso login --profile mgmt
terraform init -backend-config=backend.hcl
terraform plan -var-file=terraform.tfvars -out=tfplan
terraform apply tfplan
```

PowerShell mangles `-var-file=…`; splat an array instead — see the toolchain notes in `CLAUDE.md`.

Account creation is slow. AWS serializes it, so four accounts take roughly 4–12 minutes total, and a single one occasionally sits at `IN_PROGRESS` for several minutes on its own.

## Before the first apply — read this

**Member account emails are permanent in practice.** Closing an AWS account starts a 90-day suspension, and its root email cannot be reused until that finishes. A typo costs three months, not an edit. Check `terraform.tfvars` against the plan output before applying.

**New organizations ship with a low account quota.** If `CREATE_FAILED` comes back with `ACCOUNT_LIMIT_EXCEEDED`, the org has hit its cap and the fix is a quota increase through Support — Terraform cannot work around it. Accounts that succeeded before the failure are real; re-running continues from there.

`prevent_destroy` is set on the organization, both OUs, and all four accounts. `close_on_deletion = false` means a destroy would detach an account rather than close it, so a mistake does not burn the email address.

## Verify

```bash
aws organizations list-accounts --profile mgmt \
  --query 'Accounts[].{Id:Id,Name:Name,Email:Email,Status:Status}' --output table
aws organizations list-organizational-units-for-parent --parent-id r-ptjo --profile mgmt
aws iam list-organizations-features --profile mgmt
```

Four member accounts `ACTIVE`, two OUs, both root features enabled.

## Next

`policies/scp` attaches to the OU IDs this stack outputs. `modules/logging` needs the `log-archive` account ID.
