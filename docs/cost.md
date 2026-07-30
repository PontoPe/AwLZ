# Cost

Monthly run cost of AwLZ plus the sibling PontoAntiCrack deployment. Home
region is `sa-east-1`; the hard shared ceiling is **USD 20/month**.

## Measurement status — 2026-07-30

Cost Explorer was queried for `2026-07-28` through `2026-07-30`, grouped by
service with unblended cost and usage quantity. Both daily intervals still
returned `Estimated: true`. The only nonzero money rows offset to net USD 0:
S3 `+0.000119` and Data Transfer `-0.000119`. This is ingestion evidence, not a
closed-window actual.

| Input | Observed | How it is used |
|---|---:|---|
| Config items, most recent estimated day | 33 | `33 × 30 × USD 0.003 = USD 2.97` |
| GuardDuty accrued usage from four established detectors | USD 0.002667 | projected conservatively as USD 0.25/month |
| Mature CIS v3.0.0 account | 46 active findings, 35 evaluated controls | proxy for one daily evaluation sweep |
| Security Hub CSPM São Paulo first tier | USD 0.001/check | current AWS Price List query |
| PontoAntiCrack at-rest estimate | USD 2.35/month | [sibling cost breakdown](../../PontoAntiCrack/docs/session-report.md) |

Config bills per recorded configuration item and rule evaluation; the current
São Paulo rate is [USD 0.003 per configuration item and USD 0.001 per rule
evaluation](https://aws.amazon.com/config/pricing/). GuardDuty usage statistics
are accrued usage, not a forecast, and the [30-day trial masks the initial
invoice](https://docs.aws.amazon.com/guardduty/latest/ug/guardduty-pricing.html).
Security Hub usage is likewise still inside its trial; the calculation uses
the current CSPM price-list SKU rather than treating trial-zero as steady state.

## Conservative joint projection

The Security Hub multiplier includes a 2× change/re-evaluation margin:

```text
all five CIS accounts:
  46 checks × 5 accounts × 30 days × 2 × USD 0.001 = USD 13.80

security account only:
  46 checks × 1 account × 30 days × 2 × USD 0.001 = USD 2.76
```

| Line | Five CIS accounts | Security-only CIS |
|---|---:|---:|
| Four AwLZ customer-managed KMS keys | 4.05 | 4.05 |
| CloudTrail data events, S3 and CloudWatch Logs | 1.10 | 1.10 |
| Config items + four boundary rules | 3.12 | 3.12 |
| GuardDuty | 0.25 | 0.25 |
| Security Hub CIS v3.0.0 | **13.80** | **2.76** |
| Break-glass CloudWatch alarm | 0.10 | 0.10 |
| PontoAntiCrack at rest | 2.35 | 2.35 |
| **Joint conservative total** | **24.77** | **13.73** |
| **Buffer below USD 20** | **-4.77** | **6.27** |

The five-account configuration can exceed the ceiling and therefore cannot
remain the steady state. CIS stays enabled in all five accounts only until the
time-dependent C3 evidence is valid. After that capture, Terraform will:

1. retain CIS v3.0.0 in `awlz-security`;
2. remove the explicit standard subscription from management, log archive,
   dev and lab while leaving their Security Hub membership enabled; and
3. set future-account standard auto-enable to `NONE`.

What is lost is stated plainly: there will no longer be a live per-account CIS
score or a repeatable live lab with/without-SCP comparison. The timestamped C3
artifact remains, while preventive SCPs, Config recording/rules, GuardDuty,
Access Analyzer and centralized findings remain live. This is the cheapest
configuration that preserves an ongoing named CIS benchmark in the delegated
security account and keeps a conservative USD 7.27 buffer for usage variance.

## Fixed AwLZ cost

| Item | Count | Est. USD/mo | Basis |
|---|---:|---:|---|
| KMS CMK — Terraform state | 1 | 1.00 | flat per key |
| KMS CMK — CloudTrail archive | 1 | 1.00 | flat per key |
| KMS CMK — Config delivery | 1 | 1.00 | flat per key |
| KMS CMK — break-glass alarm topic | 1 | 1.00 | flat per key |
| KMS requests | — | ~0.05 | bucket keys collapse most requests |
| **Fixed subtotal** | | **~4.05** | |

Four keys is deliberate. A fifth for the CloudWatch log group was rejected: the
durable copy is already CMK-encrypted in S3. The Config bucket retains its own
key because it contains an inventory of every account. The break-glass topic
gained a key because `alias/aws/sns` accepts no key policy: the notification
reveals when a member account's recovery role was used, and an AWS-managed key
offers neither a source-bound grant nor a revocation switch independent of SNS.

## Cost guardrails

- The budget predates the spend: alerts at 85% and 100% actual, plus 100%
  forecast.
- CloudTrail data events cover only the Terraform state bucket.
- Config history expires after 90 days.
- The CloudWatch Logs tail expires after 14 days; the object-locked archive is
  the durable record.
- Object Lock is COMPLIANCE for 30 days. Stored objects cannot be reclaimed
  early, including by root.
- No workload run cost is included beyond PontoAntiCrack's documented at-rest
  footprint. A forgotten lab instance remains a separate risk.

## C6 — earliest valid actual

The July billing window closes at `2026-08-01T00:00:00Z`. Allowing a full day
for Cost Explorer ingestion, the earliest defensible retry is
**2026-08-02T12:00:00-03:00**, querying:

```bash
aws ce get-cost-and-usage \
  --time-period Start=2026-07-28,End=2026-08-01 \
  --granularity MONTHLY --metrics UnblendedCost UsageQuantity \
  --group-by Type=DIMENSION,Key=SERVICE \
  --profile mgmt --region us-east-1
```

Do not relabel a result as actual if Cost Explorer still returns
`Estimated: true`. Keep this projection beside the first closed-window actual;
the delta is evidence about the model.
