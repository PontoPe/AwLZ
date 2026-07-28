# Cost

Monthly run cost of the landing zone itself, excluding workloads. Filled in from `infracost breakdown` plus actual Cost Explorer data after a full billing cycle — estimates alone are not evidence.

| Service | Driver | Est. USD/mo | Actual USD/mo | Notes |
|---------|--------|------------:|--------------:|-------|
| CloudTrail (org trail) | first copy of management events free | 0.00 | | data events are the expensive part — off by default |
| S3 log archive | GB stored + Object Lock versions | | | lifecycle to Glacier after 90d |
| KMS CMK | per key + requests | 1.00 | | one key, low request volume |
| GuardDuty | events + VPC flow log volume | | | biggest variable; 30-day trial first |
| AWS Config | configuration items recorded | | | scope recorders to the resource types that matter |
| Security Hub | checks per account | | | CIS standard only |
| S3 state bucket | KB of state + versions | ~0.00 | | native S3 locking — no DynamoDB table needed since TF 1.10 |
| **Total** | | | | |

Home region is `sa-east-1`, which runs roughly 30-50% above `us-east-1` on most line items. Deliberate: data residency in Brazil is the point, and the delta on a governance-only footprint is measured in single dollars.

## Keeping it cheap

- Budget with an actions-enabled alarm at a hard ceiling, created **before** the first apply.
- Config recorder scoped, not all-resources.
- Demo workload accounts torn down between sessions (`make destroy`).
- Region allow-list keeps stray resources from appearing where nobody looks at the bill.
