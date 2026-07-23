-- ─── AI session registry + send-to-AI bridge ───────────────────────────────
-- The single place that knows which AI columns exist. toggleterm.lua PUSHES
-- sessions in here on first open (plugin→core dependency — core never requires
-- a plugin), so the bridge keymaps, the <leader>ja picker, and the tests
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
local clearer -- injected by toggleterm: { list = fn() → sorted {n,…}, clear = fn(n) → bool }
local mru_clock = 0
local function stamp()
	mru_clock = mru_clock + 1
	return mru_clock
end

function M.set_opener(fn)
	opener = fn
end

function M.set_clearer(c)
	clearer = c
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

-- Label for the clear picker: registered sessions reuse the <leader>ja
-- formula (winbar label + activity status); a panel the registry no longer
-- knows (its CLI already exited — on_exit unregistered it) is marked so.
local function clear_label(n)
	local e = registry[n]
	if not e then
		return "AI · " .. n .. " — exited"
	end
	local bufnr = e.term.bufnr
	local label = (bufnr and vim.api.nvim_buf_is_valid(bufnr) and vim.b[bufnr].nv_term_label) or ("AI · " .. n)
	local activity = require("core.ai-activity")
	local status = (activity.status and activity.status(bufnr)) or (is_open(e.term) and "idle" or "hidden")
	return string.format("%s — %s", label, status)
end

-- Clear (definitively close) an AI session: kill its CLI and drop the
-- memoised Terminal so the next <leader>j open shows the CLI picker again —
-- the counterpart to toggling, which hides without killing. Both the
-- enumeration and the teardown come from the injected clearer because the
-- panels live in toggleterm's closure and the registry can't see a panel
-- whose CLI already exited (on_exit unregisters it; the memo survives).
-- With no explicit n: a single panel clears directly, several ask via
-- vim.ui.select. Returns true when a panel was cleared.
function M.clear(n)
	local panels = clearer and clearer.list() or {}
	if #panels == 0 then
		vim.notify("No AI session to clear — open one with <leader>j", vim.log.levels.WARN)
		return false
	end
	local function do_clear(sn)
		clearer.clear(sn)
		-- shutdown's on_exit unregisters asynchronously; do it here too so
		-- the registry is deterministically clean (unregister is idempotent).
		M.unregister(sn)
		vim.notify("AI session " .. sn .. " cleared — <leader>j starts fresh", vim.log.levels.INFO)
		return true
	end
	if n then
		if not vim.tbl_contains(panels, n) then
			vim.notify("No AI session " .. n .. " to clear", vim.log.levels.WARN)
			return false
		end
		return do_clear(n)
	end
	if #panels == 1 then
		return do_clear(panels[1])
	end
	local cleared = false
	vim.ui.select(panels, {
		prompt = "Clear AI session",
		format_item = clear_label,
	}, function(choice)
		if choice then
			cleared = do_clear(choice)
		end
	end)
	return cleared
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

-- Send `text` into a SPECIFIC session entry (a registry entry or a row from
-- M.sessions() — both carry .n and .term; job_id is read LIVE from the term so
-- a snapshot row stays correct after a hide/reopen). Returns true on success.
-- opts.focus = false skips jumping into the column after the send (default is
-- to focus it and enter insert mode, so you land on the CLI input).
function M.send_to(e, text, opts)
	opts = opts or {}
	if not text or text == "" then
		return false
	end
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

-- Send `text` into the auto-resolved target session (M.target() MRU order).
function M.send(text, opts)
	if not text or text == "" then
		return false
	end
	return M.send_to(M.target(), text, opts)
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

-- Claude-style @path mentions for every VISIBLE file buffer — current buffer
-- first, then the rest in window order, deduped by cwd-relative path, joined
-- with spaces + a trailing space so the user keeps typing. Single-line on
-- purpose: M._payload sends it raw (no bracketed paste). Only listed,
-- ordinary (buftype == "") buffers whose name exists on disk qualify, so
-- terminals, pickers, and never-saved names can't produce dead @refs.
-- Returns nil when nothing qualifies.
--
-- Discovery walks WINDOWS, not vim.api.nvim_list_bufs(): the buffer list is
-- not "what I have open" — every file you :e, jump to with gd, or peek at
-- from neo-tree stays listed long after its window is gone, and mentioning
-- those scopes the AI to files the user already closed. Only the current
-- tabpage counts (seeing is tab-local) and floats are skipped, so a
-- telescope preview or hover float can't leak a mention.
-- opts.bufs supplies an explicit buffer list (kept in the caller's order,
-- bypassing window discovery) for picker-style reuse; opts.wins overrides the
-- window list.
function M.buffer_mentions(opts)
	opts = opts or {}
	local uv = vim.uv or vim.loop
	local bufs = opts.bufs
	if not bufs then
		bufs = { vim.api.nvim_get_current_buf() }
		for _, win in ipairs(opts.wins or vim.api.nvim_tabpage_list_wins(0)) do
			if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_config(win).relative == "" then
				table.insert(bufs, vim.api.nvim_win_get_buf(win))
			end
		end
	end
	local parts, seen = {}, {}
	for _, buf in ipairs(bufs) do
		if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buflisted and vim.bo[buf].buftype == "" then
			local name = vim.api.nvim_buf_get_name(buf)
			if name ~= "" and uv.fs_stat(name) then
				local rel = vim.fn.fnamemodify(name, ":.")
				if not seen[rel] then
					seen[rel] = true
					table.insert(parts, "@" .. rel)
				end
			end
		end
	end
	if #parts == 0 then
		return nil
	end
	return table.concat(parts, " ") .. " "
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

-- Clear a session for good: kill the CLI and forget the choice, so the next
-- <leader>j open asks which CLI to run again. Same <leader>j-prefix
-- timeoutlen trade-off as <leader>ja.
vim.keymap.set("n", "<leader>jc", function()
	M.clear()
end, { desc = "Clear AI session (kill CLI + forget choice)" })

-- :NvSinnerAIClear [n] — the command form (hidden from :NvSinnerHelp like the
-- other AI commands; it lives in the :NvSinnerIA hub).
vim.api.nvim_create_user_command("NvSinnerAIClear", function(a)
	M.clear(tonumber(a.args))
end, { nargs = "?", desc = "Clear an AI session — kill the CLI and forget the choice (<leader>jc)" })

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
	clearer = nil
end

return M
