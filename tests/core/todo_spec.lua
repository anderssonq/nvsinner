-- Tests for the native TODO-comment keyword chips (lua/core/todo.lua): the
-- carbon accent chip groups, keyword+colon matching (optional author tag,
-- colon required, boundary strict), rescans replacing marks, and the
-- special-buffer skip.

local todo = require("core.todo")

describe("core.todo", function()
	local path, buf

	local function open_lua_file(lines)
		path = vim.fn.tempname() .. "_todo.lua"
		vim.fn.writefile(lines, path)
		vim.cmd("edit " .. vim.fn.fnameescape(path))
		buf = vim.api.nvim_get_current_buf()
	end

	local function marks()
		return vim.api.nvim_buf_get_extmarks(buf, todo._ns, 0, -1, { details = true })
	end

	local function cleanup()
		vim.cmd("bwipeout!")
		os.remove(path)
	end

	it("styles the chip groups with carbon roles (dark text on a solid accent)", function()
		local c = require("core.carbon").colors()
		local t = vim.api.nvim_get_hl(0, { name = "NvTodoTodo" })
		local f = vim.api.nvim_get_hl(0, { name = "NvTodoFix" })
		assert.are.equal(tonumber(c.base13:sub(2), 16), t.bg, "TODO wears carbon's green Todo tone")
		assert.are.equal(tonumber(c.base10:sub(2), 16), f.bg, "FIX wears the attention magenta")
		assert.are.equal(tonumber(c.base00:sub(2), 16), t.fg)
		assert.is_true(t.bold == true)
	end)

	it("chips KEYWORD: including an optional (author) tag", function()
		open_lua_file({
			"-- TODO: migrate this",
			"-- FIXME(andersson): broken",
		})
		todo.refresh(buf)

		local got = marks()
		assert.are.equal(2, #got)
		assert.are.equal("NvTodoTodo", got[1][4].hl_group)
		assert.are.equal(#"TODO:", got[1][4].end_col - got[1][3], "the chip spans keyword + colon")
		assert.are.equal("NvTodoFix", got[2][4].hl_group)
		assert.are.equal(#"FIXME(andersson):", got[2][4].end_col - got[2][3])
		cleanup()
	end)

	it("requires the colon and a clean left boundary; lowercase never matches", function()
		open_lua_file({
			"-- TODO without a colon",
			"-- MYTODO: glued prefix",
			"-- todo: lowercase",
		})
		todo.refresh(buf)
		assert.are.equal(0, #marks())
		cleanup()
	end)

	it("a rescan replaces the previous marks", function()
		open_lua_file({ "-- HACK: temp" })
		todo.refresh(buf)
		assert.are.equal(1, #marks())
		assert.are.equal("NvTodoWarn", marks()[1][4].hl_group)

		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "-- all clean now" })
		todo.refresh(buf)
		assert.are.equal(0, #marks())
		cleanup()
	end)

	it("the autocmd path coalesces edits into one debounced rescan", function()
		open_lua_file({ "-- HACK: temp" })
		todo.refresh(buf)
		assert.are.equal(1, #marks())

		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "-- HACK: temp", "-- TODO: new" })
		-- set_lines fires no TextChanged; drive the handler like typing would.
		-- A burst of events must land as ONE rescan after DEBOUNCE_MS.
		vim.api.nvim_exec_autocmds("TextChanged", { buffer = buf })
		vim.api.nvim_exec_autocmds("TextChanged", { buffer = buf })
		assert.is_true(#marks() < 2, "the rescan must not run synchronously")
		local repainted = vim.wait(1000, function()
			return #marks() == 2
		end, 10)
		assert.is_true(repainted, "the debounced rescan must land after the burst")
		cleanup()
	end)

	it("skips special buftypes", function()
		vim.cmd("terminal")
		buf = vim.api.nvim_get_current_buf()
		todo.refresh(buf) -- must be a silent no-op
		assert.are.equal(0, #marks())
		vim.api.nvim_buf_delete(buf, { force = true })
	end)
end)
