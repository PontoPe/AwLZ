# Toolchain

Nothing here is installed on the Windows workstation yet. Pinned versions live in CI (`.github/workflows/ci.yml`) and must match locally.

| Tool | Purpose | Install (Windows) |
|------|---------|-------------------|
| terraform 1.15.8 | everything | `winget install Hashicorp.Terraform` |
| aws-cli v2 | auth, evidence export | `winget install Amazon.AWSCLI` |
| tflint | lint | `winget install TerraformLinters.tflint` |
| trivy | IaC misconfiguration scan | `winget install AquaSecurity.Trivy` |
| checkov | policy-as-code scan | `pip install checkov` |
| infracost | cost estimate | `winget install Infracost.Infracost` |

Install one package per `winget install` invocation — passing several IDs at once fails.

Verify:

```
terraform version && tflint --version && trivy --version && checkov --version && aws --version
```

## Notes

- **`tfsec` is end-of-life.** Aqua folded its rule engine into Trivy; use `trivy config` instead. Anything referencing tfsec in older AWS-security tutorials maps 1:1 to `trivy config`.
- Make targets assume a POSIX shell — run them from Git Bash or WSL, not PowerShell.
- After a `winget install`, open a new terminal so `PATH` is reloaded.
- `pip install checkov` does not put `checkov` on `PATH` — the Python `Scripts` directory has to be added manually, or invoke it as `python -m checkov`.
- PowerShell's `&&` short-circuits: if one tool in a chained version check fails, the rest never run. Check them individually when diagnosing.
