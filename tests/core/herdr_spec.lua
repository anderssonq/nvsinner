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

describe("core.herdr", function()
	before_each(function()
		herdr._send = real_send
		herdr._env = real_env
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
end)
