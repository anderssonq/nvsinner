-- ─── herdr integration ──────────────────────────────────────────────────────
-- Reports NvSinner's AI columns to a running herdr server, so the multiplexer
-- that owns this editor's pane can see the agents living INSIDE it.
--
-- WHY THIS EXISTS. herdr recognises a coding agent by watching the terminal of
-- a pane it owns. NvSinner's AI columns are toggleterm buffers inside one
-- Neovim process, so from herdr's side the whole editor is a single pane
-- "running an editor" — up to nine live agents it cannot see, count, or tell
-- you are blocked. This module closes that gap from our side.
--
-- This is the OPPOSITE of the rejected "AI plugin in the editor" direction: it
-- exports state outward to the terminal runtime, and still never reads an API
-- key, never renders a chat, never wraps a CLI. Do not delete it as one.
--
-- PROTOCOL (herdr 0.9.1, protocol 22 — `herdr api schema`). Newline-delimited
-- JSON over the AF_UNIX socket in $HERDR_SOCKET_PATH:
--   {"id":"…","method":"pane.report_agent","params":{…}}  →  {"id":"…","result":{…}}
-- `source` is our stable identity and owns authority: while we report, herdr
-- stops screen-detecting this pane, and only the same source may release it.
-- `seq` must strictly increase; out-of-order frames are dropped.
--
-- ONE AGENT PER PANE. herdr keys agents by pane id, so N columns necessarily
-- roll up into ONE reported agent (see M._payload — attention wins, the same
-- precedence core/agents.lua already uses). Per-column detail rides along as
-- report_metadata tokens j1…j9.
--
-- NO POLLING. State arrives on the `User NvSinnerAgentState` channel that
-- core/ai-activity.lua and core/ai-sessions.lua emit on; a sweep over terminal
-- buffers is the design that was already ruled out. The one timer here is a
-- COALESCER armed by an event, never a free-running poller.
--
-- HONEST LIMIT. What we report is only as good as core/agents.lua's
-- status_of(): its per-CLI screen signatures are field-verified, not
-- test-verified, so "blocked" is a heuristic, not a guarantee.
--
-- EMPIRICAL NOTES (probed on NVIM 0.12.3 against herdr 0.9.1):
--
--  * ONE REQUEST PER CONNECTION. A second frame written to the same socket is
--    accepted by chansend() but never answered and never applied — the first
--    request lands, the rest are silently dropped. So every call opens its own
--    connection, which is exactly what herdr's own shipped hooks do (connect,
--    send one request, read, close). A persistent channel looks like it works:
--    report_agent takes effect and report_metadata vanishes.
--
--  * `:help` says sockconnect() "Returns … 0 on invalid arguments or connection
--    failure". It does NOT — it throws (`Vim:connection failed: connection
--    refused`), and chansend() on a dead id throws E900. Both are pcall-wrapped.
--
--  * A report is accepted on a pane whose foreground process is not a shell,
--    and takes over from herdr's screen detection — verified end to end against
--    a live server on an agentless pane (agent "nvsinner", status "blocked",
--    title and tokens applied, then released cleanly).
--
--  * report_metadata tokens MERGE across sources; clearing ours leaves another
--    integration's tokens on the pane untouched.
--
--  * TOKEN VALUES ARE TRUNCATED AT 80 CHARACTERS, silently — the server still
--    answers "ok". That is why `v:servername` is NOT published as a token: the
--    default socket path is ~108 characters, so it would arrive unusable. The
--    discovery record below carries it instead, and the token holds the pid.
--
-- CONTROL (M.remote). Neovim always listens on `v:servername`, so anything that
-- can read the discovery record can drive the columns from another herdr pane
-- via `nvim --server … --remote-expr`. bin/nvsinner-herdr is that client. The
-- socket is the SAME default one Neovim opens, whose parent directories are
-- 0700 — deliberately not a fresh socket of our own, because Neovim creates
-- socket files 0755 and one in a shared directory would be world-connectable.
-- M.remote is an API surface, NOT a security boundary: anything holding that
-- socket can already evaluate arbitrary code in this editor.

local M = {}

local uv = vim.uv or vim.loop

-- Tunables.
local SOURCE = "nvsinner" -- our authority identity; only this source may release
local AGENT = "nvsinner" -- live agent name; must match [a-z][a-z0-9_-]{0,31}
local COALESCE_MS = 200 -- events → one frame; herdr tracks one agent per pane anyway
local BACKOFF_MS = { 1000, 2000, 5000, 15000 } -- retry schedule, last value repeats
local REPLY_MS = 2000 -- safety net: close a connection that never answers
local MAX_TOKENS = 16 -- herdr's cap on report_metadata tokens
local COLUMN_TOKENS = MAX_TOKENS - 1 -- one slot reserved for the `nvim` marker

-- ─── Environment ────────────────────────────────────────────────────────────

-- herdr injects these into every pane it owns. `opts` is a test seam so specs
-- can drive the gate without touching the real environment.
function M._env(opts)
	local e = opts or vim.env
	local env = {
		flag = e.HERDR_ENV,
		socket = e.HERDR_SOCKET_PATH,
		pane = e.HERDR_PANE_ID,
		tab = e.HERDR_TAB_ID,
		workspace = e.HERDR_WORKSPACE_ID,
	}
	-- All three are required, exactly as herdr's own shipped integrations gate
	-- themselves — the integration must be inert outside herdr.
	env.present = env.flag == "1" and (env.socket or "") ~= "" and (env.pane or "") ~= ""
	return env
end

-- True only when herdr owns this pane AND reporting is switched on.
function M.enabled()
	if not M._env().present then
		return false
	end
	local ok, settings = pcall(require, "core.settings")
	if not ok then
		return true -- settings not loaded yet (early boot): default to reporting
	end
	return settings.get("herdr") ~= false
end

-- Env table for a CLI we spawn in a column, or nil when herdr isn't here.
--
-- Columns otherwise inherit Neovim's environment verbatim, including the
-- EDITOR pane's HERDR_PANE_ID. An agent with a herdr integration installed
-- (claude ships one) then reports its own session against the editor's pane —
-- every column overwriting the last, and herdr later trying to restore that
-- mis-attributed session into a plain shell. Empty strings fail herdr's
-- `== "1"` / non-empty guards, which is all its clients check; jobstart's env
-- cannot delete a variable, and clear_env would mean rebuilding PATH by hand.
--
-- Gated on env PRESENCE, not on M.enabled(): the mis-attribution happens
-- whether or not we report, so switching reporting off must not re-open it.
function M.child_env()
	if not M._env().present then
		return nil
	end
	return {
		HERDR_ENV = "",
		HERDR_PANE_ID = "",
		HERDR_SOCKET_PATH = "",
		HERDR_TAB_ID = "",
		HERDR_WORKSPACE_ID = "",
	}
end

-- ─── Payload (pure) ─────────────────────────────────────────────────────────

-- The CLI name a column runs, off agents.lua's `kind` (which is term.cmd, or
-- "shell"/"session" for a plain terminal / an exited panel).
local function cli_of(row)
	local kind = row.kind
	if type(kind) ~= "string" or kind == "" then
		return "cli"
	end
	return kind:match("([^/%s]+)%s*$") or kind
end

-- Rows (core.agents.snapshot()) → everything the two report calls need.
--
-- ROLLUP RULE, and the one place it is written down: attention wins. Any
-- column waiting on the user makes the pane blocked, else any column working
-- makes it working, else idle. No live column at all → state = nil, meaning
-- "release our authority and let herdr go back to screen detection".
function M._payload(rows)
	rows = rows or {}
	local live, working, blocked = 0, 0, 0
	-- The pid marks the pane as hosting an editor and lets a client confirm it
	-- reached the right instance. The socket path itself cannot live here (80
	-- characters); bin/nvsinner-herdr reads it from the discovery record.
	local tokens = { nvim = tostring(vim.fn.getpid()) }
	local ntokens = 0
	for _, row in ipairs(rows) do
		if ntokens < COLUMN_TOKENS then
			ntokens = ntokens + 1
			tokens["j" .. tostring(row.n)] = cli_of(row) .. ":" .. tostring(row.status or "unknown")
		end
		if row.alive then
			live = live + 1
			if row.status == "awaiting" then
				blocked = blocked + 1
			elseif row.status == "working" then
				working = working + 1
			end
		end
	end

	local state, message
	if live == 0 then
		state = nil
		message = nil
	elseif blocked > 0 then
		state = "blocked"
		message = blocked .. " of " .. live .. " waiting for input"
	elseif working > 0 then
		state = "working"
		message = working .. " of " .. live .. " working"
	else
		state = "idle"
		message = live == 1 and "1 column idle" or (live .. " columns idle")
	end

	local title
	local ok, project = pcall(require, "core.project")
	if ok then
		local pok, name = pcall(project.name)
		if pok and name and name ~= "" then
			title = "NvSinner · " .. name
		end
	end

	return {
		agent = AGENT,
		state = state,
		message = message,
		title = title,
		live = live,
		working = working,
		blocked = blocked,
		tokens = tokens,
		-- herdr renders the label for the pane's CURRENT status, so each one
		-- describes the columns in that state only.
		state_labels = {
			blocked = blocked > 0 and (blocked .. (blocked == 1 and " needs input" or " need input")) or nil,
			working = working > 0 and (working .. " working") or nil,
			idle = (live - working - blocked) > 0 and ((live - working - blocked) .. " idle") or nil,
		},
	}
end

-- One newline-delimited JSON request line. vim.json.encode turns an empty Lua
-- table into `[]`, so empty params must be vim.empty_dict().
function M._encode(id, method, params)
	return vim.json.encode({
		id = id,
		method = method,
		params = (params and next(params) ~= nil) and params or vim.empty_dict(),
	}) .. "\n"
end

-- ─── Transport ──────────────────────────────────────────────────────────────

M._timer = nil -- coalesce/retry timer (anchored on M: an unreferenced luv
-- timer can be garbage-collected and silently stop firing)
M._pending = false -- a flush is armed
M._backoff = 0 -- index into BACKOFF_MS
M._seq = 0 -- strictly increasing report sequence
M._reported = nil -- last state we announced, so we know when to release
M._tokens = nil -- token names we published, so release() can take them back

-- Wall-clock-seeded monotonic sequence. Seconds×1000 stays far inside a
-- double's exact-integer range (ns since the epoch does not), and still
-- increases across a Neovim restart.
local seq_base = os.time() * 1000

local function next_seq()
	M._seq = M._seq + 1
	return seq_base + M._seq
end

-- The ONE function that touches the socket. Specs swap it by table field, so
-- the suite never opens a real connection. Returns true when the line went out.
--
-- One connection per request (see the header): connect, write, and close as
-- soon as the reply or EOF arrives, with a timer so a server that never answers
-- cannot leak the channel. The reply itself is an ack we have nothing to do
-- with — errors surface as the state simply not changing in herdr's UI.
function M._send(line)
	local env = M._env()
	if not env.present then
		return false
	end
	local ch, closed = nil, false
	local function shut()
		if not closed and ch then
			closed = true
			pcall(vim.fn.chanclose, ch)
		end
	end
	local ok, res = pcall(vim.fn.sockconnect, "pipe", env.socket, {
		data_buffered = false,
		-- Normal event context (unlike a raw vim.uv pipe), so no scheduling
		-- discipline is needed — but close on the next tick rather than from
		-- inside the callback that is still draining the channel.
		on_data = function()
			vim.schedule(shut)
		end,
	})
	if not ok or type(res) ~= "number" or res <= 0 then
		return false
	end
	ch = res
	if not pcall(vim.fn.chansend, ch, line) then
		shut()
		return false
	end
	vim.defer_fn(shut, REPLY_MS)
	return true
end

-- A failed send re-arms a retry on a widening backoff. Deliberately silent:
-- a herdr server that went away must be indistinguishable from no herdr, and a
-- retry loop that toasted would nag straight past the `quiet` setting.
local function schedule_retry()
	M._backoff = math.min(M._backoff + 1, #BACKOFF_MS)
	local delay = BACKOFF_MS[M._backoff]
	M._pending = true
	if not M._timer then
		M._timer = uv.new_timer()
	end
	M._timer:stop()
	M._timer:start(
		delay,
		0,
		vim.schedule_wrap(function()
			M._pending = false
			M.flush()
		end)
	)
end

-- ─── Reporting ──────────────────────────────────────────────────────────────

-- Give up our authority so herdr falls back to its own screen detection.
function M.release()
	local env = M._env()
	if not env.present then
		return
	end
	-- Take our display metadata back first: release_agent drops the lifecycle
	-- authority but leaves title/labels/tokens standing. Tokens merge per
	-- source, so nulling ours never disturbs another integration's.
	if M._tokens then
		local tokens = {}
		for name in pairs(M._tokens) do
			tokens[name] = vim.NIL
		end
		M._send(M._encode(SOURCE .. ":unmeta", "pane.report_metadata", {
			pane_id = env.pane,
			source = SOURCE,
			seq = next_seq(),
			clear_title = true,
			clear_state_labels = true,
			tokens = tokens,
		}))
		M._tokens = nil
	end
	M._send(M._encode(SOURCE .. ":release", "pane.release_agent", {
		pane_id = env.pane,
		source = SOURCE,
		agent = AGENT,
		seq = next_seq(),
	}))
	M._reported = nil
end

-- Build the current picture and push it. One snapshot, at most two frames.
function M.flush()
	if not M.enabled() then
		return
	end
	local env = M._env()

	local ok, rows = pcall(function()
		return require("core.agents").snapshot()
	end)
	if not ok then
		return
	end
	local p = M._payload(rows)

	-- Written before the first send, not after: the control path (the discovery
	-- record that bin/nvsinner-herdr resolves) must work even while reporting is
	-- failing, and a column existing is what makes it worth publishing.
	if p.state ~= nil then
		M.publish()
	end

	-- No live column left: release once, then stay quiet.
	if p.state == nil then
		if M._reported ~= nil then
			M.release()
		end
		return
	end

	local sent = M._send(M._encode(SOURCE .. ":agent", "pane.report_agent", {
		pane_id = env.pane,
		source = SOURCE,
		agent = p.agent,
		state = p.state,
		message = p.message,
		seq = next_seq(),
	}))
	if not sent then
		schedule_retry()
		return
	end
	M._reported = p.state
	M._backoff = 0

	local detail = "tokens"
	local sok, settings = pcall(require, "core.settings")
	if sok then
		detail = settings.get("herdr_detail") or "tokens"
	end
	if detail == "state" then
		return
	end

	-- Names we dropped since the last frame must be nulled explicitly, or a
	-- closed column's token would sit on the pane forever.
	local tokens, live = {}, {}
	for name, value in pairs(p.tokens) do
		tokens[name], live[name] = value, true
	end
	if M._tokens then
		for name in pairs(M._tokens) do
			if not live[name] then
				tokens[name] = vim.NIL
			end
		end
	end
	local params = { pane_id = env.pane, source = SOURCE, agent = p.agent, seq = next_seq(), tokens = tokens }
	if detail == "full" then
		params.title = p.title
		params.state_labels = p.state_labels
	end
	if M._send(M._encode(SOURCE .. ":meta", "pane.report_metadata", params)) then
		M._tokens = live
	end
end

-- Coalesce: N column events collapse into one frame, which is not an
-- optimisation but a consequence of herdr tracking one agent per pane.
function M.schedule()
	if not M.enabled() or M._pending then
		return
	end
	M._pending = true
	if not M._timer then
		M._timer = uv.new_timer()
	end
	M._timer:stop()
	M._timer:start(
		COALESCE_MS,
		0,
		vim.schedule_wrap(function()
			M._pending = false
			M.flush()
		end)
	)
end

-- ─── Discovery record ───────────────────────────────────────────────────────
--
-- One JSON file per Neovim instance, named after the herdr pane hosting it, so
-- a client in ANOTHER pane can go pane id → this editor's RPC socket. It exists
-- because the socket path does not fit in a metadata token (80 characters).
-- Written on the first successful report, removed on the way out.

function M.registry_dir()
	return vim.fn.stdpath("state") .. "/herdr"
end

-- Pane ids look like "w1:p1"; keep the filename boring.
function M.registry_path(pane)
	return M.registry_dir() .. "/" .. tostring(pane):gsub("[^%w%-_]", "-") .. ".json"
end

function M.publish()
	local env = M._env()
	if not env.present then
		return false
	end
	local record = vim.json.encode({
		pane = env.pane,
		tab = env.tab,
		workspace = env.workspace,
		servername = vim.v.servername,
		pid = vim.fn.getpid(),
		cwd = vim.fn.getcwd(),
		appname = vim.env.NVIM_APPNAME or "nvim",
	})
	local ok = pcall(function()
		vim.fn.mkdir(M.registry_dir(), "p", "0700")
		local fd = assert(io.open(M.registry_path(env.pane), "w"))
		fd:write(record .. "\n")
		fd:close()
	end)
	return ok
end

function M.unpublish()
	local env = M._env()
	if not env.present then
		return
	end
	pcall(vim.fn.delete, M.registry_path(env.pane))
end

-- ─── Remote control (bin/nvsinner-herdr) ────────────────────────────────────
--
-- Deliberately NOT gated on M.enabled(): the client may hold the socket without
-- this editor reporting to herdr at all. Every action returns a printable
-- string; `json = true` returns the same shape encoded instead, so the shell
-- client never needs a JSON parser.

local function columns()
	local ok, rows = pcall(function()
		return require("core.agents").snapshot()
	end)
	return ok and rows or {}
end

local function entry_for(n)
	for _, e in ipairs(require("core.ai-sessions").sessions()) do
		if e.n == n then
			return e
		end
	end
	return nil
end

local REMOTE = {}

function REMOTE.list()
	local rows = {}
	for _, row in ipairs(columns()) do
		rows[#rows + 1] = {
			n = row.n,
			status = row.status,
			cli = row.kind,
			alive = row.alive and true or false,
			open = row.open and true or false,
			label = row.label,
		}
	end
	local lines = {}
	for _, r in ipairs(rows) do
		lines[#lines + 1] = ("%d  %-10s %-9s %s"):format(
			r.n,
			r.cli or "?",
			r.status or "?",
			r.open and "shown" or "hidden"
		)
	end
	if #lines == 0 then
		lines[1] = "no AI columns open"
	end
	return { text = table.concat(lines, "\n"), data = { columns = rows, cwd = vim.fn.getcwd() } }
end

function REMOTE.focus(req)
	local n = tonumber(req.n)
	if not n then
		return { text = "focus needs a column number", data = { ok = false } }
	end
	local ok = require("core.ai-sessions").open_session(n)
	return { text = ok and ("focused column " .. n) or ("cannot open column " .. n), data = { ok = ok, n = n } }
end

-- Lands in the CLI's input for review. The bridge never appends a carriage
-- return, so nothing is ever auto-submitted — that contract holds here too.
function REMOTE.send(req)
	local n = tonumber(req.n)
	local text = req.text or ""
	if not n or text == "" then
		return { text = "send needs a column number and text", data = { ok = false } }
	end
	local e = entry_for(n)
	if not e then
		return { text = "column " .. n .. " is not running", data = { ok = false, n = n } }
	end
	local ok = require("core.ai-sessions").send_to(e, text, { focus = false })
	return {
		text = ok and ("queued " .. #text .. " chars in column " .. n .. " (not submitted)")
			or ("column " .. n .. " refused the send"),
		data = { ok = ok, n = n, submitted = false },
	}
end

function REMOTE.read(req)
	local n = tonumber(req.n)
	local want = tonumber(req.lines) or 40
	local e = entry_for(n or -1)
	local buf = e and e.bufnr
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return { text = "column " .. tostring(req.n) .. " has no live buffer", data = { ok = false } }
	end
	-- Trim the blank tail BEFORE taking the last `want`. A terminal buffer is a
	-- full-height grid, so a column that has not filled its screen yet keeps its
	-- output at the TOP with blank rows under it — tailing first would hand back
	-- nothing at all. Bounded so a long scrollback stays cheap.
	local lines = vim.api.nvim_buf_get_lines(buf, -2001, -1, false)
	while #lines > 0 and lines[#lines]:match("^%s*$") do
		table.remove(lines)
	end
	if #lines > want then
		lines = vim.list_slice(lines, #lines - want + 1)
	end
	return { text = table.concat(lines, "\n"), data = { ok = true, n = n, lines = lines } }
end

-- Entry point for `nvim --server … --remote-expr`. Takes the PATH of a request
-- file rather than the request itself, so the client never has to escape a
-- prompt into a Vim expression — the only interpolated value is a path it made.
--
-- Format: `key=value` header lines, then a line that is exactly `--`, then the
-- free text. Everything after that separator is taken verbatim, newlines and
-- all, which is what lets a multi-line prompt through untouched.
function M.remote(path)
	local ok, res = pcall(function()
		local raw = vim.fn.readfile(path)
		local req, body, in_body = {}, {}, false
		for _, line in ipairs(raw) do
			if in_body then
				body[#body + 1] = line
			elseif line == "--" then
				in_body = true
			else
				local k, v = line:match("^([%w_]+)=(.*)$")
				if k then
					req[k] = v
				end
			end
		end
		req.text = table.concat(body, "\n")

		local handler = REMOTE[req.action or ""]
		if not handler then
			return { text = "unknown action: " .. tostring(req.action), data = { ok = false } }
		end
		local out = handler(req)
		if req.json == "1" then
			return { text = vim.json.encode(out.data) }
		end
		return out
	end)
	if not ok then
		return "error: " .. tostring(res)
	end
	return res.text or ""
end

-- ─── Settings + lifecycle ───────────────────────────────────────────────────

function M.set_enabled(v)
	if v == false then
		M.release()
		if M._timer then
			M._timer:stop()
		end
		M._pending = false
	else
		M.schedule()
	end
end

function M._reset() -- test seam
	if M._timer then
		M._timer:stop()
	end
	M._pending, M._backoff, M._reported = false, 0, nil
end

vim.api.nvim_create_autocmd("User", {
	pattern = "NvSinnerAgentState",
	group = vim.api.nvim_create_augroup("nv_herdr", { clear = true }),
	callback = function()
		M.schedule()
	end,
})

-- Hand the pane back on the way out, so a closed editor doesn't leave herdr
-- holding a stale "blocked" from our source.
vim.api.nvim_create_autocmd("VimLeavePre", {
	group = "nv_herdr",
	callback = function()
		pcall(M.unpublish)
		pcall(M.release)
	end,
})

return M
