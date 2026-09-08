-- Source-level guard for lua/plugins/navigation/neo-tree.lua.
--
-- Both behaviours pinned here live inside the lazy spec's `config`, which never
-- runs headless (tests/minimal_init.lua loads no plugins), so nothing can be
-- asserted against a live neo-tree. Reading the source is the only assertion
-- that can actually fail when either regresses — the same reasoning as
-- tests/plugins/terminal_keymaps_spec.lua.

local function repo_root()
	local f = vim.api.nvim_get_runtime_file("lua/core/ai-activity.lua", false)[1]
	assert(f, "this config must be on the runtimepath (see tests/minimal_init.lua)")
	return vim.fn.fnamemodify(f, ":h:h:h")
end

describe("neo-tree spec", function()
	-- Assertions run against the source with LINE COMMENTS STRIPPED. That file
	-- documents these very contracts in prose, so matching the raw text would let
	-- a comment satisfy a test whose code had been deleted — which is exactly how
	-- the `use_default_mappings = false` guard first passed for the wrong reason.
	local code
	before_each(function()
		local path = repo_root() .. "/lua/plugins/navigation/neo-tree.lua"
		local fd = assert(io.open(path, "r"), path .. " must exist")
		local src = fd:read("*a")
		fd:close()
		code = src:gsub("%-%-[^\n]*", "")
	end)

	describe("click-to-open", function()
		it("binds both mouse events", function()
			assert.matches('%["<LeftRelease>"%]', code)
			assert.matches('%["<2%-LeftMouse>"%]', code)
		end)

		-- The whole feature is switchable from :NvSinnerMenu; a hardcoded handler
		-- would strand anyone who wants the stock double-click back.
		it("routes both through the persisted tree_click setting", function()
			assert.matches('get%("tree_click"%)', code)
		end)

		-- getmousepos().line CLAMPS to the last buffer line, so without a guard a
		-- click on the empty space below the tree opens the last file. The guard
		-- itself lives in core/mouse.lua (shared with diffview's file panels) and
		-- is covered behaviourally by tests/core/mouse_spec.lua.
		it("guards against clicks past the last node", function()
			assert.matches('require%("core%.mouse"%)%.clicked_line', code)
		end)
	end)

	describe("buffers source performance", function()
		-- neo-tree's buffers source registers a BEFORE_RENDER handler calling the
		-- SYNCHRONOUS git.status (vim.fn.system) on every render, and
		-- `git_status_async` does not cover it — only the filesystem source reads
		-- that option. The subscription sits in an `elseif config.before_render`
		-- branch, so defining before_render is what stops it being registered.
		-- Measured on a 24k-file repo with a 24k-file ignored tree: ~64 ms per
		-- render before, none after.
		it("defines buffers.before_render to drop the blocking git.status", function()
			assert.matches("buffers%s*=%s*{", code)
			assert.matches("before_render%s*=%s*function", code)
		end)
	end)

	describe("source selector", function()
		-- The git_status tab is removed from the winbar: its scan is synchronous
		-- (~5x a plain `git status`, and it scales with the ignored tree) and
		-- diffview already owns git. The selector must list ONLY filesystem +
		-- buffers — re-adding git_status resurrects the blocking tab.
		it("lists only the Files and Buffers tabs (no git_status)", function()
			assert.matches('source%s*=%s*"filesystem"', code)
			assert.matches('source%s*=%s*"buffers"', code)
			assert.is_nil(
				code:match('source%s*=%s*"git_status"'),
				"the Git tab was deliberately removed; diffview owns git"
			)
		end)
	end)

	-- window.mappings MERGE with neo-tree's ~40 defaults; they are only discarded
	-- when use_default_mappings = false. Setting that would silently drop every
	-- stock binding (a, r, d, y, x, p, w, …) while the click maps kept working.
	it("never disables the default mappings", function()
		assert.is_nil(code:match("use_default_mappings%s*=%s*false"))
	end)

	-- Click, never drag-select. Sweeping the pointer across tree rows used to
	-- paint a Visual selection over the filenames — meaningless in an explorer.
	-- 'mouse' is a GLOBAL option, so buffer-local maps are the only lever, and
	-- they are installed from a FileType autocmd rather than window.mappings so
	-- they can be EXPR maps (needed for the resize fall-through).
	describe("mouse selection lock", function()
		it("locks the tree's buffers via core.mouse.lock_selection", function()
			assert.matches('pattern%s*=%s*"neo%-tree"', code)
			assert.matches('require%("core%.mouse"%)%.lock_selection', code)
		end)

		-- <LeftRelease> is the click-to-open gesture AND the reason the drag-lock
		-- is sufficient: Vim finalises a mouse selection on the RELEASE, from the
		-- remembered press position, so if this ever fell through to the builtin
		-- a swept click would re-enter Visual mode despite every drag being
		-- locked. It must stay a plain consuming callback.
		it("keeps <LeftRelease> a plain consuming callback, never an expr map", function()
			assert.matches('%["<LeftRelease>"%]%s*=%s*function', code)
			-- The lock's own expr maps live in core/mouse.lua, so this file must
			-- declare no expr mapping of its own — an expr <LeftRelease> (or any
			-- table-form mapping carrying expr) would let the builtin release run.
			assert.is_nil(code:match("expr"), "neo-tree must declare no expr mapping itself")
		end)
	end)
end)
