-- Tests for the :NvSinnerSymbols document-symbols modal (lua/core/symbols.lua):
-- the user command + keymaps, _flatten() on both LSP response shapes (nested
-- DocumentSymbol[] and flat SymbolInformation[]), the float's buffer options,
-- run() jumping the source window to the picked symbol, and the no-LSP-client
-- warn path. The LSP request itself needs a live server, so the modal is
-- exercised through the _set_items/_open_modal seams; mouse clicks aren't
-- exercised headless (the click handler routes into the same run()).

describe("core.symbols", function()
	require("core.options") -- leaders first, so the <leader> maps resolve
	require("core.keymaps")
	local symbols = require("core.symbols")

	before_each(function()
		symbols.close()
	end)

	-- A nested DocumentSymbol tree: class Foo (line 3) containing method bar
	-- (line 5, col 2). Kinds: 5 = Class, 6 = Method.
	local NESTED = {
		{
			name = "Foo",
			kind = 5,
			selectionRange = { start = { line = 2, character = 0 } },
			children = { { name = "bar", kind = 6, selectionRange = { start = { line = 4, character = 2 } } } },
		},
	}

	it("defines the :NvSinnerSymbols command and its keymaps", function()
		assert.is_not_nil(vim.api.nvim_get_commands({})["NvSinnerSymbols"])
		local found_cs, found_xo = false, false
		for _, m in ipairs(vim.api.nvim_get_keymap("n")) do
			if m.lhs == vim.g.mapleader .. "cs" then
				found_cs = true
			end
			if m.lhs == vim.g.mapleader .. "xo" then
				found_xo = true
			end
		end
		assert.is_true(found_cs, "<leader>cs must be mapped")
		assert.is_true(found_xo, "<leader>xo must be mapped")
	end)

	it("_flatten() walks nested DocumentSymbols, indenting children", function()
		local rows = symbols._flatten(NESTED, 0)
		assert.are.equal(2, #rows)
		assert.are.same({ name = "Foo", kind = "Class", lnum = 2, col = 0, depth = 0 }, rows[1])
		assert.are.same({ name = "bar", kind = "Method", lnum = 4, col = 2, depth = 1 }, rows[2])
	end)

	it("_flatten() reads flat SymbolInformation locations and skips position-less entries", function()
		local rows = symbols._flatten({
			{ name = "CONST", kind = 14, location = { range = { start = { line = 9, character = 1 } } } },
			{ name = "broken", kind = 13 }, -- no selectionRange, no location → skipped
		}, 0)
		assert.are.equal(1, #rows)
		assert.are.equal("Constant", rows[1].kind)
		assert.are.equal(9, rows[1].lnum)
	end)

	it("opens a non-modifiable nvsinner_symbols float listing every symbol", function()
		local src = vim.api.nvim_get_current_win()
		symbols._set_items(symbols._flatten(NESTED, 0), src)
		symbols._open_modal()
		local win = vim.api.nvim_get_current_win()
		local buf = vim.api.nvim_get_current_buf()
		assert.are.equal("editor", vim.api.nvim_win_get_config(win).relative, "must be a float")
		assert.are.equal("nvsinner_symbols", vim.bo[buf].filetype)
		assert.are.equal("nofile", vim.bo[buf].buftype)
		assert.is_false(vim.bo[buf].modifiable)
		assert.is_true(vim.wo[win].cursorline)
		local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
		assert.matches("Foo", text, nil, true)
		assert.matches("bar", text, nil, true)
		assert.matches("q close", text, nil, true) -- the keyboard hint line
		symbols.close()
	end)

	it("run() jumps the source window to the picked symbol and closes", function()
		local buf = vim.api.nvim_create_buf(true, false)
		local lines = {}
		for i = 1, 10 do
			lines[i] = string.rep("x", 20)
		end
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		vim.api.nvim_set_current_buf(buf)
		local src = vim.api.nvim_get_current_win()

		symbols._set_items(symbols._flatten(NESTED, 0), src)
		symbols._open_modal()
		local modal = vim.api.nvim_get_current_win()
		symbols.move(1) -- onto "bar" (line 5, col 2)
		local it = symbols.run()

		assert.are.equal("bar", it.name)
		assert.are.equal(src, vim.api.nvim_get_current_win(), "must return to the source window")
		assert.is_false(vim.api.nvim_win_is_valid(modal), "must close the modal")
		assert.are.same({ 5, 2 }, vim.api.nvim_win_get_cursor(src))
	end)

	it("show_symbols() warns instead of erroring with no LSP client attached", function()
		local warned
		local old = vim.notify
		vim.notify = function(msg, level)
			warned = { msg = msg, level = level }
		end
		symbols.show_symbols()
		vim.notify = old
		assert.is_table(warned)
		assert.matches("no LSP client", warned.msg, nil, true)
		assert.are.equal(vim.log.levels.WARN, warned.level)
	end)
end)
