-- Tests for the agent/terminal activity indicator (lua/core/ai-activity.lua).

local ai = require("core.ai-activity")

describe("core.ai-activity", function()
	it("exposes a winbar function and a kept-alive timer, idle until output", function()
		assert.are.equal("function", type(ai.winbar))
		assert.is_not_nil(ai._timer, "the poll timer must be stored on M so luv won't GC it")
		-- Busy-gated: with no terminal activity yet the timer must NOT run —
		-- zero background wakeups at idle (this file's first test, fresh child).
		assert.is_false(ai._timer:is_active(), "timer must not run with no terminal activity")
		assert.is_false(ai._ticking)
	end)

	it("defines the NvAiBusy chip highlight", function()
		local hl = vim.api.nvim_get_hl(0, { name = "NvAiBusy" })
		assert.is_truthy(next(hl), "NvAiBusy should be defined")
		assert.is_not_nil(hl.bg, "NvAiBusy needs a background (the chip colour)")
	end)

	it("defines the NvAiAwait chip highlight", function()
		local hl = vim.api.nvim_get_hl(0, { name = "NvAiAwait" })
		assert.is_truthy(next(hl), "NvAiAwait should be defined")
		assert.is_not_nil(hl.bg, "NvAiAwait needs a background (the chip colour)")
	end)

	it("reports status(): nil for untracked buffers", function()
		local buf = vim.api.nvim_create_buf(true, false)
		assert.is_nil(ai.status(buf), "a plain buffer is not tracked")
		assert.is_nil(ai.status(nil))
		vim.api.nvim_buf_delete(buf, { force = true })
	end)

	describe("awaiting input (OSC prompt marks)", function()
		it("flips to 'needs input' on 133;B, clears on 133;C and on fresh output", function()
			vim.cmd("terminal cat")
			local buf = vim.api.nvim_get_current_buf()
			local job = vim.b[buf].terminal_job_id

			-- The TermOpen attach created the state entry; feed the prompt mark
			-- through the same normalized path the TermRequest autocmd uses.
			ai._on_osc(buf, "\27]133;B")
			assert.are.equal("awaiting", ai.status(buf))
			local bar = ai.winbar(buf)
			assert.matches("NvAiAwait", bar)
			assert.matches("needs input", bar)

			-- Command start clears it.
			ai._on_osc(buf, "\27]133;C")
			assert.are.equal("idle", ai.status(buf))

			-- Set again, then stream real output: on_lines must clear awaiting
			-- (fresh output trumps a stale prompt mark) and mark it working.
			ai._on_osc(buf, "\27]133;B")
			vim.fn.chansend(job, "clear it\n")
			local became_busy = vim.wait(3000, function()
				return ai.status(buf) == "working"
			end, 50)
			assert.is_true(became_busy, "output should flip awaiting → working")

			vim.api.nvim_buf_delete(buf, { force = true })
		end)

		it("treats OSC 9 notifications as 'needs input', ignores unknown sequences", function()
			vim.cmd("terminal cat")
			local buf = vim.api.nvim_get_current_buf()

			ai._on_osc(buf, "\27]9;claude finished\7")
			assert.are.equal("awaiting", ai.status(buf))

			ai._on_osc(buf, "\27]133;C")
			ai._on_osc(buf, "\27]4;totally unrelated")
			assert.are.equal("idle", ai.status(buf), "unknown sequences must not change state")

			vim.api.nvim_buf_delete(buf, { force = true })
		end)
	end)

	describe("winbar(buf)", function()
		it("returns empty for nil / invalid buffers", function()
			assert.are.equal("", ai.winbar(nil))
			assert.are.equal("", ai.winbar(999999))
		end)

		it("renders idle (no chip) for a known buffer with no activity", function()
			local buf = vim.api.nvim_create_buf(true, false)
			local out = ai.winbar(buf)
			assert.matches("idle", out)
			assert.matches("●", out)
			assert.is_nil(out:find("working"), "a quiet buffer must not say working")
			assert.is_nil(out:find("NvAiBusy"), "idle must not draw the busy chip")
			vim.api.nvim_buf_delete(buf, { force = true })
		end)

		it("prefixes the per-terminal label from b:nv_term_label", function()
			local buf = vim.api.nvim_create_buf(true, false)
			vim.b[buf].nv_term_label = "AI · 5"
			assert.matches("AI · 5", ai.winbar(buf))
			vim.api.nvim_buf_delete(buf, { force = true })
		end)
	end)

	it("flips a terminal to working while it streams output", function()
		-- A terminal that prints for a while; the TermOpen autocmd (registered when
		-- the module was required) attaches the on_lines listener that marks it busy.
		vim.cmd([[terminal sh -c 'for i in $(seq 1 30); do echo line $i; sleep 0.1; done']])
		local buf = vim.api.nvim_get_current_buf()
		assert.are.equal("terminal", vim.bo[buf].buftype)

		local became_busy = vim.wait(3000, function()
			return ai.winbar(buf):find("working") ~= nil
		end, 50)
		assert.is_true(became_busy, "winbar should report working while output streams")

		-- Busy-gating, start side: the on_lines fast-event callback must have
		-- started the poll timer (this is the empirical probe that uv timer
		-- ops are fast-context safe — real PTY, real on_lines).
		assert.is_true(ai._timer:is_active(), "the poll timer must run while a terminal is busy")

		local out = ai.winbar(buf)
		assert.matches("NvAiBusy", out) -- busy is drawn in the accent chip
		assert.matches("working", out)

		-- After output stops it should settle back to idle (IDLE_MS grace + margin).
		local went_idle = vim.wait(5000, function()
			return ai.winbar(buf):find("idle") ~= nil
		end, 100)
		assert.is_true(went_idle, "winbar should return to idle once output stops")

		-- Busy-gating, stop side: once nothing is busy the tick that flipped
		-- idle (and painted it) must also stop the timer — zero wakeups again.
		local stopped = vim.wait(2000, function()
			return not ai._timer:is_active()
		end, 50)
		assert.is_true(stopped, "the poll timer must stop once nothing is busy")

		vim.api.nvim_buf_delete(buf, { force = true })
	end)
end)
