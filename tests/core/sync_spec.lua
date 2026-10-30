-- Tests for the opt-in plugin/Mason updater (lua/core/sync.lua): the
-- :NvSinnerSync command, the outdated-package detection, and the
-- mason-unavailable warning path. The happy path (:Lazy sync + registry
-- refresh + installs) is NOT exercised — it hits the network and needs plugins
-- on the rtp, which the minimal test init omits.

describe("core.sync", function()
	local sync = require("core.sync")

	-- A Package-like fake exposing exactly what M.outdated consumes.
	local function fake_pkg(name, installed, latest, throws)
		return {
			name = name,
			get_installed_version = function()
				return installed
			end,
			get_latest_version = function()
				if throws then
					error("malformed purl")
				end
				return latest
			end,
		}
	end

	it("defines the :NvSinnerSync user command", function()
		assert.is_not_nil(vim.api.nvim_get_commands({})["NvSinnerSync"])
	end)

	it("flags only packages whose latest version differs from the installed one", function()
		local stale = fake_pkg("stale", "1.0.0", "2.0.0")
		local fresh = fake_pkg("fresh", "3.1.0", "3.1.0")
		local out = sync.outdated({ stale, fresh })
		assert.are.equal(1, #out)
		assert.are.equal("stale", out[1].name)
	end)

	it("skips packages with no receipt or a throwing version lookup", function()
		local no_receipt = fake_pkg("no-receipt", nil, "1.0.0") -- never installed via receipt
		local malformed = fake_pkg("malformed", "1.0.0", nil, true) -- get_latest_version throws
		assert.are.equal(0, #sync.outdated({ no_receipt, malformed }))
	end)

	it("reports plugins whose lockfile branch changed, sorted by name", function()
		local before = {
			["nvim-treesitter"] = { branch = "master", commit = "aaa" },
			["git-blame.nvim"] = { branch = "master", commit = "bbb" },
			["gitsigns.nvim"] = { branch = "main", commit = "ccc" },
		}
		local after = {
			["nvim-treesitter"] = { branch = "main", commit = "ddd" }, -- the 2026-07-03 incident
			["git-blame.nvim"] = { branch = "main", commit = "eee" },
			["gitsigns.nvim"] = { branch = "main", commit = "fff" }, -- commit bump only, no jump
		}
		local jumps = sync.branch_jumps(before, after)
		assert.are.equal(2, #jumps)
		assert.are.equal("git-blame.nvim", jumps[1].name) -- sorted
		assert.are.equal("nvim-treesitter", jumps[2].name)
		assert.are.equal("master", jumps[2].from)
		assert.are.equal("main", jumps[2].to)
	end)

	it("ignores plugins added or removed by the sync", function()
		local before = { removed = { branch = "master", commit = "aaa" } }
		local after = { added = { branch = "main", commit = "bbb" } }
		assert.are.equal(0, #sync.branch_jumps(before, after))
	end)

	it("warns and skips the Mason phase when mason.nvim is unavailable", function()
		-- The minimal test init has no plugins on the rtp, so both the lazy
		-- load and require("mason-registry") fail — the guarded warning path.
		local captured = {}
		local orig = vim.notify
		vim.notify = function(msg, level, opts)
			captured[#captured + 1] = { msg = msg, level = level, title = opts and opts.title }
		end

		sync.mason_update()

		vim.notify = orig -- restore BEFORE asserting so a failure can't leak it

		assert.are.equal(1, #captured, "exactly one (warning) notification should fire")
		assert.are.equal(vim.log.levels.WARN, captured[1].level)
		assert.matches("mason", captured[1].msg)
	end)

	describe("with a fake lazy", function()
		local orig_lazy, orig_notify, orig_timeout, captured

		before_each(function()
			orig_lazy, orig_notify, orig_timeout = package.loaded["lazy"], vim.notify, sync.TIMEOUT_MS
			captured = {}
			vim.notify = function(msg, level)
				captured[#captured + 1] = { msg = msg, level = level }
			end
		end)

		after_each(function()
			package.loaded["lazy"], vim.notify, sync.TIMEOUT_MS = orig_lazy, orig_notify, orig_timeout
			pcall(vim.api.nvim_clear_autocmds, { event = "User", pattern = "LazySync" })
		end)

		it("notifies ERROR and drops the LazySync hook when lazy.sync() throws", function()
			package.loaded["lazy"] = {
				sync = function()
					error("boom")
				end,
			}
			sync.sync()
			local last = captured[#captured]
			assert.are.equal(vim.log.levels.ERROR, last.level)
			assert.matches("Plugin sync failed", last.msg)
			assert.matches("boom", last.msg)
			assert.are.equal(0, #vim.api.nvim_get_autocmds({ event = "User", pattern = "LazySync" }))
		end)

		it("warns once if LazySync never arrives within the timeout", function()
			package.loaded["lazy"] = {
				sync = function() end,
			}
			sync.TIMEOUT_MS = 20
			sync.sync()
			vim.wait(500, function()
				return captured[#captured].level == vim.log.levels.WARN
			end)
			assert.are.equal(vim.log.levels.WARN, captured[#captured].level)
			assert.matches("not reported completion", captured[#captured].msg)
		end)

		it("does not arm the watchdog when LazySync fires synchronously inside lazy.sync()", function()
			package.loaded["lazy"] = {
				sync = function()
					vim.api.nvim_exec_autocmds("User", { pattern = "LazySync" })
				end,
			}
			sync.TIMEOUT_MS = 20
			sync.sync()
			-- wait well past the timeout: a late watchdog would have warned by now
			vim.wait(200, function()
				return false
			end)
			for _, n in ipairs(captured) do
				assert.is_nil(n.msg:find("not reported completion", 1, true))
			end
		end)

		it("stays quiet (no timeout warning) when LazySync fires in time", function()
			package.loaded["lazy"] = {
				sync = function() end,
			}
			sync.TIMEOUT_MS = 50
			sync.sync()
			-- mason is absent in the minimal init, so the Mason phase WARNs once itself
			vim.api.nvim_exec_autocmds("User", { pattern = "LazySync" })
			vim.wait(200, function()
				return false
			end)
			for _, n in ipairs(captured) do
				assert.is_nil(n.msg:find("not reported completion", 1, true))
			end
		end)
	end)
end)
