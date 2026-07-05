-- Global, plugin-agnostic keymaps: save/undo/redo with a notification, folds,
-- split resizing (also from terminal mode), and the buffer picker.

-- Save / undo / redo with a small notification cue.
vim.keymap.set("n", "<C-U>", function()
	vim.cmd("undo")
	vim.notify("↶ Undo", vim.log.levels.INFO, { timeout = 250 })
end, { desc = "Undo (with toast)" })

vim.keymap.set("n", "<C-R>", function()
	vim.cmd("redo")
	vim.notify("↷ Redo", vim.log.levels.INFO, { timeout = 250 })
end, { desc = "Redo (with toast)" })

vim.keymap.set("n", "<C-Y>", function()
	vim.cmd("write")
	vim.notify("✓ File saved", vim.log.levels.INFO, { timeout = 250 })
end, { desc = "Save file (with toast)" })

-- Folds.
vim.keymap.set("v", "<leader>zf", ":'<,'>fold<CR>", { desc = "Fold Selected Lines" })
vim.keymap.set("n", "<leader>za", "za", { desc = "Toggle Fold" })

-- ─── Split resize ───────────────────────────────────────────────────────────
-- One local helper per direction, mapped in BOTH normal and terminal mode
-- (a Lua callback runs in place, so you can widen/narrow the AI chat column
-- while you're typing in it). The steps are absolute: ±20 columns / ±5 rows.
-- (The old `:resize +20%` syntax LOOKED percentual, but Vim silently ignores
-- a trailing "%" on :resize — verified empirically: +20% resizes by exactly
-- 20 columns — so the "%" was dropped to stop implying a percentage.)
local function increase_width()
	vim.cmd("vertical resize +20")
end
local function decrease_width()
	vim.cmd("vertical resize -20")
end
local function increase_height()
	vim.cmd("resize +5")
end
local function decrease_height()
	vim.cmd("resize -5")
end

for _, mode in ipairs({ "n", "t" }) do
	vim.keymap.set(mode, "<C-,>", increase_width, { silent = true, desc = "Grow split width (+20 cols)" })
	vim.keymap.set(mode, "<C-.>", decrease_width, { silent = true, desc = "Shrink split width (-20 cols)" })
	vim.keymap.set(mode, "<C-;>", increase_height, { silent = true, desc = "Grow split height (+5 rows)" })
	vim.keymap.set(mode, "<C-'>", decrease_height, { silent = true, desc = "Shrink split height (-5 rows)" })
end

-- Fine-grained height step (+2 rows), normal mode only.
vim.keymap.set("n", "<C-Up>", "<Cmd>resize +2<CR>", { silent = true, desc = "Grow window height (+2)" })

-- ─── NvSinner command shortcuts — the <leader>x* namespace ──────────────────
-- Every NvSinner surface is reachable under <leader>x (visual <leader>x is
-- already the Ask-AI modal). Trouble owns <leader>xx/xX/xs/xl/xq in normal
-- mode, so these letters deliberately avoid those; that's also why symbols is
-- `xo` (outline) — trouble's `xs` was there first. Sync is capital S on
-- purpose: it rewrites lazy-lock.json, so it should not be a casual keystroke.
local nvsinner_maps = {
	{ "<leader>xm", "NvSinnerMenu", "NvSinner settings menu" },
	{ "<leader>xh", "NvSinnerHelp", "NvSinner command palette" },
	{ "<leader>xp", "NvSinnerPrompts", "Prompt library → clipboard" },
	{ "<leader>xo", "NvSinnerSymbols", "Document symbols modal" },
	{ "<leader>xu", "NvSinnerUpdate", "NvSinner update (pinned restore)" },
	{ "<leader>xS", "NvSinnerSync", "NvSinner sync — floats plugins, rewrites lockfile" },
	{ "<leader>xc", "checkhealth nvsinner", "NvSinner health check" },
}
for _, m in ipairs(nvsinner_maps) do
	vim.keymap.set("n", m[1], "<Cmd>" .. m[2] .. "<CR>", { silent = true, desc = m[3] })
end

-- Document-symbols modal (:NvSinnerSymbols) — pick a symbol, jump to it.
vim.keymap.set("n", "<leader>cs", function()
	require("core.symbols").show_symbols()
end, { silent = true, desc = "Document symbols modal" })

-- Prompt library modal (:NvSinnerPrompts) — pick a prompt, copy to clipboard.
vim.keymap.set("n", "<leader>p", "<Cmd>NvSinnerPrompts<CR>", { silent = true, desc = "Prompt library → clipboard" })

-- Find buffers (Telescope; the plugin lazy-loads on this command).
vim.keymap.set("n", "<leader>fb", "<Cmd>Telescope buffers<CR>", { silent = true, desc = "Find buffers (Telescope)" })
