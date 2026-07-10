-- Tests for the neo-tree hover row wash (lua/core/neotree-hover.lua): the
-- NvTreeHover carbon group (+ ColorScheme re-apply), the update(mp) seam
-- washing exactly one row and following the pointer, the clear paths (other
-- window / invalid win / float / out-of-range / blank rows), the two-tree
-- handoff, and the WinClosed teardown. Mouse events can't be synthesized
-- headless, so everything drives the update(mp) seam directly.

local hover = require("core.neotree-hover")

describe("core.neotree-hover", function()
	-- A fake tree: scratch buffer in a split tagged with neo-tree's filetype
	-- (same seam as window_picker_spec.lua — the module only reads the ft).
	local function make_tree(lines)
		vim.cmd("vsplit | enew")
		local buf = vim.api.nvim_get_current_buf()
		local win = vim.api.nvim_get_current_win()
		vim.bo[buf].buftype = "nofile"
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines or { "  file-a.lua", "  file-b.lua", "  file-c.lua" })
		vim.bo[buf].filetype = "neo-tree"
		return buf, win
	end

	local function marks(buf)
		return vim.api.nvim_buf_get_extmarks(buf, hover._ns, 0, -1, { details = true })
	end

	before_each(function()
		hover._reset()
		vim.cmd("only")
	end)

	it("styles NvTreeHover with the carbon base01 row wash", function()
		local c = require("core.carbon").colors()
		local hl = vim.api.nvim_get_hl(0, { name = "NvTreeHover" })
		assert.are.equal(tonumber(c.base01:sub(2), 16), hl.bg)
	end)

	it("re-applies NvTreeHover on ColorScheme", function()
		vim.api.nvim_set_hl(0, "NvTreeHover", {})
		assert.is_nil(vim.api.nvim_get_hl(0, { name = "NvTreeHover" }).bg)
		vim.api.nvim_exec_autocmds("ColorScheme", { pattern = "carbon" })
		local c = require("core.carbon").colors()
		assert.are.equal(tonumber(c.base01:sub(2), 16), vim.api.nvim_get_hl(0, { name = "NvTreeHover" }).bg)
	end)

	it("washes exactly the hovered row with NvTreeHover", function()
		local buf, win = make_tree()
		hover.update({ winid = win, line = 2 })
		local ms = marks(buf)
		assert.are.equal(1, #ms)
		assert.are.equal(1, ms[1][2], "0-based row of buffer line 2")
		assert.are.equal("NvTreeHover", ms[1][4].line_hl_group)
	end)

	it("follows the pointer to another row (still one mark)", function()
		local buf, win = make_tree()
		hover.update({ winid = win, line = 1 })
		hover.update({ winid = win, line = 3 })
		local ms = marks(buf)
		assert.are.equal(1, #ms)
		assert.are.equal(2, ms[1][2])
	end)

	it("is a no-op on the cached row (same mark id, no churn)", function()
		local buf, win = make_tree()
		hover.update({ winid = win, line = 2 })
		local id = marks(buf)[1][1]
		hover.update({ winid = win, line = 2 })
		local ms = marks(buf)
		assert.are.equal(1, #ms)
		assert.are.equal(id, ms[1][1], "the extmark was not re-created")
	end)

	it("clears when the pointer reports a non-tree window", function()
		local buf, win = make_tree()
		hover.update({ winid = win, line = 1 })
		vim.cmd("wincmd p") -- the plain code window of the split
		hover.update({ winid = vim.api.nvim_get_current_win(), line = 1 })
		assert.are.equal(0, #marks(buf))
	end)

	it("clears safely on zero / invalid window ids", function()
		local buf, win = make_tree()
		hover.update({ winid = win, line = 1 })
		hover.update({ winid = 0, line = 1 })
		assert.are.equal(0, #marks(buf))
		hover.update({ winid = win, line = 1 })
		hover.update({ winid = 99999, line = 1 })
		assert.are.equal(0, #marks(buf))
	end)

	it("never washes out-of-range or blank rows", function()
		local buf, win = make_tree({ "  file-a.lua", "", "  file-b.lua" })
		hover.update({ winid = win, line = 0 })
		assert.are.equal(0, #marks(buf))
		hover.update({ winid = win, line = 4 })
		assert.are.equal(0, #marks(buf))
		hover.update({ winid = win, line = 2 }) -- the blank padding row
		assert.are.equal(0, #marks(buf))
	end)

	it("hands the wash over between two tree windows", function()
		local buf_a, win_a = make_tree()
		local buf_b, win_b = make_tree()
		hover.update({ winid = win_a, line = 1 })
		hover.update({ winid = win_b, line = 2 })
		assert.are.equal(0, #marks(buf_a), "the first tree lost its wash")
		assert.are.equal(1, #marks(buf_b))
	end)

	it("clears when the hovered tree window closes (buffer survives)", function()
		local buf, win = make_tree()
		hover.update({ winid = win, line = 1 })
		assert.are.equal(1, #marks(buf))
		vim.api.nvim_win_close(win, true)
		assert.is_true(vim.api.nvim_buf_is_valid(buf), "neo-tree keeps its buffer")
		assert.are.equal(0, #marks(buf))
	end)

	it("clears when the pointer is over a float", function()
		local buf, win = make_tree()
		hover.update({ winid = win, line = 1 })
		local float_buf = vim.api.nvim_create_buf(false, true)
		local float = vim.api.nvim_open_win(float_buf, false, {
			relative = "editor",
			width = 5,
			height = 2,
			row = 1,
			col = 1,
		})
		hover.update({ winid = float, line = 1 })
		assert.are.equal(0, #marks(buf))
		vim.api.nvim_win_close(float, true)
	end)
end)
