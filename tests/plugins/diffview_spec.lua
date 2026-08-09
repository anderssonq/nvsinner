-- The diffview spec carries behaviour, not just options: the <leader>gi /
-- <leader>go round trip is wired through `keys` callbacks and `opts.hooks`.
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
	for _, lhs in ipairs({ "<leader>gd", "<leader>gh", "<leader>gH", "<leader>gq", "<leader>gi", "<leader>go" }) do
		it("maps " .. lhs .. " with a desc", function()
			local key = by_lhs[lhs]
			assert.is_not_nil(key, lhs .. " must be mapped")
			assert.is_true(type(key.desc) == "string" and #key.desc > 0, lhs .. " needs a desc")
		end)
	end

	it("drives the round trip from Lua callbacks, not <cmd> strings", function()
		assert.are.equal("function", type(by_lhs["<leader>gi"][2]))
		assert.are.equal("function", type(by_lhs["<leader>go"][2]))
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
		for _, lhs in ipairs({ "<leader>gi", "<leader>go" }) do
			local ok, err = pcall(by_lhs[lhs][2])
			assert.is_true(ok, lhs .. " must not error without diffview: " .. tostring(err))
		end
		assert.are.same(cursor, vim.api.nvim_win_get_cursor(0), "no window may move")
	end)

	-- Behaviours that live inside the `keys` callbacks, which never run headless
	-- (no diffview runtime). Same source-level guard as
	-- tests/plugins/terminal_keymaps_spec.lua: cheap, and it catches the silent
	-- deletion that would otherwise regress the round trip with no error.
	describe("round-trip source guards", function()
		local src = table.concat(vim.fn.readfile(repo_root() .. "/lua/plugins/git/diffview.lua"), "\n")

		-- The two keys own different halves of the trip. <leader>gi staying
		-- INSIDE the view is the whole point of having both: conflating them
		-- costs you the file list mid-review.
		it("keeps <leader>gi inside the view — only <leader>go leaves it", function()
			local body = src:match("local function into_diff%(%).-\nend\n")
			assert.is_truthy(body, "into_diff must still be a local function")
			assert.is_truthy(body:match("focus_panel"), "the in-view toggle focuses the file list")
			assert.is_nil(body:match("leave_diff"), "<leader>gi must never exit to the buffer")

			local exit = src:match("local function out_of_diff%(%).-\nend\n")
			assert.is_truthy(exit and exit:match("leave_diff"), "<leader>go is the exit")
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
