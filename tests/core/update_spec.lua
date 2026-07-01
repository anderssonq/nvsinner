-- Tests for the in-editor updater (lua/core/update.lua): the :NvSinnerUpdate
-- command, the git-repo detection, and the not-a-git-clone warning path. The
-- happy path (git pull + Lazy restore) is NOT exercised — it would hit the
-- network and needs plugins on the rtp, which the minimal test init omits.

describe("core.update", function()
	local update = require("core.update")

	it("defines the :NvSinnerUpdate user command", function()
		assert.is_not_nil(vim.api.nvim_get_commands({})["NvSinnerUpdate"])
	end)

	it("detects a git working tree via is_git_repo", function()
		local dir = vim.fn.tempname()
		vim.fn.mkdir(dir, "p")
		assert.is_false(update.is_git_repo(dir))

		vim.fn.mkdir(dir .. "/.git", "p") -- a plain clone has a .git DIRECTORY
		assert.is_true(update.is_git_repo(dir))

		vim.fn.delete(dir, "rf")
	end)

	it("warns and does not pull when the config dir is not a git clone", function()
		local dir = vim.fn.tempname()
		vim.fn.mkdir(dir, "p")

		local captured = {}
		local orig = vim.notify
		vim.notify = function(msg, level, opts)
			captured[#captured + 1] = { msg = msg, level = level, title = opts and opts.title }
		end

		update.update({ dir = dir })

		vim.notify = orig -- restore BEFORE asserting so a failure can't leak it
		vim.fn.delete(dir, "rf")

		assert.are.equal(1, #captured, "exactly one (warning) notification should fire")
		assert.are.equal(vim.log.levels.WARN, captured[1].level)
		assert.matches("not a git clone", captured[1].msg)
	end)
end)
