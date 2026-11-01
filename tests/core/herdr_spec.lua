-- Tests for the herdr integration (lua/core/herdr.lua).
--
-- M._send is the module's ONE socket toucher and is swapped by table field in
-- every test here, so the suite never opens a connection — the same seam the
-- ai-complete and version specs use for their network calls.

local herdr = require("core.herdr")

-- herdr's own env, as a pane it owns would carry it.
local function owned(overrides)
	local e = {
		HERDR_ENV = "1",
		HERDR_SOCKET_PATH = "/tmp/nvsinner-spec.sock",
		HERDR_PANE_ID = "w1:p1",
		HERDR_TAB_ID = "w1:t1",
		HERDR_WORKSPACE_ID = "w1",
	}
	for k, v in pairs(overrides or {}) do
		e[k] = v
	end
	return e
end

-- Capture every frame the module would send, as decoded requests.
local function capture()
	local frames = {}
	herdr._send = function(line)
		frames[#frames + 1] = vim.json.decode(line)
		return true
	end
	return frames
end

local real_send = herdr._send
local real_env = herdr._env
local real_hc = herdr._hc
local real_emit = herdr._emit

-- Discovery records go to a scratch directory: flush() publishes, and a record
-- left in the real state dir would point a live client at a dead socket.
local registry = vim.fn.tempname()
herdr.registry_dir = function()
	return registry
end

describe("core.herdr", function()
	before_each(function()
		herdr._send = real_send
		herdr._env = real_env
		herdr._hc = real_hc
		herdr._emit = real_emit
		herdr._reset()
		herdr._tokens = nil
	end)

	describe("gating", function()
		it("requires HERDR_ENV, the socket and the pane id together", function()
			assert.is_true(herdr._env(owned()).present)
			assert.is_false(herdr._env(owned({ HERDR_ENV = "0" })).present)
			assert.is_false(herdr._env(owned({ HERDR_SOCKET_PATH = "" })).present)
			assert.is_false(herdr._env(owned({ HERDR_PANE_ID = "" })).present)
			assert.is_false(herdr._env({}).present, "a plain environment is not a herdr pane")
		end)

		it("sends nothing at all outside herdr", function()
			local frames = capture()
			herdr._env = function()
				return herdr._env == nil and {} or { present = false }
			end
			herdr.flush()
			herdr.schedule()
			assert.are.equal(0, #frames, "the integration must be inert without herdr")
		end)

		it("child_env blanks this pane's context, and only inside herdr", function()
			herdr._env = function()
				return { present = true, pane = "w1:p1", socket = "/tmp/s" }
			end
			local env = herdr.child_env()
			assert.are.equal("", env.HERDR_PANE_ID)
			assert.are.equal("", env.HERDR_ENV)
			assert.are.equal("", env.HERDR_SOCKET_PATH)

			herdr._env = function()
				return { present = false }
			end
			assert.is_nil(herdr.child_env(), "nothing to isolate when herdr isn't here")
		end)

		-- The bridge needs the socket inside a column, under names herdr's own
		-- hooks never read, so the blanking above still holds.
		it("child_env hands a column the socket and its address under NVSINNER_*", function()
			herdr._env = function()
				return { present = true, pane = "w1:p1", socket = "/tmp/s" }
			end
			local env = herdr.child_env(3)
			assert.are.equal("", env.HERDR_PANE_ID)
			assert.are.equal("", env.HERDR_SOCKET_PATH)
			assert.are.equal("/tmp/s", env.NVSINNER_HERDR_SOCKET)
			assert.are.equal("w1:p1", env.NVSINNER_HERDR_PANE)
			assert.are.equal("3", env.NVSINNER_COLUMN)

			herdr._env = function()
				return { present = false }
			end
			assert.are.same(
				{ NVSINNER_COLUMN = "3", NVSINNER_HERDR_SOCKET = "", NVSINNER_HERDR_PANE = "" },
				herdr.child_env(3),
				"off herdr only the address is set, the herdr keys cleared"
			)

			-- Inherited by anything nested, so a non-column terminal must clear
			-- the column address rather than pass the outer one on.
			herdr._env = function()
				return { present = true, pane = "w1:p1", socket = "/tmp/s" }
			end
			assert.are.equal("", herdr.child_env().NVSINNER_COLUMN)
		end)
	end)

	describe("_payload rollup", function()
		local function rows(...)
			local out = {}
			for i, status in ipairs({ ... }) do
				out[i] = { n = i, kind = "claude", alive = status ~= "exited", status = status }
			end
			return out
		end

		it("lets attention win over work", function()
			assert.are.equal("blocked", herdr._payload(rows("working", "awaiting", "idle")).state)
		end)

		it("reports working when something works and nothing waits", function()
			assert.are.equal("working", herdr._payload(rows("idle", "working")).state)
		end)

		it("reports idle when every live column is idle", function()
			assert.are.equal("idle", herdr._payload(rows("idle", "idle")).state)
		end)

		it("returns no state at all when no column is alive — the release signal", function()
			assert.is_nil(herdr._payload(rows("exited", "exited")).state)
			assert.is_nil(herdr._payload({}).state)
		end)

		it("counts only live columns toward the rollup", function()
			local p = herdr._payload(rows("idle", "exited"))
			assert.are.equal("idle", p.state)
			assert.are.equal(1, p.live)
		end)

		it("describes each state for the columns actually in it", function()
			local p = herdr._payload(rows("awaiting", "working", "idle"))
			assert.are.equal("1 needs input", p.state_labels.blocked)
			assert.are.equal("1 working", p.state_labels.working)
			assert.are.equal("1 idle", p.state_labels.idle)
		end)
	end)

	describe("_payload tokens", function()
		it("names one token per column, keyed by session number", function()
			local p = herdr._payload({
				{ n = 1, kind = "claude", alive = true, status = "working" },
				{ n = 4, kind = "opencode", alive = true, status = "awaiting" },
			})
			assert.are.equal("claude:working", p.tokens.j1)
			assert.are.equal("opencode:awaiting", p.tokens.j4)
		end)

		it("emits only token names herdr accepts", function()
			local p = herdr._payload({
				{ n = 2, kind = "/usr/local/bin/kiro-cli", alive = true, status = "idle" },
			})
			for name in pairs(p.tokens) do
				assert.matches("^[A-Za-z0-9_-]+$", name)
				assert.is_true(#name <= 32, "token names are capped at 32 characters")
			end
			assert.are.equal("kiro-cli:idle", p.tokens.j2, "the CLI name drops its path")
		end)

		it("never exceeds herdr's 16-token cap", function()
			local many = {}
			for i = 1, 40 do
				many[i] = { n = i, kind = "claude", alive = true, status = "idle" }
			end
			local count = 0
			for _ in pairs(herdr._payload(many).tokens) do
				count = count + 1
			end
			assert.is_true(count <= 16, "got " .. count .. " tokens")
		end)
	end)

	describe("_encode", function()
		it("writes exactly one newline-terminated JSON request", function()
			local line = herdr._encode("id1", "pane.report_agent", { pane_id = "w1:p1" })
			assert.are.equal("\n", line:sub(-1))
			assert.are.equal(1, select(2, line:gsub("\n", "")), "one frame per line")
			local req = vim.json.decode(line)
			assert.are.equal("id1", req.id)
			assert.are.equal("pane.report_agent", req.method)
			assert.are.equal("w1:p1", req.params.pane_id)
		end)

		it("encodes empty params as a JSON object, not an array", function()
			assert.matches('"params":{}', herdr._encode("id", "ping", nil))
		end)
	end)

	describe("flush", function()
		local function with_rows(list)
			package.loaded["core.agents"] = {
				snapshot = function()
					return list
				end,
			}
			herdr._env = function()
				return { present = true, pane = "w1:p1", socket = "/tmp/s" }
			end
		end

		after_each(function()
			package.loaded["core.agents"] = nil
		end)

		it("reports the agent and its per-column metadata", function()
			local frames = capture()
			with_rows({ { n = 1, kind = "claude", alive = true, status = "awaiting" } })
			herdr.flush()

			assert.are.equal("pane.report_agent", frames[1].method)
			assert.are.equal("blocked", frames[1].params.state)
			assert.are.equal("nvsinner", frames[1].params.source)
			assert.are.equal("w1:p1", frames[1].params.pane_id)
			assert.are.equal("pane.report_metadata", frames[2].method)
			assert.are.equal("claude:awaiting", frames[2].params.tokens.j1)
		end)

		it("gives each frame a strictly increasing sequence", function()
			local frames = capture()
			with_rows({ { n = 1, kind = "claude", alive = true, status = "working" } })
			herdr.flush()
			herdr.flush()
			local seqs = {}
			for _, f in ipairs(frames) do
				seqs[#seqs + 1] = f.params.seq
			end
			assert.is_true(#seqs >= 4)
			for i = 2, #seqs do
				assert.is_true(seqs[i] > seqs[i - 1], "seq must strictly increase")
			end
		end)

		it("takes back a token when its column goes away", function()
			local frames = capture()
			with_rows({
				{ n = 1, kind = "claude", alive = true, status = "idle" },
				{ n = 2, kind = "opencode", alive = true, status = "idle" },
			})
			herdr.flush()
			with_rows({ { n = 1, kind = "claude", alive = true, status = "idle" } })
			herdr.flush()

			local meta = frames[#frames]
			assert.are.equal("pane.report_metadata", meta.method)
			assert.are.equal("claude:idle", meta.params.tokens.j1)
			assert.are.equal(vim.NIL, meta.params.tokens.j2, "a closed column's token must be nulled")
		end)

		it("releases the pane once the last column dies, then stays quiet", function()
			local frames = capture()
			with_rows({ { n = 1, kind = "claude", alive = true, status = "idle" } })
			herdr.flush()
			local before = #frames

			with_rows({ { n = 1, kind = "claude", alive = false, status = "exited" } })
			herdr.flush()
			local methods = {}
			for i = before + 1, #frames do
				methods[#methods + 1] = frames[i].method
			end
			assert.is_true(vim.tbl_contains(methods, "pane.release_agent"))

			local after_release = #frames
			herdr.flush()
			assert.are.equal(after_release, #frames, "nothing more to say once released")
		end)

		it("survives a send that fails without touching the editor", function()
			herdr._send = function()
				return false
			end
			with_rows({ { n = 1, kind = "claude", alive = true, status = "working" } })
			assert.has_no.errors(function()
				herdr.flush()
			end)
			assert.is_nil(herdr._reported, "a failed report must not be recorded as sent")
		end)

		it("honours the 'state' detail level by sending no metadata", function()
			local settings = require("core.settings")
			local previous = settings.get("herdr_detail")
			settings.set("herdr_detail", "state")
			local frames = capture()
			with_rows({ { n = 1, kind = "claude", alive = true, status = "working" } })
			herdr.flush()
			settings.set("herdr_detail", previous)

			assert.are.equal(1, #frames)
			assert.are.equal("pane.report_agent", frames[1].method)
		end)
	end)

	describe("coalescing", function()
		it("collapses a burst of events into a single armed flush", function()
			herdr._env = function()
				return { present = true, pane = "w1:p1", socket = "/tmp/s" }
			end
			herdr._pending = false
			for _ = 1, 20 do
				herdr.schedule()
			end
			assert.is_true(herdr._pending, "the burst must leave exactly one flush armed")
			herdr._reset()
		end)
	end)

	it("subscribes to the state channel core/ai-activity emits on", function()
		local found = false
		for _, au in ipairs(vim.api.nvim_get_autocmds({ group = "nv_herdr", event = "User" })) do
			if au.pattern == "NvSinnerAgentState" then
				found = true
			end
		end
		assert.is_true(found, "herdr must listen for NvSinnerAgentState, not poll")
	end)

	-- ─── One agent per pane: the measured ceiling ────────────────────────────
	--
	-- Measured 2026-09-20 against a live herdr 0.9.1 (protocol 22) on an idle
	-- shell pane, released afterwards. Reporting into the SAME pane:
	--
	--   report agent "probe-alpha", source "probe-a"  -> agent.list: 1 entry, alpha
	--   report agent "probe-beta",  source "probe-b"  -> agent.list: 1 entry, BETA
	--   report agent "probe-gamma", source "probe-a"  -> agent.list: 1 entry, GAMMA
	--
	-- One agent per pane, last writer wins, REGARDLESS of source. Per-column
	-- herdr agents would therefore require per-column herdr *panes* — moving the
	-- CLIs out of the editor, which is the whole thing NvSinner exists not to do.
	-- The rollup is this API's ceiling, not a shortcut we took.
	--
	-- Two consequences are code invariants, so they are pinned below rather than
	-- left in prose. The third — that a REPORTED agent is not addressable by name
	-- (`agent.get` answers agent_not_found while `agent.list` still lists it) —
	-- lives in lua/core/CLAUDE.md, since nothing in this module depends on it.
	describe("one agent per pane", function()
		it("reports a single identity however many columns are open", function()
			local rows = {}
			for i = 1, 9 do
				rows[i] = { n = i, kind = "claude", alive = true, status = "working" }
			end
			local p = herdr._payload(rows)
			assert.are.equal("nvsinner", p.agent, "one pane can hold exactly one agent name")
			assert.are.equal("working", p.state)
			assert.are.equal(9, p.working, "the columns survive as counts, not as identities")
		end)

		-- release_agent honours the SAME seq watermark as a report: one carrying a
		-- lower number is answered `ok` and silently ignored. That is how the CLI's
		-- own `herdr pane release-agent` failed to undo a socket-reported state
		-- during the measurement above — it generates its own numbering. So every
		-- frame this module sends, releases included, must come off one counter.
		it("never lets a release carry a lower sequence than the report before it", function()
			local frames = capture()
			package.loaded["core.agents"] = {
				snapshot = function()
					return { { n = 1, kind = "claude", alive = true, status = "working" } }
				end,
			}
			herdr._env = function()
				return { present = true, pane = "w1:p1", socket = "/tmp/s" }
			end
			herdr.flush()
			herdr.release()
			package.loaded["core.agents"] = nil

			local seqs, saw_release = {}, false
			for _, f in ipairs(frames) do
				if f.params.seq then
					seqs[#seqs + 1] = f.params.seq
				end
				saw_release = saw_release or f.method == "pane.release_agent"
			end
			assert.is_true(saw_release, "the release must actually have been sent")
			for i = 2, #seqs do
				assert.is_true(seqs[i] > seqs[i - 1], "frame " .. i .. " went backwards")
			end
		end)
	end)

	-- ─── Discovery + remote control (Phase 2) ────────────────────────────────

	describe("discovery record", function()
		it("names the file after the pane, keeping it filesystem-safe", function()
			assert.matches("/w1%-p1%.json$", herdr.registry_path("w1:p1"))
		end)

		it("writes the servername a client needs, and takes it back", function()
			herdr._env = function()
				return { present = true, pane = "spec:p9", socket = "/tmp/s", tab = "spec:t1", workspace = "spec" }
			end
			assert.is_true(herdr.publish())

			local path = herdr.registry_path("spec:p9")
			local fd = assert(io.open(path, "r"), "the record must exist")
			local record = vim.json.decode(fd:read("*a"))
			fd:close()

			assert.are.equal("spec:p9", record.pane)
			assert.are.equal(vim.v.servername, record.servername)
			assert.are.equal(vim.fn.getpid(), record.pid)

			herdr.unpublish()
			assert.are.equal(0, vim.fn.filereadable(path), "leaving must remove the record")
		end)

		-- The socket path is ~108 characters and herdr truncates token VALUES at
		-- 80 without complaining, so the path can never ride in a token.
		it("publishes the pid as a token, never the socket path", function()
			local p = herdr._payload({ { n = 1, kind = "claude", alive = true, status = "idle" } })
			assert.are.equal(tostring(vim.fn.getpid()), p.tokens.nvim)
			for _, value in pairs(p.tokens) do
				assert.is_true(#value <= 80, "herdr truncates token values at 80 characters")
			end
		end)
	end)

	-- The Herdr desktop app runs its terminals in herdr-core (`hc`): HC_* env,
	-- no HERDR_*, and reports are OSC 7501 written to our own terminal.
	describe("hc backend", function()
		local function in_hc()
			herdr._env = function()
				return { present = false }
			end
			herdr._hc = function(opts)
				return real_hc(opts or { HC_TERMINAL_ID = "t1h", HC_TERMINAL_SOCKET = "/tmp/hc.sock" })
			end
		end

		-- Every OSC 7501 body written, in order.
		local function emitted()
			local bodies = {}
			herdr._emit = function(seq)
				for body in seq:gmatch("\27%]7501;(.-)\7") do
					bodies[#bodies + 1] = body
				end
				return true
			end
			return bodies
		end

		local function with_rows(list)
			package.loaded["core.agents"] = {
				snapshot = function()
					return list
				end,
			}
		end

		after_each(function()
			package.loaded["core.agents"] = nil
		end)

		it("needs the terminal id and the core socket together", function()
			assert.is_true(real_hc({ HC_TERMINAL_ID = "t1", HC_TERMINAL_SOCKET = "/s" }).present)
			assert.is_false(real_hc({ HC_TERMINAL_ID = "t1" }).present)
			assert.is_false(real_hc({ HC_TERMINAL_SOCKET = "/s" }).present)
			assert.is_false(real_hc({}).present)
		end)

		it("prefers herdr when both are present, and is nil with neither", function()
			assert.is_nil(herdr.backend())
			in_hc()
			assert.are.equal("hc", herdr.backend())
			assert.are.equal("t1h", herdr._self_key())
			herdr._env = function()
				return { present = true, pane = "w1:p1", socket = "/tmp/s" }
			end
			assert.are.equal("herdr", herdr.backend())
			assert.are.equal("w1:p1", herdr._self_key())
		end)

		-- An agent in a column must not be able to `hc send $HC_TERMINAL_ID`
		-- into Neovim itself; it gets the editor's id under NVSINNER_* instead.
		it("hides the editor's terminal id from the columns", function()
			in_hc()
			local env = herdr.child_env(2)
			assert.are.equal("", env.HC_TERMINAL_ID)
			assert.are.equal("t1h", env.NVSINNER_HC_TERMINAL)
			assert.are.equal("2", env.NVSINNER_COLUMN)
			assert.are.equal("", env.NVSINNER_HERDR_PANE)
			assert.are.equal("", herdr.child_env().NVSINNER_COLUMN)
		end)

		it("reports the rollup as the root record and each column as its own", function()
			in_hc()
			local bodies = emitted()
			with_rows({
				{ n = 1, kind = "claude", alive = true, status = "awaiting" },
				{ n = 2, kind = "/usr/bin/opencode", alive = true, status = "working" },
				{ n = 3, kind = "claude", alive = false, status = "exited" },
			})
			herdr.flush()
			table.sort(bodies)
			assert.are.same({
				"id=j1:state=blocked:app=claude",
				"id=j2:state=working:app=opencode",
				"state=blocked:app=nvsinner",
			}, bodies)
		end)

		it("writes only what changed, and clears a column that went away", function()
			in_hc()
			local bodies = emitted()
			with_rows({
				{ n = 1, kind = "claude", alive = true, status = "idle" },
				{ n = 2, kind = "claude", alive = true, status = "idle" },
			})
			herdr.flush()
			assert.are.equal(3, #bodies)

			herdr.flush()
			assert.are.equal(3, #bodies, "nothing changed, nothing written")

			with_rows({ { n = 1, kind = "claude", alive = true, status = "working" } })
			herdr.flush()
			local tail = { bodies[4], bodies[5], bodies[6] }
			table.sort(tail)
			assert.are.same({
				"id=j1:state=working:app=claude",
				"id=j2:state=clear",
				"state=working:app=nvsinner",
			}, tail)
		end)

		it("clears every record once the last column dies", function()
			in_hc()
			local bodies = emitted()
			with_rows({ { n = 4, kind = "claude", alive = true, status = "idle" } })
			herdr.flush()
			with_rows({})
			herdr.flush()
			local tail = { bodies[3], bodies[4] }
			table.sort(tail)
			assert.are.same({ "id=j4:state=clear", "state=clear" }, tail)
			herdr.flush()
			assert.are.equal(4, #bodies, "released once, then quiet")
		end)

		-- Without a terminal UI there is nothing to write through, and a retry
		-- loop would re-snapshot forever; UIEnter re-sends instead. A write that
		-- fails WITH one attached backs off like a failed socket send.
		it("backs off a failed write only while a terminal UI is attached", function()
			in_hc()
			herdr._emit = function()
				return false
			end
			with_rows({ { n = 1, kind = "claude", alive = true, status = "idle" } })
			herdr.flush()
			assert.is_false(herdr._pending, "no tty UI: no retry loop")
			assert.is_nil(herdr._reported)

			local real_tty = herdr._tty_ui
			herdr._tty_ui = function()
				return true
			end
			herdr.flush()
			herdr._tty_ui = real_tty
			assert.is_true(herdr._pending, "a failed write with a UI arms the backoff")
			assert.is_nil(herdr._reported)
		end)

		-- A clear that could not be written (a second UI attached) must be
		-- retried, or the terminal keeps showing columns that are gone.
		it("keeps trying to clear when the release could not be written", function()
			in_hc()
			emitted()
			with_rows({ { n = 1, kind = "claude", alive = true, status = "idle" } })
			herdr.flush()
			herdr._emit = function()
				return false
			end
			with_rows({})
			herdr.flush()
			assert.are.equal("idle", herdr._reported, "still reported: the clear did not land")
			local bodies = emitted()
			herdr.flush()
			table.sort(bodies)
			assert.are.same({ "id=j1:state=clear", "state=clear" }, bodies)
			assert.is_nil(herdr._reported)
		end)

		it("re-sends every record when a UI attaches", function()
			in_hc()
			local bodies = emitted()
			with_rows({ { n = 1, kind = "claude", alive = true, status = "idle" } })
			herdr.flush()
			assert.are.equal(2, #bodies)
			herdr.flush()
			assert.are.equal(2, #bodies)
			vim.api.nvim_exec_autocmds("UIEnter", {})
			herdr._timer:stop()
			herdr._pending = false
			herdr.flush()
			assert.are.equal(4, #bodies, "a fresh UI gets the whole picture again")
		end)

		it("names the discovery record after the hc terminal", function()
			in_hc()
			assert.is_true(herdr.publish())
			local path = herdr.registry_path("t1h")
			local fd = assert(io.open(path, "r"), "the record must exist")
			local record = vim.json.decode(fd:read("*a"))
			fd:close()
			assert.are.equal("t1h", record.pane)
			assert.are.equal("hc", record.backend)
			herdr.unpublish()
			assert.are.equal(0, vim.fn.filereadable(path))
		end)
	end)

	describe("remote control", function()
		-- Build the request file bin/nvsinner-herdr writes: `key=value` header
		-- lines, a bare `--`, then the free text verbatim.
		local function request(header, text)
			local path = vim.fn.tempname()
			local fd = assert(io.open(path, "w"))
			fd:write(header .. "\n--\n" .. (text or ""))
			fd:close()
			return path
		end

		local function fake_column(n, cmd)
			local sessions = require("core.ai-sessions")
			vim.cmd("terminal cat")
			local buf = vim.api.nvim_get_current_buf()
			local term = {
				bufnr = buf,
				job_id = vim.b[buf].terminal_job_id,
				cmd = cmd,
				is_open = function()
					return true
				end,
			}
			sessions.set_clearer({
				list = function()
					return { n }
				end,
				clear = function()
					return true
				end,
				hide = function()
					return true
				end,
			})
			sessions.register(n, term)
			return buf
		end

		after_each(function()
			require("core.ai-sessions")._reset()
		end)

		it("lists the columns with their status", function()
			fake_column(2, "claude")
			local out = herdr.remote(request("action=list"))
			assert.matches("^2%s+claude", out)
		end)

		it("answers JSON when the client asks for it", function()
			fake_column(2, "claude")
			local decoded = vim.json.decode(herdr.remote(request("action=list\njson=1")))
			assert.are.equal(2, decoded.columns[1].n)
			assert.are.equal("claude", decoded.columns[1].cli)
		end)

		it("says so plainly when there is nothing to list", function()
			assert.matches("no AI columns", herdr.remote(request("action=list")))
		end)

		it("carries a multi-line prompt through verbatim", function()
			local buf = fake_column(2, "claude")
			local text = "line one\nline two\nline three"
			local out = herdr.remote(request("action=send\nn=2", text))
			assert.matches("not submitted", out, "the bridge must never auto-submit")

			-- It reached the CLI: the terminal echoed something back.
			local arrived = vim.wait(3000, function()
				return require("core.ai-activity").status(buf) == "working"
			end, 50)
			assert.is_true(arrived, "the text should have reached the job")
		end)

		it("refuses to send to a column that is not running", function()
			local out = herdr.remote(request("action=send\nn=7", "hi"))
			assert.matches("not running", out)
		end)

		it("needs both a column and text to send", function()
			fake_column(2, "claude")
			assert.matches("needs a column number and text", herdr.remote(request("action=send\nn=2", "")))
		end)

		it("tells the client which pane the editor runs in", function()
			herdr._env = function()
				return { present = true, pane = "w1:p4", socket = "/tmp/s" }
			end
			fake_column(2, "claude")
			local decoded = vim.json.decode(herdr.remote(request("action=list\njson=1")))
			assert.are.equal("w1:p4", decoded.pane)
		end)

		it("reports a column's state in herdr's vocabulary", function()
			fake_column(2, "claude")
			assert.matches("^idle$", herdr.remote(request("action=status\nn=2")))
			assert.are.equal("unknown", herdr.remote(request("action=status\nn=7")))

			local agents = require("core.agents")
			local real = agents.status_of
			agents.status_of = function()
				return "awaiting"
			end
			local ok, out = pcall(herdr.remote, request("action=status\nn=2"))
			agents.status_of = real
			assert.is_true(ok)
			assert.are.equal("blocked", out)
		end)

		-- `prompt` is the one action that submits: the text first, then exactly
		-- one Enter in a SEPARATE write, after a gap.
		it("prompt submits with one Enter written after the text", function()
			local buf = fake_column(2, "claude")
			local job = vim.b[buf].terminal_job_id
			local writes = {}
			local real = vim.fn.chansend
			vim.fn.chansend = function(id, data)
				if id == job then
					writes[#writes + 1] = data
				end
				return real(id, data)
			end
			local out = herdr.remote(request("action=prompt\nn=2", "hello"))
			local landed = vim.wait(2000, function()
				return #writes >= 2
			end, 20)
			vim.fn.chansend = real

			assert.matches("^submitted", out)
			assert.is_true(landed, "the Enter should follow the text")
			assert.are.same({ "hello", "\r" }, writes)
		end)

		it("send still never submits", function()
			local buf = fake_column(2, "claude")
			local job = vim.b[buf].terminal_job_id
			local writes = {}
			local real = vim.fn.chansend
			vim.fn.chansend = function(id, data)
				if id == job then
					writes[#writes + 1] = data
				end
				return real(id, data)
			end
			herdr.remote(request("action=send\nn=2", "hello"))
			vim.wait(400)
			vim.fn.chansend = real
			assert.are.same({ "hello" }, writes)
		end)

		-- herdr's own `agent prompt` refuses a blocked agent: the Enter would
		-- answer the dialog instead of sending the prompt.
		it("prompt refuses a column blocked on a question, before typing", function()
			local buf = fake_column(2, "claude")
			local job = vim.b[buf].terminal_job_id
			local agents = require("core.agents")
			local real_status, real_chansend = agents.status_of, vim.fn.chansend
			local writes = 0
			agents.status_of = function()
				return "awaiting"
			end
			vim.fn.chansend = function(id, data)
				if id == job then
					writes = writes + 1
				end
				return real_chansend(id, data)
			end
			local ok, out = pcall(herdr.remote, request("action=prompt\nn=2", "yes"))
			vim.wait(400)
			agents.status_of, vim.fn.chansend = real_status, real_chansend

			assert.is_true(ok)
			assert.matches("agent_blocked", out)
			assert.are.equal(0, writes)
		end)

		it("prompt refuses a plain-shell column: the Enter would run the text", function()
			fake_column(2, nil) -- no cmd → kind "shell"
			local out = herdr.remote(request("action=prompt\nn=2", "echo `id`"))
			assert.matches("not_an_agent", out)
		end)

		it("prompt refuses a second prompt while the first Enter is pending", function()
			fake_column(2, "claude")
			assert.matches("^submitted", herdr.remote(request("action=prompt\nn=2", "one")))
			assert.matches("agent_busy", herdr.remote(request("action=prompt\nn=2", "two")))
			vim.wait(600)
			assert.matches("^submitted", herdr.remote(request("action=prompt\nn=2", "three")))
		end)

		-- Typing the text alone makes the column look busy; `fresh` only counts
		-- output written after the Enter.
		it("fresh status waits for output after the Enter", function()
			fake_column(2, "claude")
			herdr.remote(request("action=prompt\nn=2", "hello"))
			assert.are.equal("pending", herdr.remote(request("action=status\nn=2\nfresh=1")))
			local started = vim.wait(3000, function()
				return herdr.remote(request("action=status\nn=2\nfresh=1")) == "started"
			end, 50)
			assert.is_true(started, "cat echoes the Enter, which is output after it")
		end)

		-- A bare CR is an Enter and ESC can end the bracketed paste early: either
		-- would let `send` submit, or run a line in a shell column.
		it("send refuses control characters and writes nothing", function()
			local buf = fake_column(2, nil)
			local job = vim.b[buf].terminal_job_id
			local writes = {}
			local real = vim.fn.chansend
			vim.fn.chansend = function(id, data)
				if id == job then
					writes[#writes + 1] = data
				end
				return real(id, data)
			end
			local cr = herdr.remote(request("action=send\nn=2", "rm -rf build\rx"))
			local esc = herdr.remote(request("action=send\nn=2", "a\nb\27[201~\rc"))
			vim.wait(100)
			vim.fn.chansend = real

			assert.matches("control_chars", cr)
			assert.matches("control_chars", esc)
			assert.are.same({}, writes)
		end)

		it("send passes CRLF text through as plain newlines", function()
			fake_column(2, "claude")
			assert.matches("^queued", herdr.remote(request("action=send\nn=2", "one\r\ntwo")))
		end)

		-- Anything typed while a prompt's Enter is pending would be submitted
		-- with it, so `send` waits its turn too.
		it("send refuses a column whose prompt Enter is still pending", function()
			fake_column(2, "claude")
			assert.matches("^submitted", herdr.remote(request("action=prompt\nn=2", "one")))
			assert.matches("agent_busy", herdr.remote(request("action=send\nn=2", "draft")))
			vim.wait(600)
			assert.matches("^queued", herdr.remote(request("action=send\nn=2", "draft")))
		end)

		-- A dialog that opens inside the gap keeps the Enter; fresh status must
		-- say so rather than pass on the previous prompt's output.
		it("fresh status reports an Enter skipped for a dialog", function()
			fake_column(2, "claude")
			herdr.remote(request("action=prompt\nn=2", "first"))
			assert.is_true(vim.wait(3000, function()
				return herdr.remote(request("action=status\nn=2\nfresh=1")) == "started"
			end, 50))

			local agents = require("core.agents")
			local real_status = agents.status_of
			assert.matches("^submitted", herdr.remote(request("action=prompt\nn=2", "second")))
			agents.status_of = function()
				return "awaiting"
			end
			vim.wait(400)
			local s = herdr.remote(request("action=status\nn=2\nfresh=1"))
			agents.status_of = real_status
			assert.are.equal("not_submitted", s)
		end)

		it("prompt fails closed when the column's state can't be read", function()
			fake_column(2, "claude")
			local agents = require("core.agents")
			local real_snapshot = agents.snapshot
			agents.snapshot = function()
				error("boom")
			end
			local out = herdr.remote(request("action=prompt\nn=2", "hi"))
			agents.snapshot = real_snapshot
			assert.matches("agent_unknown", out)
		end)

		it("prompt refuses a column that is not running", function()
			assert.matches("not running", herdr.remote(request("action=prompt\nn=7", "hi")))
		end)

		-- End to end through the real client: bin/nvsinner-herdr resolves `j2`
		-- through $NVIM and calls back into this editor. Async on purpose — a
		-- blocking system() would hold the loop the callback needs.
		it("the client resolves a column through $NVIM", function()
			if vim.fn.executable("nvim") == 0 or vim.v.servername == "" then
				return pending("needs nvim on PATH and a server socket")
			end
			fake_column(2, "claude")
			local bin = vim.fn.fnamemodify("bin/nvsinner-herdr", ":p")
			local out = {}
			local job = vim.fn.jobstart({ bin, "status", "j2" }, {
				env = { NVIM = vim.v.servername, NVSINNER_COLUMN = "", HERDR_PANE_ID = "" },
				stdout_buffered = true,
				on_stdout = function(_, data)
					out = data
				end,
			})
			local done = vim.wait(10000, function()
				return vim.fn.jobwait({ job }, 0)[1] ~= -1
			end, 50)
			assert.is_true(done, "the client should finish")
			assert.are.equal("idle", out[1])
		end)

		it("rejects an action it does not implement", function()
			assert.matches("unknown action", herdr.remote(request("action=eval", "os.exit()")))
		end)

		it("never throws, whatever the client sends", function()
			assert.has_no.errors(function()
				herdr.remote("/nonexistent/request/file")
			end)
			assert.matches("error", herdr.remote("/nonexistent/request/file"))
		end)

		-- A fresh terminal keeps its output at the TOP of a full-height grid, so
		-- tailing before trimming the blank rows would return nothing at all.
		it("reads a column whose output has not filled the screen yet", function()
			local buf = fake_column(2, "claude")
			vim.fn.chansend(vim.b[buf].terminal_job_id, "marker-line\n")
			vim.wait(2000, function()
				return require("core.ai-activity").status(buf) == "working"
			end, 50)
			vim.wait(300)
			assert.matches("marker%-line", herdr.remote(request("action=read\nn=2\nlines=10")))
		end)
	end)

	-- bin/nvsinner-herdr under the Herdr app, against a fake `hc` on PATH that
	-- logs its arguments and answers from canned files — never the real core.
	-- The addresses are made up and the core socket does not exist, so even a
	-- real `hc` picked up by mistake could not reach a live terminal; `run`
	-- also refuses to start unless `hc` resolves to the fake.
	describe("client against herdr-core", function()
		local bin = vim.fn.fnamemodify("bin/nvsinner-herdr", ":p")
		local dir, log

		local function write(path, text)
			local fd = assert(io.open(path, "w"))
			fd:write(text)
			fd:close()
		end

		before_each(function()
			dir = vim.fn.tempname()
			vim.fn.mkdir(dir, "p")
			log = dir .. "/log"
			write(
				dir .. "/hc",
				table.concat({
					"#!/bin/sh",
					'printf "%s\\n" "$*" >> "$HC_LOG"',
					'for a in "$@"; do last="$a"; done',
					'case "$1" in',
					'  get) cat "$HC_DIR/get-$last.json" 2>/dev/null && exit 0',
					'       echo \'{"error":{"message":"no terminal"}}\'; exit 3 ;;',
					'  send|wait) [ -n "$HC_RC" ] && exit "$HC_RC"; cat "$HC_DIR/$1.json" ;;',
					"esac",
				}, "\n")
			)
			vim.fn.setfperm(dir .. "/hc", "rwx------")
			write(dir .. "/get-tzz8.json", '{"address":"tzz8","status":{"app":"claude-code","state":"idle"}}')
			write(
				dir .. "/get-tzz1h.json",
				'{"address":"tzz1h","foreground":{"name":"nvim","argv":["nvim"]},"status":null}'
			)
			write(
				dir .. "/get-tzz7.json",
				'{"address":"tzz7","foreground":{"name":"zsh","argv":["zsh"]},"status":null}'
			)
			write(dir .. "/send.json", '{"started":true,"wait":{"ended":true,"status":"idle","reason":"status"}}')
		end)

		local function run(args, env)
			local e = {
				PATH = dir .. ":" .. vim.env.PATH,
				HC_LOG = log,
				HC_DIR = dir,
				HC_TERMINAL_ID = "tzz9",
				HC_TERMINAL_SOCKET = dir .. "/no-such-core.sock",
				XDG_STATE_HOME = dir .. "/state",
				NVIM = "",
				NVSINNER_COLUMN = "",
				NVSINNER_HERDR_SOCKET = "",
			}
			for k, v in pairs(env or {}) do
				e[k] = v
			end
			local which = vim.system({ "sh", "-c", "command -v hc" }, { env = e, text = true }):wait()
			assert(vim.trim(which.stdout or "") == dir .. "/hc", "refusing to run: hc is not the fake")
			local cmd = { bin }
			vim.list_extend(cmd, args)
			local r = vim.system(cmd, { env = e, text = true }):wait()
			return r.code, (r.stdout or "") .. (r.stderr or "")
		end

		local function calls()
			return vim.fn.filereadable(log) == 1 and vim.fn.readfile(log) or {}
		end

		local function needs_jq()
			return vim.fn.executable("jq") == 0 and pending("needs jq") or nil
		end

		-- hc would paste the text and press Enter into Neovim's normal mode.
		it("refuses a terminal running Neovim even without a discovery record", function()
			if needs_jq() then
				return
			end
			local code, out = run({ "prompt", "tzz1h", "fix it" })
			assert.are.equal(1, code)
			assert.matches("NvSinner editor", out)
			for _, line in ipairs(calls()) do
				assert.is_nil(line:match("^send"), "nothing may be sent: " .. line)
			end
		end)

		-- No 7501 status means no agent: a shell would run the text, `$(…)`
		-- included, whatever prefix it carries.
		it("refuses a terminal that reports no agent status", function()
			if needs_jq() then
				return
			end
			local code, out = run({ "prompt", "tzz7", "echo $(id)" })
			assert.are.equal(1, code)
			assert.matches("not_an_agent", out)
			for _, line in ipairs(calls()) do
				assert.is_nil(line:match("^send"), "nothing may be sent: " .. line)
			end
		end)

		it("prompts through hc send, shielding text that looks like an option", function()
			if needs_jq() then
				return
			end
			local code, out = run({ "prompt", "tzz8", "--no-from", "--", "-h" })
			assert.are.equal(0, code, out)
			assert.matches("submitted 2 chars to tzz8", out)
			assert.are.equal("send --json -- tzz8 -h", calls()[#calls()])
		end)

		it("maps hc's own exit codes onto the client's", function()
			if needs_jq() then
				return
			end
			local code, out = run({ "prompt", "tzz8", "hi" }, { HC_RC = "9" })
			assert.are.equal(3, code)
			assert.matches("agent_blocked", out)
			code = run({ "prompt", "tzz8", "hi" }, { HC_RC = "3" })
			assert.are.equal(4, code, "hc's not_found is a gone target, not a stall")
		end)

		it("turns a wait that never started or never ended into 3 and 124", function()
			if needs_jq() then
				return
			end
			write(dir .. "/send.json", '{"started":false,"wait":{"ended":true,"status":"idle"}}')
			assert.are.equal(3, (run({ "prompt", "tzz8", "hi", "--wait" })))
			write(dir .. "/send.json", '{"started":true,"wait":{"ended":false,"status":"working"}}')
			assert.are.equal(124, (run({ "prompt", "tzz8", "hi", "--wait", "--timeout", "1500" })))
			assert.matches("%-%-timeout 2", calls()[#calls()], "ms are rounded up to hc's seconds")
		end)

		it("refuses send (hc can't type without Enter) and messaging yourself", function()
			if needs_jq() then
				return
			end
			local code, out = run({ "send", "tzz8", "draft" })
			assert.are.equal(1, code)
			assert.matches("use prompt", out)
			code, out = run({ "prompt", "tzz8", "hi" }, { HC_TERMINAL_ID = "tzz8" })
			assert.are.equal(1, code)
			assert.matches("yourself", out)
			for _, line in ipairs(calls()) do
				assert.is_nil(line:match("^send"), "nothing may be sent: " .. line)
			end
		end)
	end)
end)
