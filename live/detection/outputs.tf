output "config_bucket_name" {
  description = "Config delivery bucket in the log archive account."
  value       = module.detection.config_bucket_name
}

output "guardduty_detector_id" {
  description = "GuardDuty detector in the delegated administrator account."
  value       = module.detection.guardduty_detector_id
}

output "security_hub_standards" {
  description = "Standards subscribed in the administrator account."
  value       = module.detection.security_hub_standards
}

output "config_aggregator_arn" {
  description = "Organization-wide Config aggregator."
  value       = module.detection.config_aggregator_arn
}

output "config_recorder_accounts" {
  description = "Accounts that received a Config recorder. Should be five distinct IDs."
  value = {
    mgmt        = module.config_mgmt.account_id
    security    = module.config_security.account_id
    log-archive = module.config_log_archive.account_id
    dev         = module.config_dev.account_id
    lab         = module.config_lab.account_id
  }
}

output "permissions_boundary_names" {
  description = "Member account name to permissions boundary policy name."
  value = {
    security    = module.boundary_security.name
    log-archive = module.boundary_log_archive.name
    dev         = module.boundary_dev.name
    lab         = module.boundary_lab.name
  }
}

output "boundary_config_rule_names" {
  description = "Member account name to T5 Config rule name."
  value = {
    security    = module.boundary_rule_security.name
    log-archive = module.boundary_rule_log_archive.name
    dev         = module.boundary_rule_dev.name
    lab         = module.boundary_rule_lab.name
  }
}
