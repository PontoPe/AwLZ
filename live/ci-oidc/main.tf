module "oidc" {
  source = "../../modules/iam-oidc"

  project                     = var.project
  github_repository           = var.github_repository
  apply_environment           = var.apply_environment
  additional_subject_prefixes = var.additional_subject_prefixes
  state_bucket_arn            = var.state_bucket_arn
  state_kms_key_arn           = var.state_kms_key_arn
  member_plan_role_arns = [
    for id in values(var.account_ids) :
    "arn:aws:iam::${id}:role/${var.project}-gha-plan-readonly"
  ]
}

module "member_plan_security" {
  source = "../../modules/member-plan-role"

  providers = { aws = aws.security }

  project                  = var.project
  management_plan_role_arn = module.oidc.plan_role_arn
  permissions_boundary_arn = "arn:aws:iam::${var.account_ids.security}:policy/${var.project}-permissions-boundary"
}

module "member_plan_log_archive" {
  source = "../../modules/member-plan-role"

  providers = { aws = aws.log_archive }

  project                  = var.project
  management_plan_role_arn = module.oidc.plan_role_arn
  permissions_boundary_arn = "arn:aws:iam::${var.account_ids.log-archive}:policy/${var.project}-permissions-boundary"
}

module "member_plan_dev" {
  source = "../../modules/member-plan-role"

  providers = { aws = aws.dev }

  project                  = var.project
  management_plan_role_arn = module.oidc.plan_role_arn
  permissions_boundary_arn = "arn:aws:iam::${var.account_ids.dev}:policy/${var.project}-permissions-boundary"
}

module "member_plan_lab" {
  source = "../../modules/member-plan-role"

  providers = { aws = aws.lab }

  project                  = var.project
  management_plan_role_arn = module.oidc.plan_role_arn
  permissions_boundary_arn = "arn:aws:iam::${var.account_ids.lab}:policy/${var.project}-permissions-boundary"
}

check "member_plan_roles_landed_in_distinct_accounts" {
  assert {
    condition = length(distinct([
      module.member_plan_security.account_id,
      module.member_plan_log_archive.account_id,
      module.member_plan_dev.account_id,
      module.member_plan_lab.account_id,
    ])) == 4

    error_message = "two member plan roles resolved to the same account — check provider aliases."
  }
}
