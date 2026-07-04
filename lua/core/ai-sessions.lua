-- ─── AI session registry + send-to-AI bridge ───────────────────────────────
-- The single place that knows which AI columns exist. toggleterm.lua PUSHES
-- sessions in here on first open (plugin→core dependency — core never requires
-- a plugin), so the bridge keymaps, the lualine cockpit badge, and the tests
-- can all reach the sessions without loading toggleterm.
--
-- Send semantics (probed 2026-07 — see the plan's Phase 0):
--   * Multi-line payloads are wrapped in bracketed paste (\27[200~ … \27[201~)
--     so a TUI CLI (claude, …) receives them as ONE editable block instead of
--     submitting each line.
--   * We NEVER append "\r": the text lands in the CLI's input for the user to
--     review and submit. No auto-run.
--
-- Targeting: the "current" AI session is (1) the terminal you are inside of,
-- else (2) the most recently used session whose column is open, else (3) the
-- most recently used session whose job is still alive (hidden column), else
-- none — in which case sending opens session 1 via the injected opener and
-- asks you to resend once the CLI is up (no queued auto-flush: CLI startup
-- timing makes a deferred flush flaky).

local M = {}

-- registry[n] = { n = n, term = <toggleterm Terminal>, last_used = <stamp> }
-- bufnr/job_id are read LIVE from the Terminal object so hidden/reopened
-- panels stay correct. last_used is a monotonic counter, not uv.now(): two
-- touches inside the same millisecond would otherwise tie and make the MRU
-- order depend on pairs() iteration.
local registry = {}
local opener -- injected by toggleterm: function(n) → toggle/open session n
local mru_clock = 0
local function stamp()
	mru_clock = mru_clock + 1
	return mru_clock
end

function M.set_opener(fn)
	opener = fn
end

function M.register(n, term)
	registry[n] = { n = n, term = term, last_used = stamp() }
end

function M.unregister(n)
	registry[n] = nil
end

-- Bump a session's MRU stamp (called from toggleterm's on_panel_open and the
-- TermEnter autocmd below).
function M.touch(n)
	local e = registry[n]
	if e then
		e.last_used = stamp()
	end
end

-- A session column counts as open when its Terminal reports so; fakes in the
-- test suite provide their own is_open, real Terminals ship one.
local function is_open(term)
	if type(term.is_open) == "function" then
		local ok, open = pcall(term.is_open, term)
		return ok and open or false
	end
	return term.window ~= nil and vim.api.nvim_win_is_valid(term.window)
end

local function job_alive(job_id)
	if not job_id then
		return false
	end
	local ok, res = pcall(vim.fn.jobwait, { job_id }, 0)
	return ok and res[1] == -1
end

-- Public cockpit API: sorted snapshot of every registered session.
function M.sessions()
	local out = {}
	for _, e in pairs(registry) do
		table.insert(out, {
			n = e.n,
			term = e.term,
			bufnr = e.term.bufnr,
			job_id = e.term.job_id,
			open = is_open(e.term),
		})
	end
	table.sort(out, function(a, b)
		return a.n < b.n
	end)
	return out
end

-- Most-recently-used entry passing `pred`, or nil.
local function mru(pred)
	local best
	for _, e in pairs(registry) do
		if pred(e) and (not best or e.last_used > best.last_used) then
			best = e
		end
	end
	return best
end

-- Resolve the session a send should go to (targeting order documented above).
function M.target()
	local cur = vim.api.nvim_get_current_buf()
	for _, e in pairs(registry) do
		if e.term.bufnr == cur then
			return e
		end
	end
	return mru(function(e)
		return is_open(e.term)
	end) or mru(function(e)
		return job_alive(e.term.job_id)
	end)
end

-- Send `text` into the target session's terminal job. Returns true on success.
-- opts.focus = false skips jumping into the column after the send (default is
-- to focus it and enter insert mode, so you land on the CLI input).
function M.send(text, opts)
	opts = opts or {}
	if not text or text == "" then
		return false
	end
	local e = M.target()
	if not e or not job_alive(e.term.job_id) then
		if opener then
			opener(1)
			vim.notify("Opening AI session 1 — send again once the CLI is up", vim.log.levels.WARN)
		else
			vim.notify("No AI session to send to — open one with <leader>j", vim.log.levels.WARN)
		end
		return false
	end
	vim.fn.chansend(e.term.job_id, M._payload(text))
	M.touch(e.n)
	if opts.focus ~= false and e.term.window and vim.api.nvim_win_is_valid(e.term.window) then
		vim.api.nvim_set_current_win(e.term.window)
		vim.cmd("startinsert!")
	end
	return true
end

-- What actually goes down the wire (exposed as a test seam): multi-line text
-- is wrapped in bracketed paste so a TUI receives one editable block, not N
-- submitted lines; single-line text goes raw.
function M._payload(text)
	if text:find("\n", 1, true) then
		return "\27[200~" .. text .. "\27[201~"
	end
	return text
end

-- ─── Bridge payload builders (exposed for the keymaps + tests) ─────────────

-- Current visual selection as one string (call FROM visual mode).
function M.selection_text()
	local ok, region = pcall(vim.fn.getregion, vim.fn.getpos("v"), vim.fn.getpos("."), { type = vim.fn.mode() })
	if not ok or #region == 0 then
		return nil
	end
	return table.concat(region, "\n")
end

-- Claude-style @path mention for the current buffer (cwd-relative), with a
-- trailing space so the user keeps typing after it lands in the input.
function M.buffer_mention(buf)
	local name = vim.api.nvim_buf_get_name(buf or 0)
	if name == "" then
		return nil
	end
	return "@" .. vim.fn.fnamemodify(name, ":.") .. " "
end

-- Diagnostics on the given (1-based) line of the buffer, formatted for an AI
-- prompt; nil when the line is clean.
function M.diagnostics_text(buf, lnum)
	buf = buf or 0
	lnum = lnum or vim.fn.line(".")
	local diags = vim.diagnostic.get(buf, { lnum = lnum - 1 })
	if #diags == 0 then
		return nil
	end
	local rel = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":.")
	local lines = { "Fix this diagnostic in " .. rel .. ":" }
	for _, d in ipairs(diags) do
		local sev = vim.diagnostic.severity[d.severity] or "?"
		table.insert(lines, string.format("%s:%d [%s] %s", rel, d.lnum + 1, sev, d.message))
	end
	return table.concat(lines, "\n")
end

-- ─── Keymaps ────────────────────────────────────────────────────────────────

vim.keymap.set("x", "<leader>as", function()
	local text = M.selection_text()
	-- Leave visual mode SYNCHRONOUSLY ("x" processes the escape now, not via
	-- typeahead) before the send switches windows + startinserts into the AI
	-- column — a queued <Esc> could otherwise land on the terminal instead.
	vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
	if text then
		M.send(text)
	end
end, { desc = "Send selection to AI" })

vim.keymap.set("n", "<leader>ab", function()
	local mention = M.buffer_mention(0)
	if not mention then
		vim.notify("Current buffer has no file path", vim.log.levels.WARN)
		return
	end
	M.send(mention)
end, { desc = "Send buffer path to AI" })

vim.keymap.set("n", "<leader>ad", function()
	local text = M.diagnostics_text(0)
	if not text then
		vim.notify("No diagnostics on this line", vim.log.levels.WARN)
		return
	end
	M.send(text)
end, { desc = "Send line diagnostics to AI" })

-- Cockpit picker: jump to (or reopen) a session. Sits under the bare
-- <leader>j prefix, so like <leader>j2.. it costs bare <leader>j one
-- 'timeoutlen' — the documented prefix trade-off.
vim.keymap.set("n", "<leader>ja", function()
	local sessions = M.sessions()
	if #sessions == 0 then
		vim.notify("No AI sessions yet — open one with <leader>j", vim.log.levels.WARN)
		return
	end
	local activity = require("core.ai-activity")
	vim.ui.select(sessions, {
		prompt = "AI sessions",
		format_item = function(s)
			local label = (s.bufnr and vim.api.nvim_buf_is_valid(s.bufnr) and vim.b[s.bufnr].nv_term_label)
				or ("AI · " .. s.n)
			local status = (activity.status and activity.status(s.bufnr)) or (s.open and "idle" or "hidden")
			return string.format("%s — %s", label, status)
		end,
	}, function(s)
		if not s then
			return
		end
		if s.open and s.term.window and vim.api.nvim_win_is_valid(s.term.window) then
			vim.api.nvim_set_current_win(s.term.window)
			vim.cmd("startinsert!")
		elseif opener then
			opener(s.n)
		end
	end)
end, { desc = "Jump to AI session" })

-- Keep last_used honest when the user moves into a column by any route
-- (mouse, <C-h/l>, window commands) — not just via the toggles.
vim.api.nvim_create_autocmd("TermEnter", {
	group = vim.api.nvim_create_augroup("nv_ai_sessions", { clear = true }),
	callback = function(args)
		for _, e in pairs(registry) do
			if e.term.bufnr == args.buf then
				e.last_used = stamp()
				return
			end
		end
	end,
})

-- Test seam: wipe the registry between specs.
function M._reset()
	registry = {}
	opener = nil
end

return M
