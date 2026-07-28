variable "project" {
  description = "Prefix for every resource name in this landing zone. Also the role prefix protect-guardrail-roles.json defends."
  type        = string
  default     = "awlz"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,15}$", var.project))
    error_message = "project must be lowercase alphanumeric with hyphens, 3-16 chars."
  }
}

variable "region" {
  description = "Provider region. SCPs are global; this only decides which endpoint the API call goes to."
  type        = string
  default     = "sa-east-1"
}

variable "profile" {
  description = "Local AWS CLI profile backed by IAM Identity Center. Never a static access key."
  type        = string
  default     = ""
}

variable "account_id" {
  description = "Management account ID. Guard rail — the provider refuses to run anywhere else."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be exactly 12 digits."
  }
}

variable "allowed_regions" {
  description = <<-EOT
    Regions member accounts may operate in.

    us-east-1 is mandatory, not optional: IAM, Organizations, CloudFront,
    Route 53 and CloudTrail global events report there regardless of where
    anything is deployed. Removing it breaks the organization.
  EOT

  type    = list(string)
  default = ["sa-east-1", "us-east-1"]

  validation {
    condition     = contains(var.allowed_regions, "us-east-1")
    error_message = "us-east-1 must stay in the allow-list — global services report there and excluding it breaks the org."
  }
}

variable "deployment_principal_arns" {
  description = <<-EOT
    Principals exempt from the *weakening* half of protect-security-services —
    the calls that reconfigure detection rather than destroy it.

    Needed because those same calls are how detection gets stood up.
    `config:PutConfigurationRecorder` creates the recorder and can also neuter
    an existing one; `guardduty:UpdateDetector` is used by the delegated
    administrator in awlz-security. Denying them outright means
    modules/detection can never run in any account the policy covers.

    The destructive half — delete, stop, disable, disassociate — has no
    exemption and applies to these principals too.

    Wildcards are matched with ArnNotLike, so `*` in the account field covers
    every member account.
  EOT

  type = list(string)

  default = [
    "arn:aws:iam::*:role/OrganizationAccountAccessRole",
    "arn:aws:iam::*:role/awlz-*",
  ]
}

variable "scp_targets" {
  description = <<-EOT
    Policy name -> list of OU or account IDs it attaches to.

    Start narrow. A wrong SCP breaks every principal in the account it is
    attached to, and only the management account can detach it — the
    management account is itself exempt from SCPs, which is the only reason
    recovery is possible at all.

    Roll out per policy: lab account, verify, then the Workloads OU, then
    Security. Widening is an edit here and nothing else.
  EOT

  type = map(list(string))

  validation {
    condition     = alltrue([for k, v in var.scp_targets : length(v) > 0])
    error_message = "a policy with no targets is dead weight — remove it or give it a target."
  }

  validation {
    condition = alltrue([
      for k, v in var.scp_targets : alltrue([
        for t in v : can(regex("^(ou-[a-z0-9]+-[a-z0-9]+|r-[a-z0-9]+|[0-9]{12})$", t))
      ])
    ])
    error_message = "targets must be an OU id (ou-xxxx-xxxxxxxx), a root id (r-xxxx), or a 12-digit account id."
  }
}
