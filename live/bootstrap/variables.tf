variable "project" {
  description = "Prefix for every resource name in this landing zone."
  type        = string
  default     = "awlz"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,15}$", var.project))
    error_message = "project must be lowercase alphanumeric with hyphens, 3-16 chars — it becomes part of a globally unique S3 bucket name."
  }
}

variable "region" {
  description = "Home region. Global services (IAM, Organizations, CloudFront, and CloudTrail global events) still report to us-east-1, which is why the SCP region allow-list must include it."
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

variable "state_retention_days" {
  description = "How long superseded state versions are kept. State history is the rollback path after a bad apply."
  type        = number
  default     = 90
}
