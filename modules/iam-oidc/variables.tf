variable "project" {
  description = "Prefix for every resource name."
  type        = string
}

variable "github_repository" {
  description = "owner/name of the repository allowed to assume these roles."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$", var.github_repository))
    error_message = "github_repository must be owner/name."
  }
}

variable "additional_subject_prefixes" {
  description = <<-EOT
    Extra `sub` prefixes to trust, alongside `repo:<owner>/<name>`.

    GitHub issues immutable subject claims for some repositories, where the
    prefix embeds numeric IDs: `repo:owner@<owner-id>/name@<repo-id>`. That
    form survives a rename, which is the point — trust cannot follow a name
    someone else later claims — but it does not match a policy written for the
    plain form, and STS rejects it with a message that says only "Not
    authorized".

    Read the actual value with:
      gh api repos/<owner>/<name>/actions/oidc/customization/sub

    Every entry is still an exact match for one repository, so listing both
    forms widens nothing.
  EOT

  type    = list(string)
  default = []
}

variable "plan_branch" {
  description = "Branch whose pushes may assume the plan role, in addition to pull requests."
  type        = string
  default     = "main"
}

variable "apply_environment" {
  description = <<-EOT
    GitHub Environment gating the apply role.

    The trust policy binds to `environment:<name>`, so a workflow that has not
    passed through this environment cannot assume the role no matter what it
    puts in its own YAML. That is the property an approval gate needs: it must
    not be bypassable by editing the file that requests it.
  EOT

  type    = string
  default = "production"
}

variable "state_bucket_arn" {
  description = "Terraform state bucket. The plan role needs read; the apply role needs write."
  type        = string
}

variable "state_kms_key_arn" {
  description = "CMK protecting state. Reading state is impossible without it, so a role with s3 access and no kms grant fails confusingly."
  type        = string
}

variable "member_plan_role_arns" {
  description = "Exact member-account read-only roles the management plan role may assume."
  type        = list(string)

  validation {
    condition = (
      length(var.member_plan_role_arns) > 0 &&
      alltrue([
        for arn in var.member_plan_role_arns :
        can(regex("^arn:[^:]+:iam::[0-9]{12}:role/[A-Za-z0-9+=,.@_/-]+$", arn))
      ])
    )
    error_message = "member_plan_role_arns must contain exact IAM role ARNs."
  }
}
