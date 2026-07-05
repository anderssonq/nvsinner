-- ─── Sessions (native) ──────────────────────────────────────────────────────
-- Replaces persistence.nvim with a thin `:mksession` wrapper: one session
-- file per cwd (percent-encoded path) under stdpath("state")/sessions/,
-- autosaved on VimLeavePre once a real file has been opened this run.
-- `stop()` pauses only the autosave — explicit saves/loads still work.
--
-- Same surface as before: <leader>Sc restores the cwd session, <leader>Sl the
-- most recent session anywhere, <leader>SQ quits without saving; plus
-- :NvSinnerSession* commands so the actions show up in :NvSinnerHelp.
-- (stdpath("state") is already NVIM_APPNAME-scoped, so nvsinner sessions
-- never collide with another config's.)

local M = {}

M.dir = vim.fn.stdpath("state") .. "/sessions/"

-- What a session captures — persistence.nvim's `options` list, verbatim.
vim.o.sessionoptions = "buffers,curdir,tabpages,winsize"

local started = false -- a real file was opened this run (autosave gate)
local stopped = false -- <leader>SQ / :NvSinnerSessionStop pause the autosave

local function session_file()
	return M.dir .. vim.fn.getcwd():gsub("[/\\:]", "%%") .. ".vim"
end

-- Most recently written session file, for "restore last session anywhere".
function M.last()
	local newest, newest_mtime
	for name, kind in vim.fs.dir(M.dir) do
		if kind == "file" and name:sub(-4) == ".vim" then
			local stat = vim.uv.fs_stat(M.dir .. name)
			if stat and (not newest_mtime or stat.mtime.sec > newest_mtime) then
				newest, newest_mtime = M.dir .. name, stat.mtime.sec
			end
		end
	end
	return newest
end

function M.save()
	vim.fn.mkdir(M.dir, "p")
	vim.cmd("mksession! " .. vim.fn.fnameescape(session_file()))
end

-- Load the cwd session, or with {last=true} the most recent one anywhere.
-- Returns true when a session was sourced.
function M.load(opts)
	local file = (opts and opts.last) and M.last() or session_file()
	if not (file and vim.uv.fs_stat(file)) then
		return false
	end
	vim.cmd("silent! source " .. vim.fn.fnameescape(file))
	return true
end

function M.stop()
	stopped = true
end

local grp = vim.api.nvim_create_augroup("nv_sessions", { clear = true })

-- persistence.nvim only armed itself once an actual file was opened; keep
-- that gate so quitting straight from the dashboard doesn't save an empty
-- session over a real one.
vim.api.nvim_create_autocmd("BufReadPre", {
	group = grp,
	callback = function(args)
		if vim.bo[args.buf].buftype == "" then
			started = true
		end
	end,
})

vim.api.nvim_create_autocmd("VimLeavePre", {
	group = grp,
	callback = function()
		if started and not stopped then
			M.save()
		end
	end,
})

local function toast(msg)
	vim.notify(msg, vim.log.levels.INFO, { timeout = 250 })
end

local function restore_cwd()
	toast(M.load() and "↺ Session restored" or "No session for this directory yet")
end

local function restore_last()
	toast(M.load({ last = true }) and "↺ Last session restored" or "No sessions saved yet")
end

local function quit_no_save()
	M.stop()
	toast("■ Session paused")
end

vim.api.nvim_create_user_command("NvSinnerSessionLoad", restore_cwd, {
	desc = "Restore the session for the current directory",
})
vim.api.nvim_create_user_command("NvSinnerSessionLast", restore_last, {
	desc = "Restore the most recent session",
})
vim.api.nvim_create_user_command("NvSinnerSessionStop", quit_no_save, {
	desc = "Skip saving the session when quitting",
})

vim.keymap.set("n", "<leader>Sc", restore_cwd, { desc = "Restore last session for current dir" })
vim.keymap.set("n", "<leader>Sl", restore_last, { desc = "Restore last session" })
vim.keymap.set("n", "<leader>SQ", quit_no_save, { desc = "Quit without saving session" })

-- Test seams: state reset + a sandbox session dir per spec.
function M._reset(opts)
	started, stopped = false, false
	if opts and opts.dir then
		M.dir = opts.dir:sub(-1) == "/" and opts.dir or opts.dir .. "/"
	end
end

function M._started()
	return started, stopped
end

return M
