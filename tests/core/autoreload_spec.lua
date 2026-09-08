-- Tests for the AI-workflow auto-reload + edit toast (lua/core/autoreload.lua).

describe("core.autoreload", function()
	require("core.autoreload")

	it("enables autoread", function()
		assert.is_true(vim.o.autoread)
	end)

	it("registers FileChangedShell and FileChangedShellPost in its augroup", function()
		local grp = "auto_reload_on_disk_change"
		assert.is_true(#vim.api.nvim_get_autocmds({ group = grp, event = "FileChangedShell" }) > 0)
		assert.is_true(#vim.api.nvim_get_autocmds({ group = grp, event = "FileChangedShellPost" }) > 0)
	end)

	it("toasts the filename when an OPEN file is rewritten on disk", function()
		local captured = {}
		local orig = vim.notify
		vim.notify = function(msg, _, opts)
			captured[#captured + 1] = { msg = msg, title = opts and opts.title }
		end

		local path = vim.fn.tempname() .. "_ai_edit.txt"
		vim.fn.writefile({ "original" }, path)
		vim.cmd("edit " .. vim.fn.fnameescape(path))

		-- External rewrite with a guaranteed-later mtime, then re-check timestamps.
		vim.fn.system({ "sh", "-c", "sleep 1; printf 'original\\nby agent\\n' > " .. vim.fn.shellescape(path) })
		vim.cmd("checktime")

		local got = vim.wait(3000, function()
			for _, c in ipairs(captured) do
				if type(c.msg) == "string" and c.msg:find("edited") then
					return true
				end
			end
			return false
		end, 100)

		vim.notify = orig -- restore BEFORE asserting (so a failure can't leak it)
		local last = captured[#captured]
		vim.cmd("bwipeout!")
		os.remove(path)

		assert.is_true(got, "a '🤖 AI edited <file>' toast should fire on external change")
		assert.matches(vim.fn.fnamemodify(path, ":t"), last.msg)
	end)

	-- ─── Focus a terminal -> start typing immediately ──────────────────────────
	-- The mode itself cannot be asserted here: headless Neovim cannot enter
	-- terminal mode synchronously (see tests/core/ai_sessions_spec.lua). What IS
	-- assertable is the predicate that gates it, which is why it is a seam.

	local autoreload = require("core.autoreload")

	--- Open a terminal running `cmd` in the current window and return its buffer.
	local function term(cmd)
		vim.cmd("enew")
		local buf = vim.api.nvim_get_current_buf()
		vim.fn.termopen(cmd)
		return buf, vim.b[buf].terminal_job_id
	end

	it("registers the terminal focus autocmd in its augroup", function()
		local grp = "term_focus_startinsert"
		assert.is_true(#vim.api.nvim_get_autocmds({ group = grp, event = "WinEnter" }) > 0)
		assert.is_true(#vim.api.nvim_get_autocmds({ group = grp, event = "BufEnter" }) > 0)
	end)

	it("wants insert mode for a terminal whose job is alive", function()
		local buf = term({ "sh", "-c", "while :; do sleep 1; done" })
		assert.is_true(autoreload.should_insert(buf))
		vim.cmd("bwipeout!")
	end)

	it("does NOT want insert mode once the job has exited", function()
		-- The dead AI column case: close_on_exit = false keeps the buffer, and
		-- normal mode is what lets you read and scroll the final output.
		-- b:terminal_job_id SURVIVES the exit, so presence alone proves nothing —
		-- this is exactly what the jobwait liveness probe is for.
		local buf, job = term({ "true" })
		vim.wait(3000, function()
			return vim.fn.jobwait({ job }, 0)[1] ~= -1
		end, 50)
		assert.is_not_nil(vim.b[buf].terminal_job_id, "the job id outlives the job")
		assert.is_false(autoreload.should_insert(buf))
		vim.cmd("bwipeout!")
	end)

	it("never wants insert mode in a non-terminal buffer", function()
		vim.cmd("enew")
		local buf = vim.api.nvim_get_current_buf()
		assert.is_false(autoreload.should_insert(buf))
		assert.is_false(autoreload.should_insert(999999), "invalid buffers are safe")
		vim.cmd("bwipeout!")
	end)
end)
