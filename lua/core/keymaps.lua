-- Global, plugin-agnostic keymaps: save/undo/redo with a notification, folds,
-- split resizing (also from terminal mode), and the buffer picker.

-- Save / undo / redo with a small notification cue.
vim.keymap.set("n", "<C-U>", function()
	vim.cmd("undo")
	vim.notify("↶ Undo", vim.log.levels.INFO, { timeout = 250 })
end)

vim.keymap.set("n", "<C-R>", function()
	vim.cmd("redo")
	vim.notify("↷ Redo", vim.log.levels.INFO, { timeout = 250 })
end)

vim.keymap.set("n", "<C-Y>", function()
	vim.cmd("write")
	vim.notify("✓ File saved", vim.log.levels.INFO, { timeout = 250 })
end)

-- Folds.
vim.keymap.set("v", "<leader>zf", ":'<,'>fold<CR>", { desc = "Fold Selected Lines" })
vim.keymap.set("n", "<leader>za", "za", { desc = "Toggle Fold" })
vim.api.nvim_set_keymap("n", "<C-Up>", ":resize +2<CR>", { noremap = true, silent = true })

-- ─── Split resize helpers ───────────────────────────────────────────────────
-- Global functions so the `:lua ...()` keymaps below can call them by name.
-- Function to increase the width of the current split by 20%
function IncreaseWidth()
	vim.cmd("vertical resize +20%")
end

-- Function to decrease the width of the current split by 20%
function DecreaseWidth()
	vim.cmd("vertical resize -20%")
end

function IncreaseHeight()
	vim.cmd("horizontal resize +5%")
end

function DecreaseHeight()
	vim.cmd("horizontal resize -5%")
end

-- Width ±20% (use for the vertical AI panel) / height ±5% (horizontal terminal).
vim.api.nvim_set_keymap("n", "<C-,>", ":lua IncreaseWidth()<CR>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "<C-.>", ":lua DecreaseWidth()<CR>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "<C-;>", ":lua IncreaseHeight()<CR>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "<C-'>", ":lua DecreaseHeight()<CR>", { noremap = true, silent = true })

-- Same split-resize keys, usable from INSIDE a terminal (e.g. the AI chat
-- column) without leaving terminal mode. <Cmd> runs the function in place, so
-- the resize applies to the focused window — i.e. you can widen/narrow the chat
-- while you're typing in it.
vim.keymap.set("t", "<C-,>", "<Cmd>lua IncreaseWidth()<CR>", { noremap = true, silent = true })
vim.keymap.set("t", "<C-.>", "<Cmd>lua DecreaseWidth()<CR>", { noremap = true, silent = true })
vim.keymap.set("t", "<C-;>", "<Cmd>lua IncreaseHeight()<CR>", { noremap = true, silent = true })
vim.keymap.set("t", "<C-'>", "<Cmd>lua DecreaseHeight()<CR>", { noremap = true, silent = true })

-- Prompt library modal (:NvSinnerPrompts) — pick a prompt, copy to clipboard.
vim.keymap.set("n", "<leader>p", "<Cmd>NvSinnerPrompts<CR>", { silent = true, desc = "Prompt library → clipboard" })

-- Find buffers (Telescope; the plugin lazy-loads on this command).
vim.api.nvim_set_keymap("n", "<leader>fb", ":Telescope buffers<CR>", { noremap = true, silent = true })
