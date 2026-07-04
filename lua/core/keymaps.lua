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

-- Prompt library modal (:NvSinnerPrompts) — pick a prompt, copy to clipboard.
vim.keymap.set("n", "<leader>p", "<Cmd>NvSinnerPrompts<CR>", { silent = true, desc = "Prompt library → clipboard" })

-- Find buffers (Telescope; the plugin lazy-loads on this command).
vim.keymap.set("n", "<leader>fb", "<Cmd>Telescope buffers<CR>", { silent = true, desc = "Find buffers (Telescope)" })
