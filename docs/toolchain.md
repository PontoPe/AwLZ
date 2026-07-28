# Toolchain

Nothing here is installed on the Windows workstation yet. Pinned versions live in CI ( .github/workflows/ci.yml ) and must match locally.

| Tool | Purpose | Install (Windows) |
|------|---------|-------------------|
| terraform 1.9.x | everything | winget install HashiCorp.Terraform |
| aws-cli v2 | auth, evidence export | winget install Amazon.AWSCLI |
| tflint | lint | winget install TerraformLinters.tflint |
| tfsec | static security | winget install Aquasecurity.tfsec |
| checkov | policy-as-code scan | pip install checkov |
| infracost | cost estimate | winget install Infracost.Infracost |

Verify: 	erraform version && tflint --version && tfsec --version && checkov --version

Make targets assume a POSIX shell — run them from Git Bash or WSL, not PowerShell.
