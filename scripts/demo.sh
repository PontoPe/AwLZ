#!/usr/bin/env bash
#
# Deterministic replay of the sanitized IAM simulation captured during C5.
# It performs no AWS call and accepts no external path or command input.
set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd -- "$HERE/.." && pwd)"
EVIDENCE="$REPO/docs/evidence/ci-readonly-simulation.json"

if [ ! -f "$EVIDENCE" ]; then
  printf 'demo evidence is not available\n' >&2
  exit 1
fi

if [ -t 1 ]; then
  B=$'\033[1m'
  G=$'\033[32m'
  R=$'\033[31m'
  D=$'\033[2m'
  Z=$'\033[0m'
else
  B=""
  G=""
  R=""
  D=""
  Z=""
fi

printf '%sAwLZ — least-privilege CI plan%s\n\n' "$B" "$Z"
printf '%s# Replaying sanitized evidence from AWS IAM policy simulation%s\n' "$D" "$Z"
printf '%s# No credential, account ID, ARN or live write is used by this demo.%s\n\n' "$D" "$Z"

python3 - "$EVIDENCE" <<'PY'
import json
import sys

path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8") as handle:
        data = json.load(handle)
except (OSError, UnicodeError, json.JSONDecodeError):
    print("evidence validation failed", file=sys.stderr)
    raise SystemExit(1)

expected = {
    "schema": "awlz-ci-readonly-simulation/v1",
    "evaluations": [
        {
            "action": "config:DescribeConfigurationRecorders",
            "decision": "allowed",
        },
        {
            "action": "config:PutConfigurationRecorder",
            "decision": "explicitDeny",
        },
    ],
}

if data != expected:
    print("evidence validation failed", file=sys.stderr)
    raise SystemExit(1)
PY

printf '%s$ evaluate config:DescribeConfigurationRecorders%s\n' "$B" "$Z"
printf '%sALLOWED%s  read-only configuration discovery\n\n' "$G" "$Z"

printf '%s$ evaluate config:PutConfigurationRecorder%s\n' "$B" "$Z"
printf '%sDENIED%s   write path blocked by the member role boundary\n\n' "$R" "$Z"

printf '%sResult: plan can refresh real state; it cannot reconfigure detection.%s\n' "$B" "$Z"
