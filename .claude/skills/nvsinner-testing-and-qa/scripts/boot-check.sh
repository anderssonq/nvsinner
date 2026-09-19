#!/usr/bin/env bash
# boot-check.sh — boot the NvSinner config headless and surface any startup
# messages. Exits 0 with "boot clean" when the message log is empty, exits 1
# and prints the messages otherwise. Read-only. Run from the repo root.
set -euo pipefail
if [[ "${1:-}" == "--help" ]]; then
  echo "usage: scripts/boot-check.sh   (from the repo root; no arguments)"
  exit 0
fi
out=$(nvim --headless -c "lua vim.defer_fn(function() local m=vim.fn.execute('messages'); if m:match('%S') then print('MESSAGES:'..m) else print('boot clean, no messages') end; vim.cmd('qa!') end, 400)" 2>&1)
echo "$out"
[[ "$out" == *"boot clean"* ]]
