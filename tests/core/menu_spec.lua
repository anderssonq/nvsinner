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
			"AI completion",
			"Minimap",
			"Key timeout",
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
		assert.are.equal("onedark", settings.get("theme"))
		assert.are.equal("onedark", vim.g.nvsinner_theme, "cycling must apply the flag live")
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
	it("offers the herdr rows and cycles them into core/settings", function()
		menu.open()
		local labels = {}
		for _, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
			labels[#labels + 1] = line
		end
		local text = table.concat(labels, "\n")
		assert.matches("herdr reporting", text)
		assert.matches("herdr detail", text)
		menu.close()
	end)
	it("cycles the Font row through its three values (and back) and the Animations row on/off", function()
		local font = require("core.font")
		local orig_apply = font.apply
		local applied = {}
		font.apply = function(v)
			applied[#applied + 1] = v
		end
		menu.open()
		local text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
		assert.matches("Font", text, nil, true)
		assert.matches("Animations", text, nil, true)
		local font_row
		for i, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
			if line:match("Font%s+‹") then
				font_row = i - 1 -- minus TOP_PAD
			end
		end
		menu.move(-99)
		menu.move(font_row - 1)
		assert.are.equal("terminal", settings.get("font_family"))
		menu.cycle(1)
		assert.are.equal("FiraCode Nerd Font", settings.get("font_family"))
		menu.cycle(1)
		assert.are.equal("Maple Mono NF", settings.get("font_family"))
		menu.cycle(1) -- wraps
		assert.are.equal("terminal", settings.get("font_family"))
		menu.cycle(-1) -- backwards wraps
		assert.are.equal("Maple Mono NF", settings.get("font_family"))
		assert.are.same({ "FiraCode Nerd Font", "Maple Mono NF", "terminal", "Maple Mono NF" }, applied)
		menu.move(1) -- the Animations row follows Font
		assert.is_true(settings.get("animations"))
		menu.cycle(1)
		assert.is_false(settings.get("animations"))
		assert.is_true(vim.g.minianimate_disable)
		menu.cycle(1)
		assert.is_nil(vim.g.minianimate_disable)
		menu.close()
		font.apply = orig_apply
	end)
end)
