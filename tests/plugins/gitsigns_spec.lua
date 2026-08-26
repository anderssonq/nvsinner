-- Source-level guard for lua/plugins/git/gitsigns.lua.
--
-- The hunk maps and the unified-inline-diff toggle live inside the spec's
-- `on_attach`, which never runs headless (tests/minimal_init.lua loads no
-- plugins and gitsigns never attaches), so nothing can be asserted against a
-- live gitsigns. Reading the source is the only assertion that can actually
-- fail when one regresses — the same reasoning as tests/plugins/neotree_spec.lua.

local function repo_root()
	local f = vim.api.nvim_get_runtime_file("lua/core/ai-activity.lua", false)[1]
	assert(f, "this config must be on the runtimepath (see tests/minimal_init.lua)")
	return vim.fn.fnamemodify(f, ":h:h:h")
end

describe("gitsigns spec", function()
	local spec = dofile(repo_root() .. "/lua/plugins/git/gitsigns.lua")

	-- Assertions run against the source with LINE COMMENTS STRIPPED: that file
	-- documents these contracts in prose, and matching the raw text would let a
	-- comment satisfy a test whose code had been deleted.
	local code
	before_each(function()
		local path = repo_root() .. "/lua/plugins/git/gitsigns.lua"
		local fd = assert(io.open(path, "r"), path .. " must exist")
		local src = fd:read("*a")
		fd:close()
		code = src:gsub("%-%-[^\n]*", "")
	end)

	it("is the gitsigns plugin", function()
		assert.are.equal("lewis6991/gitsigns.nvim", spec[1])
	end)

	it("attaches on a real file buffer", function()
		assert.is_true(vim.tbl_contains(spec.event, "BufReadPre"))
	end)

	-- Inline blame is lua/core/git-blame.lua's job; gitsigns owns the POPUP
	-- blame. Enabling this would draw two annotations on every cursor line.
	it("never enables current_line_blame", function()
		assert.is_not_true(spec.opts.current_line_blame)
		assert.is_nil(code:match("current_line_blame%s*=%s*true"))
	end)

	describe("unified inline diff", function()
		-- The merged, one-column reading Azure DevOps calls "unified". It cannot
		-- come from diffview — that renders through Neovim's native window 'diff'
		-- mode, which needs two diffed windows — so it lives here.
		it("is bound to <leader>gu", function()
			assert.matches('"<leader>gu"', code)
		end)

		-- The three flags ARE the view: any subset reads as a rendering bug.
		-- show_deleted alone shows the old lines with nothing marking the new
		-- ones; linehl alone is the sign column widened.
		for _, fn in ipairs({ "toggle_deleted", "toggle_linehl", "toggle_word_diff" }) do
			it("drives " .. fn, function()
				assert.matches("gs%." .. fn .. "%(inline%)", code)
			end)
		end

		-- `show_deleted` is deprecated as a *setup* option: gitsigns warns and
		-- drops it. Only the runtime toggle above still reaches the renderer.
		it("never passes show_deleted through opts", function()
			assert.is_nil(spec.opts.show_deleted)
			assert.is_nil(code:match("show_deleted%s*="))
		end)
	end)
end)
