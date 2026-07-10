-- Tests for native inline AI completion (lua/core/ai-complete.lua): the pure
-- context/payload/extract builders, the curl-result classifier, the NvAiGhost
-- carbon group, and the trigger→ghost / accept / error-and-fallback flow. The
-- network is NEVER touched — every request path goes through the swapped
-- M._request seam (restored before asserting so a failure can't leak the stub),
-- and the no-key / cooldown guards short-circuit before any spawn.

local ai = require("core.ai-complete")

describe("core.ai-complete", function()
	before_each(function()
		ai._reset()
		vim.env.OPENCODE_API_KEY = nil
		vim.env.OPENCODE_FALLBACK_MODEL = nil
	end)

	-- A normal, editable buffer with the cursor on an empty line (col 0 is always
	-- valid, so no normal-mode end-of-line clamping muddies the anchor).
	local function scratch(lines, cursor)
		local buf = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_set_current_buf(buf)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		vim.api.nvim_win_set_cursor(0, cursor)
		return buf
	end

	local function fresh_buf()
		return scratch({ "x", "" }, { 2, 0 })
	end

	-- ─── Pure builders ─────────────────────────────────────────────────────────

	it("_build_context splits prefix and suffix around the cursor", function()
		local buf = scratch({ "local a = 1", "local b = ", "return a" }, { 2, 10 })
		local ctx = ai._build_context(buf, 2, 10) -- row 2, col 10 = end of "local b = "
		assert.is_truthy(ctx.prefix:find("local a = 1", 1, true), "prefix keeps the line above")
		assert.are.equal("local b = ", ctx.prefix:sub(-10), "prefix ends exactly at the cursor")
		assert.is_truthy(ctx.suffix:find("return a", 1, true), "suffix keeps the line below")
		vim.api.nvim_buf_delete(buf, { force = true })
	end)

	it("_build_context includes imports far above the cursor (whole-file FIM)", function()
		-- The old fixed 60-line window dropped the imports once the cursor was far
		-- enough below them; the FIM budget keeps the whole file (well under the
		-- 16000-char window), so a require on line 1 still reaches the model.
		local lines = { 'local special = require("core.special_marker")' }
		for i = 2, 140 do
			lines[i] = "local x" .. i .. " = " .. i
		end
		lines[141] = "return "
		local buf = scratch(lines, { 141, 7 })
		local ctx = ai._build_context(buf, 141, 7)
		assert.is_truthy(ctx.prefix:find("core.special_marker", 1, true), "import 140 lines up must survive")
		vim.api.nvim_buf_delete(buf, { force = true })
	end)

	it("_build_context budgets by CONTEXT_RATIO when the file overflows the window", function()
		local pw, pr = ai.CONTEXT_WINDOW, ai.CONTEXT_RATIO
		ai.CONTEXT_WINDOW, ai.CONTEXT_RATIO = 100, 0.75
		local lines = {}
		for _ = 1, 50 do
			lines[#lines + 1] = "AAAAA"
		end
		lines[#lines + 1] = "CURSORLINE"
		for _ = 1, 50 do
			lines[#lines + 1] = "ZZZZZ"
		end
		local buf = scratch(lines, { 51, 10 })
		local ctx = ai._build_context(buf, 51, 10)
		local total = vim.fn.strchars(ctx.prefix) + vim.fn.strchars(ctx.suffix)
		assert.is_true(total <= 100, "combined context must fit the window, got " .. total)
		assert.are.equal("CURSORLINE", ctx.prefix:sub(-10), "prefix keeps the cursor-adjacent tail")
		assert.is_true(vim.fn.strchars(ctx.prefix) > vim.fn.strchars(ctx.suffix), "the ratio favours the prefix (3:1)")
		ai.CONTEXT_WINDOW, ai.CONTEXT_RATIO = pw, pr
		vim.api.nvim_buf_delete(buf, { force = true })
	end)

	it("_build_payload carries the model, no streaming, and system+user messages", function()
		local ctx = { prefix = "PFX", suffix = "SFX", filetype = "lua", relpath = "x.lua" }
		local p = ai._build_payload(ctx, "deepseek-v4-flash")
		assert.are.equal("deepseek-v4-flash", p.model)
		assert.is_false(p.stream)
		assert.are.equal(2, #p.messages)
		assert.are.equal("system", p.messages[1].role)
		assert.are.equal("user", p.messages[2].role)
		assert.is_truthy(p.messages[2].content:find("<PREFIX>", 1, true))
		assert.is_truthy(p.messages[2].content:find("<CURSOR>", 1, true))
		assert.is_truthy(p.messages[2].content:find("PFX", 1, true))
	end)

	it("_extract pulls the content and strips a code fence", function()
		assert.are.equal("foo()", ai._extract({ choices = { { message = { content = "foo()" } } } }))
		assert.are.equal("foo()", ai._extract({ choices = { { message = { content = "```lua\nfoo()\n```" } } } }))
		assert.is_nil(ai._extract({ choices = {} }))
		assert.is_nil(ai._extract({ choices = { { message = { content = "   " } } } }))
	end)

	it("_classify maps curl output (status/signal) to result kinds", function()
		assert.are.equal("timeout", ai._classify({ code = 28, stdout = "" }).kind)
		assert.are.equal("curl", ai._classify({ code = 6, stdout = "" }).kind)
		assert.are.equal("killed", ai._classify({ code = 0, signal = 15, stdout = "" }).kind)
		assert.are.equal("auth", ai._classify({ code = 0, stdout = "{}\n401" }).kind)
		assert.are.equal("rate", ai._classify({ code = 0, stdout = "{}\n429" }).kind)
		assert.are.equal("http", ai._classify({ code = 0, stdout = "{}\n500" }).kind)
		assert.are.equal("parse", ai._classify({ code = 0, stdout = "not json\n200" }).kind)
		assert.are.equal("empty", ai._classify({ code = 0, stdout = '{"choices":[]}\n200' }).kind)
		local okr = ai._classify({ code = 0, stdout = '{"choices":[{"message":{"content":"hi"}}]}\n200' })
		assert.are.equal("ok", okr.kind)
		assert.are.equal("hi", okr.text)
	end)

	-- ─── Highlight ─────────────────────────────────────────────────────────────

	it("defines the NvAiGhost comment-tone highlight from carbon base03", function()
		-- Re-apply against the CURRENT theme so the assertion is independent of
		-- whatever theme the ambient state resolved to at module-load time.
		vim.api.nvim_exec_autocmds("ColorScheme", { pattern = "carbon" })
		local hl = vim.api.nvim_get_hl(0, { name = "NvAiGhost" })
		assert.is_not_nil(hl.fg, "ghost text needs a muted fg")
		assert.is_true(hl.italic == true, "ghost text reads as an aside — italic")
		local c = require("core.carbon").colors()
		assert.are.equal(tonumber(c.base03:sub(2), 16), hl.fg, "must use the carbon comment role")
	end)

	-- ─── Trigger → ghost → accept (via the swapped seam, no network) ────────────

	it("renders ghost text on a successful completion", function()
		vim.env.OPENCODE_API_KEY = "test-key"
		local buf = scratch({ "local x =", "" }, { 2, 0 })
		local orig = ai._request
		ai._request = function(_, done)
			done({ ok = true, kind = "ok", status = 200, text = "return 1" })
		end
		ai.trigger()
		ai._request = orig
		vim.env.OPENCODE_API_KEY = nil

		local marks = vim.api.nvim_buf_get_extmarks(buf, ai._ns, 0, -1, { details = true })
		assert.is_true(#marks > 0, "a ghost extmark should be present")
		assert.is_not_nil(ai._pending())
		assert.are.equal("return 1", ai._pending().lines[1])
		vim.api.nvim_buf_delete(buf, { force = true })
	end)

	it("accept() inserts the pending suggestion and clears the ghost", function()
		vim.env.OPENCODE_API_KEY = "k"
		local buf = scratch({ "local x =", "" }, { 2, 0 })
		local orig = ai._request
		ai._request = function(_, done)
			done({ ok = true, kind = "ok", status = 200, text = "return 1" })
		end
		ai.trigger()
		ai._request = orig
		vim.env.OPENCODE_API_KEY = nil

		ai.accept()
		assert.are.same({ "local x =", "return 1" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
		assert.are.equal(0, #vim.api.nvim_buf_get_extmarks(buf, ai._ns, 0, -1, {}))
		assert.is_nil(ai._pending())
		vim.api.nvim_buf_delete(buf, { force = true })
	end)

	-- ─── Comment-only trigger line → replace on accept + AI wash ────────────────

	it("_is_comment_line detects comment-only lines via commentstring", function()
		local buf = scratch({ "// make add", "const x = 1", "" }, { 1, 0 })
		vim.bo[buf].commentstring = "// %s"
		assert.is_true(ai._is_comment_line(buf, 1), "a bare // line is comment-only")
		assert.is_false(ai._is_comment_line(buf, 2), "real code is not a comment line")
		vim.bo[buf].commentstring = ""
		assert.is_false(ai._is_comment_line(buf, 1), "no commentstring → never a comment line")
		vim.api.nvim_buf_delete(buf, { force = true })
	end)

	it("accept() on a comment-only line replaces the comment with the suggestion", function()
		vim.env.OPENCODE_API_KEY = "k"
		local buf = scratch({ "// make add", "" }, { 1, 0 })
		vim.bo[buf].commentstring = "// %s"
		local orig = ai._request
		ai._request = function(_, done)
			done({ ok = true, kind = "ok", status = 200, text = "const add = (a, b) => a + b" })
		end
		ai.trigger()
		ai._request = orig
		vim.env.OPENCODE_API_KEY = nil

		assert.is_not_nil(ai._pending())
		assert.is_true(ai._pending().comment_replace, "the comment line is tagged for replacement")
		ai.accept()
		-- The comment is GONE (replaced), not appended to.
		assert.are.same({ "const add = (a, b) => a + b", "" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
		assert.is_nil(ai._pending())
		vim.api.nvim_buf_delete(buf, { force = true })
	end)

	it("accept() washes the accepted rows (ai-edits) and clears on the first edit", function()
		local edits = require("core.ai-edits")
		edits._reset()
		vim.env.OPENCODE_API_KEY = "k"
		local buf = scratch({ "local x =", "" }, { 2, 0 })
		local orig = ai._request
		ai._request = function(_, done)
			done({ ok = true, kind = "ok", status = 200, text = "return 1" })
		end
		ai.trigger()
		ai._request = orig
		vim.env.OPENCODE_API_KEY = nil

		ai.accept()
		assert.is_true(
			#vim.api.nvim_buf_get_extmarks(buf, edits._ns, 0, -1, {}) > 0,
			"the accepted code is washed in the AI accent (reusing ai-edits)"
		)

		-- arm_clear is scheduled one tick late; wait for the buffer-local group,
		-- then a typed letter (TextChangedI) must wipe the wash.
		local armed = vim.wait(1000, function()
			return #vim.api.nvim_get_autocmds({ event = "CursorMoved", buffer = buf }) > 0
		end, 20)
		assert.is_true(armed, "the wash's take-over autocmds must arm after accept")
		vim.api.nvim_exec_autocmds("TextChangedI", { buffer = buf })
		assert.are.equal(
			0,
			#vim.api.nvim_buf_get_extmarks(buf, edits._ns, 0, -1, {}),
			"typing the first letter clears the wash"
		)
		vim.api.nvim_buf_delete(buf, { force = true })
	end)

	-- ─── Errors + fallback ─────────────────────────────────────────────────────

	it("a 429 warns once, sets a cooldown, and the next trigger no-ops", function()
		vim.env.OPENCODE_API_KEY = "k"
		local buf = fresh_buf()
		local calls = 0
		local orig = ai._request
		ai._request = function(_, done)
			calls = calls + 1
			done({ ok = false, kind = "rate", status = 429 })
		end
		local warns, onote = {}, vim.notify
		vim.notify = function(msg, level)
			warns[#warns + 1] = { msg = msg, level = level }
		end
		ai.trigger()
		local cooled = ai._cooldown_active()
		ai.trigger() -- cooldown must block a second request
		vim.notify = onote
		ai._request = orig
		vim.env.OPENCODE_API_KEY = nil

		assert.are.equal(1, calls, "the cooldown must block the second request")
		assert.is_true(cooled)
		assert.are.equal(1, #warns)
		assert.are.equal(vim.log.levels.WARN, warns[1].level)
		vim.api.nvim_buf_delete(buf, { force = true })
	end)

	it("a 429 retries once with $OPENCODE_FALLBACK_MODEL when set", function()
		vim.env.OPENCODE_API_KEY = "k"
		vim.env.OPENCODE_FALLBACK_MODEL = "free-model"
		local buf = scratch({ "a", "" }, { 2, 0 })
		local models = {}
		local orig = ai._request
		ai._request = function(payload, done)
			models[#models + 1] = payload.model
			if #models == 1 then
				done({ ok = false, kind = "rate", status = 429 })
			else
				done({ ok = true, kind = "ok", status = 200, text = "42" })
			end
		end
		ai.trigger()
		ai._request = orig
		vim.env.OPENCODE_API_KEY = nil

		assert.are.equal(2, #models, "a 429 with a fallback model retries once")
		assert.are.equal("free-model", models[2])
		assert.is_not_nil(ai._pending(), "the fallback completion renders")
		vim.api.nvim_buf_delete(buf, { force = true })
	end)

	it("a 401 warns about the key and sets a cooldown", function()
		vim.env.OPENCODE_API_KEY = "bad"
		local buf = fresh_buf()
		local orig = ai._request
		ai._request = function(_, done)
			done({ ok = false, kind = "auth", status = 401 })
		end
		local warns, onote = {}, vim.notify
		vim.notify = function(msg)
			warns[#warns + 1] = msg
		end
		ai.trigger()
		vim.notify = onote
		ai._request = orig
		vim.env.OPENCODE_API_KEY = nil

		assert.are.equal(1, #warns)
		assert.is_truthy(warns[1]:find("OPENCODE_API_KEY", 1, true))
		assert.is_true(ai._cooldown_active())
		vim.api.nvim_buf_delete(buf, { force = true })
	end)

	it("a timeout warns and paints no ghost", function()
		vim.env.OPENCODE_API_KEY = "k"
		local buf = fresh_buf()
		local orig = ai._request
		ai._request = function(_, done)
			done({ ok = false, kind = "timeout" })
		end
		local warns, onote = {}, vim.notify
		vim.notify = function(msg)
			warns[#warns + 1] = msg
		end
		ai.trigger()
		vim.notify = onote
		ai._request = orig
		vim.env.OPENCODE_API_KEY = nil

		assert.are.equal(1, #warns)
		assert.are.equal(0, #vim.api.nvim_buf_get_extmarks(buf, ai._ns, 0, -1, {}))
		vim.api.nvim_buf_delete(buf, { force = true })
	end)

	it("with no API key it warns once and never calls _request", function()
		vim.env.OPENCODE_API_KEY = nil
		local buf = fresh_buf()
		local calls = 0
		local orig = ai._request
		ai._request = function()
			calls = calls + 1
		end
		local warns, onote = {}, vim.notify
		vim.notify = function(msg)
			warns[#warns + 1] = msg
		end
		ai.trigger()
		ai.trigger()
		vim.notify = onote
		ai._request = orig

		assert.are.equal(0, calls, "no request may fire without a key")
		assert.are.equal(1, #warns, "warns once, then stays quiet")
		vim.api.nvim_buf_delete(buf, { force = true })
	end)

	it("an empty completion emits an INFO toast and paints no ghost", function()
		vim.env.OPENCODE_API_KEY = "k"
		local buf = fresh_buf()
		local orig = ai._request
		ai._request = function(_, done)
			done({ ok = false, kind = "empty", status = 200 })
		end
		local notes, onote = {}, vim.notify
		vim.notify = function(msg, level)
			notes[#notes + 1] = { msg = msg, level = level }
		end
		ai.trigger()
		vim.notify = onote
		ai._request = orig
		vim.env.OPENCODE_API_KEY = nil

		-- A blank completion is no longer silent (silence read as a bug on a manual
		-- trigger); it's an INFO toast so `quiet` can still mute it if the user opted in.
		assert.are.equal(1, #notes, "an empty result tells the user")
		assert.are.equal(vim.log.levels.INFO, notes[1].level, "INFO so quiet mode can mute it")
		assert.is_truthy(notes[1].msg:find("nothing to suggest", 1, true))
		assert.are.equal(0, #vim.api.nvim_buf_get_extmarks(buf, ai._ns, 0, -1, {}))
		vim.api.nvim_buf_delete(buf, { force = true })
	end)

	-- ─── Loading spinner (in-flight UI state) ───────────────────────────────────

	it("defines the NvAiLoading accent chip from carbon base09", function()
		vim.api.nvim_exec_autocmds("ColorScheme", { pattern = "carbon" })
		local hl = vim.api.nvim_get_hl(0, { name = "NvAiLoading" })
		assert.is_not_nil(hl.bg, "the loading chip needs a solid bg")
		assert.is_not_nil(hl.fg, "the loading chip needs a fg")
		local c = require("core.carbon").colors()
		assert.are.equal(tonumber(c.base09:sub(2), 16), hl.bg, "chip bg is the identity accent")
	end)

	it("shows the spinner while the request is in flight, then clears it on success", function()
		vim.env.OPENCODE_API_KEY = "k"
		local buf = scratch({ "local x =", "" }, { 2, 0 })
		local held
		local orig = ai._request
		ai._request = function(_, done)
			held = done -- hold the callback so the request is "in flight"
		end
		ai.trigger()
		assert.is_true(ai._loading_active(), "the spinner shows while waiting")
		held({ ok = true, kind = "ok", status = 200, text = "return 1" })
		assert.is_false(ai._loading_active(), "the spinner clears when the result lands")
		assert.is_not_nil(ai._pending(), "and the ghost is shown")
		ai._request = orig
		vim.env.OPENCODE_API_KEY = nil
		vim.api.nvim_buf_delete(buf, { force = true })
	end)

	it("clears the spinner on an error result", function()
		vim.env.OPENCODE_API_KEY = "k"
		local buf = fresh_buf()
		local held
		local orig = ai._request
		ai._request = function(_, done)
			held = done
		end
		local onote = vim.notify
		vim.notify = function() end -- swallow the warn
		ai.trigger()
		assert.is_true(ai._loading_active())
		held({ ok = false, kind = "timeout" })
		assert.is_false(ai._loading_active(), "an error result also stops the spinner")
		vim.notify = onote
		ai._request = orig
		vim.env.OPENCODE_API_KEY = nil
		vim.api.nvim_buf_delete(buf, { force = true })
	end)

	it("cancels the spinner when the cursor moves while waiting", function()
		vim.env.OPENCODE_API_KEY = "k"
		local buf = fresh_buf()
		local orig = ai._request
		ai._request = function() end -- never completes
		ai.trigger()
		assert.is_true(ai._loading_active())
		vim.api.nvim_exec_autocmds("TextChangedI", { buffer = buf }) -- user keeps typing
		assert.is_false(ai._loading_active(), "movement/edit orphans the request and drops the spinner")
		ai._request = orig
		vim.env.OPENCODE_API_KEY = nil
		vim.api.nvim_buf_delete(buf, { force = true })
	end)

	-- ─── Real-grid paint (regression: "extmark exists but never shows") ────────

	it("paints the ghost on the rendered grid while idle in insert mode", function()
		-- Extmark existence can't catch a paint/flush regression, so this spec
		-- reads the REAL grid: a child nvim runs as a TUI inside a terminal
		-- buffer (PTY → libvterm) and we assert the ghost text — rendered from a
		-- scheduled callback while the child sits blocked on input in insert
		-- mode — actually reaches the screen.
		local minimal_init = vim.api.nvim_get_runtime_file("tests/minimal_init.lua", false)[1]
		assert.is_truthy(minimal_init, "minimal_init must be resolvable from the rtp")
		local child = table.concat({
			'vim.api.nvim_buf_set_lines(0,0,-1,false,{"local x ="})',
			"vim.api.nvim_win_set_cursor(0,{1,9})",
			'vim.cmd("startinsert!")',
			"vim.defer_fn(function()",
			'  local ai = require("core.ai-complete")',
			"  ai._reset()",
			'  vim.env.OPENCODE_API_KEY = "k"',
			"  ai._request = function(_, done)",
			"    vim.defer_fn(function()",
			'      done({ ok = true, kind = "ok", status = 200, text = "GHOST_PAINTED_OK" })',
			"    end, 300)",
			"  end",
			"  ai.trigger()",
			"end, 400)",
		}, " ")
		vim.cmd("enew")
		local term_buf = vim.api.nvim_get_current_buf()
		local job = vim.fn.jobstart(
			{ vim.v.progpath, "-u", minimal_init, "-i", "NONE", "-n", "-c", "lua " .. child },
			{ term = true }
		)
		assert.is_true(job > 0, "the child nvim must start")
		local function grid_has(needle)
			for _, l in ipairs(vim.api.nvim_buf_get_lines(term_buf, 0, -1, false)) do
				if l:find(needle, 1, true) then
					return true
				end
			end
			return false
		end
		local painted = vim.wait(8000, function()
			return grid_has("GHOST_PAINTED_OK")
		end, 100)
		local in_insert = grid_has("-- INSERT --")
		vim.fn.jobstop(job)
		assert.is_true(painted, "the ghost text must reach the rendered grid without any keypress")
		assert.is_true(in_insert, "the child must still be in insert mode when the ghost paints")
		vim.api.nvim_buf_delete(term_buf, { force = true })
	end)

	-- ─── Surface ───────────────────────────────────────────────────────────────

	it("model() precedence: $OPENCODE_MODEL > persisted ai_model > default", function()
		-- The default must be the fastest VERIFIED model: a reasoning-heavy model
		-- burns the token budget on reasoning_content and returns empty content,
		-- so the feature silently produces no ghost (glm-5/deepseek failure mode).
		local settings = require("core.settings")
		settings.load({ file = vim.fn.tempname() }) -- default ai_model = minimax-m2.5
		local prev = vim.env.OPENCODE_MODEL
		vim.env.OPENCODE_MODEL = nil
		assert.are.equal("minimax-m2.5", ai.model(), "falls back to the fastest verified default")
		assert.are.equal(ai.DEFAULT_MODEL, ai.model(), "settings default and DEFAULT_MODEL stay in lockstep")
		settings.set("ai_model", "minimax-m2.7")
		assert.are.equal("minimax-m2.7", ai.model(), "the persisted :NvSinnerIA choice is used")
		vim.env.OPENCODE_MODEL = "custom-x"
		assert.are.equal("custom-x", ai.model(), "$OPENCODE_MODEL still overrides")
		vim.env.OPENCODE_MODEL = prev
	end)

	it("SAFE_MODELS is the picker's whole world: default included, notes attached", function()
		-- The picker (:NvSinnerIA) never offers ids outside this verified set; the
		-- default must be in it, and the fastest one must carry the recommendation
		-- note the picker displays.
		assert.is_true(vim.tbl_contains(ai.SAFE_MODELS, ai.DEFAULT_MODEL))
		assert.matches("recommended", ai.MODEL_NOTES[ai.DEFAULT_MODEL])
		for _, id in ipairs(ai.SAFE_MODELS) do
			assert.is_string(ai.MODEL_NOTES[id], id .. " needs its probe note")
		end
	end)

	it("registers :NvSinnerComplete + :NvSinnerCompleteToggle and the insert maps", function()
		local cmds = vim.api.nvim_get_commands({})
		assert.is_not_nil(cmds["NvSinnerComplete"], "the command-based trigger")
		assert.is_not_nil(cmds["NvSinnerCompleteToggle"])
		local function imap(lhs)
			return next(vim.fn.maparg(lhs, "i", false, true)) ~= nil
		end
		assert.is_true(imap("<C-l>"), "insert-mode trigger map")
		assert.is_true(imap("<Tab>"), "accept/Tab map")
		assert.is_true(imap("<C-]>"), "dismiss map")
	end)
end)
