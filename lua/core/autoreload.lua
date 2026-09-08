-- Behaviour tied to the AI terminal-column workflow: keep buffers in sync with
-- what the CLI agent writes to disk, and make terminals immediately typable on
-- focus. Both are autocmd-driven; no plugin involved.

local M = {}

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
-- Kept on M so the handle is never garbage-collected: an unreferenced active
-- luv timer can be reaped and silently stop the disk poll — the same guard as
-- core/ai-activity.lua's M._timer. (Nothing closes over this handle, so a
-- plain local would be collectible once this chunk returns.)
M._timer = assert(vim.uv.new_timer())
M._timer:start(
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
--
-- This module is the SINGLE authority on terminal focus mode. toggleterm would
-- otherwise restore the mode it snapshotted on WinLeave and undo this from a
-- vim.schedule; its spec sets `persist_mode = false` to stand down (see
-- lua/plugins/terminal/toggleterm.lua).

--- Should focusing `buf` drop straight into terminal-insert mode?
---
--- Only terminals whose job is still ALIVE qualify. A column whose CLI exited
--- keeps its buffer (AI panels set `close_on_exit = false`), and there normal
--- mode is what you want — the final output is there to be read and scrolled.
--- `b:terminal_job_id` SURVIVES the job's death, so its presence proves nothing;
--- jobwait with a 0 timeout is the liveness probe (-1 = still running).
--- Exposed as the test seam: headless Neovim cannot enter terminal mode
--- synchronously, so the predicate is what specs can actually assert.
--- @param buf integer|nil buffer to test; defaults to the current buffer
--- @return boolean
function M.should_insert(buf)
	buf = buf or vim.api.nvim_get_current_buf()
	if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= "terminal" then
		return false
	end
	local job = vim.b[buf].terminal_job_id
	if not job then
		return false
	end
	local ok, res = pcall(vim.fn.jobwait, { job }, 0)
	return ok and res[1] == -1
end

local term_insert_grp = vim.api.nvim_create_augroup("term_focus_startinsert", { clear = true })
vim.api.nvim_create_autocmd({ "WinEnter", "BufEnter" }, {
	group = term_insert_grp,
	pattern = "*",
	callback = function()
		if not M.should_insert() then
			return
		end
		-- Deferred, and re-checked. `startinsert` from an autocmd only takes
		-- effect once the autocmd finishes, so a focus change in between would
		-- land insert mode in whatever window won — and toggleterm shuffles
		-- windows on exactly this path (`restore_layout()` runs wincmd J/H/L on
		-- every open panel, and the ai_side handler restores the previously
		-- current window afterwards). Re-asserting that the same terminal window
		-- is still current turns that race into a no-op instead of stray insert
		-- mode in a code buffer.
		local win = vim.api.nvim_get_current_win()
		vim.schedule(function()
			if vim.api.nvim_get_current_win() == win and M.should_insert() then
				vim.cmd("startinsert")
			end
		end)
	end,
})

return M
