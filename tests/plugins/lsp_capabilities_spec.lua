-- Guards for the Neovim 0.12 native LSP capabilities wired in
-- lua/plugins/lsp/lsp-config.lua. Two halves:
--
--   1. The APIs themselves exist on this Neovim. These are 0.12-only, and the
--      repo's floor is 0.12 — if a future Neovim moves or renames them, this
--      fails here rather than as "the keymap does nothing".
--   2. Source-level guards on the spec, because `config` only runs under lazy
--      and never in this harness (the neotree_spec / gitsigns_spec pattern).

describe("Neovim 0.12 LSP APIs", function()
	it("ships the capabilities this config wires up", function()
		assert.are.equal("function", type(vim.lsp.foldexpr), "vim.lsp.foldexpr backs <leader>zl")
		assert.are.equal("function", type(vim.lsp.linked_editing_range.enable))
		assert.are.equal("function", type(vim.lsp.buf.workspace_diagnostics))
	end)

	-- The reason <leader>zl is a per-window TOGGLE and not a default: the two
	-- fold methods are mutually exclusive, and this config binds <leader>zf to
	-- `:fold`. Pin the conflict so nobody "simplifies" the toggle into an
	-- always-on LspAttach and silently breaks manual folds.
	it("proves 'foldmethod=expr' makes :fold fail (why folding is opt-in)", function()
		local buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_set_current_buf(buf)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "a", "b", "c", "d" })

		vim.wo.foldmethod = "manual"
		assert.is_true(pcall(vim.cmd, "1,2fold"), "manual folding must work by default")

		vim.wo.foldmethod = "expr"
		vim.wo.foldexpr = "v:lua.vim.lsp.foldexpr()"
		local ok, err = pcall(vim.cmd, "3,4fold")
		assert.is_false(ok, "with expr folding, :fold must fail — that is the trade-off")
		assert.is_truthy(tostring(err):find("E350"), "expected E350, got " .. tostring(err))

		vim.wo.foldmethod = "manual"
		vim.wo.foldexpr = ""
	end)
end)

describe("lsp-config spec", function()
	local src = table.concat(vim.fn.readfile("lua/plugins/lsp/lsp-config.lua"), "\n")
	local code = src:gsub("%-%-[^\n]*", "")

	it("gates each capability on the server advertising it", function()
		assert.is_truthy(
			code:find('supports_method%("textDocument/linkedEditingRange"%)'),
			"linked editing must be capability-gated, not enabled blindly"
		)
		assert.is_truthy(
			code:find('supports_method%("textDocument/foldingRange"%)'),
			"the folding toggle must check for a capable client before switching foldmethod"
		)
	end)

	it("keeps LSP folding opt-in per window, never a default", function()
		assert.is_falsy(
			code:find('vim%.o%.foldmethod%s*=%s*"expr"'),
			"foldmethod must never be set globally — it would break <leader>zf everywhere"
		)
		assert.is_truthy(code:find("<leader>zl"), "the toggle keymap must exist")
		assert.is_truthy(
			code:find('foldmethod%s*=%s*"manual"'),
			"toggling off must restore manual folding, or <leader>zf stays broken"
		)
	end)

	it("exposes workspace diagnostics as a discoverable NvSinner command", function()
		-- The name matters: :NvSinnerHelp auto-discovers `NvSinner*` commands,
		-- so this shows up in the palette for free.
		assert.is_truthy(code:find('nvim_create_user_command%("NvSinnerDiagnosticsWorkspace"'))
		assert.is_truthy(code:find("pcall%(vim%.lsp%.buf%.workspace_diagnostics%)"), "must degrade, not throw")
	end)
end)
