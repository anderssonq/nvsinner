-- Tests for the AI session registry + send-to-AI bridge (lua/core/ai-sessions.lua):
-- registration and the sessions() snapshot, target() MRU semantics, send() into a
-- real terminal job, the bracketed-paste payload wrapping, the no-session opener
-- fallback, and the bridge/picker keymaps existing.

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

	it("maps the bridge and picker keys", function()
		assert.are_not.equal("", vim.fn.maparg("<leader>as", "x"), "<leader>as (visual) must exist")
		assert.are_not.equal("", vim.fn.maparg("<leader>ab", "n"), "<leader>ab must exist")
		assert.are_not.equal("", vim.fn.maparg("<leader>ad", "n"), "<leader>ad must exist")
		assert.are_not.equal("", vim.fn.maparg("<leader>ja", "n"), "<leader>ja must exist")
	end)
end)
