#!/usr/bin/env bash
# palette-audit.sh — find hex colors in lua/ that are NOT in the approved
# NvSinner glass palette (one accent doctrine). Prints violations; exits 1 if
# any are found. Read-only. Run from the repo root.
#
# The whitelist mirrors .claude/skills/nvsinner-config-catalog (§3): the
# canonical palette plus the monochrome-family secondary shades used by
# dashboard/incline/illuminate/barbacue/identmini/noice. The lone COLOR accent
# is #c4746e (kanagawa dragonRed). Update both places together.
set -euo pipefail
if [[ "${1:-}" == "--help" ]]; then
  echo "usage: scripts/palette-audit.sh   (from the repo root; no arguments)"
  exit 0
fi
whitelist=(
  # canonical
  0a0a0f 111118 333345 c5c9d5 7a7f8d c4746e 2a2a38 5b5b70 80949e 16161d 15151c
  # monochrome-family secondary shades (see config-catalog §3)
  e8e8ee 9aa0b4 737a8e 54546d 3c3c4e 20202c 1c1c26 121219 1b1b24 211b22 676767
)
pattern=$(IFS='|'; echo "${whitelist[*]}")
violations=$(grep -rniE '#[0-9a-f]{6}' lua/ --include='*.lua' -o \
  | grep -viE "#(${pattern})\$" || true)
if [[ -n "$violations" ]]; then
  echo "OFF-PALETTE HEXES FOUND:"
  echo "$violations"
  exit 1
fi
echo "palette clean: every hex in lua/ is whitelisted"
