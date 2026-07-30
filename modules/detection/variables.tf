variable "project" {
  description = "Prefix for every resource name."
  type        = string
}

variable "region" {
  description = "Region the detectors run in."
  type        = string
}

variable "security_account_id" {
  description = "Account that becomes delegated administrator for GuardDuty, Security Hub, Config and Access Analyzer."
  type        = string
}

variable "log_archive_account_id" {
  description = "Account that owns the Config delivery bucket."
  type        = string
}

variable "organization_id" {
  description = "Organization ID, for the delivery bucket policy."
  type        = string
}

variable "recording_account_ids" {
  description = "Every account that runs a Config recorder. Scopes the CMK grant to Config by source account."
  type        = list(string)
}

variable "config_retention_days" {
  description = <<-EOT
    Lifecycle expiry on Config delivery objects.

    Config history is a cost driver that grows without bound if left alone.
    The audit record of *who changed what* is CloudTrail, which is retained
    separately and immutably; Config's snapshots are inputs to rule evaluation,
    and stale ones have little value.
  EOT

  type    = number
  default = 90
}

variable "security_standards" {
  description = <<-EOT
    Security Hub standards to subscribe the delegated administrator to.

    CIS is the one this project is measured against. Each standard bills per
    control evaluation per account, so this is an explicit list rather than
    "enable everything".
  EOT

  type = map(string)

  default = {
    cis = "standards/cis-aws-foundations-benchmark/v/3.0.0"
  }
}

variable "auto_enable_standards" {
  description = <<-EOT
    Whether future member accounts joining Security Hub get AWS's default
    standards (FSBP and CIS v1.2.0).

    This does not cover existing organization accounts and does not enable the
    CIS v3.0.0 benchmark used for this project's evidence. Existing accounts
    and their CIS v3.0.0 subscriptions are explicit in live/detection.
  EOT

  type    = string
  default = "DEFAULT"

  validation {
    condition     = contains(["DEFAULT", "NONE"], var.auto_enable_standards)
    error_message = "auto_enable_standards must be DEFAULT or NONE."
  }
}

variable "security_permissions_boundary_arn" {
  description = "Account-local boundary for the Config aggregator role in the security account."
  type        = string

  validation {
    condition     = can(regex("^arn:[^:]+:iam::[0-9]{12}:policy/[A-Za-z0-9+=,.@_/-]+$", var.security_permissions_boundary_arn))
    error_message = "security_permissions_boundary_arn must be an IAM managed-policy ARN."
  }
}

variable "guardduty_finding_frequency" {
  description = "How often GuardDuty publishes findings to the administrator. Six hours is the default; fifteen minutes costs nothing extra and shortens time-to-detect."
  type        = string
  default     = "FIFTEEN_MINUTES"
}
