#!/usr/bin/env bash
# palette-audit.sh — find hex colors in lua/ that are NOT part of the carbon
# palette. Prints violations; exits 1 if any are found. Read-only.
# Run from the repo root. Works on bash 3.2 (macOS default).
#
# The whitelist is DERIVED from lua/core/carbon.lua at run time — every theme,
# accent pack, folder pack and slot — so it cannot drift the way a hand-kept
# list did (it froze on the kanagawa/glass palette and flagged all of carbon).
# carbon.lua itself is excluded from the scan: it is the source of truth.
set -euo pipefail

if [ "${1:-}" = "--help" ]; then
  echo "usage: palette-audit.sh   (from the repo root; no arguments)"
  exit 0
fi

PALETTE="lua/core/carbon.lua"
[ -f "$PALETTE" ] || { echo "palette-audit: $PALETTE not found — run from the repo root" >&2; exit 2; }

# Sanctioned literals that are deliberately NOT palette roles.
# Keep this list short, and give every entry a reason.
# lua/plugins/ui/dashboard.lua — the ASCII logo's monochrome fade:
allow="b6b6b6 9c9c9c 838383 6a6a6a"

roles=$(grep -oiE '#[0-9a-f]{6}' "$PALETTE" | tr -d '#' | tr 'A-F' 'a-f' | sort -u)
role_count=$(printf '%s\n' "$roles" | grep -c . || true)
if [ "$role_count" -eq 0 ]; then
  echo "palette-audit: no hexes found in $PALETTE — did its format change?" >&2
  exit 2
fi

pattern=$(printf '%s\n%s\n' "$roles" "$(printf '%s\n' $allow)" | grep . | sort -u | tr '\n' '|' | sed 's/|$//')

# Strip `-- ...` comments before matching: a hex NAMED in a comment (e.g. one
# recording a literal that was removed) is prose, not a color the editor uses.
# sed keeps the line count, so grep -n line numbers stay accurate.
violations=""
for f in $(find lua -name '*.lua' | sort); do
  [ "$f" = "$PALETTE" ] && continue
  hits=$(sed 's/--.*$//' "$f" | grep -niE '#[0-9a-f]{6}' -o \
    | grep -viE ":#(${pattern})$" || true)
  [ -n "$hits" ] && violations="${violations}$(printf '%s\n' "$hits" | sed "s|^|${f}:|")
"
done
violations=$(printf '%s' "$violations" | grep . || true)

if [ -n "$violations" ]; then
  echo "OFF-PALETTE HEXES FOUND (not a role in $PALETTE, not in the allow list):"
  echo "$violations"
  echo
  echo "Fix: use a role from require('core.carbon').colors(), or add the literal"
  echo "to the allow list above WITH a reason."
  exit 1
fi

echo "palette clean: every hex in lua/ is a carbon role or a sanctioned literal"
echo "  ($role_count roles derived from $PALETTE)"
