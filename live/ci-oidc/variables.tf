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
