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
-- or hc terminal
-- via `nvim --server … --remote-expr`. bin/nvsinner-herdr is that client. The
-- socket is the SAME default one Neovim opens, whose parent directories are
-- 0700 — deliberately not a fresh socket of our own, because Neovim creates
-- socket files 0755 and one in a shared directory would be world-connectable.
-- M.remote is an API surface, NOT a security boundary: anything holding that
-- socket can already evaluate arbitrary code in this editor.
--
-- AGENT-TO-AGENT. The same client is how agents talk to each other (column ↔
-- column, column ↔ herdr agent). Its `prompt` verb is the one path that
-- SUBMITS (REMOTE.prompt); everything else keeps the never-auto-submit rule.
--
-- TWO BACKENDS. The Herdr desktop app does not run its terminals in `herdr
-- server`: they live in herdr-core (`hc`), which sets HC_TERMINAL_ID /
-- HC_TERMINAL_SOCKET and never HERDR_*. Under hc the report is not a socket
-- call but an OSC 7501 sequence written to our own terminal through the UI
-- (nvim_ui_send — what the built-in OSC 52 clipboard uses), and hc keeps one
-- RECORD per id, so each column is reported on its own beside the rollup.
-- Probed against herdr-core 0.9.5 (2026-10-31): `ESC]7501;state=working:
-- app=nvsinner BEL` sets the root record, `id=j2:state=blocked` a record of
-- its own, `id=j2:state=clear` removes it; pairs are `:`-separated, and a
-- report carrying an unknown key (`title`) is dropped whole. herdr wins when
-- both are present: HERDR_* means a herdr server owns this pane.

local M = {}

local uv = vim.uv or vim.loop

-- Tunables.
local SOURCE = "nvsinner" -- our authority identity; only this source may release
local AGENT = "nvsinner" -- live agent name; must match [a-z][a-z0-9_-]{0,31}
local COALESCE_MS = 200 -- events → one frame; herdr tracks one agent per pane anyway
local BACKOFF_MS = { 1000, 2000, 5000, 15000 } -- retry schedule, last value repeats
local REPLY_MS = 2000 -- safety net: close a connection that never answers
local SUBMIT_MS = 200 -- paste → Enter gap; a TUI that sees both in one burst takes Enter as a pasted newline
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

-- herdr-core (the desktop app's terminal runtime) injects these instead.
function M._hc(opts)
	local e = opts or vim.env
	local env = { id = e.HC_TERMINAL_ID, socket = e.HC_TERMINAL_SOCKET }
	env.present = (env.id or "") ~= "" and (env.socket or "") ~= ""
	return env
end

-- "herdr", "hc" or nil. herdr first: HERDR_* means a herdr server owns the pane.
function M.backend()
	if M._env().present then
		return "herdr"
	end
	if M._hc().present then
		return "hc"
	end
	return nil
end

-- This editor's address inside its backend: the herdr pane id or the hc
-- terminal id (`t1h`). Names the discovery record and prefixes `<addr>/jN`.
function M._self_key()
	local b = M.backend()
	if b == "herdr" then
		return M._env().pane
	elseif b == "hc" then
		return M._hc().id
	end
	return nil
end

-- True only when a backend owns this terminal AND reporting is switched on.
function M.enabled()
	if not M.backend() then
		return false
	end
	local ok, settings = pcall(require, "core.settings")
	if not ok then
		return true -- settings not loaded yet (early boot): default to reporting
	end
	return settings.get("herdr") ~= false
end

-- Env table for a terminal we spawn, or nil when there is nothing to set.
--
-- Columns otherwise inherit Neovim's environment verbatim, including the
-- editor's own address (HERDR_PANE_ID under herdr, HC_TERMINAL_ID under hc —
-- the hc case is explained in its branch below). An agent with a herdr integration installed
-- (claude ships one) then reports its own session against the editor's pane —
-- every column overwriting the last, and herdr later trying to restore that
-- mis-attributed session into a plain shell. Empty strings fail herdr's
-- `== "1"` / non-empty guards, which is all its clients check; jobstart's env
-- cannot delete a variable, and clear_env would mean rebuilding PATH by hand.
--
-- Gated on env PRESENCE (either backend), not on M.enabled(): the mis-attribution happens
-- whether or not we report, so switching reporting off must not re-open it.
--
-- The agent-to-agent bridge still needs the herdr socket, so it rides under
-- NVSINNER_* names that herdr's hooks never read: bin/nvsinner-herdr puts
-- HERDR_SOCKET_PATH back for its own `herdr` subprocess only, and never a pane
-- id, so nothing it runs can be attributed to the editor's pane. `n` (an AI
-- column's number) becomes NVSINNER_COLUMN, the column's own address — set off
-- herdr too, since column-to-column talk needs no herdr at all.
function M.child_env(n)
	local env = M._env()
	local hc = M._hc()
	local out
	-- Under herdr, and for any column, every NVSINNER_* key is written, ""
	-- where it does not apply: they are inherited, so an editor nested inside a
	-- column would otherwise hand ITS terminals the outer column's address.
	-- Off herdr a non-column terminal gets nil (nothing to isolate), so there
	-- that nested case still inherits the outer address.
	if env.present then
		out = {
			HERDR_ENV = "",
			HERDR_PANE_ID = "",
			HERDR_SOCKET_PATH = "",
			HERDR_TAB_ID = "",
			HERDR_WORKSPACE_ID = "",
			NVSINNER_HERDR_SOCKET = env.socket,
			NVSINNER_HERDR_PANE = env.pane,
			NVSINNER_HC_TERMINAL = "",
			NVSINNER_COLUMN = "",
		}
	elseif hc.present then
		-- Same reasoning under hc: the editor's terminal id would let an agent
		-- in a column `hc send $HC_TERMINAL_ID …` straight into Neovim, and
		-- would make an `hc run` from a column a child of the editor. The core
		-- socket stays: it names the runtime, not this terminal.
		out = {
			HC_TERMINAL_ID = "",
			NVSINNER_HERDR_SOCKET = "",
			NVSINNER_HERDR_PANE = "",
			NVSINNER_HC_TERMINAL = hc.id,
			NVSINNER_COLUMN = "",
		}
	end
	if n then
		out = out or { NVSINNER_HERDR_SOCKET = "", NVSINNER_HERDR_PANE = "" }
		out.NVSINNER_COLUMN = tostring(n)
	end
	return out
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

-- ─── hc transport (OSC 7501) ────────────────────────────────────────────────

-- nvim_ui_send reaches only UIs that write to a tty, and every one of them.
-- So exactly ONE must be attached: none means nothing to write to (a GUI
-- counts as none), and two would put our records on a second terminal too
-- (`nvim --remote-ui` from another hc terminal). Limit: a lone remote UI in a
-- different terminal than the one that started the editor still gets them.
function M._tty_ui()
	local n = 0
	for _, ui in ipairs(vim.api.nvim_list_uis()) do
		if ui.stdout_tty then
			n = n + 1
		end
	end
	return n == 1
end

-- The ONE function that writes to the terminal under hc; specs swap it.
function M._emit(seq)
	if not M._tty_ui() then
		return false
	end
	return (pcall(vim.api.nvim_ui_send, seq))
end

-- agents.lua's vocabulary mapped onto herdr's (and hc's, which uses the same
-- words): the 7501 records, and `status` so a client can wait on a column with
-- the same --until states it uses for a herdr agent.
local HERDR_STATUS = { working = "working", awaiting = "blocked", idle = "idle" }

-- Values must be escape-code-safe and must not carry the `:` separator.
local function hc_word(v)
	return (tostring(v):gsub("[^%w%._%-]", ""))
end

-- Rows + rollup → { [record id] = report body }, `""` being the root record.
-- A column that is not alive gets "state=clear", as does one we reported
-- before that is gone now (M._hc_records holds the ids we put up).
function M._hc_frames(p, rows, previous)
	local frames, live = {}, {}
	frames[""] = p.state and ("state=" .. p.state .. ":app=" .. AGENT) or "state=clear"
	for _, row in ipairs(rows or {}) do
		local id = "j" .. tostring(row.n)
		local st = row.alive and HERDR_STATUS[row.status]
		if st then
			frames[id] = "id=" .. id .. ":state=" .. st .. ":app=" .. hc_word(cli_of(row))
			live[id] = true
		end
	end
	for id in pairs(previous or {}) do
		if id ~= "" and not live[id] then
			frames[id] = "id=" .. id .. ":state=clear"
		end
	end
	return frames, live
end

local function hc_osc(body)
	return "\27]7501;" .. body .. "\7"
end

-- Writes only what changed since the last frame (M._hc_sent), so a burst of
-- events that leaves a column where it was costs nothing.
local function hc_flush(p, rows)
	local frames, live = M._hc_frames(p, rows, M._hc_records)
	local out = {}
	M._hc_sent = M._hc_sent or {}
	for id, body in pairs(frames) do
		if M._hc_sent[id] ~= body then
			out[#out + 1] = hc_osc(body)
		end
	end
	if #out > 0 and not M._emit(table.concat(out)) then
		return false
	end
	for id, body in pairs(frames) do
		if body:find("state=clear", 1, true) then
			M._hc_sent[id] = nil
		else
			M._hc_sent[id] = body
		end
	end
	M._hc_records = live
	return true
end

-- Returns false when the clear could not be written (no or several tty UIs):
-- the bookkeeping then stays, so the next flush or UIEnter clears for real.
local function hc_release()
	local frames = M._hc_frames({ state = nil }, {}, M._hc_records)
	local out = {}
	for _, body in pairs(frames) do
		out[#out + 1] = hc_osc(body)
	end
	if not M._emit(table.concat(out)) then
		return false
	end
	M._hc_sent, M._hc_records = nil, nil
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
	if M.backend() == "hc" then
		if not M._hc_records or hc_release() then
			M._reported = nil
		end
		return
	end
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

	-- Re-written before the first send, not after: the control path (the
	-- discovery record that bin/nvsinner-herdr resolves) must work even while
	-- reporting is failing. It is also published at startup, below.
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

	if M.backend() == "hc" then
		if hc_flush(p, rows) then
			M._reported, M._backoff = p.state, 0
		elseif M._tty_ui() then
			schedule_retry()
		end
		-- No tty UI: no retry loop. UIEnter (below) re-sends everything.
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
-- One JSON file per Neovim instance, named after the herdr pane or hc terminal
-- hosting it (M._self_key), so a client elsewhere can go address → this
-- editor's RPC socket. It exists
-- because the socket path does not fit in a metadata token (80 characters).
-- Published at startup (once a UI is attached, see the bottom of this file),
-- refreshed on every report, removed on the way out.

function M.registry_dir()
	return vim.fn.stdpath("state") .. "/herdr"
end

-- Pane ids look like "w1:p1"; keep the filename boring.
function M.registry_path(pane)
	return M.registry_dir() .. "/" .. tostring(pane):gsub("[^%w%-_]", "-") .. ".json"
end

function M.publish()
	local key = M._self_key()
	if not key then
		return false
	end
	local env = M._env()
	local record = vim.json.encode({
		pane = key, -- the address prefix: a herdr pane id or an hc terminal id
		backend = M.backend(),
		tab = env.tab,
		workspace = env.workspace,
		servername = vim.v.servername,
		pid = vim.fn.getpid(),
		cwd = vim.fn.getcwd(),
		appname = vim.env.NVIM_APPNAME or "nvim",
	})
	local ok = pcall(function()
		vim.fn.mkdir(M.registry_dir(), "p", "0700")
		local fd = assert(io.open(M.registry_path(key), "w"))
		fd:write(record .. "\n")
		fd:close()
	end)
	return ok
end

function M.unpublish()
	local key = M._self_key()
	if not key then
		return
	end
	pcall(vim.fn.delete, M.registry_path(key))
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

local function find_n(list, n)
	for _, x in ipairs(list) do
		if x.n == n then
			return x
		end
	end
	return nil
end

local function entry_for(n)
	return find_n(require("core.ai-sessions").sessions(), n)
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
	return {
		text = table.concat(lines, "\n"),
		data = { columns = rows, cwd = vim.fn.getcwd(), pane = M._self_key() },
	}
end

function REMOTE.focus(req)
	local n = tonumber(req.n)
	if not n then
		return { text = "focus needs a column number", data = { ok = false } }
	end
	local ok = require("core.ai-sessions").open_session(n)
	return { text = ok and ("focused column " .. n) or ("cannot open column " .. n), data = { ok = ok, n = n } }
end

-- The shared front half of `send` and `prompt`: validate, find the live
-- column, run `guard` (prompt's blocked check), then type the text without
-- submitting. Returns `entry, n, #text`, or `nil, reply` for the caller to
-- hand straight back.
local function type_into(req, verb, guard)
	local n = tonumber(req.n)
	local text = (req.text or ""):gsub("\r\n", "\n")
	if not n or text == "" then
		return nil, { text = verb .. " needs a column number and text", data = { ok = false } }
	end
	-- Only newline and tab get through. A bare CR is an Enter (it would submit
	-- a `send`, or run a line in a shell column), and ESC can close the
	-- bracketed paste early and smuggle an Enter in after it.
	if text:find("[%z\1-\8\11-\31\127]") then
		return nil,
			{
				text = verb .. " refused: the text holds control characters (control_chars); nothing sent",
				data = { ok = false, n = n, error = "control_chars" },
			}
	end
	local e = entry_for(n)
	if not e then
		return nil, { text = "column " .. n .. " is not running", data = { ok = false, n = n } }
	end
	-- A prompt's Enter is still pending: anything typed now would be submitted
	-- with it, `send` included.
	if M._inflight[n] then
		return nil,
			{
				text = "column " .. n .. " is still taking the previous prompt (agent_busy); nothing sent",
				data = { ok = false, n = n, error = "agent_busy" },
			}
	end
	local refusal = guard and guard(n)
	if refusal then
		return nil, refusal
	end
	if not require("core.ai-sessions").send_to(e, text, { focus = false }) then
		return nil, { text = "column " .. n .. " refused the " .. verb, data = { ok = false, n = n } }
	end
	return e, n, #text
end

-- Lands in the CLI's input for review. The bridge never appends a carriage
-- return, so nothing is ever auto-submitted — that contract holds here too.
function REMOTE.send(req)
	local e, n, len = type_into(req, "send")
	if not e then
		return n -- the refusal
	end
	return {
		text = "queued " .. len .. " chars in column " .. n .. " (not submitted)",
		data = { ok = true, n = n, submitted = false },
	}
end

local function row_for(n)
	return find_n(columns(), n)
end

-- Per column: uv.now() when prompt's Enter was written (M._submitted[n]),
-- whether an Enter is still pending (M._inflight[n]), and whether the last
-- prompt's Enter was skipped because a dialog appeared (M._skipped[n]).
M._submitted, M._inflight, M._skipped = {}, {}, {}

-- `fresh=1` asks a different question: has the column produced output SINCE
-- the last prompt's Enter? Typing the text redraws the CLI's input line, which
-- alone reads as "working" for a second — so a client gating `prompt --wait`
-- on plain status would pass on the echo even if the Enter was never written.
-- It cannot tell a TUI that folded the Enter into its input (that redraw is
-- output too). Answers "started", "pending" (Enter not written yet / no
-- output after it), "not_submitted" (the Enter was skipped) or "unknown".
function REMOTE.status(req)
	local n = tonumber(req.n)
	local row = n and row_for(n)
	if not row or not row.alive then
		return { text = "unknown", data = { ok = false, n = n, status = "unknown" } }
	end
	local s = HERDR_STATUS[row.status] or "unknown"
	if req.fresh == "1" and M._skipped[n] then
		s = "not_submitted"
	elseif req.fresh == "1" then
		local at = M._submitted[n]
		local last = row.bufnr and require("core.ai-activity").last_output(row.bufnr)
		local started = not M._inflight[n] and at ~= nil and last ~= nil and last > at
		-- A column that blocked right after the Enter has started too.
		if not M._inflight[n] and at ~= nil and s == "blocked" then
			started = true
		end
		s = started and "started" or "pending"
	end
	return { text = s, data = { ok = true, n = n, status = s, cli = row.kind } }
end

-- The agent-to-agent verb, and the ONE place anything submits. `send` and the
-- in-editor bridge (<leader>as/ab/ad, Ask-AI) still never press Enter; an
-- agent asking another agent has no human at the receiving end to press it,
-- so the explicit `prompt` action does. Mirrors herdr's `agent prompt`: a
-- column waiting on an approval or a question is refused before anything is
-- typed, since the Enter would answer that dialog instead.
--
-- Refused before typing, too: a plain-terminal column (the Enter would hand the
-- text to a SHELL — backticks and $(…) in a prompt would run), and a column
-- whose state can't be read (fail closed: no row, no Enter). A column with an
-- Enter still pending is refused by type_into for every verb.
local function refuse_prompt(n)
	local row = row_for(n)
	if not row then
		return {
			text = "column " .. n .. " has no readable state (agent_unknown); nothing sent",
			data = { ok = false, n = n, error = "agent_unknown" },
		}
	end
	if row.kind == "shell" or row.kind == "session" then
		return {
			text = "column " .. n .. " runs a plain shell, not an agent (not_an_agent); nothing sent",
			data = { ok = false, n = n, error = "not_an_agent" },
		}
	end
	if row.status == "awaiting" then
		return {
			text = "column " .. n .. " is blocked on an approval or a question (agent_blocked); nothing sent",
			data = { ok = false, n = n, error = "agent_blocked" },
		}
	end
end

function REMOTE.prompt(req)
	local e, n, len = type_into(req, "prompt", refuse_prompt)
	if not e then
		return n -- the refusal
	end
	-- Enter goes in a second write, after a gap: sent in the same burst as the
	-- text, a TUI with paste detection (claude) folds it into the paste as a
	-- newline and the prompt just sits there. Re-checked at write time: a
	-- dialog that appeared inside the gap would take the Enter as its default
	-- answer ("Yes"), so the text is left unsubmitted instead. The check is
	-- agents.lua's screen heuristic — a dialog it misses is still at risk.
	-- Skipped Enters are recorded for `status fresh=1`, and the previous
	-- prompt's timestamp is dropped so its output can't pass for this one.
	local job = e.term.job_id
	M._inflight[n], M._submitted[n], M._skipped[n] = true, nil, nil
	vim.defer_fn(function()
		M._inflight[n] = nil
		local row = row_for(n)
		if not row or row.status == "awaiting" then
			M._skipped[n] = true
			return
		end
		if pcall(vim.fn.chansend, job, "\r") then
			M._submitted[n] = uv.now()
		end
	end, SUBMIT_MS)
	-- "submitted" is the client's success token; the Enter itself lands
	-- SUBMIT_MS later, and only `--wait` (status fresh=1) can confirm it.
	return {
		text = "submitted " .. len .. " chars to column " .. n,
		data = { ok = true, n = n, submitted = true },
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
	M._submitted, M._inflight, M._skipped = {}, {}, {}
	M._hc_sent, M._hc_records = nil, nil
end

vim.api.nvim_create_autocmd("User", {
	pattern = "NvSinnerAgentState",
	group = vim.api.nvim_create_augroup("nv_herdr", { clear = true }),
	callback = function()
		M.schedule()
	end,
})

-- The discovery record is the client's only way to know a pane or terminal
-- hosts an EDITOR (and so must never be typed into as an agent), so it exists
-- for as long as this editor runs under a backend — not only once reporting flushed,
-- and not only while reporting is switched on. Only an editor with a UI: a
-- headless run in the same pane (a test, a script) would overwrite the live
-- editor's record and could exit without taking it back.
if M.backend() then
	local function publish()
		pcall(M.publish)
	end
	if #vim.api.nvim_list_uis() > 0 then
		vim.schedule(publish)
	else
		vim.api.nvim_create_autocmd("UIEnter", { once = true, callback = publish })
	end
end

-- Under hc a UI that (re)attaches has seen none of our records, and one that
-- left took them with it: forget what was written and send the full picture.
vim.api.nvim_create_autocmd({ "UIEnter", "UILeave" }, {
	group = "nv_herdr",
	callback = function()
		if M.backend() == "hc" then
			M._hc_sent = nil
			M.schedule()
		end
	end,
})

-- Hand the pane back on the way out, so a closed editor doesn't leave herdr
-- holding a stale "blocked" from our source. (A VimLeavePre nvim_ui_send
-- still reaches the tty, so hc gets its `state=clear` too.)
vim.api.nvim_create_autocmd("VimLeavePre", {
	group = "nv_herdr",
	callback = function()
		pcall(M.unpublish)
		pcall(M.release)
	end,
})

return M
