#!/usr/bin/env bash
# startup-time.sh — measure cold-start time with nvim --startuptime and print
# the total plus the 10 slowest entries. Read-only (writes only a temp file).
# Run from the repo root.
set -euo pipefail
if [[ "${1:-}" == "--help" ]]; then
  echo "usage: scripts/startup-time.sh   (from the repo root; no arguments)"
  exit 0
fi
log=$(mktemp)
trap 'rm -f "$log"' EXIT
nvim --headless --startuptime "$log" -c "qa!" >/dev/null 2>&1
total=$(grep -E '^[0-9]' "$log" | awk '{ if ($1+0 > t) t = $1+0 } END { print t }')
echo "total startup: ${total} ms"
echo "10 slowest entries (self+sourced ms | event):"
# startuptime lines: "clock  self+sourced  self:  event" — sort by column 2.
grep -E '^[0-9]' "$log" | sort -t' ' -k2 -rn | head -10
