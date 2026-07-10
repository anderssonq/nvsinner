-- Tests for the AI edit highlights (lua/core/ai-edits.lua): the NvAiEdit
-- underline group, a real external rewrite producing extmarks on the changed
-- lines after the autoread reload, and the marks clearing (plus re-snapshot)
-- when the user takes over the buffer.

local edits = require("core.ai-edits")
require("core.autoreload") -- provides autoread + the FileChangedShell* plumbing

describe("core.ai-edits", function()
	local path, buf

	local function open_tempfile(lines)
		path = vim.fn.tempname() .. "_ai_marks.txt"
		vim.fn.writefile(lines, path)
		vim.cmd("edit " .. vim.fn.fnameescape(path))
		buf = vim.api.nvim_get_current_buf()
	end

	local function marks()
		return vim.api.nvim_buf_get_extmarks(buf, edits._ns, 0, -1, {})
	end

	before_each(function()
		edits._reset()
	end)

	it("defines the NvAiEdit accent-wash highlight", function()
		local hl = vim.api.nvim_get_hl(0, { name = "NvAiEdit" })
		assert.is_not_nil(hl.bg, "NvAiEdit needs a background (the accent wash)")
		assert.is_nil(hl.fg, "NvAiEdit must not recolor the code text (bg-only wash)")
		-- The wash is the accent BLENDED into the editor bg, never the raw
		-- accent: at full strength the code text would lose contrast.
		local c = require("core.carbon").colors()
		local raw_accent = tonumber(c.base09:sub(2), 16)
		assert.are_not.equal(raw_accent, hl.bg, "wash must be blended, not the raw accent")
	end)

	it("underlines the lines an external write changed, after the reload", function()
		open_tempfile({ "one", "two", "three" })
		assert.are.equal(0, #marks())

		-- External rewrite with a guaranteed-later mtime (same recipe as the
		-- autoreload spec), then re-check timestamps to trigger the reload.
		vim.fn.system({
			"sh",
			"-c",
			"sleep 1; printf 'one\\nTWO by agent\\nthree\\nfour by agent\\n' > " .. vim.fn.shellescape(path),
		})
		vim.cmd("checktime")

		local got = vim.wait(3000, function()
			return #marks() > 0
		end, 100)
		assert.is_true(got, "the changed lines should get NvAiEdit extmarks")

		-- Line 2 was rewritten and line 4 added; line 1 untouched.
		local rows = {}
		for _, m in ipairs(marks()) do
			rows[m[2]] = true
		end
		assert.is_true(rows[1], "changed line 2 (row 1) must be marked")
		assert.is_true(rows[3], "added line 4 (row 3) must be marked")
		assert.is_nil(rows[0], "untouched line 1 must not be marked")

		vim.cmd("bwipeout!")
		os.remove(path)
	end)

	it("clear() removes the marks and re-baselines the snapshot", function()
		open_tempfile({ "alpha" })
		vim.fn.system({ "sh", "-c", "sleep 1; printf 'alpha\\nbeta\\n' > " .. vim.fn.shellescape(path) })
		vim.cmd("checktime")
		assert.is_true(vim.wait(3000, function()
			return #marks() > 0
		end, 100))

		edits.clear(buf)
		assert.are.equal(0, #marks())
		-- Re-baselined: diffing again without a new external write marks nothing.
		assert.are.equal(0, edits.mark(buf))

		vim.cmd("bwipeout!")
		os.remove(path)
	end)

	it("arms take-over autocmds that clear on cursor move / edit", function()
		open_tempfile({ "alpha" })
		vim.fn.system({ "sh", "-c", "sleep 1; printf 'alpha\\nbeta\\n' > " .. vim.fn.shellescape(path) })
		vim.cmd("checktime")
		assert.is_true(vim.wait(3000, function()
			return #marks() > 0
		end, 100))

		-- arm_clear is scheduled; wait for the buffer-local group to exist.
		local armed = vim.wait(1000, function()
			return #vim.api.nvim_get_autocmds({ event = "CursorMoved", buffer = buf }) > 0
		end, 20)
		assert.is_true(armed, "take-over autocmds must be registered after marking")

		-- The user takes over (same direct-fire technique as ai_sessions_spec:
		-- cursor events don't fire synchronously in a headless spec).
		vim.api.nvim_exec_autocmds("CursorMoved", { buffer = buf })
		assert.are.equal(0, #marks(), "user movement must wipe the AI marks")

		vim.cmd("bwipeout!")
		os.remove(path)
	end)

	it("skips terminal/special buffers and returns 0 without a snapshot", function()
		vim.cmd("terminal")
		local tbuf = vim.api.nvim_get_current_buf()
		assert.are.equal(0, edits.mark(tbuf))
		vim.api.nvim_buf_delete(tbuf, { force = true })
	end)

	it("flash() washes an explicit row range and arms the take-over clear", function()
		local sbuf = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_buf_set_lines(sbuf, 0, -1, false, { "a", "b", "c" })

		assert.are.equal(2, edits.flash(sbuf, 0, 2), "flash washes exactly rows [0,2)")
		local rows = {}
		for _, e in ipairs(vim.api.nvim_buf_get_extmarks(sbuf, edits._ns, 0, -1, {})) do
			rows[e[2]] = true
		end
		assert.is_true(rows[0] and rows[1], "rows 0 and 1 are washed")
		assert.is_nil(rows[2], "row 2 is outside the range")

		-- Same arm-then-clear machinery as mark(): wait for the scheduled group,
		-- then a typed letter wipes the wash.
		local armed = vim.wait(1000, function()
			return #vim.api.nvim_get_autocmds({ event = "CursorMoved", buffer = sbuf }) > 0
		end, 20)
		assert.is_true(armed, "flash arms the same take-over autocmds as mark()")
		vim.api.nvim_exec_autocmds("TextChangedI", { buffer = sbuf })
		assert.are.equal(0, #vim.api.nvim_buf_get_extmarks(sbuf, edits._ns, 0, -1, {}), "typing clears the flash wash")

		vim.api.nvim_buf_delete(sbuf, { force = true })
	end)

	it("flash() skips ineligible (terminal) buffers", function()
		vim.cmd("terminal")
		local tbuf = vim.api.nvim_get_current_buf()
		assert.are.equal(0, edits.flash(tbuf, 0, 1))
		assert.are.equal(0, #vim.api.nvim_buf_get_extmarks(tbuf, edits._ns, 0, -1, {}))
		vim.api.nvim_buf_delete(tbuf, { force = true })
	end)
end)
