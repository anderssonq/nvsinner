-- Tests for the :NvSinnerMenu settings modal (lua/core/menu.lua): the user
-- command, the float and its rendered rows, and the move/cycle interaction
-- writing through to core/settings. Mouse clicks aren't exercised headless;
-- the click handler routes into the same cycle() these specs cover.

describe("core.menu", function()
	local settings = require("core.settings")
	local menu = require("core.menu")

	before_each(function()
		-- Throwaway persistence so cycling in a spec never touches real settings.
		settings.load({ file = vim.fn.tempname() })
		menu.close()
	end)

	it("defines the :NvSinnerMenu user command", function()
		assert.is_not_nil(vim.api.nvim_get_commands({})["NvSinnerMenu"])
	end)

	it("opens a floating modal listing every settings row", function()
		menu.open()
		local win = vim.api.nvim_get_current_win()
		assert.are.equal("editor", vim.api.nvim_win_get_config(win).relative, "must be a float")
		local text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
		local rows = {
			"Background theme",
			"Transparency",
			"Accent",
			"Folder color",
			"Notif color",
			"Variables",
			"Strings",
			"Functions",
			"Neo-tree side",
			"AI column side",
			"Notifications",
		}
		for _, row in ipairs(rows) do
			assert.matches(row, text, nil, true)
		end
		assert.matches("q close", text, nil, true) -- the keyboard hint line
		menu.close()
		assert.are_not.equal(win, vim.api.nvim_get_current_win())
	end)

	it("cycle() walks the background themes in carbon's declared order", function()
		local saved = vim.g.nvsinner_theme
		menu.open()
		menu.move(-99) -- row 1: Background theme
		assert.are.equal("carbon", settings.get("theme"))
		menu.cycle(1)
		assert.are.equal("moon", settings.get("theme"))
		assert.are.equal("moon", vim.g.nvsinner_theme, "cycling must apply the flag live")
		menu.cycle(-1) -- and back
		assert.are.equal("carbon", settings.get("theme"))
		menu.close()
		vim.g.nvsinner_theme = saved
		vim.cmd.colorscheme("carbon")
	end)

	it("cycle() changes and persists the selected setting", function()
		menu.open()
		menu.move(-99) -- clamp to the first row…
		menu.move(8) -- …then land on row 9: Neo-tree side (left/right)
		assert.are.equal("left", settings.get("tree_side"))
		menu.cycle(1)
		assert.are.equal("right", settings.get("tree_side"))
		menu.cycle(1) -- wraps around
		assert.are.equal("left", settings.get("tree_side"))
		menu.close()
	end)
end)
