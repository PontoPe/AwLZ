variable "project" {
  description = "Prefix for every resource name."
  type        = string
  default     = "awlz"
}

variable "region" {
  description = "Home region for the archive bucket. The trail itself is multi-region."
  type        = string
  default     = "sa-east-1"
}

variable "profile" {
  description = "Local AWS CLI profile backed by IAM Identity Center."
  type        = string
  default     = ""
}

variable "member_role_name" {
  description = "Cross-account role used by providers: break-glass for apply, read-only for CI plan."
  type        = string
  default     = "OrganizationAccountAccessRole"

  validation {
    condition     = can(regex("^(OrganizationAccountAccessRole|[a-z][a-z0-9-]{2,15}-gha-plan-readonly)$", var.member_role_name))
    error_message = "member_role_name must be OrganizationAccountAccessRole or a project-prefixed gha-plan-readonly role."
  }
}

variable "account_id" {
  description = "Management account ID. The trail is created here."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be exactly 12 digits."
  }
}

variable "log_archive_account_id" {
  description = "Log archive account ID. From: cd ../org-root && terraform output account_ids"
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.log_archive_account_id))
    error_message = "log_archive_account_id must be exactly 12 digits."
  }
}

variable "account_ids" {
  description = "Member account short name to ID, used to build exact break-glass role ARNs."

  type = object({
    log-archive = string
    security    = string
    dev         = string
    lab         = string
  })

  validation {
    condition = alltrue([
      for id in values(var.account_ids) : can(regex("^[0-9]{12}$", id))
    ])
    error_message = "every account id must be exactly 12 digits."
  }
}

variable "organization_id" {
  description = "Organization ID. Scopes the bucket policy and the log prefix."
  type        = string
}

variable "state_bucket_arn" {
  description = <<-EOT
    ARN of the Terraform state bucket, recorded as an S3 data event source.

    This is what closes T6b: without data events, a read of the state object
    leaves no trace anywhere. Scoped to this one bucket because data events
    bill per event and "all S3" is how an org trail gets expensive.
  EOT

  type = string
}

variable "object_lock_mode" {
  description = "COMPLIANCE or GOVERNANCE. See modules/logging/variables.tf for the trade-off."
  type        = string
  default     = "COMPLIANCE"
}

variable "object_lock_retention_days" {
  description = "Days each object stays undeletable. Short on purpose — see the module."
  type        = number
  default     = 30
}

locals {
  tags = {
    Project   = var.project
    Stack     = "logging"
    ManagedBy = "terraform"
    Repo      = "github.com/PontoPe/AwLZ"
  }
}
