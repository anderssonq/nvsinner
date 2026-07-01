-- Minimal init for the test harness (plenary busted). Used by every spawned
-- test child via `PlenaryBustedDirectory ... { minimal_init = ... }`.
-- It puts THIS config and plenary on the runtimepath so specs can
-- `require("core.*")` and `dofile` the plugin specs, with no plugin side effects.

-- Repo root = parent of this tests/ directory (derived from the script path so it
-- works regardless of the cwd the runner is invoked from).
local here = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(here, ":p:h:h")

local data = vim.fn.stdpath("data")
vim.opt.runtimepath:prepend(root)
vim.opt.runtimepath:prepend(data .. "/lazy/plenary.nvim")

-- Quiet, deterministic environment.
vim.opt.swapfile = false
vim.opt.shadafile = "NONE"
vim.opt.more = false

-- Load plenary's :PlenaryBusted* commands.
vim.cmd("runtime plugin/plenary.vim")
