-- ─── Inline git blame (native) ──────────────────────────────────────────────
-- Replaces git-blame.nvim: an always-on virtual-text blame for the cursor
-- line — " <summary> • <date> • <author> • <sha>" rendered at end-of-line in
-- the comment tone. The cursor settles (debounced vim.uv timer, same anchor
-- discipline as ai-activity), then one async `git blame -L <line>,<line>
-- --porcelain` runs via vim.system; the result is dropped if the cursor moved
-- while it was in flight (generation counter — async results must never paint
-- a stale line).
--
-- The buffer's CURRENT content is blamed (`--contents -` with the buffer lines
-- on stdin), so an unsaved edit shifts blame like git-blame.nvim did instead
-- of blaming the wrong on-disk line. Untracked files are cached as dead per
-- buffer (cleared on save) so a scratch note doesn't spawn a git process on
-- every cursor move.

local M = {}

local ns = vim.api.nvim_create_namespace("nvsinner_git_blame")
M._ns = ns -- test seam: specs read the extmark in this namespace

M.DELAY = 350 -- ms after the cursor settles before blaming
M.DATE_FORMAT = "%m-%d-%Y %H:%M:%S" -- same format the plugin used

local enabled = true
local gen = 0 -- bumped on every movement; in-flight results check it
local dead = {} -- dead[buf] = true when git said "untracked / not a repo"

-- Comment-tone virtual text: muted and italic, like the blame it replaces.
-- Role only (base03 = comments), re-applied on ColorScheme.
local function apply_hl()
	local c = require("core.carbon").colors()
	vim.api.nvim_set_hl(0, "NvGitBlame", { fg = c.base03, italic = true })
end
apply_hl()
vim.api.nvim_create_autocmd("ColorScheme", { pattern = "*", callback = apply_hl })

local function eligible(buf)
	return vim.api.nvim_buf_is_valid(buf)
		and vim.bo[buf].buftype == ""
		and vim.api.nvim_buf_get_name(buf) ~= ""
		and not dead[buf]
end

function M.clear(buf)
	if vim.api.nvim_buf_is_valid(buf) then
		vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
	end
end

-- Parse `git blame --porcelain` for a single line into a display string.
-- Returns nil for uncommitted lines (all-zero sha) — no annotation is better
-- than a fake one.
function M._format(stdout)
	local sha = stdout:match("^(%x+) ")
	if not sha or sha:match("^0+$") then
		return nil
	end
	local author = stdout:match("\nauthor ([^\n]+)")
	local time = tonumber(stdout:match("\nauthor%-time (%d+)"))
	local summary = stdout:match("\nsummary ([^\n]+)")
	if not (author and time and summary) then
		return nil
	end
	local date = os.date(M.DATE_FORMAT, time)
	return string.format(" %s • %s • %s • <%s>", summary, date, author, sha:sub(1, 7))
end

local function annotate(buf, row, text)
	if not text or not vim.api.nvim_buf_is_valid(buf) or row >= vim.api.nvim_buf_line_count(buf) then
		return
	end
	vim.api.nvim_buf_set_extmark(buf, ns, row, 0, {
		virt_text = { { text, "NvGitBlame" } },
		virt_text_pos = "eol",
		hl_mode = "combine",
	})
end

-- Blame the cursor line of `buf` right now (the debounce is the caller's
-- job — tests call this directly since CursorMoved doesn't fire headless).
function M.refresh(buf)
	buf = buf or vim.api.nvim_get_current_buf()
	if not (enabled and eligible(buf)) then
		return
	end
	local win = vim.api.nvim_get_current_win()
	if vim.api.nvim_win_get_buf(win) ~= buf then
		return
	end
	local row = vim.api.nvim_win_get_cursor(win)[1]
	local path = vim.api.nvim_buf_get_name(buf)
	local dir = vim.fs.dirname(path)
	gen = gen + 1
	local this_gen = gen
	-- Blame the buffer content, not the file on disk: unsaved edits above the
	-- cursor would otherwise shift every annotation onto the wrong commit.
	local contents = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n") .. "\n"
	vim.system({
		"git",
		"-C",
		dir,
		"blame",
		"-L",
		row .. "," .. row,
		"--porcelain",
		"--contents",
		"-",
		"--",
		path,
	}, { stdin = contents, text = true }, function(out)
		vim.schedule(function()
			if this_gen ~= gen or not vim.api.nvim_buf_is_valid(buf) then
				return
			end
			if out.code ~= 0 then
				-- Untracked file or not a repo: stop asking until the next save.
				dead[buf] = true
				return
			end
			M.clear(buf)
			annotate(buf, row - 1, M._format(out.stdout or ""))
		end)
	end)
end

-- Debounce: movement wipes the annotation immediately (a stale blame under a
-- new cursor line reads as wrong data) and re-arms the timer.
M._timer = nil -- anchored on the module table so luv can't GC a live timer
local function schedule(buf)
	gen = gen + 1 -- invalidate any in-flight result
	M.clear(buf)
	if not (enabled and eligible(buf)) then
		return
	end
	if M._timer then
		M._timer:stop()
	else
		M._timer = vim.uv.new_timer()
	end
	M._timer:start(
		M.DELAY,
		0,
		vim.schedule_wrap(function()
			M.refresh(buf)
		end)
	)
end

function M.toggle()
	enabled = not enabled
	if not enabled then
		for _, buf in ipairs(vim.api.nvim_list_bufs()) do
			M.clear(buf)
		end
	else
		schedule(vim.api.nvim_get_current_buf())
	end
	vim.notify("Inline blame " .. (enabled and "on" or "off"), vim.log.levels.INFO, { timeout = 250 })
end

function M.enabled()
	return enabled
end

local grp = vim.api.nvim_create_augroup("nv_git_blame", { clear = true })

vim.api.nvim_create_autocmd({ "CursorMoved", "BufEnter", "InsertLeave" }, {
	group = grp,
	callback = function(args)
		schedule(args.buf)
	end,
})

-- While typing, only clear — re-blaming every keystroke is churn.
vim.api.nvim_create_autocmd({ "CursorMovedI", "InsertEnter" }, {
	group = grp,
	callback = function(args)
		gen = gen + 1
		M.clear(args.buf)
	end,
})

-- A save can turn an untracked file into a tracked one (git add + write from
-- the AI column, `:w` after `git add -N`, …): forget the dead verdict.
vim.api.nvim_create_autocmd("BufWritePost", {
	group = grp,
	callback = function(args)
		dead[args.buf] = nil
		schedule(args.buf)
	end,
})

vim.api.nvim_create_autocmd("BufWipeout", {
	group = grp,
	callback = function(args)
		dead[args.buf] = nil
	end,
})

vim.api.nvim_create_user_command("NvSinnerBlameToggle", M.toggle, {
	desc = "Toggle the inline git blame annotation",
})

-- Test seam: drop all state between specs.
function M._reset()
	gen = gen + 1
	dead = {}
	enabled = true
	if M._timer then
		M._timer:stop()
	end
end

return M
