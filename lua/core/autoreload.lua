-- Behaviour tied to the AI terminal-column workflow: keep buffers in sync with
-- what the CLI agent writes to disk, and make terminals immediately typable on
-- focus. Both are autocmd-driven; no plugin involved.

-- ─── Auto-reload files changed on disk ──────────────────────────────────────
-- When the AI CLI (claude, etc.) in the terminal column edits a file, refresh
-- the buffer in place instead of showing the W11/W12 "file changed" prompt.
-- NOTE: on conflict the on-disk version (what the AI just wrote) wins and any
-- unsaved in-Vim edits to that buffer are discarded. That matches this
-- viewer-style workflow where the editing happens in the AI pane.
vim.opt.autoread = true

local autoread_grp = vim.api.nvim_create_augroup("auto_reload_on_disk_change", { clear = true })

-- Toast naming the file an external process (the AI CLI) just wrote, plus the
-- silent-reload plumbing. With 'autoread' on and the buffer UNMODIFIED, Neovim
-- reloads silently and fires FileChangedShellPost (not FileChangedShell). Hook
-- both: FileChangedShell handles conflicts (forcing reload), FileChangedShellPost
-- handles the common silent reload. 250ms dedup prevents double-toasting the same write.
local last_notify = { name = nil, t = 0 }
local function notify_ai_edit(file)
	local name = vim.fn.fnamemodify(file or "", ":t")
	if name == "" then
		return
	end
	local now = (vim.uv or vim.loop).now()
	if last_notify.name == name and (now - last_notify.t) < 250 then
		return
	end
	last_notify.name, last_notify.t = name, now
	vim.schedule(function()
		vim.notify("edited " .. name, vim.log.levels.INFO, { title = "🤖 AI", timeout = 250 })
	end)
end

vim.api.nvim_create_autocmd("FileChangedShell", {
	group = autoread_grp,
	pattern = "*",
	callback = function(args)
		vim.v.fcs_choice = "reload"
		notify_ai_edit(args.file)
	end,
})
vim.api.nvim_create_autocmd("FileChangedShellPost", {
	group = autoread_grp,
	pattern = "*",
	callback = function(args)
		notify_ai_edit(args.file)
	end,
})

-- Re-check timestamps promptly: on focus, when entering a window/buffer, and
-- when leaving the AI terminal — so the code pane reloads the moment you look
-- back at it.
vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "WinEnter", "TermLeave", "CursorHold", "CursorHoldI" }, {
	group = autoread_grp,
	pattern = "*",
	command = "checktime",
})

-- Also poll on a light timer so the code pane refreshes even while you stay
-- focused in the AI terminal (Vim has no CursorHold in terminal mode). The
-- check is cheap; it only reloads buffers whose file actually changed on disk.
local autoread_timer = vim.uv.new_timer()
autoread_timer:start(
	1000,
	1000,
	vim.schedule_wrap(function()
		-- Don't interrupt command-line entry.
		if vim.fn.mode() ~= "c" then
			vim.cmd("silent! checktime")
		end
	end)
)

-- ─── Click / focus a terminal -> start typing immediately ──────────────────
-- With `mouse=a` (set in options.lua) a click already FOCUSES the window under
-- the cursor. But for a terminal that drops you in terminal-normal mode, so
-- you'd still have to press `i` before you can type. Auto-enter insert mode
-- whenever a terminal window gains focus (by mouse OR by <C-h/j/k/l>
-- navigation), so a click on any terminal column — the horizontal <leader>t
-- terminals or the vertical AI panels — is immediately typable. Code/file
-- windows are left alone: clicking them just focuses in normal mode, as
-- expected. To make this mouse-only (and keep keyboard nav landing in
-- terminal-normal mode for scrolling), map <LeftRelease> with the same buftype
-- check instead.
local term_insert_grp = vim.api.nvim_create_augroup("term_focus_startinsert", { clear = true })
vim.api.nvim_create_autocmd({ "WinEnter", "BufEnter" }, {
	group = term_insert_grp,
	pattern = "*",
	callback = function()
		if vim.bo.buftype == "terminal" then
			vim.cmd("startinsert")
		end
	end,
})
