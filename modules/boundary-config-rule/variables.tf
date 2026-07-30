variable "project" {
  description = "Prefix for the Config rule name."
  type        = string
}

variable "required_boundary_arn" {
  description = "Exact account-local permissions boundary required on customer-managed roles."
  type        = string

  validation {
    condition     = can(regex("^arn:[^:]+:iam::[0-9]{12}:policy/[A-Za-z0-9+=,.@_/-]+$", var.required_boundary_arn))
    error_message = "required_boundary_arn must be an IAM managed-policy ARN."
  }
}
