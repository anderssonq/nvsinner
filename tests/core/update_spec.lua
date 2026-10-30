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

	-- Scripted git: `script` maps the git subcommand to a list of results
	-- (consumed in order). Returns the call log plus restore helpers. Nothing
	-- here touches a real repo, remote or lazy.
	describe("with a stubbed job runner", function()
		local dir, orig_system, orig_restore, orig_notify
		local calls, notes, restored, stub_errors

		local function stub(script)
			calls, notes, restored, stub_errors = {}, {}, 0, {}
			update._system = function(cmd, _, cb)
				local sub = cmd[4] -- { "git", "-C", dir, <sub>, ... }
				calls[#calls + 1] = sub
				local res = script[sub] and table.remove(script[sub], 1)
				if not res then
					-- Most calls run inside vim.schedule'd callbacks, where a thrown
					-- error would only print and never fail the test. Record it and
					-- let run() assert, so an unscripted git call fails loudly.
					stub_errors[#stub_errors + 1] = "update_spec stub: no scripted result left for `git "
						.. tostring(sub)
						.. "`"
					return
				end
				cb({ code = res.code or 0, stdout = res.stdout or "", stderr = res.stderr or "" })
			end
			update._restore = function()
				restored = restored + 1
			end
			vim.notify = function(msg, level)
				notes[#notes + 1] = { msg = msg, level = level }
			end
		end

		local function run()
			update.update({ dir = dir })
			-- the callbacks are vim.schedule_wrap'd: let the chain drain
			vim.wait(200, function()
				return false
			end)
			assert.are.same({}, stub_errors)
		end

		local function joined()
			local t = {}
			for _, n in ipairs(notes) do
				t[#t + 1] = n.msg
			end
			return table.concat(t, "\n")
		end

		before_each(function()
			dir = vim.fn.tempname()
			vim.fn.mkdir(dir .. "/.git", "p")
			orig_system, orig_restore, orig_notify = update._system, update._restore, vim.notify
		end)

		after_each(function()
			update._system, update._restore, vim.notify = orig_system, orig_restore, orig_notify
			vim.fn.delete(dir, "rf")
		end)

		it("aborts with a WARN before pulling when the tree is dirty", function()
			stub({ status = { { stdout = " M lua/core/foo.lua\n" } } })
			run()
			assert.are.same({ "status" }, calls, "nothing but the status probe may run")
			assert.are.equal(0, restored)
			assert.are.equal(1, #notes)
			assert.are.equal(vim.log.levels.WARN, notes[1].level)
			assert.matches("uncommitted changes", notes[1].msg)
			assert.matches("stash", notes[1].msg)
		end)

		it("reports no-op when HEAD is unchanged, whatever git printed", function()
			-- stdout deliberately NOT the English "Already up to date": the
			-- decision must come from the HEAD compare, not the string.
			stub({
				status = { { stdout = "" } },
				["rev-parse"] = { { stdout = "abc123\n" }, { stdout = "abc123\n" } },
				pull = { { stdout = "Ya esta actualizado.\n" } },
			})
			run()
			assert.are.same({ "status", "rev-parse", "pull", "rev-parse" }, calls)
			assert.are.equal(0, restored)
			assert.matches("Already up to date", joined())
		end)

		it("restores plugins when HEAD moved, even if git printed 'Already up to date'", function()
			stub({
				status = { { stdout = "" } },
				["rev-parse"] = { { stdout = "abc123\n" }, { stdout = "def456\n" } },
				pull = { { stdout = "Already up to date.\n" } }, -- would have fooled the old string match
			})
			run()
			assert.are.equal(1, restored)
			assert.matches("Restoring plugins", joined())
		end)

		it("reports a failing git status as ERROR and never pulls", function()
			stub({ status = { { code = 128, stderr = "fatal: not a git repository" } } })
			run()
			assert.are.same({ "status" }, calls)
			assert.are.equal(0, restored)
			assert.are.equal(1, #notes)
			assert.are.equal(vim.log.levels.ERROR, notes[1].level)
			assert.matches("git status failed", notes[1].msg)
		end)

		it("falls through to restore when rev-parse fails (HEAD unknown)", function()
			-- Without a readable HEAD we cannot prove "nothing changed". Restore is
			-- idempotent (it re-checks out the lockfile set), so doing it needlessly
			-- is the safe default; skipping it wrongly could leave stale plugins.
			stub({
				status = { { stdout = "" } },
				["rev-parse"] = { { code = 128, stderr = "fatal: bad revision" }, { code = 128, stderr = "fatal" } },
				pull = { { stdout = "Updating\n" } },
			})
			run()
			assert.are.equal(1, restored)
			assert.matches("Restoring plugins", joined())
		end)

		it("reports a failed pull as ERROR and does not restore", function()
			stub({
				status = { { stdout = "" } },
				["rev-parse"] = { { stdout = "abc123\n" } },
				pull = { { code = 128, stderr = "fatal: Not possible to fast-forward" } },
			})
			run()
			assert.are.equal(0, restored)
			assert.are.equal(vim.log.levels.ERROR, notes[#notes].level)
			assert.matches("git pull failed", notes[#notes].msg)
		end)
	end)
end)
