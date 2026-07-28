# Cost

Monthly run cost of the landing zone itself, excluding workloads. Home region `sa-east-1`, which runs roughly 30–50% above `us-east-1` on most line items — deliberate, see ADR-001.

**These are estimates, and they are labelled as such.** Cost Explorer returns `DataUnavailableException` on this organization: it was created on 2026-07-28 and billing data has not been ingested yet. Actuals need a full cycle. Nothing in this file is a measurement.

## Fixed

| Item | Count | Est. USD/mo | Basis |
|---|---:|---:|---|
| KMS CMK — Terraform state | 1 | 1.00 | flat per key |
| KMS CMK — CloudTrail archive | 1 | 1.00 | flat per key |
| KMS CMK — Config delivery | 1 | 1.00 | flat per key |
| KMS requests | — | ~0.05 | bucket keys collapse most requests |
| **Fixed subtotal** | | **~3.05** | |

Three keys is a deliberate number. A fourth was considered for the CloudWatch log group and rejected — the durable copy is already CMK-encrypted in S3. The Config bucket got one after both scanners rated SSE-S3 a HIGH finding and the argument held up: that bucket holds an inventory of every account.

## Variable

| Service | Driver | Est. USD/mo | Confidence |
|---|---|---:|---|
| CloudTrail management events | first copy free | 0.00 | high |
| CloudTrail S3 data events | scoped to the state bucket only | ~0.10 | high |
| S3 — trail archive | GB stored, Glacier IR after 90d | ~0.20 | high |
| S3 — Config delivery | GB stored, expires at 90d | ~0.30 | medium |
| CloudWatch Logs | trail tail, 14-day retention | ~0.50 | medium |
| GuardDuty | events analysed across 5 accounts | 2–8 | low |
| AWS Config | configuration items + rule evaluations | 1–6 | low |
| Security Hub | checks per account per month | **4–18** | **low** |
| **Total** | | **~11–36** | |

Against a **USD 20 budget** with alerts at 85% and 100% actual, 100% forecast.

## Security Hub is the budget risk

It is the one line that can exceed the entire budget on its own.

Pricing is per security check: roughly USD 0.0010 for the first 100,000 checks per account per month. CIS v3.0.0 is about 60 controls. Evaluated on configuration change plus a periodic sweep, a quiet account lands somewhere near 2,000–4,000 checks/month — call it USD 2–4 per account. Across five accounts that is **USD 10–20/month by itself.**

That is a consequence of `auto_enable_standards = "DEFAULT"`, which was chosen on purpose: the deliverable is a **per-account** CIS score, and findings aggregate to the administrator either way but the *score* is computed per account. `"NONE"` would leave member accounts unscored and cut this line to roughly one fifth.

**The one-line lever**, in `live/detection/terraform.tfvars`:

```hcl
auto_enable_standards = "NONE"
```

**GuardDuty's first 30 days are free.** The trial hides the real number until month two, so the first invoice will understate the steady state. Do not read August as representative.

## What would change these numbers

- **Data events.** Currently one bucket. Enabling them broadly is the single easiest way to multiply the CloudTrail line by an order of magnitude.
- **Config recording scope.** `all_supported = true` in five accounts. Scoping to the resource types CIS actually evaluates would cut it, at the cost of blind spots on everything else.
- **Object Lock retention.** COMPLIANCE at 30 days. Storage cannot be reclaimed early by anyone, so raising retention raises a floor that cannot be lowered until it expires.
- **Workloads.** None of the above includes anything running in `awlz-dev` or `awlz-lab`.

## Keeping it cheap

- Budget alarm exists and predates the spend, which is the only order that helps.
- Region allow-list stops resources appearing where nobody reads the bill.
- Config history expires at 90 days; CloudTrail is the immutable record, Config snapshots are inputs to rule evaluation and lose value once superseded.
- CloudWatch Logs retention is 14 days for the same reason.

## Filling this in

After a full billing cycle:

```bash
aws ce get-cost-and-usage \
  --time-period Start=2026-08-01,End=2026-09-01 \
  --granularity MONTHLY --metrics UnblendedCost \
  --group-by Type=DIMENSION,Key=SERVICE \
  --profile mgmt --region us-east-1
```

Replace the estimate column with actuals and keep both. The gap between the two is more informative than either alone.
