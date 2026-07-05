-- Tests for the shared modal backdrop (lua/core/backdrop.lua): attach()
-- opening a full-screen, non-focusable, winblend-washed float one zindex
-- layer below the given window, the WinClosed teardown when that window
-- closes, and the invalid-window guard. The NvMenuBackdrop group must carry
-- the carbon `backdrop` role.

describe("core.backdrop", function()
	local backdrop = require("core.backdrop")

	-- A small host float standing in for a modal window.
	local function open_modal()
		local buf = vim.api.nvim_create_buf(false, true)
		return vim.api.nvim_open_win(buf, true, {
			relative = "editor",
			row = 2,
			col = 2,
			width = 20,
			height = 5,
			style = "minimal",
		})
	end

	it("attach() opens a full-screen dim float below the modal", function()
		local modal = open_modal()
		local bd = backdrop.attach(modal)
		assert.is_number(bd)
		local cfg = vim.api.nvim_win_get_config(bd)
		assert.are.equal("editor", cfg.relative)
		assert.is_false(cfg.focusable)
		assert.are.equal(vim.o.columns, cfg.width)
		assert.are.equal(vim.o.lines, cfg.height)
		assert.is_true(cfg.zindex < vim.api.nvim_win_get_config(modal).zindex, "backdrop must sit below the modal")
		assert.are.equal(60, vim.wo[bd].winblend)
		assert.matches("NvMenuBackdrop", vim.wo[bd].winhighlight, nil, true)
		assert.are.equal(modal, vim.api.nvim_get_current_win(), "attach() must not steal focus")
		vim.api.nvim_win_close(modal, true)
	end)

	it("tears the backdrop down when the modal window closes", function()
		local modal = open_modal()
		local bd = backdrop.attach(modal)
		vim.api.nvim_win_close(modal, true)
		vim.wait(200, function()
			return not vim.api.nvim_win_is_valid(bd)
		end)
		assert.is_false(vim.api.nvim_win_is_valid(bd), "backdrop must close with its modal")
	end)

	it("attach() returns nil for a missing or invalid window", function()
		assert.is_nil(backdrop.attach(nil))
		assert.is_nil(backdrop.attach(999999))
	end)

	it("NvMenuBackdrop carries the carbon backdrop role", function()
		local hl = vim.api.nvim_get_hl(0, { name = "NvMenuBackdrop" })
		local want = require("core.carbon").colors().backdrop:gsub("#", ""):lower()
		assert.are.equal(want, string.format("%06x", hl.bg))
	end)
end)
