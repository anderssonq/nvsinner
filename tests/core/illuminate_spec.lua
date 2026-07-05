-- Tests for the native symbol-occurrence highlight (lua/core/illuminate.lua):
-- the LspReference* carbon underlines, the visible-range fallback marking
-- every occurrence of the cursor word (word-boundary strict), movement
-- clearing, and the denylist/large-file/special-buffer guards.

local illum = require("core.illuminate")

describe("core.illuminate", function()
	local path, buf

	-- A real lua file: Neovim bundles the lua treesitter parser, so the
	-- parser-backed fallback path runs headless without nvim-treesitter.
	local function open_lua_file(lines)
		path = vim.fn.tempname() .. "_illum.lua"
		vim.fn.writefile(lines, path)
		vim.cmd("edit " .. vim.fn.fnameescape(path))
		buf = vim.api.nvim_get_current_buf()
	end

	local function marks()
		return vim.api.nvim_buf_get_extmarks(buf, illum._ns, 0, -1, { details = true })
	end

	before_each(function()
		illum._reset()
	end)

	it("styles the LspReference* groups with the carbon panel grays", function()
		local c = require("core.carbon").colors()
		local text = vim.api.nvim_get_hl(0, { name = "LspReferenceText" })
		local write = vim.api.nvim_get_hl(0, { name = "LspReferenceWrite" })
		assert.is_true(text.underline == true)
		assert.are.equal(tonumber(c.base01:sub(2), 16), text.bg)
		assert.are.equal(tonumber(c.base02:sub(2), 16), write.bg, "writes read one step brighter")
	end)

	it("marks every visible occurrence of the cursor word, word-boundary strict", function()
		open_lua_file({
			"local count = 1",
			"count = count + 1",
			"local counter = count", -- `counter` must NOT match
		})
		vim.api.nvim_win_set_cursor(0, { 1, 7 }) -- on `count`
		illum.refresh(buf)

		local got = marks()
		assert.are.equal(4, #got, "count appears 4 times; counter must not match")
		for _, m in ipairs(got) do
			assert.are.equal("LspReferenceText", m[4].hl_group)
		end

		vim.cmd("bwipeout!")
		os.remove(path)
	end)

	it("clear() wipes the occurrence marks (movement path)", function()
		open_lua_file({ "local x = x" })
		vim.api.nvim_win_set_cursor(0, { 1, 6 })
		illum.refresh(buf)
		assert.is_true(#marks() > 0)

		illum.clear(buf)
		assert.are.equal(0, #marks())

		vim.cmd("bwipeout!")
		os.remove(path)
	end)

	it("skips denylisted filetypes, huge buffers, and special buftypes", function()
		open_lua_file({ "local y = y" })
		vim.api.nvim_win_set_cursor(0, { 1, 6 })

		vim.bo[buf].filetype = "lazy" -- denylisted
		illum.refresh(buf)
		assert.are.equal(0, #marks())

		vim.bo[buf].filetype = "lua"
		local huge = {}
		for i = 1, illum.MAX_LINES + 1 do
			huge[i] = "local y = y -- " .. i
		end
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, huge)
		illum.refresh(buf)
		assert.are.equal(0, #marks(), "beyond MAX_LINES the buffer is skipped")

		vim.cmd("bwipeout!")
		os.remove(path)

		vim.cmd("terminal")
		buf = vim.api.nvim_get_current_buf()
		illum.refresh(buf) -- must be a silent no-op
		assert.are.equal(0, #marks())
		vim.api.nvim_buf_delete(buf, { force = true })
	end)
end)
