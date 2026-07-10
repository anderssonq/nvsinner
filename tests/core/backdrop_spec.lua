-- Tests for the shared modal backdrop (lua/core/backdrop.lua): attach()
-- opening a full-screen, non-focusable, winblend-washed float one zindex
-- layer below the given window, the WinClosed teardown when that window
-- closes, the invalid-window guard, and the interaction guard — the backdrop
-- consumes mouse events (mouse = true, no click-through) and a WinEnter trap
-- bounces focus that escapes to a non-floating window back to the modal
-- (floats stay exempt so vim.ui pickers can layer on top). The NvMenuBackdrop
-- group must carry the carbon `backdrop` role.

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

	it("the backdrop consumes mouse events instead of passing them through", function()
		-- focusable=false alone makes a float mouse-transparent (the `mouse`
		-- config field defaults to the focusable value), so a click on the dim
		-- would reach the editor behind the modal. The guard is mouse = true.
		local modal = open_modal()
		local bd = backdrop.attach(modal)
		assert.is_true(vim.api.nvim_win_get_config(bd).mouse, "clicks on the dim must be consumed")
		vim.api.nvim_win_close(modal, true)
	end)

	it("bounces focus escaping to a non-floating window back to the modal", function()
		local main = vim.api.nvim_get_current_win()
		local modal = open_modal()
		backdrop.attach(modal)
		vim.api.nvim_set_current_win(main) -- focus escapes (e.g. <C-w>w)
		local bounced = vim.wait(1000, function()
			return vim.api.nvim_get_current_win() == modal
		end, 10)
		assert.is_true(bounced, "the trap must restore focus to the modal")
		vim.api.nvim_win_close(modal, true)
	end)

	it("lets a floating window (vim.ui picker) keep focus over the modal", function()
		local modal = open_modal()
		backdrop.attach(modal)
		local pbuf = vim.api.nvim_create_buf(false, true)
		local picker = vim.api.nvim_open_win(pbuf, true, {
			relative = "editor",
			row = 1,
			col = 1,
			width = 10,
			height = 3,
			style = "minimal",
			zindex = 200,
		})
		vim.wait(200, function()
			return vim.api.nvim_get_current_win() ~= picker
		end, 10)
		assert.are.equal(picker, vim.api.nvim_get_current_win(), "floats layered on the modal keep focus")
		vim.api.nvim_win_close(picker, true)
		vim.api.nvim_win_close(modal, true)
	end)

	it("drops the focus trap when the modal closes", function()
		local main = vim.api.nvim_get_current_win()
		local modal = open_modal()
		backdrop.attach(modal)
		vim.api.nvim_win_close(modal, true) -- user closed the modal
		vim.api.nvim_set_current_win(main)
		vim.wait(200, function()
			return vim.api.nvim_get_current_win() ~= main
		end, 10)
		assert.are.equal(main, vim.api.nvim_get_current_win(), "no bounce once the modal is gone")
	end)

	it("NvMenuBackdrop carries the carbon backdrop role", function()
		local hl = vim.api.nvim_get_hl(0, { name = "NvMenuBackdrop" })
		local want = require("core.carbon").colors().backdrop:gsub("#", ""):lower()
		assert.are.equal(want, string.format("%06x", hl.bg))
	end)
end)
