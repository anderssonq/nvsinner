-- Tests for the global keymaps (lua/core/keymaps.lua).

local function map_exists(mode, lhs)
	local m = vim.fn.maparg(lhs, mode, false, true)
	return type(m) == "table" and next(m) ~= nil
end

describe("core.keymaps", function()
	require("core.keymaps")

	it("maps save / undo / redo in normal mode", function()
		assert.is_true(map_exists("n", "<C-Y>"), "<C-Y> should save")
		assert.is_true(map_exists("n", "<C-U>"), "<C-U> should undo")
		assert.is_true(map_exists("n", "<C-R>"), "<C-R> should redo")
	end)

	it("maps the buffer picker", function()
		assert.is_true(map_exists("n", "<leader>fb"))
	end)

	it("defines split-resize maps in normal and terminal mode", function()
		assert.is_true(map_exists("n", "<C-,>"))
		assert.is_true(map_exists("t", "<C-,>"), "resize must also work from terminal mode")
		assert.is_true(map_exists("t", "<C-'>"))
	end)

	it("maps the whole <leader>x* NvSinner shortcut namespace to its commands", function()
		local want = {
			xm = "NvSinnerMenu",
			xh = "NvSinnerHelp",
			xp = "NvSinnerPrompts",
			xo = "NvSinnerSymbols",
			xu = "NvSinnerUpdate",
			xS = "NvSinnerSync",
			xc = "checkhealth nvsinner",
		}
		for suffix, cmd in pairs(want) do
			local m = vim.fn.maparg("<leader>" .. suffix, "n", false, true)
			assert.is_true(type(m) == "table" and next(m) ~= nil, "<leader>" .. suffix .. " must be mapped")
			assert.matches(cmd, m.rhs, nil, true, "<leader>" .. suffix .. " must run " .. cmd)
		end
	end)

	it("resizes the split when the width map is triggered", function()
		-- Behavioral: feed the <C-,> mapping and watch the window grow by the
		-- documented absolute step (+20 columns — Vim ignores a trailing "%" on
		-- :resize, so the step is columns, not a percentage).
		vim.cmd("vsplit")
		local before = vim.api.nvim_win_get_width(0)
		local keys = vim.api.nvim_replace_termcodes("<C-,>", true, false, true)
		vim.api.nvim_feedkeys(keys, "x", false)
		assert.are.equal(before + 20, vim.api.nvim_win_get_width(0))
		vim.cmd("only")
	end)
end)
