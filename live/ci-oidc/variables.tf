variable "project" {
  description = "Prefix for every resource name."
  type        = string
  default     = "awlz"
}

variable "region" {
  description = "Provider region. IAM is global; this only picks an endpoint."
  type        = string
  default     = "sa-east-1"
}

variable "profile" {
  description = "Local AWS CLI profile backed by IAM Identity Center."
  type        = string
  default     = ""
}

variable "account_id" {
  description = "Management account ID. The roles CI assumes live here, because that is where the stacks apply."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be exactly 12 digits."
  }
}

variable "account_ids" {
  description = "Member account short name to ID for the read-only plan roles."

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

variable "member_role_name" {
  description = "Cross-account role used by this stack: break-glass for apply, read-only for CI plan."
  type        = string
  default     = "OrganizationAccountAccessRole"

  validation {
    condition     = can(regex("^(OrganizationAccountAccessRole|[a-z][a-z0-9-]{2,15}-gha-plan-readonly)$", var.member_role_name))
    error_message = "member_role_name must be OrganizationAccountAccessRole or a project-prefixed gha-plan-readonly role."
  }
}

variable "github_repository" {
  description = "owner/name allowed to assume the roles."
  type        = string
  default     = "PontoPe/AwLZ"
}

variable "apply_environment" {
  description = "GitHub Environment gating the apply role."
  type        = string
  default     = "production"
}

variable "state_bucket_arn" {
  description = "Terraform state bucket ARN."
  type        = string
}

variable "state_kms_key_arn" {
  description = "CMK protecting Terraform state."
  type        = string
}

variable "additional_subject_prefixes" {
  description = "Extra sub prefixes to trust — the immutable form GitHub issues for this repo. See modules/iam-oidc/variables.tf."
  type        = list(string)
  default     = []
}
