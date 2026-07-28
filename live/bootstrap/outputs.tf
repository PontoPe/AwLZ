output "state_bucket" {
  description = "Name of the Terraform state bucket."
  value       = aws_s3_bucket.state.id
}

output "state_kms_key_arn" {
  description = "CMK encrypting state at rest."
  value       = aws_kms_key.state.arn
}

output "backend_config" {
  description = "Paste this into any stack's backend.tf. Change the key per stack."
  value       = <<-EOT
    terraform {
      backend "s3" {
        bucket       = "${aws_s3_bucket.state.id}"
        key          = "<STACK-NAME>/terraform.tfstate"
        region       = "${var.region}"
        profile      = "${var.profile}"
        encrypt      = true
        kms_key_id   = "${aws_kms_key.state.arn}"
        use_lockfile = true
      }
    }
  EOT
}
