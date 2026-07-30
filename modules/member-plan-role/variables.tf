variable "project" {
  description = "Prefix for the member-account plan role."
  type        = string
}

variable "management_plan_role_arn" {
  description = "Exact management-account OIDC plan role allowed to assume this role."
  type        = string

  validation {
    condition     = can(regex("^arn:[^:]+:iam::[0-9]{12}:role/[A-Za-z0-9+=,.@_/-]+$", var.management_plan_role_arn))
    error_message = "management_plan_role_arn must be an IAM role ARN."
  }
}

variable "permissions_boundary_arn" {
  description = "Account-local permissions boundary required by T5."
  type        = string

  validation {
    condition     = can(regex("^arn:[^:]+:iam::[0-9]{12}:policy/[A-Za-z0-9+=,.@_/-]+$", var.permissions_boundary_arn))
    error_message = "permissions_boundary_arn must be an IAM managed-policy ARN."
  }
}
