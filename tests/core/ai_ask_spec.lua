-- Tests for the Ask-AI action modal (lua/core/ai-ask.lua): the pure payload
-- builder, visual-mode capture (before the synchronous Esc), the modal
-- rendering the four actions, run() sending into a real terminal via the
-- ai-sessions bridge, the custom-question vim.ui.input flow, the >1-session
-- vim.ui.select branch (send_to), and the keymap/command existing.

require("core.options") -- leaders must be set before the module maps <leader>x
local sessions = require("core.ai-sessions")
local ask = require("core.ai-ask")

describe("core.ai-ask", function()
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

	local CTX = { text = "local a = 1\nlocal b = 2", path = "lua/core/foo.lua", l1 = 10, l2 = 25 }

	before_each(function()
		ask._reset()
		sessions._reset()
	end)

	it("build() formats the fix/refactor/explain headers with path:range", function()
		assert.are.equal("Fix this code in lua/core/foo.lua:10-25:\nlocal a = 1\nlocal b = 2", ask.build("fix", CTX))
		assert.matches("^Refactor this code in lua/core/foo.lua:10%-25:\n", ask.build("refactor", CTX))
		assert.matches("^Explain this code in lua/core/foo.lua:10%-25:\n", ask.build("explain", CTX))
	end)

	it("build() collapses a one-line range to path:N", function()
		local one = { text = "x", path = "a.lua", l1 = 7, l2 = 7 }
		assert.are.equal("Fix this code in a.lua:7:\nx", ask.build("fix", one))
	end)

	it("build() makes the custom question the header, keeping the location", function()
		assert.are.equal(
			"Why is this slow?\nCode in lua/core/foo.lua:10-25:\nlocal a = 1\nlocal b = 2",
			ask.build("ask", CTX, "Why is this slow?")
		)
	end)

	it("captures the selection + range from visual mode and returns to normal", function()
		local buf = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_buf_set_name(buf, vim.fn.getcwd() .. "/capture_me.lua")
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "line one", "line two", "line three" })
		vim.api.nvim_set_current_buf(buf)
		vim.api.nvim_win_set_cursor(0, { 1, 0 })

		-- Select lines 1-2 and fire the visual <leader>x map synchronously.
		vim.api.nvim_feedkeys(
			vim.api.nvim_replace_termcodes("Vj" .. vim.g.mapleader .. "x", true, false, true),
			"x",
			false
		)

		assert.are.equal("n", vim.fn.mode(), "must be back in normal mode")
		local c = ask._ctx()
		assert.is_not_nil(c, "the map must capture the selection")
		assert.are.equal("line one\nline two", c.text)
		assert.are.equal("capture_me.lua", c.path)
		assert.are.equal(1, c.l1)
		assert.are.equal(2, c.l2)

		ask.close()
		vim.api.nvim_buf_delete(buf, { force = true })
	end)

	it("open() renders the four actions in a centered float; q closes", function()
		ask.open(vim.deepcopy(CTX))
		local win = vim.api.nvim_get_current_win()
		local cfg = vim.api.nvim_win_get_config(win)
		assert.are.equal("editor", cfg.relative)
		assert.are.equal("nvsinner-ai-ask", vim.bo.filetype)

		local text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
		for _, title in ipairs({ "Fix", "Refactor", "Explain", "Ask custom question" }) do
			assert.matches(title, text, nil, true)
		end

		ask.move(1)
		ask.close()
		assert.is_false(vim.api.nvim_win_is_valid(win))
	end)

	it("run() sends the built payload into a real terminal, never submitting", function()
		vim.cmd("terminal cat")
		local buf = vim.api.nvim_get_current_buf()
		local job = vim.b[buf].terminal_job_id
		sessions.register(1, fake_term({ bufnr = buf, job_id = job, __open = true }))
		vim.cmd("new")

		ask.open(vim.deepcopy(CTX)) -- selection 1 = Fix
		local key = ask.run()
		assert.are.equal("fix", key)
		assert.is_nil(ask._ctx(), "ctx must be cleared after dispatch")

		local arrived = vim.wait(3000, function()
			return table
				.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
				:find("Fix this code in lua/core/foo.lua:10-25:", 1, true) ~= nil
		end, 50)
		assert.is_true(arrived, "payload header should appear in the terminal")

		vim.cmd("bdelete!")
		vim.api.nvim_buf_delete(buf, { force = true })
	end)

	it("run() on the custom action asks via vim.ui.input; cancel sends nothing", function()
		local sent = {}
		local orig_send = sessions.send
		sessions.send = function(text)
			sent[#sent + 1] = text
			return true
		end
		local orig_input = vim.ui.input
		local answer = "What does this do?"
		vim.ui.input = function(_, cb)
			cb(answer)
		end

		ask.open(vim.deepcopy(CTX))
		ask.move(3) -- selection 4 = Ask custom question
		local key = ask.run()

		assert.are.equal("ask", key)
		assert.are.equal(1, #sent)
		assert.matches("^What does this do%?\nCode in lua/core/foo.lua:10%-25:\n", sent[1])

		-- Cancelled input (nil) must not send.
		answer = nil
		ask.open(vim.deepcopy(CTX))
		ask.move(3)
		ask.run()
		assert.are.equal(1, #sent)
		assert.is_nil(ask._ctx())

		vim.ui.input = orig_input
		sessions.send = orig_send
	end)

	it("asks which session with >1 registered, sending to the chosen one", function()
		vim.cmd("terminal cat")
		local buf = vim.api.nvim_get_current_buf()
		local job = vim.b[buf].terminal_job_id
		sessions.register(1, fake_term({ __open = true, job_id = nil }))
		sessions.register(2, fake_term({ bufnr = buf, job_id = job, __open = true }))
		vim.cmd("new")

		local orig_select = vim.ui.select
		local offered
		vim.ui.select = function(items, _, cb)
			offered = items
			cb(items[2]) -- pick session 2
		end

		ask.open(vim.deepcopy(CTX))
		ask.run() -- Fix

		vim.ui.select = orig_select

		assert.are.equal(2, #offered, "both sessions must be offered")
		local arrived = vim.wait(3000, function()
			return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n"):find("Fix this code in", 1, true)
				~= nil
		end, 50)
		assert.is_true(arrived, "payload should land in the chosen session's terminal")

		vim.cmd("bdelete!")
		vim.api.nvim_buf_delete(buf, { force = true })
	end)

	it("send_to() a dead entry warns via the opener fallback", function()
		local opened
		sessions.set_opener(function(n)
			opened = n
		end)
		local toasts = {}
		local orig = vim.notify
		vim.notify = function(msg, level)
			toasts[#toasts + 1] = { msg = msg, level = level }
		end

		local ok = sessions.send_to({ n = 5, term = fake_term() }, "text") -- no job_id → dead

		vim.notify = orig

		assert.is_false(ok)
		assert.are.equal(1, opened)
		assert.are.equal(vim.log.levels.WARN, toasts[1].level)
	end)

	it("double_click() selects the word under the cursor and opens the modal", function()
		local buf = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_buf_set_name(buf, vim.fn.getcwd() .. "/dblclick.lua")
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "local answer = 42" })
		vim.api.nvim_set_current_buf(buf)
		vim.api.nvim_win_set_cursor(0, { 1, 7 }) -- inside "answer"

		ask.double_click()

		assert.are.equal("n", vim.fn.mode(), "must be back in normal mode")
		local c = ask._ctx()
		assert.is_not_nil(c, "double-click must capture the word")
		assert.are.equal("answer", c.text)
		assert.are.equal("dblclick.lua", c.path)
		assert.are.equal(1, c.l1)
		assert.are.equal(1, c.l2)
		assert.are.equal("nvsinner-ai-ask", vim.bo.filetype, "the modal must be open and focused")

		ask.close()
		vim.api.nvim_buf_delete(buf, { force = true })
	end)

	it("double_click() uses the active visual selection when there is one", function()
		local buf = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_buf_set_name(buf, vim.fn.getcwd() .. "/dblsel.lua")
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "one two", "three four" })
		vim.api.nvim_set_current_buf(buf)
		vim.api.nvim_win_set_cursor(0, { 1, 0 })
		vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("Vj", true, false, true), "x", false)

		ask.double_click()

		local c = ask._ctx()
		assert.are.equal("one two\nthree four", c.text)
		assert.are.equal(1, c.l1)
		assert.are.equal(2, c.l2)

		ask.close()
		vim.api.nvim_buf_delete(buf, { force = true })
	end)

	it("double_click() bails silently in special buffers and on whitespace", function()
		local toasts = 0
		local orig = vim.notify
		vim.notify = function()
			toasts = toasts + 1
		end

		-- Terminal buffer (buftype ~= "") → no modal, no toast.
		vim.cmd("terminal cat")
		local term = vim.api.nvim_get_current_buf()
		ask.double_click()
		assert.is_nil(ask._ctx())
		vim.api.nvim_buf_delete(term, { force = true })

		-- Whitespace-only word → no modal, no toast.
		local buf = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_buf_set_name(buf, vim.fn.getcwd() .. "/blank.lua")
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "x   y" })
		vim.api.nvim_set_current_buf(buf)
		vim.api.nvim_win_set_cursor(0, { 1, 2 }) -- on the spaces
		ask.double_click()
		assert.are_not.equal("nvsinner-ai-ask", vim.bo.filetype, "no modal on whitespace")

		vim.notify = orig
		assert.are.equal(0, toasts)
		vim.api.nvim_buf_delete(buf, { force = true })
	end)

	it("maps visual <leader>x and registers :NvSinnerAskAI", function()
		assert.are_not.equal("", vim.fn.maparg("<leader>x", "x"), "<leader>x (visual) must exist")
		assert.are.equal("", vim.fn.maparg("<leader>x", "n"), "no bare normal-mode <leader>x map expected")
		assert.are_not.equal("", vim.fn.maparg("<2-LeftMouse>", "n"), "double-click map must exist")
		assert.are_not.equal("", vim.fn.maparg("<2-LeftMouse>", "x"), "visual double-click map must exist")
		assert.is_not_nil(vim.api.nvim_get_commands({})["NvSinnerAskAI"])
	end)
end)
