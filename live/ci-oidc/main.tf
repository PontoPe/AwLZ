module "oidc" {
  source = "../../modules/iam-oidc"

  project                     = var.project
  github_repository           = var.github_repository
  apply_environment           = var.apply_environment
  additional_subject_prefixes = var.additional_subject_prefixes
  state_bucket_arn            = var.state_bucket_arn
  state_kms_key_arn           = var.state_kms_key_arn
}
