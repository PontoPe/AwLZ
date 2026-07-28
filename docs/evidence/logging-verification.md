# Organization trail verification

Stack: `live/logging`. Date: 2026-07-28.

Account IDs redacted as `<mgmt>`, `<log-archive>`, `<lab>`; the organization ID is shown because it appears in the S3 prefix and is not sensitive on its own.

## Trail configuration

```
IsOrganizationTrail        true
IsMultiRegionTrail         true
LogFileValidationEnabled   true
KmsKeyId                   arn:aws:kms:sa-east-1:<log-archive>:key/…
CloudWatchLogsLogGroupArn  arn:aws:logs:sa-east-1:<mgmt>:log-group:/aws/cloudtrail/awlz-org-trail:*
IsLogging                  true
```

The CMK is in `<log-archive>`, not `<mgmt>`. An attacker holding the management account cannot read the archive without also holding a grant on a key in a different account.

## Archive bucket, checked from inside the log archive account

| Control | Value |
|---|---|
| Object Lock | `Enabled`, `COMPLIANCE`, 30 days |
| Versioning | `Enabled` |
| Encryption | `aws:kms` with the archive CMK, bucket keys on |
| Public access | all four flags `true` |

Reading the bucket *configuration* from the management account returns `AccessDenied`. That is correct, not a defect: the bucket policy grants the organization `s3:GetObject` and `s3:ListBucket` so an investigation can read logs, and nothing more. Configuration reads require credentials in the archive account.

## Delivery actually happened

Configuration proves intent. These prove function.

**S3 — a real log object, not a placeholder:**

```
675 B  AWSLogs/o-ej4pie4fmg/<mgmt>/CloudTrail/us-east-1/2026/07/28/
       <mgmt>_CloudTrail_us-east-1_20260728T2055Z_xcyGAp3LZK6JFOG6.json.gz
```

Two things worth reading off that path. The prefix is `AWSLogs/<org-id>/`, the organization-trail layout — a single-account trail writes `AWSLogs/<account-id>/` and a bucket policy scoped to the wrong one produces a trail that creates cleanly and then silently never delivers. And the region segment is `us-east-1`, which is global service events arriving as ADR-002 predicted; a region allow-list excluding `us-east-1` would have discarded them.

**CloudWatch Logs — streams from more than one account:**

```
<mgmt>_CloudTrail_sa-east-1
o-ej4pie4fmg_<lab>_CloudTrail_sa-east-1
```

The second stream is the one that matters. Events from `awlz-lab` are reaching a log group in the management account, which is what makes this an *organization* trail rather than a trail that happens to live in the management account. No agent, no per-account configuration, no opt-in.

## A status field that lies

`LatestDeliveryTime` read `null` while log objects were already in the bucket, and `LatestCloudWatchLogsDeliveryTime` was populated.

The field lags. Treating `get-trail-status` as the source of truth for "is delivery working" produces a false negative in the first minutes after creation — long enough to send someone debugging a trail that is fine. List the bucket instead.

## What this does not cover

- No alarm on trail state changes yet. The CloudWatch log group exists precisely so metric filters and alarms have somewhere to attach; none are defined. T2 is prevented by SCP and recorded here, but not *alerted* on.
- Log file validation is enabled, but no one has run `aws cloudtrail validate-logs` against the archive. The digest files are being written; verifying the chain is a separate exercise.
- Data events cover the Terraform state bucket only. Any other bucket in the organization is invisible at object level, deliberately — see the cost reasoning in `modules/logging/variables.tf`.
