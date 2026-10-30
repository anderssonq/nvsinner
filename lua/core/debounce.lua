-- Per-buffer debounced callback: the timer map, the stop+start re-arm and the
-- BufWipeout cleanup that colorizer.lua, todo.lua and markdown.lua each carried
-- a private copy of. Pure library: no autocmds fire until `per_buffer` is
-- called, and it requires nothing, so it is cheap to load.
--
-- Why timers are kept in a plain table the caller can read (`d.timers`): an
-- active luv timer that nothing references can be garbage-collected and
-- silently stop, so the map doubles as the GC anchor.

local M = {}

local uv = vim.uv or vim.loop

--- Create a per-buffer debouncer.
--- @param opts table
---   fn     fun(buf: integer)   runs (scheduled) once a burst settles
---   delay  integer|fun():integer  ms to wait; a function is read on every
---                                 trigger so a module's tunable stays live
---   name   string              unique suffix for the cleanup augroup
--- @return table d { timers, trigger(buf), cancel(buf) }
function M.per_buffer(opts)
	local d = { timers = {} } -- bufnr -> one-shot uv timer

	local function delay()
		local v = opts.delay
		if type(v) == "function" then
			return v()
		end
		return v
	end

	--- Re-arm the buffer's timer; a burst of calls lands as ONE `fn(buf)`.
	function d.trigger(buf)
		local t = d.timers[buf]
		if not t then
			t = assert(uv.new_timer())
			d.timers[buf] = t
		end
		t:stop()
		t:start(
			delay(),
			0,
			vim.schedule_wrap(function()
				opts.fn(buf)
			end)
		)
	end

	--- Drop the buffer's timer (stop + close); a no-op when there is none.
	function d.cancel(buf)
		local t = d.timers[buf]
		if t then
			t:stop()
			t:close()
			d.timers[buf] = nil
		end
	end

	vim.api.nvim_create_autocmd("BufWipeout", {
		group = vim.api.nvim_create_augroup("nv_debounce_" .. (opts.name or "anon"), { clear = true }),
		callback = function(args)
			d.cancel(args.buf)
		end,
	})

	return d
end

return M
