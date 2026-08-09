-- Tests for the native window picker (lua/core/window-picker.lua): the
-- package.preload shim serving neo-tree's `require("window-picker")`, the
-- candidate filter (floats + denylisted ft/buftype out), single-candidate
-- autoselect, the letter-overlay pick flow (choice, abort, overlay
-- teardown), the NvWinPick carbon chip group, and `editable_win(tabpage)` —
-- the "which window may a file be :edit-ed into" answer diffview's round-trip
-- exit needs for ANOTHER tabpage.

local picker = require("core.window-picker")

describe("core.window-picker", function()
	local orig_getchar = picker._getchar

	local function floats()
		local n = 0
		for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
			if vim.api.nvim_win_get_config(win).relative ~= "" then
				n = n + 1
			end
		end
		return n
	end

	before_each(function()
		picker._getchar = orig_getchar
		vim.cmd("only")
	end)

	it("serves require('window-picker') with the pick_window API (neo-tree seam)", function()
		package.loaded["window-picker"] = nil
		local served = require("window-picker")
		assert.are.equal(picker, served, "the preload shim hands out the native module")
		assert.is_function(served.pick_window)
		assert.is_function(served.setup)
	end)

	it("styles NvWinPick as a carbon accent chip", function()
		local c = require("core.carbon").colors()
		local hl = vim.api.nvim_get_hl(0, { name = "NvWinPick" })
		assert.are.equal(tonumber(c.base09:sub(2), 16), hl.bg)
		assert.are.equal(tonumber(c.base00:sub(2), 16), hl.fg)
	end)

	it("filters floats and denylisted windows out of the candidates", function()
		-- The split gets its OWN buffer (a bare vsplit shares one buffer
		-- across both windows, which would denylist both at once below).
		vim.cmd("vsplit | enew")
		local split_buf = vim.api.nvim_get_current_buf()
		local float_buf = vim.api.nvim_create_buf(false, true)
		local float = vim.api.nvim_open_win(float_buf, false, {
			relative = "editor",
			width = 5,
			height = 2,
			row = 1,
			col = 1,
		})
		assert.are.equal(2, #picker._candidates(), "the float is not a candidate")
		vim.api.nvim_win_close(float, true)

		vim.bo[split_buf].filetype = "neo-tree"
		assert.are.equal(1, #picker._candidates(), "denylisted filetypes are excluded")
		vim.bo[split_buf].filetype = ""
	end)

	it("returns the single candidate without prompting", function()
		picker._getchar = function()
			error("must not prompt for a single window")
		end
		assert.are.equal(vim.api.nvim_get_current_win(), picker.pick_window({}))
	end)

	it("letter-overlays multiple windows and returns the picked one", function()
		vim.cmd("vsplit")
		local wins = picker._candidates()
		assert.are.equal(2, #wins)

		local seen_overlays
		picker._getchar = function()
			seen_overlays = floats()
			return "j" -- second letter of CHARS, lowercase on purpose
		end
		local picked = picker.pick_window({})
		assert.are.equal(2, seen_overlays, "one letter chip float per candidate")
		assert.are.equal(wins[2], picked)
		assert.are.equal(0, floats(), "the overlays are torn down")
	end)

	it("returns nil on abort (<Esc>) and still tears the overlays down", function()
		vim.cmd("vsplit")
		picker._getchar = function()
			return "\27"
		end
		assert.is_nil(picker.pick_window({}))
		assert.are.equal(0, floats())
	end)

	-- `:edit` in another tabpage lands in whatever window that tab last focused.
	-- editable_win is what keeps a file from being dropped into neo-tree or an
	-- AI terminal column; the real regression is the CURRENT window being unfit.
	describe("editable_win", function()
		it("keeps the tab's current window when it is an ordinary pane", function()
			vim.cmd("vsplit | enew")
			local cur = vim.api.nvim_get_current_win()
			assert.are.equal(cur, picker.editable_win(0))
		end)

		it("skips the tree and picks a real pane instead", function()
			vim.cmd("vsplit | enew")
			local tree = vim.api.nvim_get_current_win()
			local tree_buf = vim.api.nvim_get_current_buf()
			vim.bo[tree_buf].filetype = "neo-tree"

			local picked = picker.editable_win(0)
			assert.is_not_nil(picked)
			assert.are_not.equal(tree, picked, "the tree window is never an edit target")
			assert.is_true(picker._editable(picked))
			vim.bo[tree_buf].filetype = ""
		end)

		it("skips terminal buffers (the AI column is not an edit target)", function()
			vim.cmd("vsplit | terminal")
			local term = vim.api.nvim_get_current_win()
			assert.are.equal("terminal", vim.bo[vim.api.nvim_get_current_buf()].buftype)
			assert.are_not.equal(term, picker.editable_win(0))
		end)

		it("never answers a float", function()
			local float_buf = vim.api.nvim_create_buf(false, true)
			local float = vim.api.nvim_open_win(float_buf, true, {
				relative = "editor",
				width = 5,
				height = 2,
				row = 1,
				col = 1,
			})
			local picked = picker.editable_win(0)
			assert.are_not.equal(float, picked, "a float is not somewhere to edit a file")
			vim.api.nvim_win_close(float, true)
		end)

		it("answers nil when the tabpage has no usable window", function()
			-- A lone terminal: the caller must fall back, not edit into it.
			vim.cmd("terminal")
			assert.is_nil(picker.editable_win(0))
		end)

		it("resolves another tabpage, not just the current one", function()
			local home = vim.api.nvim_get_current_tabpage()
			vim.cmd("tabnew")
			local other = vim.api.nvim_get_current_tabpage()
			local other_win = vim.api.nvim_get_current_win()
			vim.api.nvim_set_current_tabpage(home)

			assert.are.equal(other_win, picker.editable_win(other))
			vim.api.nvim_set_current_tabpage(other)
			vim.cmd("tabclose")
		end)
	end)
end)
