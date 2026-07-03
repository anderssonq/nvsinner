-- Tests for the :NvSinnerPrompts prompt-library modal (lua/core/prompts.lua):
-- the user command, JSON loading (object/array content, corrupt-file fallback)
-- via the { file = … } test seam, the float rendering title + description
-- rows, and copy() closing the modal with the prompt text. Mouse clicks aren't
-- exercised headless; the click handler routes into the same copy().

describe("core.prompts", function()
	local prompts = require("core.prompts")

	local temp
	local function write_library(tbl)
		local fd = assert(io.open(temp, "w"))
		fd:write(type(tbl) == "string" and tbl or vim.json.encode(tbl))
		fd:close()
	end

	before_each(function()
		prompts.close()
		-- Re-point the library at a throwaway file so specs never read the
		-- repo's real settings/prompts.json.
		temp = vim.fn.tempname()
		write_library({
			prompts = {
				{ title = "Alpha", description = "first prompt", content = { "line one", "line two" } },
				{ title = "Beta", description = "second prompt", content = "plain string body" },
			},
		})
		prompts.load({ file = temp })
	end)

	it("defines the :NvSinnerPrompts user command", function()
		assert.is_not_nil(vim.api.nvim_get_commands({})["NvSinnerPrompts"])
	end)

	it("loads titles and joins array content into one string", function()
		local items = prompts.load({ file = temp })
		assert.are.equal(2, #items)
		assert.are.equal("Alpha", items[1].title)
		assert.are.equal("line one\nline two", items[1].content)
		assert.are.equal("plain string body", items[2].content)
	end)

	it("skips invalid entries and survives a corrupt file", function()
		write_library({ prompts = { { title = "NoContent" }, { content = "no title" }, "junk" } })
		assert.are.equal(0, #prompts.load({ file = temp }))
		write_library("{ not json !!!")
		assert.are.equal(0, #prompts.load({ file = temp }))
	end)

	it("opens a floating modal listing every prompt with its description", function()
		prompts.open()
		local win = vim.api.nvim_get_current_win()
		assert.are.equal("editor", vim.api.nvim_win_get_config(win).relative, "must be a float")
		local text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
		for _, row in ipairs({ "Alpha", "first prompt", "Beta", "second prompt" }) do
			assert.matches(row, text, nil, true)
		end
		assert.matches("q close", text, nil, true) -- the keyboard hint line
		prompts.close()
		assert.are_not.equal(win, vim.api.nvim_get_current_win())
	end)

	it("copy() returns the selected prompt with a trailing newline and closes", function()
		local toasts = {}
		local orig = vim.notify
		vim.notify = function(msg)
			toasts[#toasts + 1] = msg
		end

		prompts.open()
		local win = vim.api.nvim_get_current_win()
		prompts.move(-99) -- clamp to the first prompt
		prompts.move(1) -- land on Beta
		local copied = prompts.copy()

		vim.notify = orig -- restore BEFORE asserting so a failure can't leak it

		assert.are.equal("plain string body\n", copied)
		assert.are_not.equal(win, vim.api.nvim_get_current_win(), "copy must close the modal")
		assert.are.equal(1, #toasts)
		assert.matches("Beta", toasts[1], nil, true)
	end)

	it("opens with an edit hint when the library is empty", function()
		write_library("{ not json !!!")
		prompts.load({ file = temp })
		prompts.open()
		local text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
		assert.matches("No prompts found", text, nil, true)
		assert.is_nil(prompts.copy(), "copy() on an empty library must return nil")
		prompts.close()
	end)
end)
