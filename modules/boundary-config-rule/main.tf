resource "aws_config_config_rule" "this" {
  name        = "${var.project}-role-permissions-boundary"
  description = "Checks if customer-managed IAM roles use the approved permissions boundary."

  input_parameters = jsonencode({
    requiredBoundaryArn = var.required_boundary_arn
  })

  scope {
    compliance_resource_types = ["AWS::IAM::Role"]
  }

  source {
    owner = "CUSTOM_POLICY"

    source_detail {
      event_source = "aws.config"
      message_type = "ConfigurationItemChangeNotification"
    }

    source_detail {
      event_source = "aws.config"
      message_type = "OversizedConfigurationItemChangeNotification"
    }

    custom_policy_details {
      policy_runtime            = "guard-2.x.x"
      enable_debug_log_delivery = false
      policy_text               = <<-GUARD
        rule boundary_present when
          resourceType == "AWS::IAM::Role"
          configuration.roleName != "OrganizationAccountAccessRole"
          configuration.roleName != /(?i)^AWSServiceRoleFor/
          configuration.roleName != /(?i)^AWSReservedSSO_/
        {
          configuration.permissionsBoundary exists
          configuration.permissionsBoundary is_struct
        }

        rule boundary_matches when boundary_present {
          configuration.permissionsBoundary.permissionsBoundaryArn == CONFIG_RULE_PARAMETERS.requiredBoundaryArn
        }
      GUARD
    }
  }
}
