-- Tests for the native per-window file badge (lua/core/filebadge.lua) — the
-- in-repo replacement for incline.nvim: winbar badge (focus dot · filename ·
-- modified dot), barbecue custom_section adapter, and the markdown winbar
-- ownership with the "Open view" chip click region.

describe("core.filebadge", function()
	local badge = require("core.filebadge")

	local function hl(name)
		return vim.api.nvim_get_hl(0, { name = name })
	end

	it("defines the carbon badge highlight groups", function()
		local c = require("core.carbon").colors()
		local function hex(n)
			return string.format("#%06x", hl(n).fg)
		end
		assert.equals(c.base09:lower(), hex("NvBadgeDot"):lower())
		assert.equals(c.base04:lower(), hex("NvBadgeFile"):lower())
		assert.equals(c.base10:lower(), hex("NvBadgeMod"):lower())
		assert.equals(c.base09:lower(), hex("NvBadgeChip"):lower())
	end)

	it("parts() carries the focus dot, the filename, and the modified dot", function()
		local buf = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_buf_set_name(buf, "badge_test.txt")
		vim.bo[buf].modified = true

		local function texts(focused)
			local out = {}
			for _, p in ipairs(badge.parts(buf, focused)) do
				out[#out + 1] = p[1]
			end
			return table.concat(out)
		end

		assert.matches("● .*badge_test%.txt ●", texts(true))
		local unfocused = texts(false)
		assert.matches("badge_test%.txt ●", unfocused)
		assert.is_nil(unfocused:match("^● "))

		vim.bo[buf].modified = false
		assert.is_nil(texts(true):match("badge_test%.txt ●"))
		vim.api.nvim_buf_delete(buf, { force = true })
	end)

	it("section() hands barbecue the dynamic fragment expression", function()
		assert.equals(badge.SECTION_EXPR, badge.section())
		assert.matches("filebadge'%.fragment%(%)", badge.SECTION_EXPR)
	end)

	it("fragment() escapes '%' and decides focus at draw time via g:actual_curwin", function()
		vim.cmd("enew")
		vim.api.nvim_buf_set_name(0, "100%_done.txt")

		-- drawn window IS the focused one → focus dot
		vim.g.actual_curwin = tostring(vim.api.nvim_get_current_win())
		local focused = badge.fragment()
		assert.matches("100%%%%_done%.txt", focused)
		assert.matches("● ", focused)
		assert.matches("NvBadgeFile#", focused)

		-- drawn window is NOT the focused one → no dot, muted name
		vim.g.actual_curwin = "-1"
		local unfocused = badge.fragment()
		assert.is_nil(unfocused:match("NvBadgeDot"))
		assert.matches("NvBadgeFileNC#", unfocused)

		vim.g.actual_curwin = nil
		vim.cmd("bwipeout!")
	end)

	it("owns the winbar of markdown windows", function()
		vim.cmd("enew")
		vim.bo.filetype = "markdown"
		assert.equals(badge.EXPR, vim.wo.winbar)
		vim.bo.filetype = ""
		vim.cmd("bwipeout!")
	end)

	it("winbar() renders the badge and the Open view chip click region", function()
		vim.cmd("enew")
		vim.api.nvim_buf_set_name(0, "chip_test.md")
		vim.bo.filetype = "markdown"
		local saved = _G.NvMdReader
		_G.NvMdReader = {
			label = function()
				return "󰈙 Open view"
			end,
			click = function() end,
		}

		local s = badge.winbar()
		assert.matches("chip_test%.md", s)
		assert.matches("%%@v:lua%.NvMdReader%.click@", s)
		assert.matches("Open view", s)

		-- and it must survive real winbar evaluation
		local ok, res = pcall(vim.api.nvim_eval_statusline, vim.wo.winbar, { use_winbar = true, fillchar = " " })
		assert.is_true(ok)
		assert.matches("Open view │", res.str)
		assert.matches("chip_test%.md", res.str)

		_G.NvMdReader = saved
		vim.bo.filetype = ""
		vim.cmd("bwipeout!")
	end)

	it("renders plain badge (no chip) when no reader is registered", function()
		vim.cmd("enew")
		vim.api.nvim_buf_set_name(0, "plain_test.md")
		vim.bo.filetype = "markdown"
		local saved = _G.NvMdReader
		_G.NvMdReader = nil

		local s = badge.winbar()
		assert.matches("plain_test%.md", s)
		assert.is_nil(s:match("Open view"))

		_G.NvMdReader = saved
		vim.bo.filetype = ""
		vim.cmd("bwipeout!")
	end)
end)
