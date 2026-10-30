-- Tests for the shared per-buffer debouncer (lua/core/debounce.lua).

local debounce = require("core.debounce")

describe("core.debounce", function()
	it("coalesces a burst into one call after the delay", function()
		local calls = {}
		local d = debounce.per_buffer({
			name = "spec_burst",
			delay = 20,
			fn = function(buf)
				calls[#calls + 1] = buf
			end,
		})
		local buf = vim.api.nvim_create_buf(false, true)
		for _ = 1, 5 do
			d.trigger(buf)
		end
		assert.are.equal(0, #calls, "nothing runs synchronously")
		assert.is_true(vim.wait(1000, function()
			return #calls > 0
		end, 5))
		vim.wait(80, function()
			return false
		end, 5)
		assert.are.same({ buf }, calls)
		d.cancel(buf)
	end)

	it("reads a function delay on every trigger", function()
		local ms = 10
		local d = debounce.per_buffer({
			name = "spec_delay_fn",
			delay = function()
				return ms
			end,
			fn = function() end,
		})
		local buf = vim.api.nvim_create_buf(false, true)
		d.trigger(buf)
		ms = 15
		d.trigger(buf) -- must not error with a changed delay
		assert.is_not_nil(d.timers[buf])
		d.cancel(buf)
	end)

	it("keeps separate timers per buffer", function()
		local seen = {}
		local d = debounce.per_buffer({
			name = "spec_per_buf",
			delay = 10,
			fn = function(buf)
				seen[buf] = true
			end,
		})
		local a = vim.api.nvim_create_buf(false, true)
		local b = vim.api.nvim_create_buf(false, true)
		d.trigger(a)
		d.trigger(b)
		assert.is_true(vim.wait(1000, function()
			return seen[a] and seen[b]
		end, 5))
		d.cancel(a)
		d.cancel(b)
	end)

	it("cancel closes the timer and forgets it; a second cancel is a no-op", function()
		local d = debounce.per_buffer({ name = "spec_cancel", delay = 1000, fn = function() end })
		local buf = vim.api.nvim_create_buf(false, true)
		d.trigger(buf)
		local t = d.timers[buf]
		d.cancel(buf)
		assert.is_nil(d.timers[buf])
		assert.is_true(t:is_closing())
		d.cancel(buf)
	end)

	it("drops the timer when the buffer is wiped", function()
		local ran = false
		local d = debounce.per_buffer({
			name = "spec_wipe",
			delay = 30,
			fn = function()
				ran = true
			end,
		})
		local buf = vim.api.nvim_create_buf(false, true)
		d.trigger(buf)
		vim.api.nvim_buf_delete(buf, { force = true })
		assert.is_nil(d.timers[buf])
		vim.wait(100, function()
			return false
		end, 5)
		assert.is_false(ran, "a wiped buffer's pending call must not fire")
	end)
end)
