# Architecture — AwLZ

The diagram lives in the [README](../README.md). This file records **why**, not what.

Each decision: context, options, choice, consequence. Short. Append, never rewrite — a decision that turns out wrong gets a superseding record, not an edit.

---

### ADR-001 — Home region `sa-east-1`

- **Status:** accepted
- **Context:** Every resource needs a home region. The operator is in Brazil and the scenario this repo models is a Brazilian organization with data residency requirements.
- **Options:** `us-east-1` (cheapest, most services, everything launches there first); `sa-east-1` (residency, higher cost, occasional service lag).
- **Decision:** `sa-east-1`.
- **Consequences:** Roughly 30–50% higher unit cost on most line items. On a governance-only footprint that is single dollars per month, which is affordable and honest — the point of the repo is that the constraint is real, not that the bill is minimal. Some services arrive late or not at all in `sa-east-1`; that has to be checked per service rather than assumed.

### ADR-002 — SCP region allow-list includes `us-east-1`

- **Status:** accepted
- **Context:** ADR-001 picks a home region. A region allow-list SCP is the control that keeps resources from appearing where nobody is watching (T3).
- **Options:** Allow `sa-east-1` only; allow `sa-east-1` + `us-east-1`.
- **Decision:** Both.
- **Consequences:** Global services report to `us-east-1` whether or not anything is deployed there — IAM, Organizations, CloudFront, Route 53, CloudTrail global events. An allow-list of `sa-east-1` alone breaks the organization, including the tooling that would diagnose it. The cost is that `us-east-1` is genuinely open, so detection has to cover it rather than the SCP.

### ADR-003 — No static AWS access keys, anywhere

- **Status:** accepted
- **Context:** Long-lived access keys are the most common root cause of cloud compromise and the easiest thing to leave in a repo, a CI runner, or a laptop.
- **Options:** IAM users with rotated keys; Identity Center for humans and OIDC federation for CI.
- **Decision:** Identity Center locally, GitHub OIDC for CI. No access key is created at any point, including temporarily during bootstrap.
- **Consequences:** Every session is short-lived and re-authentication is routine — the `AdministratorAccess` permission set is capped at one hour rather than the twelve-hour default. Bootstrap could not take the shortcut of a temporary key, so it runs under an SSO session like everything else. If Identity Center is unavailable, the only way in is management account root; see ADR-007.

### ADR-004 — Terraform state in the management account

- **Status:** accepted
- **Context:** State holds the full resource graph of the organization. The threat model says it belongs in the security account (T6). That account does not exist until `live/org-root` runs, which itself needs a state backend.
- **Options:** Bootstrap in the management account and migrate to the security account later; bootstrap there and accept it.
- **Decision:** Accept it. State stays in the management account.
- **Consequences:** Cross-account state migration was judged riskier than the residual exposure. Anyone who can read state in the management account can already read everything the state describes — it is the most privileged account in the organization by construction. Recorded as accepted residual risk on T6, not as a solved problem. Revisit if the management account ever gains a principal that should not see the whole graph.

### ADR-005 — Native S3 state locking, no DynamoDB table

- **Status:** accepted
- **Context:** Terraform state needs a lock. The long-standing pattern is a DynamoDB table.
- **Options:** DynamoDB lock table; `use_lockfile` (Terraform 1.10+), which locks with an S3 object using conditional writes.
- **Decision:** `use_lockfile`.
- **Consequences:** One less resource to create, pay for, encrypt, and remember to encrypt. Pins the repo to Terraform 1.10 or newer, which is pinned anyway.

### ADR-006 — The organization is imported and managed, not read

- **Status:** accepted
- **Context:** The organization was created in the console before this repo had a Terraform stack. An organization cannot be created twice.
- **Options:** Read it through a data source and manage only the tree below it; adopt it with an `import` block and manage the resource.
- **Decision:** Import and manage.
- **Consequences:** Trusted access becomes declarative — enabling the CloudTrail org trail, GuardDuty or Config is one line in a variable and shows up in a plan diff, rather than a console click nobody records. The cost is coupling: `aws_organizations_organization` is a single global resource, so exactly one stack may own it. A later stack that needs a new service principal edits `live/org-root` instead of managing the org itself.

### ADR-007 — Centralized root access, and no blanket root-deny SCP

- **Status:** accepted
- **Context:** Every member account ships with a root user — a standing credential outside Identity Center, outside MFA policy, outside the permission model (T9). The conventional landing zone answer is an SCP denying all actions by `arn:aws:iam::*:root`.
- **Options:** Blanket root-deny SCP; `RootCredentialsManagement` + `RootSessions`; both.
- **Decision:** Enable both IAM organization features. **No** root-deny SCP.
- **Consequences:** Root credentials are deleted from member accounts rather than merely denied — the threat is eliminated at the source. Adding a blanket root deny on top would also block `RootSessions`, the mechanism that performs the handful of genuinely root-only operations from the management account with a CloudTrail record. That trades a real recovery capability for a control that is already redundant. This decision is load-bearing on the features staying enabled: if centralized root access is ever disabled, the root-deny SCP has to come back in the same change. The management account root is out of scope and remains a standing credential, protected by hardware MFA on two devices with the password stored separately.

### ADR-008 — SCPs attach to OUs, never the organization root

- **Status:** accepted
- **Context:** A wrong SCP breaks every principal in its target — including Terraform, which authenticates as a principal in that account. Recovery works only because the management account is exempt from SCPs.
- **Options:** Attach at the root for uniform coverage; attach per OU; attach per account.
- **Decision:** Per OU, rolled out through a single account first.
- **Consequences:** The management account's exemption is the only recovery path from a bad policy, so nothing may compromise it. Root attachment buys nothing — the management account is exempt regardless — and makes the blast radius harder to reason about. New policies land on one throwaway account, get probed, then widen. That exemption path is not theoretical: it was exercised during verification, in [evidence](evidence/scp-verification.md).

### ADR-009 — Detection protection splits destructive from weakening

- **Status:** accepted
- **Context:** The SCP protecting detection services (T2) initially denied both destroying detection and reconfiguring it. Attaching that to the Security OU would break `modules/detection` before it was written: `config:PutConfigurationRecorder` is both how a recorder is created and how an existing one is neutered, and the delegated administrator lives in `awlz-security`.
- **Options:** Exempt the Security OU from the policy; drop the reconfiguration actions; split the policy and exempt deployment principals from the weakening half only.
- **Decision:** Split it. Destroy/stop/disable/disassociate is denied to everyone with no exemption; reconfiguration is denied except to `OrganizationAccountAccessRole` and `awlz-*` roles.
- **Consequences:** Deployment works without a hole in the destructive protection. The exemption is only as narrow as those role names, which is why the same stack denies IAM writes against the `awlz-*` prefix — otherwise anything able to create a matching role inherits the exemption.

### ADR-010 — Partial backend config, account IDs out of git

- **Status:** accepted
- **Context:** The state bucket name embeds the account ID. The repo already gitignores `terraform.tfvars` specifically to keep account IDs out of version control, and is intended to go public.
- **Options:** Commit a fully-specified `backend.tf`; declare an empty `backend "s3" {}` and pass values via `-backend-config`.
- **Decision:** Partial backend, with `example.backend.hcl` as the committed template.
- **Consequences:** Every `init` needs `-backend-config=backend.hcl`, which CI already assumed. Account IDs are identifiers, not credentials — this is consistency with a stated convention rather than a claim that leaking one is dangerous. Evidence documents redact them for the same reason.

### ADR-011 — Object Lock in COMPLIANCE mode, with short retention

- **Status:** accepted
- **Context:** The log archive exists so that an attacker holding the management account cannot erase the record. Versioning and a bucket policy do not survive an attacker who holds the account that owns them.
- **Options:** Versioning only; Object Lock GOVERNANCE; Object Lock COMPLIANCE.
- **Decision:** COMPLIANCE, 30 days.
- **Consequences:** No principal can delete a locked object before expiry — not the account root, not AWS Support. GOVERNANCE would be bypassable by anyone holding `s3:BypassGovernanceRetention`, which is exactly the principal being defended against. The cost is symmetrical and permanent for the retention window: the bucket cannot be emptied or destroyed, and `terraform destroy` will fail. Thirty days is short on purpose — this is a portfolio organization on a hard budget, and under COMPLIANCE every extra day is storage nobody can reclaim. A production archive would use years and size the bill for it.

### ADR-012 — S3 data events instead of server access logging for T6b

- **Status:** accepted, supersedes the original plan for T6b
- **Context:** Reads of the Terraform state object left no trace. The plan was S3 server access logging on the state bucket, delivered to the log archive.
- **Options:** Server access logging to the archive account; server access logging within the management account; CloudTrail S3 data events.
- **Decision:** Data events, scoped to the state bucket alone.
- **Consequences:** The original plan was not implementable — S3 requires a server access logging target bucket to be owned by the **same account** as the source, so delivery to `awlz-log-archive` was never possible. Logging within the management account would put the audit record in the same account as the audited bucket, which defeats the purpose. Data events land in the object-locked archive instead. They bill per event, so the bucket list is an explicit allow-list rather than "all S3" — that is the difference between cents and the largest line on the invoice.

### ADR-013 — Detection delegated to the security account

- **Status:** accepted
- **Context:** GuardDuty, Security Hub, Config and Access Analyzer can each be administered from the management account or delegated to another.
- **Options:** Administer from management; delegate to `awlz-security`.
- **Decision:** Delegate all four.
- **Consequences:** If the management account is compromised, the findings that would reveal it are not in the same blast radius. The cost is complexity: `modules/detection` needs three providers, and Config has no organization-wide auto-enable at all, so a recorder is created per account with a provider each. Terraform cannot iterate over providers, so those five blocks are written out longhand and a `check` block asserts they landed in five distinct accounts.

### ADR-014 — Guardrails exempt their own deployment principals

- **Status:** accepted
- **Context:** Two SCPs blocked the landing zone from deploying itself. `protect-security-services` denied `config:PutConfigurationRecorder`, which is how a recorder is created as well as how one is neutered. `protect-guardrail-roles` denied `iam:AttachRolePolicy` on `awlz-*`, and the Config aggregator role is `awlz-config-aggregator`.
- **Options:** Rename resources outside the protected prefix; drop the offending actions; exempt the deployment principals from the subset of actions that deployment needs.
- **Decision:** Split each policy. Destructive actions — delete, stop, disable, disassociate — are denied to everyone with no exemption. Actions that also occur during legitimate deployment are denied except to `OrganizationAccountAccessRole` and `awlz-*` roles. `OrganizationAccountAccessRole` itself keeps unconditional protection, because nothing legitimately edits the break-glass path.
- **Consequences:** A guardrail that prevents the landing zone from existing is not protecting anything. The exemption is honest about its own limit: a principal able to create a role matching `awlz-*` inherits it, which is bounded only by the same statement denying IAM writes on that prefix to everyone else. Both collisions were found by an apply failing, not by review — recorded in the evidence rather than quietly patched.

### ADR-015 — The CI apply role is AdministratorAccess

- **Status:** accepted
- **Context:** The apply role manages Organizations, SCPs, KMS key policies and cross-account roles.
- **Options:** Enumerate least privilege; use AdministratorAccess and constrain who may assume it.
- **Decision:** AdministratorAccess, with the control placed entirely on the trust policy.
- **Consequences:** An accurate least-privilege policy for a role that manages the organization is administrator with extra steps and a false sense of containment — and it fails open as new services are added, at the worst moment. The real boundary is the `sub` claim: only a workflow that has passed the `production` GitHub Environment can assume it. The plan role, which runs on unreviewed pull requests, is read-only and explicitly denied state writes. Sessions cap at one hour and every action lands in the org trail.

### ADR-016 — Existing Security Hub accounts are explicit

- **Status:** accepted
- **Context:** Local organization auto-enable applies only to accounts that join after it is configured. All four member accounts predated `live/detection`, so only the delegated security account had Security Hub and CIS v3.0.0; configuration was present but the claimed organization evidence was not.
- **Options:** Keep local configuration and create the existing memberships explicitly; migrate to central configuration; rely on out-of-band `CreateMembers`.
- **Decision:** Terraform enables Security Hub without default standards in management, log archive, dev and lab, associates those four with `awlz-security`, and subscribes all five accounts explicitly to CIS v3.0.0. Keep local configuration for future accounts until cost evidence justifies a separate change.
- **Consequences:** The benchmark has one named version and a reproducible per-account denominator. FSBP and CIS v1.2.0 are not silently added to existing accounts. The root module has repeated resources because provider aliases cannot be iterated. Future-account defaults remain a separate cost decision; a new account is not considered covered by CIS v3.0.0 until Terraform adds its provider and explicit subscription.

---

## Open questions

- [ ] Permission boundaries for role creation in member accounts, plus the Config rule that catches drift. T5 stays partial until both exist.
- [ ] Identity Center roles (`aws-reserved/sso.amazonaws.com/*`) are excluded from guardrail-role protection, because denying IAM writes there breaks permission-set provisioning. Needs a condition exempting the Identity Center service principal.
- [ ] The break-glass path — management account root to `OrganizationAccountAccessRole` — is documented and partially exercised, but has never been rehearsed end to end from a genuine Identity Center outage. T8 stays open until it is.
- [ ] No alarm on break-glass role assumption.
