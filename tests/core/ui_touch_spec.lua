-- Tests for the touch/focus layer (lua/core/ui-touch.lua).

describe("core.ui-touch", function()
	require("core.ui-touch")

	it("defines the focus/terminal-bar highlight groups", function()
		for _, name in ipairs({ "WinSeparator", "NvFocusNormal", "NvTermFocusBar", "NvTermBarDim", "CursorLine" }) do
			assert.is_truthy(next(vim.api.nvim_get_hl(0, { name = name })), name .. " should be defined")
		end
	end)

	it("gives the dim terminal bar a readable fg (fg != bg) so the label shows when unfocused", function()
		local hl = vim.api.nvim_get_hl(0, { name = "NvTermBarDim" })
		assert.is_not_nil(hl.fg)
		assert.is_not_nil(hl.bg)
		assert.are_not.equal(hl.fg, hl.bg)
	end)

	it("enables mouse move events and continuous box-drawing separators", function()
		assert.is_true(vim.o.mousemoveevent)
		assert.are.equal("│", vim.opt.fillchars:get().vert)
	end)

	it("bakes the buffer number into a focused terminal's winbar expression", function()
		vim.cmd("terminal")
		local win = vim.api.nvim_get_current_win()
		local buf = vim.api.nvim_win_get_buf(win)

		-- focus() runs on TermOpen/WinEnter; give the autocmds a tick to apply.
		vim.wait(500, function()
			return vim.wo[win].winbar ~= ""
		end, 20)

		local wb = vim.wo[win].winbar
		assert.matches("ai%-activity'%.winbar%(", wb)
		local baked = wb:match("winbar%((%d+)%)")
		assert.are.equal(buf, tonumber(baked), "the winbar must reference its own buffer")

		vim.api.nvim_buf_delete(buf, { force = true })
	end)
end)
