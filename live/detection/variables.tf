variable "project" {
  description = "Prefix for every resource name."
  type        = string
  default     = "awlz"
}

variable "region" {
  description = "Region the detectors run in."
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
  description = "Management account ID. Delegation is registered here."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be exactly 12 digits."
  }
}

variable "account_ids" {
  description = "Member account short name -> ID. From: cd ../org-root && terraform output account_ids"

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
  description = "Organization ID, for the Config bucket policy."
  type        = string
}

variable "config_retention_days" {
  description = "Lifecycle expiry on Config delivery objects."
  type        = number
  default     = 90
}

variable "auto_enable_standards" {
  description = "Whether future accounts get AWS's default FSBP and CIS v1.2.0 standards. Existing accounts use explicit CIS v3.0.0 subscriptions."
  type        = string
  default     = "DEFAULT"
}

locals {
  tags = {
    Project   = var.project
    Stack     = "detection"
    ManagedBy = "terraform"
    Repo      = "github.com/PontoPe/AwLZ"
  }
}
