-- Tests for the native hex color chips (lua/core/colorizer.lua): #rgb /
-- #rrggbb / #rrggbbaa literals get a bg chip in their own color with a
-- carbon-role contrast fg, invalid lengths and glued tokens are skipped,
-- rescans replace old marks, and special buffers are skipped.

local colorizer = require("core.colorizer")

describe("core.colorizer", function()
	local path, buf

	local function open_file(lines)
		path = vim.fn.tempname() .. "_colors.css"
		vim.fn.writefile(lines, path)
		vim.cmd("edit " .. vim.fn.fnameescape(path))
		buf = vim.api.nvim_get_current_buf()
	end

	local function marks()
		return vim.api.nvim_buf_get_extmarks(buf, colorizer._ns, 0, -1, { details = true })
	end

	local function cleanup()
		vim.cmd("bwipeout!")
		os.remove(path)
	end

	it("chips a #rrggbb literal with its own color as bg", function()
		open_file({ "a { color: #ff0000; }" })
		colorizer.refresh(buf)

		local got = marks()
		assert.are.equal(1, #got)
		assert.are.equal("NvColorFF0000", got[1][4].hl_group)
		local hl = vim.api.nvim_get_hl(0, { name = "NvColorFF0000" })
		assert.are.equal(0xff0000, hl.bg)
		cleanup()
	end)

	it("expands #rgb, accepts #rrggbbaa, and picks a readable fg per chip", function()
		open_file({ "x: #fff;", "y: #00000080;" })
		colorizer.refresh(buf)

		local got = marks()
		assert.are.equal(2, #got)
		local c = require("core.carbon").colors()
		local light = vim.api.nvim_get_hl(0, { name = "NvColorFFFFFF" })
		local dark = vim.api.nvim_get_hl(0, { name = "NvColor000000" })
		assert.are.equal(0xffffff, light.bg, "#fff expands to ffffff")
		assert.are.equal(0x000000, dark.bg, "the alpha byte is dropped")
		assert.are.equal(tonumber(c.base00:sub(2), 16), light.fg, "dark text on a light chip")
		assert.are.equal(tonumber(c.base06:sub(2), 16), dark.fg, "white text on a dark chip")
		cleanup()
	end)

	it("skips invalid lengths and glued tokens", function()
		open_file({ "bad: #ff00;", "glued: abc#fff;", "double: ##fff;" })
		colorizer.refresh(buf)
		assert.are.equal(0, #marks())
		cleanup()
	end)

	it("a rescan replaces the previous marks", function()
		open_file({ "a: #ff0000;" })
		colorizer.refresh(buf)
		assert.are.equal(1, #marks())

		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "no colors here" })
		colorizer.refresh(buf)
		assert.are.equal(0, #marks())
		cleanup()
	end)

	it("skips special buftypes", function()
		vim.cmd("terminal")
		buf = vim.api.nvim_get_current_buf()
		colorizer.refresh(buf) -- must be a silent no-op
		assert.are.equal(0, #marks())
		vim.api.nvim_buf_delete(buf, { force = true })
	end)
end)
