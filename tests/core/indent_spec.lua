-- Tests for the native current-scope indent guide (lua/core/indent.lua):
-- the IndentLineCurrent carbon panel gray, the scope computation around the
-- cursor (guide column, top/bottom, blank-line membership + edge trimming),
-- and the top-level/denylist/special-buffer guards.

local indent = require("core.indent")

describe("core.indent", function()
	local path, buf

	local function open_lua_file(lines)
		path = vim.fn.tempname() .. "_indent.lua"
		vim.fn.writefile(lines, path)
		vim.cmd("edit " .. vim.fn.fnameescape(path))
		buf = vim.api.nvim_get_current_buf()
		vim.bo[buf].shiftwidth = 4
		vim.bo[buf].tabstop = 4
	end

	local function cleanup()
		vim.cmd("bwipeout!")
		os.remove(path)
	end

	before_each(function()
		indent._reset()
	end)

	it("styles IndentLineCurrent with the carbon panel gray", function()
		local c = require("core.carbon").colors()
		local hl = vim.api.nvim_get_hl(0, { name = "IndentLineCurrent" })
		assert.are.equal(tonumber(c.base02:sub(2), 16), hl.fg)
	end)

	it("computes the enclosing scope for the cursor line", function()
		open_lua_file({
			"local function outer()", -- 1: indent 0
			"    local a = 1", -- 2: indent 4
			"    if a then", -- 3: indent 4
			"        local b = 2", -- 4: indent 8
			"    end", -- 5: indent 4
			"end", -- 6: indent 0
		})
		vim.api.nvim_win_set_cursor(0, { 2, 4 })
		indent.refresh(buf)

		local s = indent._scope(buf)
		assert.is_table(s)
		assert.are.equal(0, s.col, "guide sits one shiftwidth left of the cursor indent")
		assert.are.equal(2, s.top)
		assert.are.equal(5, s.bot, "the whole function body is the scope")

		-- Deeper cursor → the inner scope only.
		vim.api.nvim_win_set_cursor(0, { 4, 8 })
		indent.refresh(buf)
		s = indent._scope(buf)
		assert.are.equal(4, s.col)
		assert.are.equal(4, s.top)
		assert.are.equal(4, s.bot)
		cleanup()
	end)

	it("blank lines ride along inside a scope but trim off its edges", function()
		open_lua_file({
			"local function outer()", -- 1
			"    local a = 1", -- 2
			"", -- 3: blank INSIDE the body
			"    local b = 2", -- 4
			"end", -- 5
			"", -- 6: blank after the block
		})
		vim.api.nvim_win_set_cursor(0, { 4, 4 })
		indent.refresh(buf)

		local s = indent._scope(buf)
		assert.are.equal(2, s.top)
		assert.are.equal(4, s.bot, "the trailing blank is not part of the body")
		cleanup()
	end)

	it("top-level lines have no enclosing scope", function()
		open_lua_file({ "local x = 1", "local y = 2" })
		vim.api.nvim_win_set_cursor(0, { 1, 0 })
		indent.refresh(buf)
		assert.is_nil(indent._scope(buf))
		cleanup()
	end)

	it("skips denylisted filetypes and special buftypes", function()
		open_lua_file({ "local function f()", "    return 1", "end" })
		vim.api.nvim_win_set_cursor(0, { 2, 4 })
		vim.bo[buf].filetype = "lazy" -- denylisted
		indent.refresh(buf)
		assert.is_nil(indent._scope(buf))
		cleanup()

		vim.cmd("terminal")
		buf = vim.api.nvim_get_current_buf()
		indent.refresh(buf) -- must be a silent no-op
		assert.is_nil(indent._scope(buf))
		vim.api.nvim_buf_delete(buf, { force = true })
	end)
end)
