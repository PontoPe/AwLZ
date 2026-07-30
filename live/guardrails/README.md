# guardrails

Creates the service control policies in `policies/scp` and attaches them to organization targets. Runs in the **management account** with the `mgmt` profile.

Depends on `live/org-root` for the account and OU IDs it attaches to.

## Why this is `live/guardrails` and not `policies/scp`

The original agent instructions planned a stack at `policies/scp`. The repo convention is that root modules live under `live/<stack>/`, so the two split:

- `policies/scp/` — the policy documents. Data, no Terraform.
- `live/guardrails/` — the root module that renders, creates, and attaches them.

Separate from `live/org-root` on purpose: an SCP change should be planned and rolled back without a plan that also touches account creation.

## The thing to understand before applying

**A wrong SCP breaks every principal in the account it is attached to.** Not the deploy — the account. Terraform included, since Terraform authenticates as a principal in that account.

Recovery exists for one reason: **SCPs do not apply to the management account.** Detaching is always possible from `mgmt`. That is the whole safety net, so it must never be the thing that breaks.

Consequences, all load-bearing:

- Roll out narrow. `terraform.tfvars` starts with the `lab` account and nothing else. Verify, then widen to the Workloads OU, then Security.
- Never attach at the org root. It buys nothing — the management account is exempt anyway — and makes the blast radius harder to reason about.
- Never put the management account in `scp_targets`. It would be ignored, and having it there suggests a protection that does not exist.

## Rollout

```bash
cp example.tfvars terraform.tfvars       # account_id + scp_targets
cp example.backend.hcl backend.hcl
aws sso login --profile mgmt
terraform init -backend-config=backend.hcl
terraform plan -var-file=terraform.tfvars -out=tfplan
terraform apply tfplan
```

Then verify against the `lab` account before widening. `aws:RequestedRegion` is the condition key, so a denied call fails with `AccessDenied` and an explicit-deny reason in CloudTrail.

```bash
# should fail — eu-west-1 is not in the allow-list
aws ec2 describe-vpcs --region eu-west-1 --profile lab

# should succeed — sa-east-1 is
aws ec2 describe-vpcs --region sa-east-1 --profile lab
```

Widening is an edit to `scp_targets` and nothing else: swap the account ID for an OU ID from `cd ../org-root && terraform output organizational_unit_ids`.

## Size limit

An SCP caps at **5120 bytes**. A `check` block asserts every rendered policy fits, so the plan fails instead of the API call. Current sizes come out in `terraform output policy_sizes` — 412 to 1042 bytes, so there is room, but pretty-printed JSON burns it fast. Documents are minified through `jsonencode(jsondecode(…))` before they are sent.

That same round-trip fails the plan on malformed JSON, which is worth more than it sounds: a template typo otherwise surfaces as an opaque API error.

## Two statements, not one

`protect-security-services` splits into a destructive half and a weakening half.

Destroying detection — delete, stop, disable, disassociate — is denied to everyone with no exemption.

Reconfiguring it is denied except to `var.deployment_principal_arns`, because the same calls that weaken detection are the ones that create it. `config:PutConfigurationRecorder` builds the recorder and can also neuter an existing one; `guardduty:UpdateDetector` is what the delegated administrator in `awlz-security` uses. Denying them outright would mean `modules/detection` can never run in any account this policy covers.

The exemption is only as tight as the role names in it. Anything able to create a role matching `awlz-*` inherits it — which is why `protect-guardrail-roles` denies IAM writes against that same prefix.

## What is deliberately not here

No blanket root-deny SCP. Centralized root access already deleted member root credentials, and a root deny would also block `RootSessions`, the break-glass path. Reasoning in `policies/scp/README.md`; revisit if centralized root access is ever disabled.

`require-permissions-boundary` applies to the union of the existing guardrail
targets. This is deliberate: the policy must not exist unattached because an
older private `terraform.tfvars` map predates it. New customer roles require
the account-local `awlz-permissions-boundary`; only
`OrganizationAccountAccessRole` can recover or replace the boundary.

Identity Center's `aws-reserved/sso.amazonaws.com/*` roles are not protected by `protect-guardrail-roles` — denying IAM writes there would break permission-set provisioning. Needs a condition exempting the Identity Center service principal.

## Next

`modules/logging` — the org trail these policies protect does not exist yet. `protect-security-services` currently defends nothing; it is in place first so the trail is never briefly unprotected.
