#!/usr/bin/env bash
#
# Record an AwLZ terminal demo and promote it only after a text leak audit.
# Requires asciinema, agg, python3 and a preinstalled monospace font.
set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd -- "$HERE/.." && pwd)"
DEMO_SCRIPT="$HERE/demo.sh"
TITLE="${TITLE:-AwLZ guardrail denial}"
OUT_DIR="$REPO/docs/img"
NAME="awlz-ci-readonly"
COLS="${COLS:-88}"
ROWS="${ROWS:-18}"
FONT_FAMILY="${FONT_FAMILY:-DejaVu Sans Mono}"
FONT_SIZE="${FONT_SIZE:-15}"
THEME="${THEME:-asciinema}"
SPEED="${SPEED:-0.6}"
# The driver prints in one burst, so the only idle in the cast is the shell
# warm-up before it. At 5s that became a six-second blank opening frame — a
# third of the GIF showing nothing. Collapsing idle to 1s keeps the pacing in
# the render, where it belongs, rather than padding the recording.
RENDER_IDLE_LIMIT="${RENDER_IDLE_LIMIT:-1}"
LAST_FRAME_DURATION="${LAST_FRAME_DURATION:-6}"

# AWS-specific additions: organization IDs, SSO portal URLs, email addresses,
# webhook tokens, account IDs and ARNs must never reach the committed cast.
DENY_PATTERNS="${DENY_PATTERNS:-BEGIN( RSA| EC)? PRIVATE KEY|client-certificate-data|client-key-data|Bearer [A-Za-z0-9._-]{16,}|password[[:space:]=:]|passwd[[:space:]=:]|secret[_-]?(key|access)|aws_secret_access_key|AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|[^0-9][0-9]{12}[^0-9]|arn:aws[a-z-]*:|o-[a-z0-9]{10,32}|https://[A-Za-z0-9.-]+[.]awsapps[.]com|hooks[.]slack[.]com|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+[.][A-Za-z]{2,}|ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}}"
WARN_PATTERNS="${WARN_PATTERNS:-([0-9]{1,3}[.]){3}[0-9]{1,3}|kubeconfig|[A-Za-z0-9-]+[.](internal|local|lan)}"

say() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
die() { printf '\n\033[31m!! %s\033[0m\n' "$*" >&2; exit 1; }

for dependency in asciinema agg python3; do
  command -v "$dependency" >/dev/null || die "$dependency is not installed"
done
[ -x "$DEMO_SCRIPT" ] || die "$DEMO_SCRIPT is not executable"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
CAST="$WORK/$NAME.cast"
GIF="$WORK/$NAME.gif"

# A leak audit that never rejects anything is not a control. Prove the deny
# regex catches a known fake ARN before recording the real output.
printf '%s\n' 'arn:aws:iam::000000000000:role/deny-pattern-self-test' >"$WORK/audit-canary.txt"
if ! grep -qEi "$DENY_PATTERNS" "$WORK/audit-canary.txt"; then
  die "deny-pattern self-test failed"
fi
echo "deny-pattern self-test: PASS"

say "recording"
asciinema rec \
  --overwrite \
  --cols "$COLS" \
  --rows "$ROWS" \
  --title "$TITLE" \
  --command "$DEMO_SCRIPT" \
  "$CAST" </dev/null
[ -s "$CAST" ] || die "no cast produced"

say "leak audit"
echo "--- cast header env ---"
head -1 "$CAST" |
  python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin).get("env",{}),indent=1))'
if grep -nEi "$DENY_PATTERNS" "$CAST" >"$WORK/hits.txt" 2>/dev/null; then
  head -20 "$WORK/hits.txt"
  die "forbidden data found; nothing promoted to $OUT_DIR"
fi
echo "   no forbidden patterns"
if grep -oEi "$WARN_PATTERNS" "$CAST" 2>/dev/null | sort -u >"$WORK/warn.txt" &&
   [ -s "$WORK/warn.txt" ]; then
  echo "   review allowed-but-sensitive values:"
  sed 's/^/     /' "$WORK/warn.txt" | head -20
fi

say "rendering"
agg \
  --font-family "$FONT_FAMILY" \
  --font-size "$FONT_SIZE" \
  --theme "$THEME" \
  --speed "$SPEED" \
  --idle-time-limit "$RENDER_IDLE_LIMIT" \
  --last-frame-duration "$LAST_FRAME_DURATION" \
  "$CAST" "$GIF"
[ -s "$GIF" ] || die "no GIF produced"

say "inspecting render"
python3 - "$GIF" "$WORK/$NAME-frame.png" <<'PY'
import sys
from PIL import Image

image = Image.open(sys.argv[1])
durations = []
for index in range(image.n_frames):
    image.seek(index)
    durations.append(image.info.get("duration") or 0)
image.seek(min(image.n_frames - 1, image.n_frames // 2))
image.convert("RGB").save(sys.argv[2])
print(f"   size: {image.size[0]}x{image.size[1]}")
print(f"   frames: {image.n_frames}")
print(f"   duration: {sum(durations) / 1000:.1f}s")
PY

mkdir -p "$OUT_DIR"
cp "$GIF" "$OUT_DIR/$NAME.gif"
cp "$CAST" "$OUT_DIR/$NAME.cast"

say "done"
echo "   $OUT_DIR/$NAME.gif"
echo "   $OUT_DIR/$NAME.cast"
echo "Watch the GIF at full size before committing; the text audit cannot inspect pixels."
