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
