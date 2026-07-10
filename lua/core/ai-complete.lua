-- ─── Inline AI code completion (native, manual trigger) ─────────────────────
-- Copilot-style ghost-text suggestions, served by OpenCode Zen — the ONLY
-- supported provider (see M.endpoint below). Distinct from the agentic AI
-- terminal column (ai-sessions/toggleterm): this completes code *inline* in
-- the buffer you're editing.
--
-- Deliberate design invariants (also recorded in lua/core/CLAUDE.md):
--   * OPENCODE ZEN EXCLUSIVE — the endpoint speaks the OpenAI chat shape, but
--     auth, the model catalogue, the response quirks (reasoning_content eating
--     the token budget) and the usage-cap handling are verified against the
--     OpenCode Zen "Go" plan only; no other provider is supported.
--   * MANUAL trigger only (<C-l> in insert, or :NvSinnerComplete) — cost is
--     bounded by explicit triggers, which keeps the OpenCode Zen Go plan's usage
--     caps predictable. No type-ahead requests.
--   * FAST, low/non-reasoning model by default — a reasoning model spends
--     the token budget on reasoning_content and returns empty content (no ghost).
--   * The API key is read from $OPENCODE_API_KEY at request time (vim.env) and
--     is NEVER hardcoded, persisted, or written to settings/. With no key the
--     feature is a quiet no-op after one WARN.
--   * Zero plugin dependency: the HTTP call is `curl` via vim.system (same shape
--     as git-blame.lua / image-open.lua). `M._request` is the ONLY function that
--     touches the network, called by table field so tests swap it — the suite
--     never makes a real request.
--   * Async results are dropped when superseded (generation counter + :kill,
--     same discipline as git-blame.lua) so ghost text never paints under a moved
--     cursor.
--   * Ghost-text accept yields to nvim-cmp: <Tab> accepts only when a suggestion
--     is pending AND cmp's popup is not visible; otherwise it is a literal Tab.

local M = {}

local ns = vim.api.nvim_create_namespace("nvsinner_ai_complete")
M._ns = ns -- test seam: specs read the ghost extmark in this namespace

-- ─── Tunables ────────────────────────────────────────────────────────────────
-- Context is FIM-style (minuet-ai / Copilot shape): the whole file around the
-- cursor, clamped to one character budget split by a ratio — NOT a fixed line
-- window. CONTEXT_WINDOW is the combined prefix+suffix char cap; CONTEXT_RATIO
-- gives the prefix (before the cursor) the larger share (0.75 → 3:1), since what
-- precedes the cursor matters more. Most files fit whole (imports included);
-- only very large files get tail/head-clamped around the cursor.
M.CONTEXT_WINDOW = 16000 -- combined prefix+suffix character budget
M.CONTEXT_RATIO = 0.75 -- fraction of the window reserved for the prefix
M.MAX_TOKENS = 512 -- upper bound on a single completion (headroom over a short
-- reasoning preamble: some OpenCode Zen models spend tokens on reasoning_content
-- before the visible content, and too small a cap leaves content empty)
M.TEMPERATURE = 0.1 -- low → deterministic, code-shaped output
M.TIMEOUT_S = 12 -- curl --max-time
M.AUTH_COOLDOWN_MS = 60 * 1000 -- pause after a 401/403 so a bad key can't hammer
M.RATE_COOLDOWN_MS = 5 * 60 * 1000 -- pause after a 429 / usage-limit response
-- How the ghost previews when the trigger line is a comment-only line (see
-- M._is_comment_line): "below" renders the whole suggestion as a dimmed block
-- BENEATH the comment (accept then replaces the comment with it), so the code
-- never glues onto the comment text; "inline" keeps the normal at-cursor ghost.
M.COMMENT_PREVIEW = "below"

-- ─── Endpoint / model / auth (env-driven, read at call time) ─────────────────
-- OpenCode Zen ("Go" plan) is the only supported provider. $OPENCODE_ENDPOINT
-- is an unsupported escape hatch, not a provider switch — nothing off the Zen
-- endpoint is tested, and the model curation below is Zen-specific.
function M.endpoint()
	return vim.env.OPENCODE_ENDPOINT or "https://opencode.ai/zen/go/v1/chat/completions"
end

-- The models the :NvSinnerIA picker offers — the VERIFIED-SAFE subset of the
-- OpenCode Zen Go catalogue, speed-ordered. Every id here survived a 5-run
-- probe (2026-07-09; Lua + TypeScript completion payloads, sequential timing):
-- clean code-only content on every run, well inside the 12s request cap.
-- Everything else in the 20-model catalogue failed at least once and is
-- deliberately NOT offered:
--   * empty content, always or intermittently (reasoning_content burns the
--     MAX_TOKENS budget): glm-5, glm-5.1, deepseek-v4-flash, deepseek-v4-pro,
--     mimo-v2.5, mimo-v2.5-pro
--   * narrates prose instead of returning code: kimi-k2.5, kimi-k2.6
--   * emits <think> inside content: minimax-m3
--   * HTTP 4xx/5xx on the Go plan: kimi-k2.7-code, mimo-v2-pro, mimo-v2-omni,
--     hy3-preview
--   * blows the 12s cap: qwen3.7-max (~18s), qwen3.7/3.6/3.5-plus (>25s)
M.SAFE_MODELS = { "minimax-m2.5", "minimax-m2.7", "glm-5.2" }
-- Probe latency (avg of 5 runs): minimax-m2.5 ~4.1s (3.3–4.8 — the fastest),
-- minimax-m2.7 ~4.7s (never emits reasoning — the steadiest), glm-5.2 ~5.4s
-- (1.5–10.6s swings, reasoning bursts near the token cap). Shown by the picker.
M.MODEL_NOTES = {
	["minimax-m2.5"] = "fastest — recommended",
	["minimax-m2.7"] = "steadiest — never reasons",
	["glm-5.2"] = "variable latency",
}
M.DEFAULT_MODEL = "minimax-m2.5"

-- Model precedence: $OPENCODE_MODEL (launch override) > the persisted :NvSinnerIA
-- choice (settings.ai_model) > DEFAULT_MODEL. settings is already a dependency.
function M.model()
	if vim.env.OPENCODE_MODEL and vim.env.OPENCODE_MODEL ~= "" then
		return vim.env.OPENCODE_MODEL
	end
	local ok, settings = pcall(require, "core.settings")
	if ok then
		local m = settings.get("ai_model")
		if type(m) == "string" and m ~= "" then
			return m
		end
	end
	return M.DEFAULT_MODEL
end

-- Optional free/cheaper model to retry with once on a 429 before giving up.
local function fallback_model()
	local m = vim.env.OPENCODE_FALLBACK_MODEL
	if m and m ~= "" then
		return m
	end
	return nil
end

-- The API key — env only, never cached, never persisted. nil when unset.
function M._api_key()
	local k = vim.env.OPENCODE_API_KEY
	if k and k ~= "" then
		return k
	end
	return nil
end

-- ─── Highlights (carbon) — ghost comment tone + loading chip ─────────────────
local function apply_hl()
	local c = require("core.carbon").colors()
	vim.api.nvim_set_hl(0, "NvAiGhost", { fg = c.base03, italic = true })
	-- Loading chip: blue identity accent (base09) with dark text, distinct from
	-- ai-activity's pink terminal-busy chip (base12).
	vim.api.nvim_set_hl(0, "NvAiLoading", { fg = c.base00, bg = c.base09, bold = true })
end
apply_hl()
vim.api.nvim_create_autocmd("ColorScheme", { pattern = "*", callback = apply_hl })

-- ─── State ───────────────────────────────────────────────────────────────────
local enabled = true
local gen = 0 -- bumped on every trigger/movement; in-flight results check it
M._job = nil -- the live vim.system handle, killed when superseded
M._suggestion = nil -- { buf, row(1-based), col(0-based), lines }
M._cooldown_until = nil -- uv.now() timestamp; requests no-op until then
M._warned = {} -- warn-once flags keyed by reason

-- Seed the on/off state from the persisted :NvSinnerMenu value (honours a user
-- who durably disabled it); _reset() overrides this to a known state in tests.
do
	local ok, settings = pcall(require, "core.settings")
	if ok then
		local v = settings.get("ai_complete")
		if type(v) == "boolean" then
			enabled = v
		end
	end
end

-- ─── Notifications ───────────────────────────────────────────────────────────
-- WARN (feature-affecting failures) always passes the `quiet` filter; INFO (an
-- empty completion → "nothing to suggest") is muted only when the user opted into
-- quiet mode, so a manual trigger is never a silent no-op you can't distinguish
-- from a bug.
local function warn(msg)
	vim.notify(msg, vim.log.levels.WARN, { title = "AI completion" })
end

local function info(msg)
	vim.notify(msg, vim.log.levels.INFO, { title = "AI completion" })
end

local function warn_once(reason, msg)
	if M._warned[reason] then
		return
	end
	M._warned[reason] = true
	warn(msg)
end

local function start_cooldown(ms)
	M._cooldown_until = vim.uv.now() + ms
end

function M._cooldown_active()
	return M._cooldown_until ~= nil and vim.uv.now() < M._cooldown_until
end

-- ─── Eligibility ─────────────────────────────────────────────────────────────
local function eligible(buf)
	return vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == "" and vim.bo[buf].modifiable
end

-- Is `row` (1-based) a comment-only line? Used to drive the comment→code flow:
-- when the user triggers on a bare comment like `// create an arrow function`,
-- accept REPLACES the whole line with the suggestion (see accept()) instead of
-- inserting after it. Detection is the buffer's static `commentstring` split on
-- `%s` (this repo has no ts-context-commentstring; plain patterns are house
-- style): the leader is everything before `%s` (`//`, `--`, `#`, `<!--`, …), and
-- a line whose first non-blank run is that leader is comment-only. An empty or
-- `%s`-less commentstring (some filetypes) yields no leader → false (safe).
function M._is_comment_line(buf, row)
	local cs = vim.bo[buf].commentstring
	local leader = vim.trim((cs or ""):match("^(.-)%%s") or "")
	if leader == "" then
		return false
	end
	local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ""
	return vim.startswith(vim.trim(line), leader)
end

-- ─── Ghost text ──────────────────────────────────────────────────────────────
function M.clear(buf)
	if buf and vim.api.nvim_buf_is_valid(buf) then
		vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
	end
	if M._suggestion and (buf == nil or M._suggestion.buf == buf) then
		M._suggestion = nil
	end
end

-- Draw the pending suggestion. `row` is 1-based (cursor convention), `col` is a
-- 0-based byte column. Normally the first line renders inline at the cursor and
-- extra lines render below as virt_lines (copilot-style). When `block` is true
-- (comment-only trigger line — see M.COMMENT_PREVIEW), nothing renders inline and
-- the WHOLE suggestion renders as a dimmed block of virt_lines beneath the line,
-- so the code never glues onto the comment text; accept then replaces the comment
-- with it.
function M.render(buf, row, col, lines, block)
	M.clear(buf)
	if not (lines and #lines > 0) or not vim.api.nvim_buf_is_valid(buf) then
		return
	end
	local row0 = row - 1
	if row0 < 0 or row0 >= vim.api.nvim_buf_line_count(buf) then
		return
	end
	local opts = { hl_mode = "combine" }
	if block then
		local vlines = {}
		for i = 1, #lines do
			vlines[#vlines + 1] = { { lines[i], "NvAiGhost" } }
		end
		opts.virt_lines = vlines
		opts.virt_lines_above = false
	else
		opts.virt_text = { { lines[1], "NvAiGhost" } }
		opts.virt_text_pos = "inline"
		if #lines > 1 then
			local vlines = {}
			for i = 2, #lines do
				vlines[#vlines + 1] = { { lines[i], "NvAiGhost" } }
			end
			opts.virt_lines = vlines
			opts.virt_lines_above = false
		end
	end
	pcall(vim.api.nvim_buf_set_extmark, buf, ns, row0, col, opts)
	M._suggestion = { buf = buf, row = row, col = col, lines = lines }
	-- Repaint now AND once more on the next main-loop tick (nvim-cmp's
	-- misc.redraw(true) discipline). Probed on 0.12.3: insert mode does repaint
	-- scheduled virtual text on its own (copilot.lua/minuet force no redraw at
	-- all), but a single flush inside the same K_EVENT can be held back by the
	-- TUI layer (iTerm2 + 'termsync'/DEC 2026 synchronized output) until the
	-- next keystroke — the ghost then shows only as a flash. The next-tick
	-- flush releases it. valid=false is the `redraw!` analog; win-scoped;
	-- pcall because nvim__redraw is private API (same as ai-activity.lua).
	local win = vim.fn.bufwinid(buf)
	local function repaint()
		if not pcall(vim.api.nvim__redraw, { win = win >= 0 and win or nil, valid = false, flush = true }) then
			pcall(vim.cmd, "redraw!")
		end
	end
	repaint()
	vim.schedule(repaint)
end

-- Accept the pending suggestion, but only if the cursor still sits exactly where
-- it was requested (anchor guard — a drifted suggestion must never inject text
-- at the wrong spot).
function M.accept()
	local s = M._suggestion
	if not s then
		return false
	end
	if not vim.api.nvim_buf_is_valid(s.buf) then
		M.clear(s.buf)
		return false
	end
	local win = vim.api.nvim_get_current_win()
	if vim.api.nvim_win_get_buf(win) ~= s.buf then
		return false
	end
	local cur = vim.api.nvim_win_get_cursor(win)
	if cur[1] ~= s.row or cur[2] ~= s.col then
		M.clear(s.buf)
		return false
	end
	local last = s.lines[#s.lines]
	local new_row, new_col
	if s.comment_replace then
		-- Comment-only trigger line: replace the whole line with the suggestion
		-- (verbatim, no indent injection). Cursor lands at the end of the last
		-- inserted line — the multi-line formula, NOT col + #last (the line was
		-- replaced, not inserted into).
		pcall(vim.api.nvim_buf_set_lines, s.buf, s.row - 1, s.row, false, s.lines)
		new_row, new_col = s.row + #s.lines - 1, #last
	else
		pcall(vim.api.nvim_buf_set_text, s.buf, s.row - 1, s.col, s.row - 1, s.col, s.lines)
		if #s.lines == 1 then
			new_row, new_col = s.row, s.col + #last
		else
			new_row, new_col = s.row + #s.lines - 1, #last
		end
	end
	-- Range of rows the accept just wrote, for the AI-edit wash below (correct for
	-- all three paths: single-line set_text, multi-line set_text, comment
	-- set_lines). Captured before M.clear (which nils M._suggestion).
	local flash_from, flash_to = s.row - 1, s.row - 1 + #s.lines
	M.clear(s.buf)
	pcall(vim.api.nvim_win_set_cursor, win, { new_row, new_col })
	-- Wash the accepted code in the accent, cleared on the first typed letter —
	-- the same "AI wrote this" cue as the AI terminal column (ai-edits.lua).
	local ok_e, edits = pcall(require, "core.ai-edits")
	if ok_e then
		edits.flash(s.buf, flash_from, flash_to)
	end
	return true
end

function M.dismiss()
	M.clear(vim.api.nvim_get_current_buf())
end

function M._pending()
	return M._suggestion
end

-- ─── Loading spinner — a top-right chip while a request is in flight ──────────
-- Self-contained (no notify dependency): a tiny non-focusable float in the
-- top-right corner (where nvim-notify toasts appear), animated by a vim.uv timer
-- with the same braille frames as ai-activity.lua. It tells you "wait, a
-- suggestion is coming" during the endpoint's ~2–4s. Opened with enter=false +
-- noautocmd so it never fires InsertLeave/BufLeave — our own invalidate autocmd
-- listens for those and would cancel the very request we're waiting on. Handle
-- lives on M._spin (module table → durable, so luv won't GC the active timer).
local SPINNER = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local SPIN_MS = 100
M._spin = { win = nil, buf = nil, timer = nil, frame = 1 }

function M._loading_active()
	return M._spin.win ~= nil and vim.api.nvim_win_is_valid(M._spin.win)
end

local function spin_text()
	return " " .. SPINNER[M._spin.frame] .. "  AI completion… "
end

local function spin_draw()
	local sp = M._spin
	if not (sp.buf and vim.api.nvim_buf_is_valid(sp.buf)) then
		return
	end
	pcall(vim.api.nvim_buf_set_lines, sp.buf, 0, -1, false, { spin_text() })
	if sp.win and vim.api.nvim_win_is_valid(sp.win) then
		-- Insert-mode idle needs a forced flush (same TUI/termsync reason as render).
		if not pcall(vim.api.nvim__redraw, { win = sp.win, flush = true }) then
			pcall(vim.cmd, "redraw")
		end
	end
end

function M._loading_stop()
	local sp = M._spin
	if sp.timer then
		pcall(function()
			sp.timer:stop()
			sp.timer:close()
		end)
		sp.timer = nil
	end
	if sp.win and vim.api.nvim_win_is_valid(sp.win) then
		pcall(vim.api.nvim_win_close, sp.win, true)
	end
	if sp.buf and vim.api.nvim_buf_is_valid(sp.buf) then
		pcall(vim.api.nvim_buf_delete, sp.buf, { force = true })
	end
	sp.win, sp.buf, sp.timer = nil, nil, nil
end

function M._loading_start()
	M._loading_stop() -- idempotent restart
	local sp = M._spin
	sp.frame = 1
	sp.buf = vim.api.nvim_create_buf(false, true)
	vim.bo[sp.buf].bufhidden = "wipe"
	pcall(vim.api.nvim_buf_set_lines, sp.buf, 0, -1, false, { spin_text() })
	local ok, win = pcall(vim.api.nvim_open_win, sp.buf, false, {
		relative = "editor",
		anchor = "NE",
		row = 1,
		col = math.max(1, vim.o.columns - 1),
		width = vim.fn.strdisplaywidth(spin_text()),
		height = 1,
		style = "minimal",
		focusable = false,
		noautocmd = true,
		zindex = 200,
		border = "none",
	})
	if not ok then
		M._loading_stop()
		return
	end
	sp.win = win
	vim.wo[sp.win].winhighlight = "Normal:NvAiLoading,NormalNC:NvAiLoading"
	spin_draw()
	sp.timer = vim.uv.new_timer()
	sp.timer:start(
		SPIN_MS,
		SPIN_MS,
		vim.schedule_wrap(function()
			if not M._loading_active() then
				return
			end
			sp.frame = sp.frame % #SPINNER + 1
			spin_draw()
		end)
	)
end

-- ─── Context + request builders (pure, unit-tested directly) ─────────────────
-- FIM context, minuet-ai / Copilot shape: take the WHOLE file on each side of
-- the cursor, then fit it into CONTEXT_WINDOW split by CONTEXT_RATIO. Char-based
-- (strchars/strcharpart) so multibyte code isn't cut mid-codepoint. When the
-- file overflows the budget, keep the cursor-adjacent part — the prefix's tail,
-- the suffix's head — favouring whichever side is short (so a cursor near the top
-- still gets lots of suffix, and vice versa).
function M._build_context(buf, row, col)
	-- row: 1-based cursor row · col: 0-based byte column
	local total = vim.api.nvim_buf_line_count(buf)
	local cur = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ""
	local before = cur:sub(1, col)
	local after = cur:sub(col + 1)

	local above = vim.api.nvim_buf_get_lines(buf, 0, row - 1, false)
	local prefix = table.concat(above, "\n")
	if #above > 0 then
		prefix = prefix .. "\n"
	end
	prefix = prefix .. before

	local below = vim.api.nvim_buf_get_lines(buf, row, total, false)
	local suffix = after
	if #below > 0 then
		suffix = suffix .. "\n" .. table.concat(below, "\n")
	end

	-- Budget the combined context, prefix favoured by CONTEXT_RATIO.
	local win = M.CONTEXT_WINDOW
	local ratio = M.CONTEXT_RATIO
	local nb = vim.fn.strchars(prefix)
	local na = vim.fn.strchars(suffix)
	if nb + na > win then
		if nb < win * ratio then
			-- Prefix fits; give the rest of the budget to the suffix.
			suffix = vim.fn.strcharpart(suffix, 0, win - nb)
		elseif na < win * (1 - ratio) then
			-- Suffix fits; give the rest of the budget to the prefix (keep its tail).
			prefix = vim.fn.strcharpart(prefix, nb + na - win)
		else
			-- Cursor mid-file: split by the ratio, keep prefix tail + suffix head.
			suffix = vim.fn.strcharpart(suffix, 0, math.floor(win * (1 - ratio)))
			prefix = vim.fn.strcharpart(prefix, nb - math.floor(win * ratio))
		end
	end

	local name = vim.api.nvim_buf_get_name(buf)
	local relpath = name ~= "" and vim.fn.fnamemodify(name, ":.") or "[No Name]"
	return { prefix = prefix, suffix = suffix, filetype = vim.bo[buf].filetype, relpath = relpath }
end

function M._build_messages(ctx)
	local system = table.concat({
		"You are a code completion engine embedded in a text editor.",
		"Continue the code exactly at the <CURSOR> marker.",
		"Return ONLY the raw characters to insert at the cursor —",
		"no explanation, no surrounding code, and no markdown code fences.",
	}, " ")
	local user = table.concat({
		("Language: %s"):format((ctx.filetype ~= "" and ctx.filetype) or "plain"),
		("File: %s"):format(ctx.relpath),
		"Insert code where <CURSOR> is, given the code before (<PREFIX>) and after (<SUFFIX>).",
		"<PREFIX>",
		ctx.prefix,
		"<CURSOR>",
		"<SUFFIX>",
		ctx.suffix,
	}, "\n")
	return {
		{ role = "system", content = system },
		{ role = "user", content = user },
	}
end

function M._build_payload(ctx, model)
	return {
		model = model,
		messages = M._build_messages(ctx),
		max_tokens = M.MAX_TOKENS,
		temperature = M.TEMPERATURE,
		stream = false,
	}
end

-- Strip a wrapping ```lang … ``` fence the model may add despite instructions.
local function strip_fence(s)
	local lines = vim.split(s, "\n", { plain = true })
	if #lines >= 2 and lines[1]:match("^```") then
		table.remove(lines, 1)
		if lines[#lines] and lines[#lines]:match("^```%s*$") then
			table.remove(lines, #lines)
		end
		return table.concat(lines, "\n")
	end
	return s
end

-- Pull the completion text out of an OpenAI-shaped chat/completions body.
function M._extract(body)
	if type(body) ~= "table" then
		return nil
	end
	local choices = body.choices
	if type(choices) ~= "table" or not choices[1] then
		return nil
	end
	local content = choices[1].message and choices[1].message.content
	if type(content) ~= "string" then
		content = choices[1].text -- some gateways use the legacy shape
	end
	if type(content) ~= "string" then
		return nil
	end
	content = strip_fence(vim.trim(content))
	if content == "" then
		return nil
	end
	return content
end

-- ─── HTTP (curl via vim.system) — the ONE network seam ───────────────────────
-- Classify a completed curl run into the { kind, status, text } envelope the
-- dispatcher switches on. `-w "\n%{http_code}"` appends the status on the final
-- line, so the body is everything before the last "\n<3 digits>".
function M._classify(res)
	if res.signal and res.signal ~= 0 then
		return { ok = false, kind = "killed" } -- superseded by :kill
	end
	if res.code == 28 then
		return { ok = false, kind = "timeout" }
	end
	if res.code ~= 0 then
		return { ok = false, kind = "curl" } -- transport / DNS / offline
	end
	local out = res.stdout or ""
	local body, status_str = out:match("^(.*)\n(%d%d%d)%s*$")
	local status = tonumber(status_str)
	if not status then
		return { ok = false, kind = "parse" }
	end
	if status == 401 or status == 403 then
		return { ok = false, kind = "auth", status = status }
	end
	if status == 429 then
		return { ok = false, kind = "rate", status = status }
	end
	if status < 200 or status >= 300 then
		return { ok = false, kind = "http", status = status }
	end
	local decoded_ok, decoded = pcall(vim.json.decode, body or "")
	if not decoded_ok or type(decoded) ~= "table" then
		return { ok = false, kind = "parse", status = status }
	end
	local text = M._extract(decoded)
	if not text then
		return { ok = false, kind = "empty", status = status }
	end
	return { ok = true, kind = "ok", status = status, text = text }
end

function M._request(payload, on_done)
	if vim.fn.executable("curl") == 0 then
		on_done({ ok = false, kind = "nocurl" })
		return
	end
	local key = M._api_key() or ""
	local body = vim.json.encode(payload)
	local argv = {
		"curl",
		"-sS",
		"-X",
		"POST",
		"--connect-timeout",
		"3",
		"--max-time",
		tostring(M.TIMEOUT_S),
		"-H",
		"Content-Type: application/json",
		"-H",
		"Authorization: Bearer " .. key,
		"-w",
		"\n%{http_code}",
		"--data-binary",
		"@-", -- body on stdin: the prompt never appears in argv (the key still
		-- does, via the -H flag above — visible to `ps` on this process only)
		M.endpoint(),
	}
	local ok, handle = pcall(
		vim.system,
		argv,
		{ stdin = body, text = true },
		vim.schedule_wrap(function(res)
			on_done(M._classify(res))
		end)
	)
	if ok then
		M._job = handle
	else
		on_done({ ok = false, kind = "curl" })
	end
end

-- Fetch the Go-plan model catalogue (GET {base}/models) so :NvSinnerIA can offer
-- the live list. Async curl, result cached for the session. on_done(ids | nil) —
-- nil when there's no key, no curl, or the request fails (the picker then falls
-- back to M.SAFE_MODELS). Called by table field so the spec can swap it.
M._models_cache = nil
function M.fetch_models(on_done)
	if M._models_cache then
		on_done(M._models_cache)
		return
	end
	if vim.fn.executable("curl") == 0 or not M._api_key() then
		on_done(nil)
		return
	end
	local base = (M.endpoint():gsub("/chat/completions%s*$", ""))
	local argv = {
		"curl",
		"-sS",
		"-X",
		"GET",
		"--connect-timeout",
		"3",
		"--max-time",
		"10",
		"-H",
		"Authorization: Bearer " .. M._api_key(),
		base .. "/models",
	}
	local ok = pcall(
		vim.system,
		argv,
		{ text = true },
		vim.schedule_wrap(function(res)
			if res.code ~= 0 or type(res.stdout) ~= "string" then
				on_done(nil)
				return
			end
			local decoded_ok, decoded = pcall(vim.json.decode, res.stdout)
			if not decoded_ok or type(decoded) ~= "table" or type(decoded.data) ~= "table" then
				on_done(nil)
				return
			end
			local ids = {}
			for _, m in ipairs(decoded.data) do
				if type(m) == "table" and type(m.id) == "string" then
					ids[#ids + 1] = m.id
				end
			end
			if #ids == 0 then
				on_done(nil)
				return
			end
			M._models_cache = ids -- server order preserved; :NvSinnerIA sorts recommended first
			on_done(ids)
		end)
	)
	if not ok then
		on_done(nil)
	end
end

local function cancel_job()
	if M._job then
		pcall(function()
			M._job:kill(15)
		end)
		M._job = nil
	end
end

-- ─── Orchestration ───────────────────────────────────────────────────────────
function M.trigger()
	if not enabled or M._cooldown_active() then
		return
	end
	local buf = vim.api.nvim_get_current_buf()
	if not eligible(buf) then
		return
	end
	if not M._api_key() then
		warn_once(
			"no_key",
			"AI completion is served by OpenCode Zen (the only supported provider) and needs "
				.. '$OPENCODE_API_KEY — add `export OPENCODE_API_KEY="…"` to your ~/.zshrc '
				.. "(or shell profile) and restart the terminal."
		)
		return
	end
	local win = vim.api.nvim_get_current_win()
	if vim.api.nvim_win_get_buf(win) ~= buf then
		return
	end
	local cursor = vim.api.nvim_win_get_cursor(win)
	local row, col = cursor[1], cursor[2]
	local ctx = M._build_context(buf, row, col)
	local anchor = { buf = buf, row = row, col = col }
	-- Trigger line is a bare comment → accept replaces it with the suggestion.
	local comment_replace = M._is_comment_line(buf, row)

	cancel_job()
	gen = gen + 1
	local this_gen = gen

	local function dispatch(result, is_fallback)
		if result.kind == "killed" or this_gen ~= gen then
			return -- superseded (a newer trigger owns the spinner now — don't touch it)
		end
		-- The request settled. A 429-with-fallback re-fires, so keep spinning
		-- through the retry; every other outcome is terminal → stop the spinner.
		if not (result.kind == "rate" and fallback_model() and not is_fallback) then
			M._loading_stop()
		end
		local kind = result.kind
		if kind == "ok" then
			local block = comment_replace and M.COMMENT_PREVIEW == "below"
			M.render(anchor.buf, anchor.row, anchor.col, vim.split(result.text, "\n", { plain = true }), block)
			-- render() rebuilds M._suggestion wholesale, so tag it AFTER: accept
			-- reads this to decide replace-the-comment vs insert-at-cursor.
			if M._suggestion then
				M._suggestion.comment_replace = comment_replace
			end
		elseif kind == "empty" then
			-- A blank completion isn't an error, but silence looks like a bug on a
			-- manual trigger — tell the user, INFO so `quiet` can still mute it.
			info("AI completion: nothing to suggest.")
		elseif kind == "nocurl" then
			warn_once("nocurl", "curl not found on PATH — AI completion needs curl.")
		elseif kind == "timeout" then
			warn("AI completion timed out.")
		elseif kind == "curl" then
			warn("AI completion: network error.")
		elseif kind == "auth" then
			warn("AI completion: auth failed — check $OPENCODE_API_KEY.")
			start_cooldown(M.AUTH_COOLDOWN_MS)
		elseif kind == "rate" then
			local fb = fallback_model()
			if fb and not is_fallback then
				M._request(M._build_payload(ctx, fb), function(r)
					dispatch(r, true)
				end)
				return
			end
			warn(
				("AI completion: usage limit reached — paused for %d min."):format(
					math.floor(M.RATE_COOLDOWN_MS / 60000)
				)
			)
			start_cooldown(M.RATE_COOLDOWN_MS)
		elseif kind == "http" then
			warn("AI completion: HTTP " .. tostring(result.status) .. ".")
		else -- "parse" / unknown
			warn("AI completion: unexpected response.")
		end
	end

	M._loading_start() -- "a suggestion is coming" chip; stopped in dispatch/invalidate
	M._request(M._build_payload(ctx, M.model()), function(r)
		dispatch(r, false)
	end)
end

-- ─── Enable / toggle ─────────────────────────────────────────────────────────
function M.enabled()
	return enabled
end

function M.set_enabled(v)
	enabled = v and true or false
	if not enabled then
		M._loading_stop()
		for _, b in ipairs(vim.api.nvim_list_bufs()) do
			M.clear(b)
		end
	end
end

function M.toggle()
	M.set_enabled(not enabled)
	pcall(function()
		require("core.settings").set("ai_complete", enabled) -- persist the choice
	end)
	vim.notify("AI completion " .. (enabled and "on" or "off"), vim.log.levels.INFO, { timeout = 250 })
end

-- ─── Autocmds: any movement / edit / mode change invalidates the ghost ───────
local function invalidate(buf)
	gen = gen + 1
	cancel_job()
	M._loading_stop() -- a request in flight is now orphaned; drop its spinner too
	M.clear(buf)
end

local grp = vim.api.nvim_create_augroup("nv_ai_complete", { clear = true })
vim.api.nvim_create_autocmd({ "CursorMovedI", "TextChangedI", "InsertLeave", "BufLeave" }, {
	group = grp,
	callback = function(args)
		invalidate(args.buf)
	end,
})

-- ─── Trigger — <C-l> (insert) + :NvSinnerComplete ────────────────────────────
-- A single insert-mode chord requests a suggestion at the cursor while you type.
-- <C-l> instead of <C-g>: <C-g> was terminal-fragile (a stray Ctrl-Shift-G
-- inserts a literal "G"), <C-l> has no insert-mode default and survives every
-- terminal. :NvSinnerComplete is the same request as a command (testing /
-- discoverability); it takes no keymap of its own.
vim.api.nvim_create_user_command("NvSinnerComplete", M.trigger, {
	desc = "Request AI inline completion at the cursor (ghost text)",
})
vim.keymap.set("i", "<C-l>", "<Cmd>lua require('core.ai-complete').trigger()<CR>", {
	silent = true,
	desc = "Request AI completion (ghost text)",
})

-- ─── Accept / dismiss (insert mode) — coexists with nvim-cmp (<Tab> is free) ──
-- <Tab>: accept the ghost ONLY when a suggestion is pending and cmp's popup is
-- not up; otherwise fall through to a literal Tab (built-in indent behaviour).
-- The mutation runs via <Cmd> so it's outside expr textlock. cmp here uses
-- cmp.mapping.preset.insert, which does not map <Tab>, so overloading it is safe.
vim.keymap.set("i", "<Tab>", function()
	local ok, cmp = pcall(require, "cmp")
	if (not ok or not cmp.visible()) and require("core.ai-complete")._pending() then
		return "<Cmd>lua require('core.ai-complete').accept()<CR>"
	end
	return "<Tab>"
end, { expr = true, replace_keycodes = true, desc = "Accept AI ghost text / Tab" })

vim.keymap.set("i", "<C-]>", "<Cmd>lua require('core.ai-complete').dismiss()<CR>", {
	silent = true,
	desc = "Dismiss AI ghost text",
})

vim.api.nvim_create_user_command("NvSinnerCompleteToggle", M.toggle, {
	desc = "Toggle inline AI completion (ghost text)",
})

-- Test seam: drop all state between specs.
function M._reset()
	gen = gen + 1
	cancel_job()
	M._loading_stop()
	M._suggestion = nil
	M._cooldown_until = nil
	M._warned = {}
	M._models_cache = nil
	enabled = true
end

return M
