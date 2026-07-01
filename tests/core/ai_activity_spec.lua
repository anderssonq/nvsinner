-- Tests for the agent/terminal activity indicator (lua/core/ai-activity.lua).

local ai = require("core.ai-activity")

describe("core.ai-activity", function()
	it("exposes a winbar function and a kept-alive timer", function()
		assert.are.equal("function", type(ai.winbar))
		assert.is_not_nil(ai._timer, "the poll timer must be stored on M so luv won't GC it")
	end)

	it("defines the NvAiBusy chip highlight", function()
		local hl = vim.api.nvim_get_hl(0, { name = "NvAiBusy" })
		assert.is_truthy(next(hl), "NvAiBusy should be defined")
		assert.is_not_nil(hl.bg, "NvAiBusy needs a background (the chip colour)")
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

		local out = ai.winbar(buf)
		assert.matches("NvAiBusy", out) -- busy is drawn in the accent chip
		assert.matches("working", out)

		-- After output stops it should settle back to idle (IDLE_MS grace + margin).
		local went_idle = vim.wait(5000, function()
			return ai.winbar(buf):find("idle") ~= nil
		end, 100)
		assert.is_true(went_idle, "winbar should return to idle once output stops")

		vim.api.nvim_buf_delete(buf, { force = true })
	end)
end)
