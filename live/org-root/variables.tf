variable "project" {
  description = "Prefix for every resource name in this landing zone."
  type        = string
  default     = "awlz"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,15}$", var.project))
    error_message = "project must be lowercase alphanumeric with hyphens, 3-16 chars."
  }
}

variable "region" {
  description = "Home region. Organizations itself is global, but the provider still needs one."
  type        = string
  default     = "sa-east-1"
}

variable "profile" {
  description = "Local AWS CLI profile backed by IAM Identity Center. Never a static access key."
  type        = string
}

variable "account_id" {
  description = "Management account ID. Guard rail — the provider refuses to run anywhere else."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be exactly 12 digits."
  }
}

variable "organization_id" {
  description = "Existing organization ID. The organization was created in the console before this stack existed, so it is adopted by an import block rather than created."
  type        = string

  validation {
    condition     = can(regex("^o-[a-z0-9]{10,32}$", var.organization_id))
    error_message = "organization_id looks like o-xxxxxxxxxx."
  }
}

variable "organizational_units" {
  description = "OUs created directly under the organization root."
  type        = set(string)
  default     = ["Security", "Workloads"]
}

variable "member_accounts" {
  description = <<-EOT
    Member accounts to create, keyed by short name. `ou` must be a member of
    var.organizational_units.

    The email is permanent in practice: closing an account starts a 90-day
    suspension and the address cannot be reused until it finishes. Get these
    right before the first apply.
  EOT

  type = map(object({
    email = string
    ou    = string
  }))

  validation {
    condition     = alltrue([for k, v in var.member_accounts : can(regex("^[^@]+@[^@]+\\.[^@]+$", v.email))])
    error_message = "every member account needs a syntactically valid email."
  }

  validation {
    condition     = length(distinct([for k, v in var.member_accounts : lower(v.email)])) == length(var.member_accounts)
    error_message = "member account emails must be unique — AWS rejects a duplicate, but only after a slow partial apply."
  }

  validation {
    condition     = alltrue([for k, v in var.member_accounts : contains(var.organizational_units, v.ou)])
    error_message = "every member account's ou must be one of var.organizational_units."
  }
}

variable "enable_centralized_root_access" {
  description = <<-EOT
    Enable the IAM organization features RootCredentialsManagement and
    RootSessions. This deletes root user credentials from every *member*
    account — the management account root is unaffected.

    Leaves the OrganizationAccountAccessRole as the break-glass path into a
    member account, assumed from the management account. Reversible: disabling
    the feature lets root credentials be recovered through password reset.

    Set false only if you need member-account root for something specific.
  EOT

  type    = bool
  default = true
}

variable "service_access_principals" {
  description = <<-EOT
    AWS services granted trusted access to the organization.

    `aws_organizations_organization` is a single resource, so this list is the
    one place trusted access can be declared — a later stack that needs a new
    principal edits this variable, it does not manage the org itself.

    Trusted access alone creates nothing and costs nothing; it is the
    prerequisite that lets the service read the org tree and act org-wide.
  EOT

  type = set(string)

  default = [
    "sso.amazonaws.com",         # already enabled — Identity Center
    "cloudtrail.amazonaws.com",  # org trail, modules/logging
    "config.amazonaws.com",      # org aggregator, modules/detection
    "guardduty.amazonaws.com",   # modules/detection
    "securityhub.amazonaws.com", # modules/detection
    "access-analyzer.amazonaws.com",
    "account.amazonaws.com", # alternate contacts, set org-wide
    "iam.amazonaws.com",     # required by centralized root access
  ]
}
