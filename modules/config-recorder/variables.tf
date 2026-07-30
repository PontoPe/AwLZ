variable "project" {
  description = "Prefix for every resource name."
  type        = string
}

variable "delivery_bucket_name" {
  description = "Config delivery bucket, owned by the log archive account."
  type        = string
}

variable "delivery_kms_key_arn" {
  description = "CMK the delivery bucket is encrypted with. The recorder role needs a data-key grant or delivery fails silently."
  type        = string
}

variable "record_global_resource_types" {
  description = <<-EOT
    Whether this recorder captures global resources (IAM users, roles,
    policies).

    Global resources are visible from every region, so recording them in more
    than one region per account bills for the same configuration item twice.
    Exactly one recorder per account should set this true — and since this
    landing zone runs a single region, that is every recorder.
  EOT

  type    = bool
  default = true
}

variable "permissions_boundary_arn" {
  description = "Optional account-local boundary for the Config recorder role."
  type        = string
  default     = null

  validation {
    condition = (
      var.permissions_boundary_arn == null ||
      can(regex("^arn:[^:]+:iam::[0-9]{12}:policy/[A-Za-z0-9+=,.@_/-]+$", var.permissions_boundary_arn))
    )
    error_message = "permissions_boundary_arn must be null or an IAM managed-policy ARN."
  }
}
