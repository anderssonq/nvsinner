-- Tests for the :NvSinnerHelp command palette (lua/core/help.lua): the user
-- command, refresh() discovering every NvSinner* command (self excluded) plus
-- the :checkhealth extra, the float rendering title + description rows, and
-- run() executing the selection and auto-closing. Mouse clicks aren't
-- exercised headless; the click handler routes into the same run().

describe("core.help", function()
	-- Load the modules that register the real commands the palette discovers.
	require("core.menu")
	require("core.prompts")
	require("core.update")
	local help = require("core.help")

	before_each(function()
		help.close()
	end)

	local function titles()
		return vim.tbl_map(function(it)
			return it.title
		end, help.refresh())
	end

	it("defines the :NvSinnerHelp user command", function()
		assert.is_not_nil(vim.api.nvim_get_commands({})["NvSinnerHelp"])
	end)

	it("discovers every NvSinner command (not itself) plus checkhealth", function()
		local t = titles()
		for _, want in ipairs({ ":NvSinnerMenu", ":NvSinnerPrompts", ":NvSinnerUpdate", ":checkhealth nvsinner" }) do
			assert.is_true(vim.tbl_contains(t, want), want .. " missing from " .. vim.inspect(t))
		end
		assert.is_false(vim.tbl_contains(t, ":NvSinnerHelp"), "the palette must not list itself")
	end)

	it("picks up commands registered after load, with their desc", function()
		vim.api.nvim_create_user_command("NvSinnerTestProbe", function() end, { desc = "probe desc" })
		local items = help.refresh()
		local found
		for _, it in ipairs(items) do
			if it.title == ":NvSinnerTestProbe" then
				found = it
			end
		end
		vim.api.nvim_del_user_command("NvSinnerTestProbe")
		assert.is_table(found)
		assert.are.equal("probe desc", found.desc)
	end)

	it("opens a floating modal listing every command with its description", function()
		help.open()
		local win = vim.api.nvim_get_current_win()
		assert.are.equal("editor", vim.api.nvim_win_get_config(win).relative, "must be a float")
		local text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
		for _, row in ipairs({ ":NvSinnerMenu", ":NvSinnerPrompts", ":NvSinnerUpdate", ":checkhealth nvsinner" }) do
			assert.matches(row, text, nil, true)
		end
		assert.matches("q close", text, nil, true) -- the keyboard hint line
		help.close()
		assert.are_not.equal(win, vim.api.nvim_get_current_win())
	end)

	it("run() executes the selected command and auto-closes the modal", function()
		local fired = false
		vim.api.nvim_create_user_command("NvSinnerTestProbe", function()
			fired = true
		end, { desc = "probe" })

		help.open()
		local win = vim.api.nvim_get_current_win()
		-- Find the probe's row index, then walk the selection onto it.
		local target
		for i, it in ipairs(help.refresh()) do
			if it.cmd == "NvSinnerTestProbe" then
				target = i
			end
		end
		assert.is_number(target)
		help.move(-99) -- clamp to the first row…
		help.move(target - 1) -- …then land on the probe
		local ran = help.run()

		vim.api.nvim_del_user_command("NvSinnerTestProbe")

		assert.are.equal("NvSinnerTestProbe", ran)
		assert.is_true(fired, "run() must execute the picked command")
		assert.are_not.equal(win, vim.api.nvim_get_current_win(), "run() must auto-close the modal")
	end)
end)
