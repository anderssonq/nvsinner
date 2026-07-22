-- Tests for the AI session registry + send-to-AI bridge (lua/core/ai-sessions.lua):
-- registration and the sessions() snapshot, target() MRU semantics, send() into a
-- real terminal job, the bracketed-paste payload wrapping, the no-session opener
-- fallback, the single- and all-buffers @path mention builders (current-first
-- order, dedup, eligibility filters), clear() killing a session + forgetting its
-- CLI choice via the injected clearer (incl. the dead-but-memoised panel the
-- registry can't see), and the bridge/picker keymaps + :NvSinnerAIClear existing.

require("core.options") -- leaders must be set before the module maps <leader>a*
local sessions = require("core.ai-sessions")

describe("core.ai-sessions", function()
	-- A minimal stand-in for a toggleterm Terminal.
	local function fake_term(fields)
		return vim.tbl_extend("force", {
			bufnr = nil,
			job_id = nil,
			window = nil,
			is_open = function(self)
				return self.__open == true
			end,
		}, fields or {})
	end

	-- A stand-in for toggleterm's injected clearer over `panels` ({ [n] = true }).
	-- Returns the list of session numbers cleared, in order.
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
				cleared[#cleared + 1] = n
				return true
			end,
		})
		return cleared
	end

	before_each(function()
		sessions._reset()
	end)

	it("registers, snapshots, and unregisters sessions", function()
		sessions.register(3, fake_term({ bufnr = 30, job_id = 300 }))
		sessions.register(1, fake_term({ bufnr = 10, job_id = 100, __open = true }))
		local snap = sessions.sessions()
		assert.are.equal(2, #snap)
		assert.are.equal(1, snap[1].n, "sessions() must be sorted by session number")
		assert.are.equal(3, snap[2].n)
		assert.are.equal(10, snap[1].bufnr)
		assert.are.equal(300, snap[2].job_id)
		assert.is_true(snap[1].open)
		assert.is_false(snap[2].open)

		sessions.unregister(1)
		assert.are.equal(1, #sessions.sessions())
	end)

	it("target() prefers the most recently used OPEN session", function()
		sessions.register(1, fake_term({ __open = true }))
		sessions.register(2, fake_term({ __open = true }))
		sessions.register(3, fake_term({ __open = false }))
		sessions.touch(1) -- 1 is now newer than 2
		sessions.touch(3) -- newest of all, but closed with no live job → skipped
		assert.are.equal(1, sessions.target().n)
	end)

	it("target() returns the terminal the cursor is inside of, over any MRU", function()
		vim.cmd("terminal")
		local buf = vim.api.nvim_get_current_buf()
		sessions.register(1, fake_term({ __open = true }))
		sessions.register(2, fake_term({ bufnr = buf, __open = false }))
		sessions.touch(1)
		assert.are.equal(2, sessions.target().n)
		vim.api.nvim_buf_delete(buf, { force = true })
	end)

	it("wraps multi-line payloads in bracketed paste, leaves single lines raw", function()
		assert.are.equal("hello", sessions._payload("hello"))
		assert.are.equal("\27[200~a\nb\27[201~", sessions._payload("a\nb"))
	end)

	it("send() delivers text into a real terminal job without submitting it", function()
		vim.cmd("terminal cat")
		local buf = vim.api.nvim_get_current_buf()
		local job = vim.b[buf].terminal_job_id
		assert.is_not_nil(job)
		local win = vim.api.nvim_get_current_win()
		sessions.register(1, fake_term({ bufnr = buf, job_id = job, window = win, __open = true }))

		-- Send from a different (non-terminal) window so targeting goes via MRU.
		vim.cmd("new")
		local ok = sessions.send("hello bridge", { focus = false })
		assert.is_true(ok)

		-- The PTY echoes the input, so the text shows up in the terminal buffer.
		local arrived = vim.wait(3000, function()
			return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n"):find("hello bridge", 1, true)
				~= nil
		end, 50)
		assert.is_true(arrived, "sent text should appear in the terminal")

		vim.cmd("bdelete!")
		vim.api.nvim_buf_delete(buf, { force = true })
	end)

	it("send() with no live session calls the opener and warns", function()
		local opened
		sessions.set_opener(function(n)
			opened = n
		end)
		local toasts = {}
		local orig = vim.notify
		vim.notify = function(msg, level)
			toasts[#toasts + 1] = { msg = msg, level = level }
		end

		local ok = sessions.send("anything")

		vim.notify = orig -- restore BEFORE asserting so a failure can't leak it

		assert.is_false(ok)
		assert.are.equal(1, opened, "the opener must be asked to open session 1")
		assert.are.equal(1, #toasts)
		assert.are.equal(vim.log.levels.WARN, toasts[1].level)
		assert.matches("send again", toasts[1].msg, nil, true)
	end)

	it("builds a cwd-relative @path mention for the current buffer", function()
		local buf = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_buf_set_name(buf, vim.fn.getcwd() .. "/lua/core/ai-sessions.lua")
		assert.are.equal("@lua/core/ai-sessions.lua ", sessions.buffer_mention(buf))
		vim.api.nvim_buf_delete(buf, { force = true })
	end)

	it("builds @path mentions for every open file buffer, current first", function()
		local a = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_buf_set_name(a, vim.fn.getcwd() .. "/lua/core/ai-sessions.lua")
		local b = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_buf_set_name(b, vim.fn.getcwd() .. "/README.md")
		vim.api.nvim_set_current_buf(b)

		assert.are.equal("@README.md @lua/core/ai-sessions.lua ", sessions.buffer_mentions())

		vim.api.nvim_buf_delete(a, { force = true })
		vim.api.nvim_buf_delete(b, { force = true })
	end)

	it("dedups mentions and filters ineligible buffers, nil when none qualify", function()
		local file = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_buf_set_name(file, vim.fn.getcwd() .. "/README.md")
		local unnamed = vim.api.nvim_create_buf(true, false)
		local ghost = vim.api.nvim_create_buf(true, false) -- named but not on disk
		vim.api.nvim_buf_set_name(ghost, vim.fn.getcwd() .. "/no-such-file.lua")
		local scratch = vim.api.nvim_create_buf(false, true) -- unlisted nofile
		vim.cmd("terminal cat")
		local term = vim.api.nvim_get_current_buf()

		local text = sessions.buffer_mentions({ bufs = { file, file, unnamed, ghost, scratch, term } })
		assert.are.equal("@README.md ", text, "one mention: duplicates and ineligible buffers dropped")

		assert.is_nil(sessions.buffer_mentions({ bufs = { unnamed, ghost, scratch, term } }))

		for _, buf in ipairs({ file, unnamed, ghost, scratch, term }) do
			vim.api.nvim_buf_delete(buf, { force = true })
		end
	end)

	it("formats line diagnostics with a fix-this header, nil on a clean line", function()
		local buf = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_buf_set_name(buf, vim.fn.getcwd() .. "/broken.lua")
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "bad line", "fine line" })
		local ns = vim.api.nvim_create_namespace("nv_ai_sessions_spec")
		vim.diagnostic.set(ns, buf, {
			{ lnum = 0, col = 0, severity = vim.diagnostic.severity.ERROR, message = "boom" },
		})

		local text = sessions.diagnostics_text(buf, 1)
		assert.matches("Fix this diagnostic in broken.lua", text, nil, true)
		assert.matches("broken.lua:1 [ERROR] boom", text, nil, true)
		assert.is_nil(sessions.diagnostics_text(buf, 2))

		vim.diagnostic.reset(ns, buf)
		vim.api.nvim_buf_delete(buf, { force = true })
	end)

	it("bumps the MRU stamp via the TermEnter autocmd without erroring", function()
		-- Regression: the TermEnter handler once referenced a removed `uv`
		-- local and blew up the moment a registered terminal entered insert.
		vim.cmd("terminal cat")
		local buf = vim.api.nvim_get_current_buf()
		sessions.register(1, fake_term({ bufnr = buf, __open = true }))
		sessions.register(2, fake_term({ __open = true })) -- newer stamp than 1

		-- Terminal-mode can't be entered synchronously in a headless spec
		-- (:startinsert and feedkeys both defer to the main loop), so fire the
		-- registered autocmd directly — it runs the same handler code.
		vim.api.nvim_exec_autocmds("TermEnter", { buffer = buf })

		-- Entering session 1's terminal must have made it the MRU target again.
		vim.cmd("new") -- leave the terminal so target() resolves via MRU
		assert.are.equal(1, sessions.target().n)
		vim.cmd("bdelete!")
		vim.api.nvim_buf_delete(buf, { force = true })
	end)

	it("clear() with no clearer or no panels is a safe warning no-op", function()
		local toasts = {}
		local orig = vim.notify
		vim.notify = function(msg, level)
			toasts[#toasts + 1] = { msg = msg, level = level }
		end

		local ok_unset = sessions.clear() -- _reset wiped the injected clearer
		fake_clearer({})
		local ok_empty = sessions.clear()

		vim.notify = orig -- restore BEFORE asserting so a failure can't leak it

		assert.is_false(ok_unset)
		assert.is_false(ok_empty)
		assert.are.equal(2, #toasts)
		for _, t in ipairs(toasts) do
			assert.are.equal(vim.log.levels.WARN, t.level)
			assert.matches("No AI session", t.msg, nil, true)
		end
	end)

	it("clear() with one panel kills it, unregisters it, and confirms", function()
		sessions.register(1, fake_term({ bufnr = 10, job_id = 100, __open = true }))
		local cleared = fake_clearer({ [1] = true })
		local toasts = {}
		local orig = vim.notify
		vim.notify = function(msg, level)
			toasts[#toasts + 1] = { msg = msg, level = level }
		end

		local ok = sessions.clear()

		vim.notify = orig

		assert.is_true(ok)
		assert.are.same({ 1 }, cleared)
		assert.are.equal(0, #sessions.sessions(), "the cleared session must leave the registry")
		assert.are.equal(1, #toasts)
		assert.are.equal(vim.log.levels.INFO, toasts[1].level)
		assert.matches("cleared", toasts[1].msg, nil, true)
	end)

	it("clear() reaches a dead panel the registry no longer knows", function()
		-- The motivating bug: the CLI exited, on_exit unregistered the session,
		-- but toggleterm still memoises the Terminal — so <leader>j reopens the
		-- corpse instead of the picker. Enumeration must come from the clearer.
		local cleared = fake_clearer({ [2] = true }) -- nothing registered in core
		assert.is_true(sessions.clear())
		assert.are.same({ 2 }, cleared)
	end)

	it("clear(n) targets that panel; an unknown n warns and clears nothing", function()
		local cleared = fake_clearer({ [1] = true, [3] = true })
		assert.is_true(sessions.clear(3))
		assert.are.same({ 3 }, cleared)

		local toasts = {}
		local orig = vim.notify
		vim.notify = function(msg, level)
			toasts[#toasts + 1] = { msg = msg, level = level }
		end
		local ok = sessions.clear(5)
		vim.notify = orig

		assert.is_false(ok)
		assert.are.same({ 3 }, cleared, "an unknown n must not clear anything")
		assert.are.equal(vim.log.levels.WARN, toasts[1].level)
		assert.matches("No AI session 5", toasts[1].msg, nil, true)
	end)

	it("clear() with several panels asks which via vim.ui.select", function()
		-- Session 1 is registered live with a labelled buffer; sessions 2 and 3
		-- are dead memos only the clearer knows — the picker marks them "exited".
		local buf = vim.api.nvim_create_buf(false, true)
		vim.b[buf].nv_term_label = "AI · 1"
		sessions.register(1, fake_term({ bufnr = buf, __open = true }))
		local cleared = fake_clearer({ [1] = true, [2] = true, [3] = true })

		local offered, labels
		local orig_select = vim.ui.select
		vim.ui.select = function(items, opts, cb)
			offered = items
			labels = vim.tbl_map(opts.format_item, items)
			cb(items[2]) -- pick session 2
		end

		local ok = sessions.clear()

		vim.ui.select = orig_select

		assert.is_true(ok)
		assert.are.same({ 1, 2, 3 }, offered)
		assert.matches("AI · 1", labels[1], nil, true)
		assert.matches("exited", labels[2], nil, true)
		assert.are.same({ 2 }, cleared)
		assert.are.equal(1, #sessions.sessions(), "session 1 must survive")

		-- Cancelling the picker (still 2 panels left) clears nothing.
		vim.ui.select = function(_, _, cb)
			cb(nil)
		end
		assert.is_false(sessions.clear())
		vim.ui.select = orig_select
		assert.are.same({ 2 }, cleared)

		vim.api.nvim_buf_delete(buf, { force = true })
	end)

	it("clear() kills a real terminal job and leaves the registry clean", function()
		vim.cmd("terminal cat")
		local buf = vim.api.nvim_get_current_buf()
		local job = vim.b[buf].terminal_job_id
		assert.is_not_nil(job)
		sessions.register(1, fake_term({ bufnr = buf, job_id = job, __open = true }))
		sessions.set_clearer({
			list = function()
				return { 1 }
			end,
			clear = function()
				-- shutdown()'s observable effect: force-deleting the terminal
				-- buffer kills its job.
				vim.api.nvim_buf_delete(buf, { force = true })
				return true
			end,
		})

		assert.is_true(sessions.clear())
		assert.are.equal(0, #sessions.sessions(), "clear() must unregister without waiting for on_exit")
		local dead = vim.wait(3000, function()
			return vim.fn.jobwait({ job }, 0)[1] ~= -1
		end, 50)
		assert.is_true(dead, "the CLI job must be dead after clear()")
	end)

	it("maps the bridge and picker keys", function()
		assert.are_not.equal("", vim.fn.maparg("<leader>as", "x"), "<leader>as (visual) must exist")
		assert.are_not.equal("", vim.fn.maparg("<leader>ab", "n"), "<leader>ab must exist")
		assert.are_not.equal("", vim.fn.maparg("<leader>ad", "n"), "<leader>ad must exist")
		assert.are_not.equal("", vim.fn.maparg("<leader>ja", "n"), "<leader>ja must exist")
		assert.are_not.equal("", vim.fn.maparg("<leader>jc", "n"), "<leader>jc must exist")
	end)

	it("defines the :NvSinnerAIClear user command", function()
		assert.is_not_nil(vim.api.nvim_get_commands({})["NvSinnerAIClear"])
	end)
end)
