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
end)
