# Cost

Monthly run cost of AwLZ plus the sibling PontoAntiCrack deployment. Home
region is `sa-east-1`; the hard shared ceiling is **USD 20/month**.

## Measured actual — 2026-08-04, July window closed

C6 is closed. Cost Explorer returns `Estimated: false` for
`2026-07-01`–`2026-08-01`, so the numbers below are billed actuals rather than
a projection.

### Read this first: grouping by service hides credits

Grouping by `SERVICE` without a record-type filter sums the `Credit` record
type into the same bucket as `Usage`. Every service in this organization
returned `0` under that grouping in July, which looks like nothing was billed
and is wrong — it means usage and credit netted out. Gross cost needs the
filter:

```bash
aws ce get-cost-and-usage \
  --time-period Start=2026-07-01,End=2026-08-01 \
  --granularity MONTHLY --metrics UnblendedCost \
  --filter '{"Dimensions":{"Key":"RECORD_TYPE","Values":["Usage"]}}' \
  --group-by Type=DIMENSION,Key=SERVICE \
  --profile mgmt --region us-east-1
```

Without `RECORD_TYPE`, a healthy Config recorder emitting 325 configuration
items reads as USD 0 and gets mistaken for a broken recorder or a free tier.
It is neither.

### July 2026 — billed actual, gross usage

| Service | USD | Note |
|---|---:|---|
| AWS Config | 0.9970 | 325 configuration items + 22 rule evaluations |
| AWS Key Management Service | 0.3723 | prorated; keys created mid-month |
| Amazon S3 | 0.0748 | |
| AWS Secrets Manager | 0.0173 | PontoAntiCrack, prorated from 2026-07-30 |
| AWS CloudTrail | 0.0015 | data events on the state bucket only |
| Amazon GuardDuty | 0.0000 | inside the 30-day trial |
| AWS Security Hub | 0.0000 | inside its trial |
| **Gross usage** | **1.4629** | |
| Other services (rounding, Data Transfer, Glue, DynamoDB, SNS, SQS) | 0.0201 | |
| **Total usage** | **1.4830** | |
| **Credits applied** | **−1.4830** | |
| **Net invoiced** | **0.0000** | |

Config bills per recorded configuration item and rule evaluation; the current
São Paulo rate is [USD 0.003 per configuration item and USD 0.001 per rule
evaluation](https://aws.amazon.com/config/pricing/). The observed figure
reconciles exactly: `325 × 0.003 + 22 × 0.001 = 0.997`.

**Do not report July as USD 0.** The operating cost was USD 1.48; a credit
covered it. Reporting the net would understate the model by the entire amount
it was supposed to measure.

### August 2026 — first uncredited month

Credits stop at the July boundary. `2026-08-01`–`2026-08-04` contains no
`Credit` record type at all: `Usage 0.6322` and `Tax 0.03`. August is the first
month whose invoice reflects what this organization actually costs.

Run rate from three full days, by account:

| Account | Service | USD/day | USD/month |
|---|---|---:|---:|
| `pegradowski-mgmt` | KMS — 2 keys | 0.0645 | 2.00 |
| `awlz-log-archive` | KMS — 2 keys | 0.0645 | 2.00 |
| `awlz-log-archive` | S3 | 0.0217 | 0.67 |
| `awlz-lab` | KMS — 1 key (`alias/pac`) | 0.0323 | 1.00 |
| `awlz-lab` | Secrets Manager (`pac/slack-webhook`) | 0.0129 | 0.40 |
| `pegradowski-mgmt` | Tax | — | 0.31 |
| | **Total** | | **6.38** |

Split: **AwLZ USD 4.67** (4 keys, S3, tax) and **PontoAntiCrack USD 1.40**
(1 key, 1 secret, three idle Lambdas).

`awlz-lab` carries a recurring USD 1.40/month. This is expected, not a leak:
`alias/pac`, `pac/slack-webhook` and the three `pac-*` Lambdas are
PontoAntiCrack's documented at-rest deployment. What was released in July was
the *concurrency quota request*, not the account. The two are easy to conflate
and the sibling repo's wording should say which.

### Confirmation — 2026-08-15, half of August observed

The three-day run rate held. Gross usage for `2026-08-01`–`2026-08-15` is
**USD 2.8364**, which annualises to roughly USD 5.86 before tax against the
USD 6.38/month projected from three days.

| Service | USD, 1–15 Aug |
|---|---:|
| AWS Key Management Service | 2.2581 |
| Amazon S3 | 0.3041 |
| AWS Secrets Manager | 0.1812 |
| **AWS Cost Explorer** | **0.0900** |
| AWS Config | 0.0030 |
| AWS CloudTrail | 0.0000 |
| **Total** | **2.8364** |

Two things in that table are worth naming.

**Cost Explorer bills for being asked.** USD 0.01 per request, and measuring C6
cost USD 0.09 — the measurement is now a line item in the thing it measures. It
is small and it is not free, and a monthly re-measurement is a recurring charge
rather than a free query.

**Config fell from USD 0.997 to USD 0.003.** A 300-fold drop that reads like a
broken recorder. It is not: July contained the first-time recording of every
existing resource, and August is a steady state where almost nothing changes.
All five recorders were checked directly and report `recording: true` /
`lastStatus: SUCCESS` — see `docs/evidence/detection-verification.md`. **The
July Config figure is a baseline, not a run rate**, and any projection built on
it would have been roughly 300x too high.

The budget reports USD 3.093 actual against the USD 20 ceiling, 15%. No
threshold has fired; alerts remain at 85% and 100% of actual plus 100% of
forecast.

### Delta against the 2026-07-30 projection

| Line | Projected | Actual (Aug run rate) | Delta |
|---|---:|---:|---|
| AwLZ four CMKs | 4.05 | 4.00 | −0.05, matched |
| CloudTrail + CloudWatch Logs | 1.10 | ~0.67 | −0.43, S3 only; log tail not yet billing |
| Config items + rules | 3.12 | 0.00 so far | **−3.12, see below** |
| GuardDuty | 0.25 | 0.00 | trial until ~2026-08-27 |
| Security Hub CIS | 2.76 | 0.00 | trial; standard removed outside `awlz-security` |
| Break-glass alarm | 0.10 | 0.00 | below billing granularity |
| PontoAntiCrack at rest | 2.35 | 1.40 | −0.95 |
| Secrets Manager | *absent* | 0.40 | **line missing from the model** |
| **Joint** | **13.73** | **6.38** | |

Two corrections to the model, and the first one matters more than the number:

1. **Config cost is change-driven, not time-driven.** The projection
   extrapolated 33 configuration items from a *deployment* day and multiplied
   by 30. August so far has recorded **zero** configuration items, because
   nothing in the organization changed — the boundary rules are
   change-triggered, so no change means no evaluation either. Config bills what
   the org does, not how long it exists. A month with a Terraform apply in it
   will bill; a quiet month will not. Neither USD 3.12 nor USD 0 is the steady
   state, and a single closed month cannot produce that figure.
2. **Secrets Manager was missing from the model entirely** at USD 0.40/month
   flat. Small, but it was invisible rather than estimated low.

### What August still cannot tell us

- **GuardDuty's trial ends around 2026-08-27**, so the August invoice covers at
  most four billed days of it. The projected USD 0.25/month came from accrued
  trial usage across four detectors, which is a fragile basis.
- **Security Hub** is in the same position.
- `get-cost-forecast` returns `DataUnavailableException — Insufficient amount
  of historical data`. The organization is too young to forecast.

**September 2026 is the first representative month.** Anything reported before
then is a partial trial month, and should say so.

### August 2026 — closed window

Measured 2026-10-08, `Estimated: false`. Gross usage **USD 6.3126**, tax USD
0.29, no credit records: **USD 6.60 invoiced**. The three-day run rate of USD
6.38 held to within four cents of usage.

It contains the trial cliff, and the usage types show where it fell: Security
Hub billed 116 paid compliance checks (USD 0.116) after 783 free ones, and
GuardDuty 1,270 paid events (USD 0.0089) after 11,996 free. About four billed
days of each — consistent with trials ending around 2026-08-27. August is
still not a steady state; it is the month the steady state started in.

AWS Cost Explorer billed USD 0.12 in August: the C6 measurement and its
re-checks, at USD 0.01 per request.

### September 2026 — first representative month

Measured 2026-10-08, `Estimated: false`. No credits and no trials anywhere in
the window. This is the first number that can be quoted as steady state.

| Service | USD | Basis |
|---|---:|---|
| AWS Key Management Service | 4.9944 | 5 keys: 2 `pegradowski-mgmt`, 2 `awlz-log-archive`, 1 `awlz-lab` (`alias/pac`) |
| **AWS Security Hub** | **0.8700** | 870 paid compliance checks, `awlz-security` only |
| Amazon S3 | 0.6517 | 0.645 of it in `awlz-log-archive` |
| AWS Secrets Manager | 0.4011 | `pac/slack-webhook` in `awlz-lab` |
| **Amazon GuardDuty** | **0.0783** | 11,186 paid events analyzed, five detectors |
| AWS Config | 0.0390 | 13 configuration items recorded |
| AWS CloudTrail | 0.0001 | |
| Amazon CloudWatch | 0.0000 | 10 alarms monitored, inside the free tier |
| DynamoDB, Glue, SNS, SQS | 0.0000 | |
| **Gross usage** | **7.0346** | |
| Tax | 0.28 | |
| Credits | 0.00 | no `Credit` record type in the window |
| **Invoiced** | **7.31** | |

Split: **AwLZ USD 5.63** (four keys, the log archive, Security Hub, GuardDuty,
Config) and **PontoAntiCrack USD 1.40** (`alias/pac` and the webhook secret —
unchanged from August, as an idle deployment should be).

No Cost Explorer line: nobody queried it in September. The queries that
produced this section will bill in October.

### Delta against the 2026-07-30 projection, September actual

| Line | Projected | Sept actual | Delta |
|---|---:|---:|---|
| AwLZ four CMKs | 4.05 | 4.00 | matched |
| CloudTrail + CloudWatch Logs | 1.10 | 0.65 | −0.45; archive S3 only, log tail still not billing |
| Config items + rules | 3.12 | 0.04 | −3.08; quiet month, 13 items |
| GuardDuty | 0.25 | 0.08 | −0.17 |
| Security Hub CIS | 2.76 | 0.87 | −1.89, see below |
| Break-glass alarm | 0.10 | 0.00 | free tier |
| PontoAntiCrack at rest (incl. Secrets Manager) | 2.35 | 1.40 | −0.95 |
| **Joint, gross usage** | **13.73** | **7.03** | **−6.70** |

**Security Hub was the largest uncertain line, and it came in at a third of
the projection.** The model assumed 46 checks × 30 days × a 2× re-evaluation
margin = 2,760 checks. The real figure is 870 — about 29 a day. The margin
was not needed in a month without changes, and the daily check count is lower
than the 46 active findings the proxy was built on. A month with Terraform
applies will evaluate more; 870 is a quiet-month floor, not a ceiling.

**The trial cliff was USD 0.95/month**, not the USD 3.01 the projection
reserved for GuardDuty and Security Hub together. The organization's measured
steady state is **USD 7.31/month invoiced — 37% of the USD 20 ceiling.**

### What is still open

- `get-cost-forecast` no longer returns `DataUnavailableException`; on
  2026-10-08 it returned `InternalFailure` on every retry. The budget's own
  forecast works: USD 6.34 for October, USD 1.69 actual by 2026-10-08.
- Config and Security Hub are change-driven, and September was quiet. A month
  with real Terraform activity is the upper bound, and none has been measured.

## The 2026-07-30 projection, retained

Kept verbatim beside the actual above. The delta *is* the evidence about the
model, and deleting the superseded estimate would destroy it.

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

### Conservative joint projection

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
remain the steady state. CIS stayed enabled in all five accounts until the
C3 control experiment was captured on 2026-07-30, which it now is. Terraform
will next:

1. retain CIS v3.0.0 in `awlz-security`;
2. remove the explicit standard subscription from management, log archive,
   dev and lab while leaving their Security Hub membership enabled; and
3. set future-account standard auto-enable to `NONE`.

What is lost is stated plainly: there will no longer be a live per-account CIS
score or a repeatable live lab with/without-SCP comparison. The timestamped C3
artifact remains, while preventive SCPs, Config recording/rules, GuardDuty,
Access Analyzer and centralized findings remain live. This is the cheapest
configuration that preserves an ongoing named CIS benchmark in the delegated
security account and keeps a conservative USD 6.27 buffer for usage variance.

## Fixed AwLZ cost

| Item | Count | Est. USD/mo | Basis |
|---|---:|---:|---|
| KMS CMK — Terraform state | 1 | 1.00 | flat per key |
| KMS CMK — CloudTrail archive | 1 | 1.00 | flat per key |
| KMS CMK — Config delivery | 1 | 1.00 | flat per key |
| KMS CMK — break-glass alarm topic | 1 | 1.00 | flat per key |
| KMS requests | — | ~0.05 | bucket keys collapse most requests |
| **Fixed subtotal** | | **~4.05** | |

**Confirmed against the August run rate: USD 4.00/month, 2 keys in
`pegradowski-mgmt` and 2 in `awlz-log-archive`.** Key requests billed below
Cost Explorer's granularity, so the `~0.05` line is an upper bound rather than
a measurement. This is the only line of the model the first closed window
confirmed outright.

A fifth customer-managed key exists in the organization — `alias/pac` in
`awlz-lab` — and it is PontoAntiCrack's, not AwLZ's. Anyone reading a
consolidated KMS charge of USD 5.00/month against this table will conclude the
table is wrong. It is not; the billing view is org-wide and this table is not.

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
- **Credits are not a guardrail.** They covered 100% of July and stopped at the
  month boundary with no warning in any dashboard this repo watches. The budget
  alarms are set against spend, so a credit expiry is invisible to them until
  the spend it was hiding shows up.

## C6 — closed 2026-08-04

The July window closed at `2026-08-01T00:00:00Z` and Cost Explorer returned
`Estimated: false` on 2026-08-04. The actual is recorded above.

Re-run for any later month with:

```bash
aws ce get-cost-and-usage \
  --time-period Start=2026-08-01,End=2026-09-01 \
  --granularity MONTHLY --metrics UnblendedCost UsageQuantity \
  --filter '{"Dimensions":{"Key":"RECORD_TYPE","Values":["Usage"]}}' \
  --group-by Type=DIMENSION,Key=SERVICE \
  --profile mgmt --region us-east-1
```

Do not relabel a result as actual if Cost Explorer still returns
`Estimated: true`. The 2026-07-30 projection stays in this file beside the
closed-window actual; the delta is evidence about the model.

Three rules this exercise produced, each from getting it wrong first:

1. **Filter `RECORD_TYPE=Usage`.** Otherwise credits net against usage inside
   the same service row and healthy infrastructure reads as free.
2. **Report gross, then credit, then net — all three.** A net of USD 0 is true
   and useless.
3. **A single closed month is not a steady state** when a service is inside a
   trial or when its billing is change-driven. Say which lines are which.
