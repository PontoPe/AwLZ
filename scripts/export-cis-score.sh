#!/usr/bin/env bash
#
# Export the CIS v3.0.0 score per account from the delegated Security Hub
# administrator, sanitized: account aliases and counts only, never IDs.
#
# The score follows the AWS definition — Passed / (Passed + Failed + Unknown).
# "No data" stays out of the denominator, suppressed findings are excluded, and
# a control with any FAILED finding counts as failed, because a control is only
# as good as its worst resource.
#
# Requires `aws` and `jq`, and an SSO session for the management profile.
set -euo pipefail

PROFILE="${PROFILE:-mgmt}"
REGION="${REGION:-sa-east-1}"
STANDARD="${STANDARD:-standards/cis-aws-foundations-benchmark/v/3.0.0}"
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
OUT="${OUT:-$HERE/../docs/evidence/cis-score.txt}"

die() { printf '!! %s\n' "$*" >&2; exit 1; }
for dependency in aws jq; do
  command -v "$dependency" >/dev/null || die "$dependency is not installed"
done

accounts="$(aws organizations list-accounts --profile "$PROFILE" --output json)"
security_id="$(echo "$accounts" | jq -r '.Accounts[] | select(.Name | test("security")) | .Id')"
[ -n "$security_id" ] || die "no account whose name contains 'security'"

# The delegated administrator holds the aggregated findings. Assume into it
# rather than widening the management profile.
session="$(aws sts assume-role \
  --profile "$PROFILE" \
  --role-arn "arn:aws:iam::${security_id}:role/OrganizationAccountAccessRole" \
  --role-session-name awlz-cis-score \
  --output json)"
export AWS_ACCESS_KEY_ID="$(echo "$session" | jq -r .Credentials.AccessKeyId)"
export AWS_SECRET_ACCESS_KEY="$(echo "$session" | jq -r .Credentials.SecretAccessKey)"
export AWS_SESSION_TOKEN="$(echo "$session" | jq -r .Credentials.SessionToken)"
export AWS_DEFAULT_REGION="$REGION"

filters="$(jq -c -n --arg s "$STANDARD" '{
  ComplianceAssociatedStandardsId: [{Value: $s, Comparison: "PREFIX"}],
  RecordState:                     [{Value: "ACTIVE", Comparison: "EQUALS"}],
  WorkflowStatus:                  [{Value: "SUPPRESSED", Comparison: "NOT_EQUALS"}]
}')"

findings='[]'
token=''
while :; do
  if [ -z "$token" ]; then
    page="$(aws securityhub get-findings --filters "$filters" --max-results 100 --output json)"
  else
    page="$(aws securityhub get-findings --filters "$filters" --max-results 100 --next-token "$token" --output json)"
  fi
  findings="$(jq -c -n \
    --argjson accumulated "$findings" \
    --argjson page "$(echo "$page" | jq -c '[.Findings[] | {account: .AwsAccountId, control: (.Compliance.SecurityControlId // "unknown"), status: .Compliance.Status}]')" \
    '$accumulated + $page')"
  token="$(echo "$page" | jq -r '.NextToken // empty')"
  [ -n "$token" ] || break
done

# The management account is named after a person. Publish a role label instead;
# member accounts already carry neutral project aliases.
management_id="$(aws organizations describe-organization --profile "$PROFILE" \
  --query 'Organization.MasterAccountId' --output text)"
alias_map="$(echo "$accounts" | jq -c --arg mgmt "$management_id" \
  '[.Accounts[] | {id: .Id, name: (if .Id == $mgmt then "management" else .Name end)}]')"

{
  printf 'CIS v3.0.0 score by account\n'
  printf 'Standard:  %s\n' "$STANDARD"
  printf 'Region:    %s\n' "$REGION"
  printf 'Timestamp: %s\n\n' "$(date -Iseconds)"
  echo "$findings" | jq -r --argjson aliases "$alias_map" '
    group_by(.account)[]
    | (.[0].account) as $id
    | ($aliases[] | select(.id == $id) | .name) as $name
    | (group_by(.control) | map({
        control: .[0].control,
        state: (map(.status)
          | if   any(. == "FAILED")                            then "FAILED"
            elif any(. == "WARNING" or . == "NOT_AVAILABLE")   then "UNKNOWN"
            elif any(. == "PASSED")                            then "PASSED"
            else "NODATA" end)
      })) as $controls
    | ([$controls[] | select(.state == "PASSED")] | length) as $passed
    | ([$controls[] | select(.state != "NODATA")] | length) as $denominator
    | "\($name // "unmapped"): passed=\($passed) failed=\([$controls[]|select(.state=="FAILED")]|length) unknown=\([$controls[]|select(.state=="UNKNOWN")]|length) denominator=\($denominator) score=\(if $denominator > 0 then (($passed * 1000 / $denominator | floor) / 10) else 0 end)%"
  ' | sort
} | tee "$OUT"

printf '\nWritten to %s\n' "$OUT"
