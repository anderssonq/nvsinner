#!/usr/bin/env bash
# keymap-audit.sh — verify the load-bearing NvSinner keymaps exist by probing a
# headless instance of the real config. Prints one line per keymap; exits 1 if
# any load-bearing map is missing. Read-only. Run from the repo root.
set -euo pipefail
if [[ "${1:-}" == "--help" ]]; then
  echo "usage: scripts/keymap-audit.sh   (from the repo root; no arguments)"
  exit 0
fi
out=$(nvim --headless -c "lua vim.defer_fn(function()
  local checks = {
    { 'n', '<leader>j',  'AI session 1' },
    { 'n', '<leader>t',  'horizontal terminal 1' },
    { 'n', '<leader>fb', 'telescope buffers' },
    { 'n', '<C-,>',      'width +20% (normal)' },
    { 't', '<C-,>',      'width +20% (terminal)' },
    { 't', '<C-;>',      'height +5% (terminal)' },
    { 'n', '<C-Y>',      'save with toast' },
    { 't', '<Esc>',      'leave terminal mode' },
  }
  local missing = 0
  -- io.stdout:write, not print: headless print() runs lines together.
  for _, c in ipairs(checks) do
    local mapped = vim.fn.maparg(c[2], c[1]) ~= ''
    io.stdout:write(string.format('%s %-12s [%s] %s\n', mapped and 'OK  ' or 'MISS', c[2], c[1], c[3]))
    if not mapped then missing = missing + 1 end
  end
  io.stdout:write(missing == 0 and 'ALL KEYMAPS PRESENT\n' or (missing .. ' KEYMAPS MISSING\n'))
  vim.cmd('qa!')
end, 400)" 2>&1)
echo "$out"
[[ "$out" == *"ALL KEYMAPS PRESENT"* ]]
