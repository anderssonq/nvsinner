-- Tests for the agent cockpit (lua/core/agents.lua): the :NvSinnerAgents
-- command + <leader>xa map, the pure per-CLI screen matcher (M._scan) and the
-- status precedence ladder over core/ai-activity, refresh() merging the
-- registry with toggleterm's dead-but-memoised panels, the two-float modal
-- (list + preview + backdrop) and its teardown, a REAL terminal's tail
-- reaching the preview pane — including after the buffer is hidden, which is
-- the whole point of previewing a closed column — focus() routing through the
-- injected opener, kill() clearing in place, the empty-state warn, and the
-- live-refresh timer starting and stopping with the modal.
--
-- Mouse clicks aren't exercised headless; their handlers route into the same
-- focus()/render() these specs cover.

require("core.options") -- leaders first, so the <leader>x* maps resolve
require("core.keymaps")
local sessions = require("core.ai-sessions")
local agents = require("core.agents")

describe("core.agents", function()
	-- A minimal stand-in for a toggleterm Terminal (same shape as
	-- tests/core/ai_sessions_spec.lua's).
	local function fake_term(fields)
		return vim.tbl_extend("force", {
			bufnr = nil,
			job_id = nil,
			window = nil,
			cmd = nil,
			is_open = function(self)
				return self.__open == true
			end,
		}, fields or {})
	end

	-- Stand-in for toggleterm's injected clearer over `panels` ({ [n] = true }).
	local function fake_clearer(panels)
		local cleared = {}
		sessions.set_clearer({
			list = function()
				local out = {}
				for n in pairs(panels) do
					table.insert(out, n)
				end
				table.sort(out)
				return out
			end,
			clear = function(n)
				if not panels[n] then
					return false
				end
				panels[n] = nil
				table.insert(cleared, n)
				return true
			end,
		})
		return cleared
	end

	-- A real terminal buffer that has produced `text`, for the preview specs.
	local function real_terminal(text)
		vim.cmd("enew")
		vim.cmd("terminal")
		local buf = vim.api.nvim_get_current_buf()
		local job = vim.b[buf].terminal_job_id
		vim.fn.chansend(job, "printf '" .. text .. "\\n'\n")
		vim.wait(2000, function()
			local joined = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
			return joined:find(text, 1, true) ~= nil
		end)
		return buf, job
	end

	-- The cockpit's preview float (non-focusable, so never the current window).
	local function preview_win()
		for _, w in ipairs(vim.api.nvim_list_wins()) do
			if vim.bo[vim.api.nvim_win_get_buf(w)].filetype == "nvsinner-agents-preview" then
				return w
			end
		end
	end

	before_each(function()
		agents._reset()
		sessions._reset()
	end)

	it("defines the :NvSinnerAgents command and maps <leader>xa to it", function()
		assert.is_not_nil(vim.api.nvim_get_commands({})["NvSinnerAgents"])
		local m = vim.fn.maparg("<leader>xa", "n", false, true)
		assert.is_true(type(m) == "table" and next(m) ~= nil, "<leader>xa must be mapped")
		assert.matches("NvSinnerAgents", m.rhs, nil, true)
	end)

	-- ─── The per-CLI screen matcher ──────────────────────────────────────────

	it("_scan reads a claude permission box as awaiting", function()
		local screen = {
			"● Edit file lua/core/agents.lua",
			"Do you want to make this edit?",
			"❯ 1. Yes",
			"  2. No, and tell Claude what to do differently",
		}
		assert.are.equal("awaiting", agents._scan("claude", screen))
	end)

	it("_scan reads a running claude turn as working", function()
		assert.are.equal("working", agents._scan("claude", { "✽ Thinking… (12s · esc to interrupt)" }))
	end)

	it("_scan reads kiro-cli's and opencode's own prompts", function()
		assert.are.equal("awaiting", agents._scan("kiro-cli", { "Allow this action? [y/n/t]:" }))
		assert.are.equal("awaiting", agents._scan("opencode", { "❯ 1. allow once" }))
	end)

	it("_scan returns nil for an unknown CLI, empty input, and unrelated output", function()
		assert.is_nil(agents._scan("fish", { "Do you want to proceed?" }), "unknown CLI must not match")
		assert.is_nil(agents._scan("claude", {}))
		assert.is_nil(agents._scan("claude", nil))
		assert.is_nil(agents._scan(nil, { "anything" }))
		assert.is_nil(agents._scan("claude", { "just some ordinary build output" }))
	end)

	-- ─── The status precedence ladder ────────────────────────────────────────

	it("status_of lets a screen prompt outrank whatever ai-activity reports", function()
		-- The exact regression this layer exists for: a permission prompt emits
		-- no output, so ai-activity flips the buffer to idle after IDLE_MS while
		-- the CLI is really blocked on the user.
		local buf = real_terminal("Do you want to make this edit?")
		local row = { alive = true, bufnr = buf, kind = "claude" }
		assert.are.equal("awaiting", agents.status_of(row))
		vim.api.nvim_buf_delete(buf, { force = true })
	end)

	it("status_of falls back to ai-activity and to idle", function()
		-- No matching signature and an untracked buffer → idle, never nil.
		assert.are.equal("idle", agents.status_of({ alive = true, bufnr = nil, kind = "claude" }))
		assert.are.equal("idle", agents.status_of({ alive = true, bufnr = 999999, kind = "terminal" }))
	end)

	it("status_of reports a dead panel as exited without touching its buffer", function()
		assert.are.equal("exited", agents.status_of({ alive = false, bufnr = nil, kind = "terminal" }))
	end)

	-- ─── The row model ───────────────────────────────────────────────────────

	it("refresh() merges live sessions with the dead-but-memoised panels", function()
		sessions.register(1, fake_term({ cmd = "claude", __open = true }))
		sessions.register(3, fake_term({ cmd = "opencode", __open = false }))
		-- Panel 2's CLI already exited: on_exit unregistered it, but toggleterm
		-- still memoises it — the registry alone cannot see it.
		fake_clearer({ [1] = true, [2] = true, [3] = true })

		local items = agents.refresh()
		assert.are.equal(3, #items, "the exited panel must be listed too")
		assert.are.same({ 1, 2, 3 }, { items[1].n, items[2].n, items[3].n })
		assert.are.equal("claude", items[1].kind)
		assert.is_true(items[1].open)
		assert.are.equal("opencode", items[3].kind)
		assert.is_false(items[3].open)
		assert.is_false(items[2].alive)
		assert.are.equal("exited", items[2].status)
	end)

	it("refresh() names a session with the label formula the other pickers use", function()
		sessions.register(2, fake_term({ __open = false }))
		fake_clearer({ [2] = true })
		local items = agents.refresh()
		assert.are.equal("AI · 2", items[1].label)
	end)

	-- ─── The modal ───────────────────────────────────────────────────────────

	it("opens a list + preview + backdrop and tears all three down", function()
		sessions.register(1, fake_term({ cmd = "claude", __open = false }))
		fake_clearer({ [1] = true })
		local before = #vim.api.nvim_list_wins()

		agents.open()
		local win = vim.api.nvim_get_current_win()
		assert.are.equal("editor", vim.api.nvim_win_get_config(win).relative, "must be a float")
		assert.matches("NvMenuNormal", vim.wo[win].winhighlight, nil, true)
		assert.are.equal(before + 3, #vim.api.nvim_list_wins(), "list + preview + backdrop expected")

		local text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
		assert.matches("claude", text, nil, true)
		assert.matches("AI · 1", text, nil, true)
		assert.matches("hidden", text, nil, true) -- the column is closed
		assert.matches("⏎ focus", text, nil, true) -- the hint line

		agents.close()
		vim.wait(200, function()
			return #vim.api.nvim_list_wins() == before
		end)
		assert.are.equal(before, #vim.api.nvim_list_wins(), "backdrop + preview must close with the list")
	end)

	-- The floats are screen-sized, not content-sized, and carbon paints
	-- EndOfBuffer on the EDITOR ground — so without the remap every row past the
	-- last buffer line showed as a lighter block (the "two-tone modal").
	it("paints one surface: EndOfBuffer + title remapped, the list filled to its height", function()
		sessions.register(1, fake_term({ cmd = "claude", __open = false }))
		sessions.register(2, fake_term({ cmd = "opencode", __open = true }))
		fake_clearer({ [1] = true, [2] = true })

		agents.open()
		local win = vim.api.nvim_get_current_win()
		local pwin = preview_win()
		assert.is_not_nil(pwin, "the preview pane must open")
		for _, w in ipairs({ win, pwin }) do
			assert.matches("EndOfBuffer:NvMenuNormal", vim.wo[w].winhighlight, nil, true)
			assert.matches("FloatTitle:NvAgentTitle", vim.wo[w].winhighlight, nil, true)
		end

		local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false)
		assert.are.equal(vim.api.nvim_win_get_height(win), #lines, "the list must fill its window exactly")
		assert.matches("⏎ focus", lines[#lines], nil, true) -- the hint is pinned to the bottom edge
		agents.close()
	end)

	it("shows a details card for the selected agent that follows the selection", function()
		sessions.register(1, fake_term({ cmd = "claude", __open = false }))
		sessions.register(2, fake_term({ cmd = "opencode", __open = true }))
		fake_clearer({ [1] = true, [2] = true })

		agents.open()
		local buf = vim.api.nvim_get_current_buf()
		local function text()
			return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
		end
		agents.move(-99)
		assert.matches("details", text(), nil, true)
		assert.matches("CLI%s+claude", text())
		assert.matches("Column%s+hidden", text())
		agents.move(1)
		assert.matches("CLI%s+opencode", text())
		assert.matches("Column%s+column open", text())
		agents.close()
	end)

	it("warns and opens nothing when there is no session at all", function()
		local warned
		local orig = vim.notify
		vim.notify = function(msg)
			warned = msg
		end
		local before = #vim.api.nvim_list_wins()
		agents.open()
		vim.notify = orig -- restore BEFORE asserting

		assert.are.equal(before, #vim.api.nvim_list_wins(), "no window may open")
		assert.is_string(warned)
		assert.matches("No AI sessions yet", warned, nil, true)
	end)

	-- ─── The preview pane ────────────────────────────────────────────────────

	it("previews a session's chat tail — including once its column is hidden", function()
		local buf = real_terminal("AGENT-PREVIEW-MARKER")
		-- Hide it: no window shows this buffer any more, which is exactly the
		-- state a toggled-off AI column is in. The lines stay readable only
		-- because core/ai-activity attached to the buffer on TermOpen.
		vim.cmd("enew")
		for _, w in ipairs(vim.api.nvim_list_wins()) do
			assert.are_not.equal(buf, vim.api.nvim_win_get_buf(w), "the buffer must be hidden")
		end

		sessions.register(1, fake_term({ bufnr = buf, cmd = "claude", __open = false }))
		fake_clearer({ [1] = true })
		agents.refresh()
		local preview = table.concat(agents._preview_lines(agents._items()[1]), "\n")
		assert.matches("AGENT-PREVIEW-MARKER", preview, nil, true)

		-- …and it reaches the pane, not just the builder.
		agents.open()
		local shown = false
		for _, w in ipairs(vim.api.nvim_list_wins()) do
			local text = table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(w), 0, -1, false), "\n")
			if text:find("AGENT-PREVIEW-MARKER", 1, true) then
				shown = true
			end
		end
		agents.close()
		assert.is_true(shown, "the preview pane must carry the agent's tail")
		vim.api.nvim_buf_delete(buf, { force = true })
	end)

	-- A fresh session's tail is a few lines; top-aligned it left most of a tall
	-- pane empty. It is anchored to the bottom edge instead, like a terminal.
	it("bottom-anchors a short chat tail in the preview pane", function()
		local buf = real_terminal("ANCHOR-MARKER")
		vim.cmd("enew")
		sessions.register(1, fake_term({ bufnr = buf, cmd = "claude", __open = false }))
		fake_clearer({ [1] = true })

		agents.open()
		local pwin = preview_win()
		assert.is_not_nil(pwin, "the preview pane must open")
		local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(pwin), 0, -1, false)
		assert.are.equal("", lines[1], "blank padding must sit above the tail")
		assert.matches("ANCHOR-MARKER", table.concat(lines, "\n"), nil, true)
		assert.is_true(
			vim.api.nvim_win_text_height(pwin, {}).all >= vim.api.nvim_win_get_height(pwin),
			"the preview must fill its pane"
		)
		agents.close()
		vim.api.nvim_buf_delete(buf, { force = true })
	end)

	it("_preview_lines degrades instead of erroring on a dead buffer", function()
		local lines = agents._preview_lines({ alive = false, bufnr = nil })
		assert.matches("exited", table.concat(lines, "\n"), nil, true)
		assert.matches("no session selected", table.concat(agents._preview_lines(nil), "\n"), nil, true)
	end)

	-- ─── Actions ─────────────────────────────────────────────────────────────

	it("focus() closes the modal and reopens a hidden session via the opener", function()
		local opened
		sessions.set_opener(function(n)
			opened = n
		end)
		sessions.register(2, fake_term({ cmd = "claude", __open = false }))
		fake_clearer({ [2] = true })

		agents.open()
		local win = vim.api.nvim_get_current_win()
		local picked = agents.focus()

		assert.are.equal(2, picked.n)
		assert.are.equal(2, opened, "a hidden column must go through the session opener")
		assert.are_not.equal(win, vim.api.nvim_get_current_win(), "focus must close the modal first")
	end)

	it("focus() lands on the window of an already-open column", function()
		local target = vim.api.nvim_get_current_win()
		vim.cmd("vsplit")
		local other = vim.api.nvim_get_current_win()
		sessions.register(1, fake_term({ window = target, __open = true }))
		fake_clearer({ [1] = true })

		agents.open()
		agents.focus()
		assert.are.equal(target, vim.api.nvim_get_current_win())
		pcall(vim.api.nvim_win_close, other, true)
	end)

	it("kill() clears the session and keeps the modal open while rows remain", function()
		sessions.register(1, fake_term({ cmd = "claude", __open = false }))
		sessions.register(2, fake_term({ cmd = "opencode", __open = false }))
		local cleared = fake_clearer({ [1] = true, [2] = true })

		local orig = vim.notify
		vim.notify = function() end
		agents.open()
		local win = vim.api.nvim_get_current_win()
		agents.move(-99) -- clamp to the first row
		local killed = agents.kill()
		vim.notify = orig

		assert.are.equal(1, killed)
		assert.are.same({ 1 }, cleared)
		assert.are.equal(win, vim.api.nvim_get_current_win(), "the modal stays open to clear more")
		assert.are.equal(1, #agents._items(), "the cleared row must be gone")
		agents.close()
	end)

	it("kill() closes the modal once nothing is left to list", function()
		sessions.register(1, fake_term({ cmd = "claude", __open = false }))
		fake_clearer({ [1] = true })

		local orig = vim.notify
		vim.notify = function() end
		agents.open()
		local win = vim.api.nvim_get_current_win()
		agents.kill()
		vim.notify = orig

		assert.are_not.equal(win, vim.api.nvim_get_current_win(), "an empty list must not stay open")
	end)

	-- ─── snapshot(): the read-only view outside the modal ────────────────────

	it("snapshot() returns the same rows refresh() would build", function()
		sessions.register(1, fake_term({ cmd = "claude", __open = false }))
		fake_clearer({ [1] = true })

		local snap = agents.snapshot()
		assert.are.equal(1, #snap)
		assert.are.equal(1, snap[1].n)
		assert.are.equal("claude", snap[1].kind)
		assert.is_true(snap[1].alive)
	end)

	-- core/herdr.lua reads the cockpit from outside it. refresh() rewrites the
	-- module's item list AND the layout, and `ui.sel` is a POSITIONAL index into
	-- that list — so an outside refresh racing a dying session can shift rows
	-- under a screen nobody repainted and make the next <CR>/d act on a
	-- different agent than the one shown. snapshot() must never touch it.
	it("snapshot() leaves the open cockpit's rows and selection alone", function()
		sessions.register(1, fake_term({ cmd = "claude", __open = false }))
		sessions.register(2, fake_term({ cmd = "opencode", __open = false }))
		fake_clearer({ [1] = true, [2] = true })

		agents.open()
		local items_before = agents._items()
		local count_before = #items_before

		sessions.unregister(2) -- a session dies while the modal is up
		agents.snapshot()

		assert.are.equal(items_before, agents._items(), "the modal must keep its own list object")
		assert.are.equal(count_before, #agents._items(), "snapshot() must not re-index the rows")
		agents.close()
	end)

	-- ─── The live-refresh timer ──────────────────────────────────────────────

	it("runs its own poll timer only while the modal is open", function()
		sessions.register(1, fake_term({ cmd = "claude", __open = false }))
		fake_clearer({ [1] = true })

		assert.is_false(agents._ticking, "a closed cockpit must cost zero wakeups")
		agents.open()
		assert.is_true(agents._ticking)
		agents.close()
		assert.is_false(agents._ticking)
	end)
end)
