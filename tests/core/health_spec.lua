-- Tests for the health module (lua/core/health.lua) + the :checkhealth nvsinner
-- provider (lua/nvsinner/health.lua): tool probing, the first-run "missing tools"
-- toast (write-once via a marker), and that the checkhealth report actually runs.

describe("core.health", function()
	local health = require("core.health")
	local orig_tools = health.tools

	after_each(function()
		health.tools = orig_tools -- restore any per-test tool table swap
	end)

	it("check_tools returns one result per tool with present/absent detected", function()
		health.tools = {
			{ name = "present", cmd = "sh", used_by = "x", install = "y" }, -- always on a POSIX box
			{ name = "absent", cmd = "nvsinner-no-such-binary-xyz", used_by = "x", install = "y" },
		}
		local res = health.check_tools()
		assert.are.equal(2, #res)
		assert.is_true(res[1].found)
		assert.is_false(res[2].found)
		assert.are.equal("present", res[1].name)
	end)

	it("first_run_notify warns once when a tool is missing, then stays quiet", function()
		local marker = vim.fn.tempname()
		health.tools = { { name = "absent", cmd = "nvsinner-no-such-binary-xyz", used_by = "x", install = "y" } }

		local notes = {}
		local orig = vim.notify
		vim.notify = function(msg, level, _)
			notes[#notes + 1] = { msg = msg, level = level }
		end

		health.first_run_notify({ marker = marker })
		health.first_run_notify({ marker = marker }) -- marker now exists → no-op

		vim.notify = orig -- restore BEFORE asserting so a failure can't leak it
		vim.fn.delete(marker)

		assert.are.equal(1, #notes, "should notify exactly once")
		assert.are.equal(vim.log.levels.WARN, notes[1].level)
		assert.matches("checkhealth nvsinner", notes[1].msg)
		assert.matches("absent", notes[1].msg)
	end)

	it("first_run_notify stays silent when nothing is missing", function()
		local marker = vim.fn.tempname()
		health.tools = { { name = "present", cmd = "sh", used_by = "x", install = "y" } }

		local notes = {}
		local orig = vim.notify
		vim.notify = function(msg)
			notes[#notes + 1] = msg
		end

		health.first_run_notify({ marker = marker })

		vim.notify = orig
		-- the marker is still written (greet-once) even with nothing missing
		assert.are.equal(1, vim.fn.filereadable(marker))
		vim.fn.delete(marker)

		assert.are.equal(0, #notes)
	end)
end)

describe("nvsinner.health provider", function()
	it("exposes a check() function for :checkhealth nvsinner", function()
		assert.is_function(require("nvsinner.health").check)
	end)

	it("runs :checkhealth nvsinner and reports the external tools", function()
		vim.cmd("checkhealth nvsinner")
		local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
		local text = table.concat(lines, "\n")
		assert.matches("external tools", text)
		assert.matches("ripgrep", text)
	end)
end)
