-- The diffview spec carries behaviour, not just options: <leader>gd's
-- one-tab-only open, <leader>gi and the `gf` exit are wired through `keys`
-- callbacks, `opts.keymaps` and `opts.hooks`.
-- tests/minimal_init.lua loads no plugins, so diffview's runtime can't be
-- exercised here — this pins the spec SHAPE, which is what regresses silently
-- (a dropped hook or a desc-less key breaks the feature with no error anywhere).

local function repo_root()
	local f = vim.api.nvim_get_runtime_file("lua/core/ai-activity.lua", false)[1]
	assert(f, "this config must be on the runtimepath (see tests/minimal_init.lua)")
	return vim.fn.fnamemodify(f, ":h:h:h")
end

describe("diffview spec", function()
	local spec = dofile(repo_root() .. "/lua/plugins/git/diffview.lua")

	local by_lhs = {}
	for _, key in ipairs(spec.keys or {}) do
		by_lhs[key[1]] = key
	end

	it("is the diffview plugin", function()
		assert.are.equal("sindrets/diffview.nvim", spec[1])
	end)

	it("keeps enhanced_diff_hl on", function()
		assert.is_true(spec.opts.enhanced_diff_hl)
	end)

	it("lazy-loads on the Diffview commands", function()
		assert.is_true(vim.tbl_contains(spec.cmd, "DiffviewOpen"))
		assert.is_true(vim.tbl_contains(spec.cmd, "DiffviewClose"))
	end)

	-- which-key renders the <leader>g group from each mapping's own desc.
	for _, lhs in ipairs({ "<leader>gd", "<leader>gh", "<leader>gH", "<leader>gq", "<leader>gi", "<leader>ga" }) do
		it("maps " .. lhs .. " with a desc", function()
			local key = by_lhs[lhs]
			assert.is_not_nil(key, lhs .. " must be mapped")
			assert.is_true(type(key.desc) == "string" and #key.desc > 0, lhs .. " needs a desc")
		end)
	end

	it("drives the round trip from Lua callbacks, not <cmd> strings", function()
		assert.are.equal("function", type(by_lhs["<leader>gd"][2]))
		assert.are.equal("function", type(by_lhs["<leader>gH"][2]))
		assert.are.equal("function", type(by_lhs["<leader>gi"][2]))
	end)

	-- <leader>go was retired: `gf` is the exit (it keeps the tab, which
	-- <leader>gd now returns to instead of opening a second one).
	it("no longer maps <leader>go", function()
		assert.is_nil(by_lhs["<leader>go"], "the exit is diffview's own gf")
	end)

	-- The cursor lands asynchronously, from diffview's own events.
	it("registers the hooks the jump depends on", function()
		local hooks = spec.opts.hooks
		assert.is_not_nil(hooks, "opts.hooks must exist")
		assert.are.equal("function", type(hooks.diff_buf_win_enter))
		assert.are.equal("function", type(hooks.view_closed))
	end)

	-- Both maps are live from the moment lazy registers them, but diffview only
	-- loads on the first press — so every entry point starts with a
	-- `pcall(require, "diffview.lib")` and must be a silent no-op if it fails.
	-- minimal_init loads no plugins, so this is that state for real.
	it("is a silent no-op while diffview is not on the runtimepath", function()
		assert.is_nil(package.loaded["diffview.lib"], "the plugin must not be loadable here")
		local cursor = vim.api.nvim_win_get_cursor(0)
		for _, lhs in ipairs({ "<leader>gd", "<leader>gH", "<leader>gi" }) do
			local ok, err = pcall(by_lhs[lhs][2])
			assert.is_true(ok, lhs .. " must not error without diffview: " .. tostring(err))
		end
		assert.are.same(cursor, vim.api.nvim_win_get_cursor(0), "no window may move")
	end)

	-- neo-tree's Git tab has no key of its own to call: it reaches <leader>gd's
	-- one-tab open through this global, published when the spec is evaluated
	-- (i.e. before diffview loads). It must be the very same function, and a
	-- silent no-op in the unloaded state like every other entry point.
	it("publishes open_diff as the _G.NvDiffview seam for neo-tree's Git tab", function()
		assert.are.equal("table", type(_G.NvDiffview))
		assert.are.equal(by_lhs["<leader>gd"][2], _G.NvDiffview.open)
		local tabs = #vim.api.nvim_list_tabpages()
		local ok, err = pcall(_G.NvDiffview.open)
		assert.is_true(ok, "NvDiffview.open must not error without diffview: " .. tostring(err))
		assert.are.equal(tabs, #vim.api.nvim_list_tabpages(), "no tab may open")
	end)

	-- Live refresh: an agent writing the working tree touches neither of
	-- diffview's own triggers (.git/index, in-Neovim BufWritePost), so the spec
	-- watches the repo itself. Exercised with fake view tables and a real temp
	-- dir — the watcher is plain luv, no plugin needed.
	describe("live refresh", function()
		local live = _G.NvDiffview.live
		local tmp, views

		-- macOS FSEvents replays events from just before the watch started (the
		-- temp dir's own creation, measured), so each case lets those land and
		-- then zeroes the counters before acting.
		local function settle(view)
			vim.wait(400)
			view.updates = 0
			live.dirty[view] = nil
		end

		local function fake_view(opts)
			local view = {
				files = {},
				set_file = function() end,
				tabpage = vim.api.nvim_get_current_tabpage(),
				adapter = { ctx = { toplevel = tmp } },
				updates = 0,
			}
			view.update_files = function(self)
				self.updates = self.updates + 1
			end
			for k, v in pairs(opts or {}) do
				view[k] = v
			end
			table.insert(views, view)
			return view
		end

		before_each(function()
			tmp = vim.fn.resolve(vim.fn.tempname())
			vim.fn.mkdir(tmp .. "/.git", "p")
			views = {}
			live.DELAY_MS = 150
		end)

		after_each(function()
			for _, view in ipairs(views) do
				live.unwatch(view)
			end
			vim.fn.delete(tmp, "rf")
		end)

		it("wires the three hooks it lives on", function()
			local hooks = spec.opts.hooks
			assert.are.equal("function", type(hooks.view_opened))
			assert.are.equal("function", type(hooks.view_enter))
			assert.are.equal("function", type(hooks.view_closed))
		end)

		it("ignores .git/ — diffview's own git status would refresh forever", function()
			assert.is_true(live.ignored(".git"))
			assert.is_true(live.ignored(".git/index.lock"))
			assert.is_true(live.ignored("vendor/sub/.git/HEAD"))
			assert.is_false(live.ignored("lua/core/a.lua"))
			assert.is_false(live.ignored(".github/workflows/ci.yml"))
			assert.is_false(live.ignored(".gitignore"))
		end)

		it("watches a DiffView and stops on close", function()
			local view = fake_view()
			spec.opts.hooks.view_opened(view)
			assert.is_not_nil(live.watchers[view])
			local handle = live.watchers[view]
			spec.opts.hooks.view_closed(view)
			assert.is_nil(live.watchers[view])
			assert.is_true(handle:is_closing())
		end)

		it("leaves a FileHistoryView alone", function()
			local view = fake_view({ files = false, set_file = false })
			live.watch(view)
			assert.is_nil(live.watchers[view])
		end)

		it("refreshes the current-tab view once per burst of writes", function()
			local view = fake_view()
			live.watch(view)
			settle(view)
			for i = 1, 5 do
				vim.fn.writefile({ "x" }, tmp .. "/f" .. i .. ".txt")
			end
			assert.is_true(vim.wait(2000, function()
				return view.updates > 0
			end, 10))
			vim.wait(400)
			assert.are.equal(1, view.updates, "five writes must coalesce into one refresh")
		end)

		it("ignores writes under .git/", function()
			local view = fake_view()
			live.watch(view)
			settle(view)
			vim.fn.writefile({ "x" }, tmp .. "/.git/index")
			vim.wait(400)
			assert.are.equal(0, view.updates)
			assert.is_nil(live.dirty[view])
		end)

		it("holds a view in another tab dirty until view_enter", function()
			vim.cmd("tabnew")
			local other = vim.api.nvim_get_current_tabpage()
			vim.cmd("tabprevious")
			local view = fake_view({ tabpage = other })
			live.watch(view)
			settle(view)
			vim.fn.writefile({ "x" }, tmp .. "/new.txt")
			assert.is_true(vim.wait(2000, function()
				return live.dirty[view] == true
			end, 10))
			vim.wait(100)
			assert.are.equal(0, view.updates, "update_files would cancel itself off-tab")

			spec.opts.hooks.view_enter(view)
			assert.are.equal(1, view.updates)
			assert.is_nil(live.dirty[view])
			vim.cmd("tabclose " .. vim.api.nvim_tabpage_get_number(other))
		end)

		it("view_enter is a no-op when nothing changed", function()
			local view = fake_view()
			live.watch(view)
			spec.opts.hooks.view_enter(view)
			assert.are.equal(0, view.updates)
		end)

		it("records the absolute path of the last write (agent mode follows it)", function()
			local view = fake_view()
			live.watch(view)
			settle(view)
			live.last = nil
			vim.fn.writefile({ "x" }, tmp .. "/written.txt")
			assert.is_true(vim.wait(2000, function()
				return live.last ~= nil
			end, 10))
			assert.are.equal(tmp .. "/written.txt", live.last)
		end)
	end)

	-- Agent mode: the diff tab with the AI column beside it, following the
	-- agent's writes. diffview's runtime is absent here, so the follow logic is
	-- driven through fake views and the toggle through a stub mover.
	describe("agent mode", function()
		local agent, live = _G.NvDiffview.agent, _G.NvDiffview.live

		local function entry_view(paths, cur)
			local entries = {}
			for _, p in ipairs(paths) do
				entries[#entries + 1] = { absolute_path = p }
			end
			local view = {
				files = {
					iter = function()
						return ipairs(entries)
					end,
				},
				cur_entry = cur and entries[cur] or nil,
				set_file_calls = {},
			}
			view.set_file = function(self, entry, focus)
				table.insert(self.set_file_calls, { entry = entry, focus = focus })
			end
			return view, entries
		end

		after_each(function()
			agent.on, agent.origin, agent.reveal, live.last = false, nil, nil, nil
		end)

		it("is reachable as :NvSinnerAgentMode before diffview loads", function()
			spec.init()
			assert.are.equal(2, vim.fn.exists(":NvSinnerAgentMode"))
		end)

		it("switches the view to the last written file, keeping focus where it is", function()
			local view, entries = entry_view({ "/r/a.lua", "/r/b.lua" }, 1)
			agent.on, live.last = true, "/r/b.lua"
			live.on_updated(view)
			assert.are.equal(1, #view.set_file_calls)
			assert.are.equal(entries[2], view.set_file_calls[1].entry)
			assert.is_false(view.set_file_calls[1].focus, "the CLI keeps focus")
			assert.is_true(agent.reveal, "the last hunk is revealed once the buffer swaps")
			assert.is_nil(live.last, "a path is followed once")
		end)

		it("does not swap when the written file is already shown", function()
			local view = entry_view({ "/r/a.lua" }, 1)
			agent.on, live.last = true, "/r/a.lua"
			live.on_updated(view)
			assert.are.equal(0, #view.set_file_calls)
		end)

		it("ignores writes outside the diff and does nothing while off", function()
			local view = entry_view({ "/r/a.lua" })
			agent.on, live.last = true, "/r/untracked-ignored.log"
			live.on_updated(view)
			agent.on, live.last = false, "/r/a.lua"
			live.on_updated(view)
			assert.are.equal(0, #view.set_file_calls)
		end)

		it("turns off when the diff view closes", function()
			agent.on = true
			spec.opts.hooks.view_closed({ files = {} })
			assert.is_false(agent.active())
		end)

		it("toggling off shows the column in the tab it came from", function()
			local sessions = require("core.ai-sessions")
			local shown = {}
			sessions.set_clearer({
				list = function()
					return {}
				end,
				clear = function()
					return false
				end,
				show_here = function(n, opts)
					shown[#shown + 1] = { n = n, tab = vim.api.nvim_get_current_tabpage(), opts = opts }
					return true
				end,
			})
			local origin = vim.api.nvim_get_current_tabpage()
			vim.cmd("tabnew")
			agent.on, agent.n, agent.origin = true, 2, origin
			agent.toggle()
			assert.is_false(agent.active())
			assert.are.equal(origin, vim.api.nvim_get_current_tabpage())
			assert.are.same(
				{ { n = 2, tab = origin, opts = { existing = true } } },
				shown,
				"agent mode only shows an existing session"
			)
			vim.cmd("tabonly")
			sessions.set_clearer(nil)
		end)
	end)

	-- Click-to-preview in the file panels. Unlike neo-tree's window.mappings,
	-- these are real spec data, so most of it is assertable directly.
	describe("click-to-preview", function()
		local PANELS = { "file_panel", "file_history_panel" }

		for _, panel in ipairs(PANELS) do
			it("binds both mouse events on " .. panel, function()
				local maps = spec.opts.keymaps and spec.opts.keymaps[panel]
				assert.is_not_nil(maps, panel .. " must carry the click maps")
				local by_lhs_map = {}
				for _, m in ipairs(maps) do
					assert.are.equal("n", m[1], "the panels are normal-mode only")
					assert.are.equal("function", type(m[3]), "handlers must be Lua callbacks")
					assert.is_true(type(m[4].desc) == "string" and #m[4].desc > 0, "g? renders the desc")
					by_lhs_map[m[2]] = m
				end
				assert.is_not_nil(by_lhs_map["<LeftRelease>"], "single click must be bound")
				assert.is_not_nil(by_lhs_map["<2-LeftMouse>"], "the stock gesture must stay bound")
			end)
		end

		-- The two panels must not share one mutable map table, or an edit to one
		-- silently rewrites the other.
		it("gives each panel its own map list", function()
			assert.is_not.equal(spec.opts.keymaps.file_panel, spec.opts.keymaps.file_history_panel)
		end)

		-- diffview rebuilds its keymap tables from pristine defaults and then
		-- extends them keyed by "<mode> <lhs>", so ours merge with the ~50 stock
		-- bindings. `disable_defaults` would throw all of them away.
		it("never disables the default keymaps", function()
			assert.is_not_true(spec.opts.keymaps.disable_defaults)
		end)

		-- The whole feature is switchable from :NvSinnerMenu, and shares the tree's
		-- setting so both explorers agree on what a click costs.
		it("routes both gestures through the persisted tree_click setting", function()
			local src = table.concat(vim.fn.readfile(repo_root() .. "/lua/plugins/git/diffview.lua"), "\n")
			assert.is_truthy(src:match('get%("tree_click"%)'))
			assert.is_truthy(
				src:match('require%("core%.mouse"%)%.clicked_line'),
				"getmousepos clamps to the last line — a click below the list must not preview it"
			)
		end)

		-- Same contract as the <leader>g maps: live from registration, but
		-- diffview only loads on first use. minimal_init loads no plugins.
		it("is a silent no-op while diffview is not on the runtimepath", function()
			assert.is_nil(package.loaded["diffview.actions"], "the plugin must not be loadable here")
			for _, panel in ipairs(PANELS) do
				for _, m in ipairs(spec.opts.keymaps[panel]) do
					local ok, err = pcall(m[3])
					assert.is_true(ok, panel .. " " .. m[2] .. " must not error: " .. tostring(err))
				end
			end
		end)
	end)

	-- `gf` is the exit now that <leader>go is gone, and it must carry the
	-- editable-window pre-positioning <leader>go used to. diffview binds the stock
	-- `goto_file_edit` in all three groups, so ours must override all three.
	describe("gf exit", function()
		for _, group in ipairs({ "view", "file_panel", "file_history_panel" }) do
			it("overrides gf on " .. group, function()
				local maps = spec.opts.keymaps and spec.opts.keymaps[group]
				assert.is_not_nil(maps, group .. " must carry the gf map")
				local gf
				for _, m in ipairs(maps) do
					if m[2] == "gf" then
						gf = m
					end
				end
				assert.is_not_nil(gf, "gf must be bound in " .. group)
				assert.are.equal("n", gf[1])
				assert.are.equal("function", type(gf[3]), "the handler must be a Lua callback")
				assert.is_true(type(gf[4].desc) == "string" and #gf[4].desc > 0, "g? renders the desc")
			end)
		end

		it("is a silent no-op while diffview is not on the runtimepath", function()
			assert.is_nil(package.loaded["diffview.lib"], "the plugin must not be loadable here")
			local cursor = vim.api.nvim_win_get_cursor(0)
			for _, m in ipairs(spec.opts.keymaps.view) do
				local ok, err = pcall(m[3])
				assert.is_true(ok, m[2] .. " must not error: " .. tostring(err))
			end
			assert.are.same(cursor, vim.api.nvim_win_get_cursor(0), "no window may move")
		end)
	end)

	-- Behaviours that live inside the `keys` callbacks, which never run headless
	-- (no diffview runtime). Same source-level guard as
	-- tests/plugins/terminal_keymaps_spec.lua: cheap, and it catches the silent
	-- deletion that would otherwise regress the round trip with no error.
	describe("round-trip source guards", function()
		local src = table.concat(vim.fn.readfile(repo_root() .. "/lua/plugins/git/diffview.lua"), "\n")

		-- Click, never drag-select in the two file panels: like neo-tree's tree
		-- they are pickers, not text. Installed from an `init` FileType autocmd
		-- rather than the keymap tables below, because the lock needs EXPR maps
		-- (to fall through on a separator resize-drag) while every panel map is
		-- asserted above to be a plain normal-mode callback with a desc.
		it("locks mouse selection on both file panels", function()
			local code = src:gsub("%-%-[^\n]*", "")
			assert.is_truthy(code:match('require%("core%.mouse"%)%.lock_selection'))
			assert.is_truthy(code:match('"DiffviewFiles"'), "the file panel must be covered")
			assert.is_truthy(code:match('"DiffviewFileHistory"'), "the history panel too")
		end)

		-- The diff windows are real text; drag-selection must survive there.
		it("never locks the diff windows themselves", function()
			assert.is_nil(
				src:match('pattern%s*=%s*{[^}]*"DiffviewView"'),
				"keymaps.view / the diff windows keep normal drag selection"
			)
		end)

		-- The keys own different halves of the trip. <leader>gi staying INSIDE
		-- the view is the whole point: conflating them costs you the file list
		-- mid-review.
		it("keeps <leader>gi inside the view — only gf leaves it", function()
			local body = src:match("local function into_diff%(%).-\nend\n")
			assert.is_truthy(body, "into_diff must still be a local function")
			assert.is_truthy(body:match("focus_panel"), "the in-view toggle focuses the file list")
			assert.is_nil(body:match("goto_file"), "<leader>gi must never exit to the buffer")

			local exit = src:match("local function goto_file%(%).-\nend\n")
			assert.is_truthy(exit and exit:match("goto_file_edit"), "gf is the exit")
		end)

		-- The bug this whole change exists for: `DiffviewOpen` never dedupes, so
		-- a raw `<cmd>DiffviewOpen<cr>` stacked one tabline entry per press.
		it("reuses the open tab instead of stacking a second one", function()
			local body = src:match("local function open_diff%(%).-\nend\n")
			assert.is_truthy(body, "open_diff must still be a local function")
			assert.is_truthy(
				body:match("nvim_set_current_tabpage"),
				"<leader>gd must adopt the DiffView that is already open"
			)
			assert.is_truthy(body:match("diff_view"), "and it must find it, not guess")
		end)

		-- Same defect, same guard — but scoped to views opened with NO path args,
		-- so <leader>gh (one file's history) still opens a tab per file.
		it("reuses the whole-repo history tab, and only that one", function()
			local body = src:match("local function open_repo_history%(%).-\nend\n")
			assert.is_truthy(body, "open_repo_history must still be a local function")
			assert.is_truthy(
				body:match("nvim_set_current_tabpage"),
				"<leader>gH must adopt the history view that is already open"
			)

			local scan = src:match("local function repo_history_view%b().-\nend\n")
			assert.is_truthy(scan, "the scanner must still be a local function")
			assert.is_truthy(
				scan:match("path_args"),
				"the path args are what tell a <leader>gH tab from a <leader>gh one"
			)
		end)

		it("leaves <leader>gh unguarded — two files are two histories", function()
			assert.are.equal("string", type(by_lhs["<leader>gh"][2]))
		end)

		it("routes the exit through core.window-picker's editable_win", function()
			assert.is_truthy(
				src:match("editable_win"),
				"goto_file_edit edits into the target tab's last-accessed window — "
					.. "without pre-positioning it, the file lands in neo-tree or the AI column"
			)
		end)

		it("resolves the selected file from neo-tree", function()
			assert.is_truthy(
				src:match("neo%-tree%.sources%.manager"),
				"<leader>gi from the tree must diff the selected node, not the first changed file"
			)
		end)

		it("prefers a DiffView over a FileHistoryView when adopting an open tab", function()
			assert.is_truthy(
				src:match("view%.files and view%.set_file"),
				"a <leader>gh tab has neither, and adopting it swallows the jump"
			)
		end)
	end)

	-- Neovim syncs 'scrollbind' only for the CURRENT window, so a mouse wheel over
	-- the other diff pane scrolled it alone. The spec's `init` re-syncs from the
	-- scrolled window. Exercised natively: two `:diffthis` windows are exactly
	-- what diffview builds (diff + scrollbind), no plugin needed.
	--
	-- It runs in an `--embed` child over RPC because nvim_input_mouse only QUEUES
	-- the event: only the main loop consumes input, and a spec never yields to
	-- its own (vim.wait and an "x" feedkeys both leave the wheel unread). The
	-- child's loop reads it between our requests, as it would under a real UI.
	describe("wheel scroll sync", function()
		local chan

		local function child(code, ...)
			return vim.rpcrequest(chan, "nvim_exec_lua", code, { ... })
		end

		-- `left` scrolled by the wheel while `right` keeps focus.
		local function tops()
			return child([[
				local t = function(w) return vim.fn.getwininfo(w)[1].topline end
				return { left = t(_G.left), right = t(_G.right), focus_right = vim.api.nvim_get_current_win() == _G.right }
			]])
		end

		local function wheel_over_left()
			local pos = child("return vim.api.nvim_win_get_position(_G.left)")
			vim.rpcrequest(chan, "nvim_input_mouse", "wheel", "down", "", 0, pos[1] + 2, pos[2] + 2)
			vim.wait(1000, function()
				return tops().left > 1
			end, 10)
			vim.wait(100) -- let a sync, if any, land
			return tops()
		end

		before_each(function()
			chan = vim.fn.jobstart({
				vim.v.progpath,
				"--embed",
				"--headless",
				"--noplugin",
				"-u",
				repo_root() .. "/tests/minimal_init.lua",
			}, { rpc = true })
			assert.is_true(chan > 0, "could not start the child nvim")
			child(
				[[
				local path, bind = ...
				dofile(path).init()
				-- A change every 10 lines: identical buffers would fold to one line
				-- under foldmethod=diff, leaving nothing to scroll.
				local old, new = {}, {}
				for i = 1, 200 do
					old[i] = "line " .. i
					new[i] = i % 10 == 0 and ("changed " .. i) or old[i]
				end
				vim.api.nvim_buf_set_lines(0, 0, -1, false, new)
				_G.right = vim.api.nvim_get_current_win()
				vim.cmd("leftabove vnew")
				vim.api.nvim_buf_set_lines(0, 0, -1, false, old)
				_G.left = vim.api.nvim_get_current_win()
				for _, win in ipairs({ _G.left, _G.right }) do
					if bind then
						vim.api.nvim_win_call(win, function() vim.cmd("diffthis") end)
					end
					vim.wo[win].scrollbind = bind
				end
				vim.api.nvim_set_current_win(_G.right)
			]],
				repo_root() .. "/lua/plugins/git/diffview.lua",
				true
			)
		end)

		after_each(function()
			vim.fn.jobstop(chan)
		end)

		it("drags the focused pane along when the wheel scrolls the other one", function()
			local t = wheel_over_left()
			assert.is_true(t.left > 1, "the wheel must scroll the pane under the pointer")
			assert.are.equal(t.left, t.right, "the focused pane must follow")
			assert.is_true(t.focus_right, "the wheel must not move focus")
		end)

		-- Negative control: without the autocmd Neovim leaves the partner behind,
		-- which is the whole reason it exists.
		it("is what makes it work — Neovim alone leaves the focused pane behind", function()
			child([[vim.api.nvim_clear_autocmds({ group = "nvsinner_diffview_mouse", event = "WinScrolled" })]])
			local t = wheel_over_left()
			assert.is_true(t.left > 1)
			assert.are.equal(1, t.right)
		end)

		it("leaves windows without 'scrollbind' alone", function()
			child([[
				vim.cmd("diffoff!")
				for _, win in ipairs({ _G.left, _G.right }) do vim.wo[win].scrollbind = false end
			]])
			local t = wheel_over_left()
			assert.is_true(t.left > 1)
			assert.are.equal(1, t.right)
		end)
	end)

	-- diffview fires diff_buf_win_enter for every diff window it opens, including
	-- the ones nobody asked to jump to. With no jump queued the hook must be
	-- inert: it runs on windows/buffers it was never told about.
	it("is inert when no jump is queued", function()
		local hook = spec.opts.hooks.diff_buf_win_enter
		local cursor = vim.api.nvim_win_get_cursor(0)
		for _, symbol in ipairs({ "a", "b" }) do
			local ok, err = pcall(hook, vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win(), {
				symbol = symbol,
				layout_name = "diff2_horizontal",
			})
			assert.is_true(ok, "symbol " .. symbol .. " must be a no-op: " .. tostring(err))
		end
		assert.are.same(cursor, vim.api.nvim_win_get_cursor(0), "an un-queued hook must not move the cursor")
	end)
end)
