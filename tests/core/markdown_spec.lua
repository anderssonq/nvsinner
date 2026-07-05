-- Tests for the native markdown reading view (lua/core/markdown.lua): the
-- _G.NvMdReader seam consumed by filebadge, the off-by-default toggle, and
-- the per-feature decorations (headings, bullets, checkboxes, quotes, fence
-- shading, rules) over the visible range.

local md = require("core.markdown")

describe("core.markdown", function()
	local path, buf

	local function open_md_file(lines)
		path = vim.fn.tempname() .. "_view.md"
		vim.fn.writefile(lines, path)
		vim.cmd("edit " .. vim.fn.fnameescape(path))
		buf = vim.api.nvim_get_current_buf()
	end

	local function marks()
		return vim.api.nvim_buf_get_extmarks(buf, md._ns, 0, -1, { details = true })
	end

	local function marks_on(row)
		local out = {}
		for _, m in ipairs(marks()) do
			if m[2] == row then
				out[#out + 1] = m
			end
		end
		return out
	end

	local function cleanup()
		vim.cmd("bwipeout!")
		os.remove(path)
	end

	before_each(function()
		md.on = false
	end)

	it("is the _G.NvMdReader seam and labels/toggles like the old plugin", function()
		assert.are.equal(md, _G.NvMdReader)
		assert.is_false(md.on)
		assert.are.equal("󰈙 Open view", md.label())
		md.click() -- winbar click handler = toggle
		assert.is_true(md.on)
		assert.are.equal("󰈙 Reading view · on", md.label())
		md.toggle()
		assert.is_false(md.on)
	end)

	it("writes nothing while off; toggle on decorates, toggle off clears", function()
		open_md_file({ "# Title", "- item" })
		md.refresh(buf)
		assert.are.equal(0, #marks(), "off by default: refresh is a no-op")

		md.toggle()
		assert.is_true(#marks() > 0, "toggling on refreshes visible markdown windows")
		md.toggle()
		assert.are.equal(0, #marks(), "toggling off clears the namespace")
		cleanup()
	end)

	it("styles headings per level with an overlay bar + line group", function()
		open_md_file({ "# One", "###### Six", "####### seven is not a heading", "plain prose" })
		md.on = true
		md.refresh(buf)

		local h1 = marks_on(0)
		assert.are.equal(1, #h1)
		assert.are.equal("NvMdH1", h1[1][4].line_hl_group)
		assert.are.equal("▎ ", h1[1][4].virt_text[1][1])
		assert.are.equal("overlay", h1[1][4].virt_text_pos)

		local h6 = marks_on(1)
		assert.are.equal("NvMdH6", h6[1][4].line_hl_group)

		assert.are.equal(0, #marks_on(2), "7 hashes is not a heading")
		assert.are.equal(0, #marks_on(3), "prose is untouched")
		cleanup()
	end)

	it("overlays • / ◦ on bullet markers at the marker column", function()
		open_md_file({ "- a", "  * b", "+ c", "not - a list" })
		md.on = true
		md.refresh(buf)

		local top = marks_on(0)
		assert.are.equal("•", top[1][4].virt_text[1][1])
		assert.are.equal("NvMdBullet", top[1][4].virt_text[1][2])
		assert.are.equal(0, top[1][3], "marker column")

		local nested = marks_on(1)
		assert.are.equal("◦", nested[1][4].virt_text[1][1])
		assert.are.equal(2, nested[1][3])

		assert.are.equal("•", marks_on(2)[1][4].virt_text[1][1])
		assert.are.equal(0, #marks_on(3))
		cleanup()
	end)

	it("replaces checkboxes with glyphs and dims done items", function()
		open_md_file({ "- [ ] open task", "- [x] done task" })
		md.on = true
		md.refresh(buf)

		local todo = marks_on(0)[1][4]
		assert.are.equal("NvMdTodo", todo.virt_text[1][2])
		assert.is_true(todo.virt_text[1][1]:find("󰄱", 1, true) ~= nil)
		assert.is_nil(todo.line_hl_group)

		local done = marks_on(1)[1][4]
		assert.are.equal("NvMdDone", done.virt_text[1][2])
		assert.is_true(done.virt_text[1][1]:find("󰱒", 1, true) ~= nil)
		assert.are.equal("NvMdDone", done.line_hl_group)
		cleanup()
	end)

	it("bars + dims blockquotes", function()
		open_md_file({ "> quoted", ">> nested" })
		md.on = true
		md.refresh(buf)

		local q = marks_on(0)[1][4]
		assert.are.equal("▍", q.virt_text[1][1])
		assert.are.equal("NvMdQuoteBar", q.virt_text[1][2])
		assert.are.equal("NvMdQuote", q.line_hl_group)
		assert.are.equal("▍▍", marks_on(1)[1][4].virt_text[1][1])
		cleanup()
	end)

	it("shades fenced blocks and never decorates inside them", function()
		open_md_file({ "```lua", "# not a heading", "- not a bullet", "```", "# real heading" })
		md.on = true
		md.refresh(buf)

		for row = 0, 3 do
			local m = marks_on(row)
			assert.are.equal(1, #m, "fence row " .. row .. " carries exactly the shade")
			assert.are.equal("NvMdCode", m[1][4].line_hl_group)
			assert.is_nil(m[1][4].virt_text)
		end
		assert.are.equal("NvMdH1", marks_on(4)[1][4].line_hl_group)
		cleanup()
	end)

	it("carries fence state opened above the visible range", function()
		local lines = { "```" }
		for i = 1, 200 do
			lines[#lines + 1] = "code line " .. i
		end
		lines[#lines + 1] = "```"
		open_md_file(lines)
		vim.api.nvim_win_set_cursor(0, { 100, 0 })
		vim.cmd("normal! zt") -- opening fence scrolls off-screen
		md.on = true
		md.refresh(buf)

		local first = vim.fn.line("w0") - 1
		assert.is_true(first > 0, "the opening fence is above the viewport")
		local m = marks_on(first)
		assert.are.equal("NvMdCode", m[1][4].line_hl_group, "interior still shaded")
		cleanup()
	end)

	it("draws horizontal rules full-width", function()
		open_md_file({ "---", "- - -", "--", "-- not a rule --" })
		md.on = true
		md.refresh(buf)

		local rule = marks_on(0)[1][4]
		assert.are.equal("NvMdRule", rule.virt_text[1][2])
		assert.is_true(vim.fn.strdisplaywidth(rule.virt_text[1][1]) >= vim.api.nvim_win_get_width(0))
		assert.are.equal(1, #marks_on(1), "spaced rule variant")
		assert.are.equal(0, #marks_on(2), "two dashes is not a rule")
		assert.are.equal(0, #marks_on(3), "mixed content is not a rule")
		cleanup()
	end)

	it("skips non-markdown filetypes and special buftypes even when on", function()
		md.on = true

		path = vim.fn.tempname() .. "_code.lua"
		vim.fn.writefile({ "# not markdown" }, path)
		vim.cmd("edit " .. vim.fn.fnameescape(path))
		buf = vim.api.nvim_get_current_buf()
		md.refresh(buf)
		assert.are.equal(0, #marks())
		cleanup()

		buf = vim.api.nvim_create_buf(false, true) -- buftype=nofile scratch
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "# heading" })
		vim.bo[buf].filetype = "markdown"
		vim.api.nvim_win_set_buf(0, buf)
		md.refresh(buf)
		assert.are.equal(0, #marks())
		vim.api.nvim_buf_delete(buf, { force = true })
	end)

	it("styles the groups with carbon roles", function()
		local c = require("core.carbon").colors()
		local h1 = vim.api.nvim_get_hl(0, { name = "NvMdH1" })
		assert.are.equal(tonumber(c.base10:sub(2), 16), h1.fg, "H1 wears the attention magenta")
		assert.is_true(h1.bold == true)
		local code = vim.api.nvim_get_hl(0, { name = "NvMdCode" })
		assert.are.equal(tonumber(c.blend:sub(2), 16), code.bg, "fence shade is the recessed float surface")
		assert.is_nil(code.fg, "bg-only so syntax fg survives")
		local quote = vim.api.nvim_get_hl(0, { name = "NvMdQuote" })
		assert.are.equal(tonumber(c.base03:sub(2), 16), quote.fg)
		assert.is_true(quote.italic == true)
	end)

	it("maps <leader>m buffer-locally on markdown buffers", function()
		open_md_file({ "# hi" })
		-- Match on the desc: <leader> resolves differently depending on whether
		-- core.options ran in this harness, so the lhs is not stable here.
		local found
		for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
			if map.desc == "Markdown reading view (Open view)" then
				found = map
			end
		end
		assert.is_not_nil(found, "<leader>m is mapped after FileType markdown")
		assert.are.equal("m", found.lhs:sub(-1), "the toggle sits on the m key of the leader")
		cleanup()
	end)

	it("renders through filebadge's winbar chip (the real seam, no stubs)", function()
		open_md_file({ "# hi" })
		local bar = require("core.filebadge").winbar()
		assert.is_true(bar:find("Open view", 1, true) ~= nil)
		assert.is_true(bar:find("v:lua.NvMdReader.click", 1, true) ~= nil)
		local ok = pcall(vim.api.nvim_eval_statusline, bar, { use_winbar = true })
		assert.is_true(ok, "the winbar string survives real evaluation")
		cleanup()
	end)
end)
