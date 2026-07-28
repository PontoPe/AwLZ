module "logging" {
  source = "../../modules/logging"

  providers = {
    aws             = aws
    aws.log_archive = aws.log_archive
  }

  project                = var.project
  region                 = var.region
  organization_id        = var.organization_id
  log_archive_account_id = var.log_archive_account_id

  object_lock_mode           = var.object_lock_mode
  object_lock_retention_days = var.object_lock_retention_days

  data_event_bucket_arns = [var.state_bucket_arn]
}
