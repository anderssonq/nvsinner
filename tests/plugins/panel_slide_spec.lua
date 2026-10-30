-- The three layout panels hand their new window to core/slide.lua, and
-- mini.animate stands down while a slide runs.
--
-- Every subject here lives inside a lazy spec's config(), which never runs
-- headless (tests/minimal_init.lua loads no plugins). So each config() runs for
-- real against a FAKE plugin, with core.slide replaced by a recorder: the
-- assertion is "this open path asks for a slide of THIS window along THIS
-- dimension" — the animation itself is pinned by tests/core/slide_spec.lua.

local function repo_root()
	local f = vim.api.nvim_get_runtime_file("lua/core/ai-activity.lua", false)[1]
	assert(f, "this config must be on the runtimepath (see tests/minimal_init.lua)")
	return vim.fn.fnamemodify(f, ":h:h:h")
end

local saved = {}
local function stub(name, value)
	if saved[name] == nil then
		saved[name] = { value = package.loaded[name] }
	end
	package.loaded[name] = value
end
local function unstub_all()
	for name, s in pairs(saved) do
		package.loaded[name] = s.value
	end
	saved = {}
end

-- core.slide recorder.
local calls, released, last_opts, held
local function stub_slide()
	calls, released, last_opts, held = {}, {}, nil, {}
	stub("core.slide", {
		open = function(win, dim, opts)
			table.insert(calls, { win = win, dim = dim })
			last_opts = opts
		end,
		release = function(buf)
			table.insert(released, buf)
		end,
		-- placeholder buffer → the terminal it stands in for (set per test)
		held_term = function(buf)
			return held[buf]
		end,
	})
end

describe("panel slide wiring", function()
	after_each(function()
		vim.cmd("silent! stopinsert")
		vim.cmd("silent! only!")
		unstub_all()
	end)

	describe("toggleterm", function()
		-- Same stand-in as tests/plugins/agent_column_spec.lua: a split on a
		-- scratch buffer with toggleterm's single-`window` bookkeeping.
		local Terminal = {}
		Terminal.__index = Terminal
		function Terminal:new(o)
			return setmetatable(o or {}, Terminal)
		end
		function Terminal:is_open()
			return self.window ~= nil and vim.api.nvim_win_is_valid(self.window)
		end
		function Terminal:open()
			if Terminal.fail_next then
				Terminal.fail_next = nil
				error("toggleterm blew up")
			end
			vim.cmd(self.direction == "horizontal" and "botright split" or "botright vsplit")
			self.window = vim.api.nvim_get_current_win()
			if not (self.bufnr and vim.api.nvim_buf_is_valid(self.bufnr)) then
				self.bufnr = vim.api.nvim_create_buf(false, true)
			end
			vim.api.nvim_win_set_buf(self.window, self.bufnr)
			if self.on_open then
				self:on_open()
			end
		end
		function Terminal:close()
			if self:is_open() then
				vim.api.nvim_win_close(self.window, true)
			end
		end
		function Terminal:toggle()
			if self:is_open() then
				self:close()
			else
				self:open()
			end
			return self
		end
		function Terminal:shutdown()
			self:close()
		end

		local sessions = require("core.ai-sessions")

		before_each(function()
			stub("toggleterm", { setup = function() end })
			stub("toggleterm.terminal", { Terminal = Terminal })
			stub("toggleterm.ui", { hl_term = function() end })
			stub_slide()
			sessions._reset()
			dofile(repo_root() .. "/lua/plugins/terminal/toggleterm.lua").config()
		end)

		after_each(function()
			sessions._reset()
		end)

		local function press(lhs)
			vim.fn.maparg(lhs, "n", false, true).callback()
		end

		it("slides a <leader>t terminal along its height", function()
			press("<leader>t")
			assert.are.equal(1, #calls)
			assert.are.equal("height", calls[1].dim)
			assert.are.equal(vim.api.nvim_get_current_win(), calls[1].win, "the focused new terminal window")
		end)

		it("slides a <leader>t<N> terminal too", function()
			press("<leader>t3")
			assert.are.equal(1, #calls)
			assert.are.equal("height", calls[1].dim)
		end)

		it("slides the first-open picker once, and a hidden column on every reopen", function()
			press("<leader>j")
			assert.are.equal("nvsinner-picker", vim.bo.filetype)
			assert.are.equal(1, #calls, "the picker is the column's space appearing")
			assert.are.same({ win = vim.api.nvim_get_current_win(), dim = "width" }, calls[1])

			press("4") -- plain terminal
			press("<CR>")
			assert.are.equal(1, #calls, "the column replacing the picker takes over at full width")

			press("<leader>j") -- hide
			press("<leader>j") -- reopen
			assert.are.equal(2, #calls)
			assert.are.equal("width", calls[2].dim)
			assert.are.equal(sessions.sessions()[1].term.window, calls[2].win)
		end)

		-- skip_slide is a one-shot flag shared by every panel: if the CLI
		-- column's open throws, it must not stay set and swallow the NEXT
		-- panel's slide.
		it("resets the picker's one-shot snap when the column's open throws", function()
			press("<leader>j")
			press("4")
			Terminal.fail_next = true
			local ok, err = pcall(press, "<CR>")
			assert.is_false(ok, "the error still surfaces")
			assert.matches("toggleterm blew up", tostring(err))
			calls = {}
			press("<leader>t")
			assert.are.equal(1, #calls, "the next panel slides as usual")
		end)

		-- Mid-slide an AI column's window shows slide.lua's placeholder, so
		-- every lookup of "the column's window in this tab" lands the slide
		-- first (slide.release puts the terminal back).
		it("lands a running slide before looking up a column's window", function()
			press("<leader>j")
			press("4")
			press("<CR>")
			released = {}
			press("<leader>j") -- hide: adopt_here → win_here
			local buf = sessions.sessions()[1].term.bufnr
			assert.is_true(vim.tbl_contains(released, buf))
		end)

		-- A column whose swap-back was refused (cmdline window) still shows
		-- slide.lua's placeholder. It must still read as THE column: <M-J>
		-- from inside it toggles that session (not session 1), and toggling
		-- hides it instead of opening a second window for the same terminal.
		local function placeholder_in(win, term_buf)
			local ph = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_win_set_buf(win, ph)
			held[ph] = term_buf
			return ph
		end

		it("treats a mid-slide placeholder as its session's column (<M-J>, toggle)", function()
			press("<leader>j2")
			press("4")
			press("<CR>")
			local e = sessions.sessions()[1]
			local win = e.term.window
			placeholder_in(win, e.term.bufnr)
			vim.api.nvim_set_current_win(win)
			vim.fn.maparg("<M-J>", "n", false, true).callback()
			assert.are_not.equal("nvsinner-picker", vim.bo.filetype, "session 1's picker must not open")
			assert.is_false(vim.api.nvim_win_is_valid(win), "session 2's column was hidden")
			local wins = #vim.api.nvim_tabpage_list_wins(0)
			press("<leader>j2") -- re-show: exactly one more window
			assert.are.equal(wins + 1, #vim.api.nvim_tabpage_list_wins(0))
		end)

		it("does not stack a second window over a mid-slide placeholder", function()
			press("<leader>j2")
			press("4")
			press("<CR>")
			local e = sessions.sessions()[1]
			local win = e.term.window
			placeholder_in(win, e.term.bufnr)
			local wins = #vim.api.nvim_tabpage_list_wins(0)
			press("<leader>j2") -- toggle: hides the column it can see
			assert.are.equal(wins - 1, #vim.api.nvim_tabpage_list_wins(0))
		end)

		-- <leader>jc on a column still sliding: the terminal goes back first,
		-- so shutdown closes the column instead of leaving a placeholder.
		it("releases a sliding column before the clearer shuts it down", function()
			press("<leader>j")
			press("4")
			press("<CR>")
			local buf = sessions.sessions()[1].term.bufnr
			released = {}
			sessions.clear(1)
			assert.are.same(
				{ buf },
				vim.tbl_filter(function(b)
					return b == buf
				end, released)
			)
		end)

		it("slides a <leader>j<N> column", function()
			press("<leader>j2")
			press("4")
			press("<CR>")
			press("<leader>j2")
			press("<leader>j2")
			assert.are.equal(2, #calls)
			assert.are.equal("width", calls[2].dim)
		end)
	end)

	describe("neo-tree", function()
		local opts

		before_each(function()
			opts = nil
			stub_slide()
			stub("neo-tree", {
				setup = function(o)
					opts = o
				end,
				ensure_config = function()
					return { source_selector = { sources = {} } }
				end,
			})
			stub("neo-tree.ui.selector", {})
			dofile(repo_root() .. "/lua/plugins/navigation/neo-tree.lua").config()
		end)

		local function handler(event)
			for _, h in ipairs(opts.event_handlers or {}) do
				if h.event == event then
					return h.handler
				end
			end
		end

		it("hooks the sidebar's window open events", function()
			assert.is_function(handler("neo_tree_window_before_open"))
			assert.is_function(handler("neo_tree_window_after_open"))
		end)

		it("slides a NEW left/right sidebar window along its width", function()
			handler("neo_tree_window_before_open")({ position = "left" })
			vim.cmd("topleft vsplit")
			local win = vim.api.nvim_get_current_win()
			handler("neo_tree_window_after_open")({ position = "left", winid = win })
			assert.are.same({ { win = win, dim = "width" } }, calls)
		end)

		-- window_after_open fires before the first draw, which records the
		-- ~1-column start width; on_done must re-record the real width and
		-- redraw THIS window's state (not other sources' or other windows').
		it("redraws the tree at its real width when the slide ends", function()
			handler("neo_tree_window_before_open")({ position = "left", source = "filesystem" })
			vim.cmd("topleft vsplit")
			local win = vim.api.nvim_get_current_win()
			vim.api.nvim_win_set_width(win, 38)
			local mine = { name = "filesystem", winid = win, win_width = 1 }
			local other = { name = "filesystem", winid = 99999, win_width = 7 }
			local seen_source
			local redrawn = {}
			stub("neo-tree.sources.manager", {
				_for_each_state = function(source, action)
					seen_source = source
					action(mine)
					action(other)
				end,
			})
			stub("neo-tree.ui.renderer", {
				redraw = function(state)
					table.insert(redrawn, state)
				end,
			})
			stub("neo-tree.utils", {
				get_inner_win_width = function(w)
					return vim.api.nvim_win_get_width(w)
				end,
			})
			handler("neo_tree_window_after_open")({ position = "left", source = "filesystem", winid = win })
			assert.is_function(last_opts and last_opts.on_done, "the slide carries an on_done")
			last_opts.on_done(win)
			assert.are.equal("filesystem", seen_source)
			assert.are.equal(38, mine.win_width)
			assert.are.same({ mine }, redrawn)
			assert.are.equal(7, other.win_width)
		end)

		-- window_after_open also fires when neo-tree REUSES its sidebar window
		-- (another source shown in the same place): that must not slide again.
		it("never slides a window that already existed, a float or position=current", function()
			local existing = vim.api.nvim_get_current_win()
			handler("neo_tree_window_before_open")({ position = "right" })
			handler("neo_tree_window_after_open")({ position = "right", winid = existing })
			handler("neo_tree_window_before_open")({ position = "float" })
			vim.cmd("vsplit")
			handler("neo_tree_window_after_open")({ position = "float", winid = vim.api.nvim_get_current_win() })
			handler("neo_tree_window_after_open")({ position = "current", winid = vim.api.nvim_get_current_win() })
			assert.are.same({}, calls)
		end)
	end)

	describe("mini.animate", function()
		local cfg, gens

		before_each(function()
			cfg, gens = nil, {}
			local function gen(kind)
				return function(o)
					gens[kind] = o
					return o
				end
			end
			stub("mini.animate", {
				setup = function(o)
					cfg = o
				end,
				gen_timing = { linear = gen("linear"), cubic = gen("cubic") },
				gen_subresize = { equal = gen("subresize") },
				gen_winconfig = { static = gen("winconfig") },
			})
			dofile(repo_root() .. "/lua/plugins/ui/mini-animate.lua").config()
		end)

		it("keeps open/close/resize on and scroll off", function()
			assert.is_true(cfg.open.enable and cfg.close.enable and cfg.resize.enable)
			assert.is_false(cfg.scroll.enable)
		end)

		it("skips its open animation for the window a slide is growing", function()
			local sliding_win = 1001
			stub("core.slide", {
				busy = function(win)
					return win == sliding_win
				end,
			})
			assert.is_false(gens.winconfig.predicate(sliding_win))
			assert.is_true(gens.winconfig.predicate(1002))
		end)

		it("skips its resize easing while any slide runs", function()
			local busy = true
			stub("core.slide", {
				busy = function()
					return busy
				end,
			})
			assert.is_false(gens.subresize.predicate({}, {}))
			busy = false
			assert.is_true(gens.subresize.predicate({}, {}))
		end)

		it("animates as before when no slide was ever loaded", function()
			stub("core.slide", nil)
			assert.is_true(gens.winconfig.predicate(1001))
			assert.is_true(gens.subresize.predicate({}, {}))
		end)
	end)
end)
