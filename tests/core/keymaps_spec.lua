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

	it("exposes the split-resize helper functions globally", function()
		assert.are.equal("function", type(_G.IncreaseWidth))
		assert.are.equal("function", type(_G.DecreaseWidth))
		assert.are.equal("function", type(_G.IncreaseHeight))
		assert.are.equal("function", type(_G.DecreaseHeight))
	end)
end)
