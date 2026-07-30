variable "project" {
  description = "Prefix for every resource name."
  type        = string
}

variable "organization_id" {
  description = "Organization ID. Scopes the bucket policy and the CloudTrail log prefix."
  type        = string
}

variable "log_archive_account_id" {
  description = "Account that owns the archive bucket. Must be the account behind the aws.log_archive provider."
  type        = string
}

variable "region" {
  description = "Region for the archive bucket. The trail is multi-region regardless."
  type        = string
}

variable "object_lock_mode" {
  description = <<-EOT
    COMPLIANCE or GOVERNANCE.

    COMPLIANCE means no principal can shorten the retention or delete an
    object before it expires — not the account root, not AWS Support. That is
    the property that survives a full account compromise, which is the entire
    reason the log archive is a separate account.

    It also means the bucket cannot be emptied or destroyed until every
    object's retention has expired. That is not a bug to work around; it is
    the control. Budget for it before setting a long retention.

    GOVERNANCE is bypassable by a principal holding
    s3:BypassGovernanceRetention. Useful for a throwaway environment, and
    strictly weaker.
  EOT

  type    = string
  default = "COMPLIANCE"

  validation {
    condition     = contains(["COMPLIANCE", "GOVERNANCE"], var.object_lock_mode)
    error_message = "object_lock_mode must be COMPLIANCE or GOVERNANCE."
  }
}

variable "object_lock_retention_days" {
  description = <<-EOT
    How long each object is locked.

    Deliberately short by default. This is a portfolio organization on a hard
    USD 20/month budget, and under COMPLIANCE mode every day of retention is a
    day the storage cannot be reclaimed by anyone. 30 days demonstrates the
    control honestly; a production log archive would use years, and would size
    the bill accordingly.
  EOT

  type    = number
  default = 30

  validation {
    condition     = var.object_lock_retention_days >= 1
    error_message = "retention must be at least 1 day."
  }
}

variable "glacier_transition_days" {
  description = "Days before objects move to Glacier Instant Retrieval. Object Lock and lifecycle transitions coexist — the lock blocks deletion, not storage class changes."
  type        = number
  default     = 90
}

variable "cloudwatch_retention_days" {
  description = <<-EOT
    Retention on the CloudWatch Logs copy of the trail.

    Short on purpose. CloudWatch Logs is the near-real-time tail that metric
    filters, alarms and subscriptions attach to — CIS requires the pairing.
    The system of record is the object-locked S3 archive, which is why paying
    to keep two long-lived copies would be waste rather than defence in depth.
  EOT

  type    = number
  default = 14
}

variable "data_event_bucket_arns" {
  description = <<-EOT
    S3 buckets to record *data* events for, as bucket ARNs.

    Management events are free for the first copy; data events are billed per
    event and are the line item that makes a naive org trail expensive. So
    this is an explicit allow-list rather than "all S3".

    The Terraform state bucket belongs here: state reads and writes are
    otherwise invisible, which is threat T6b.
  EOT

  type    = list(string)
  default = []
}

variable "break_glass_role_arns" {
  description = "Exact member-account OrganizationAccountAccessRole ARNs whose use raises the T8 alarm."
  type        = list(string)

  validation {
    condition = (
      length(var.break_glass_role_arns) > 0 &&
      alltrue([
        for arn in var.break_glass_role_arns :
        can(regex("^arn:[^:]+:iam::[0-9]{12}:role/OrganizationAccountAccessRole$", arn))
      ])
    )
    error_message = "break_glass_role_arns must contain exact OrganizationAccountAccessRole ARNs."
  }
}
