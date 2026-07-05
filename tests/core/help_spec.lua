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

	it("groups commands under section rule headers, items on their computed lines", function()
		help.open()
		local buf = vim.api.nvim_get_current_buf()
		local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
		local text = table.concat(lines, "\n")
		-- The known sections render as "─ NAME ───…" rules.
		for _, hdr in ipairs({ "─ AI ", "─ SETTINGS ", "─ MAINTENANCE " }) do
			assert.matches(hdr, text, nil, true)
		end
		-- The layout is non-uniform (headers interleave), so every item must
		-- actually sit on the buffer line refresh() computed for it.
		for _, it in ipairs(help.refresh()) do
			assert.matches(it.title, lines[it.line], nil, true)
		end
		help.close()
	end)

	it("never renders a description the command registry mangled", function()
		-- nvim_get_commands' `definition` corrupts multi-byte chars and <...>
		-- keycodes for Lua commands; the sanitizer must leave every discovered
		-- description strtrans-clean (intact or blanked — never raw bytes).
		vim.api.nvim_create_user_command("NvSinnerTestProbe", function() end, {
			desc = "mangled — <leader>z probe",
		})
		local items = help.refresh()
		vim.api.nvim_del_user_command("NvSinnerTestProbe")
		for _, it in ipairs(items) do
			assert.are.equal(vim.fn.strtrans(it.desc), it.desc, "raw bytes leaked into: " .. it.title)
		end
	end)

	it("opens on the solid NvMenuNormal surface with a backdrop behind it", function()
		local before = #vim.api.nvim_list_wins()
		help.open()
		local modal = vim.api.nvim_get_current_win()
		assert.matches("NvMenuNormal", vim.wo[modal].winhighlight, nil, true)
		assert.are.equal(before + 2, #vim.api.nvim_list_wins(), "modal + backdrop expected")
		help.close()
		vim.wait(200, function()
			return #vim.api.nvim_list_wins() == before
		end)
		assert.are.equal(before, #vim.api.nvim_list_wins(), "backdrop must close with the modal")
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
