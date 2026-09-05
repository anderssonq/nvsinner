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

describe("Vue breadcrumb LSP arbitration", function()
	local src = table.concat(vim.fn.readfile("lua/plugins/ui/barbacue.lua"), "\n")
	local code = src:gsub("%-%-[^\n]*", "")

	it("lets navic prefer vue_ls over vtsls without barbecue double-attaching", function()
		assert.is_truthy(code:find('require%("nvim%-navic"%)%.setup'))
		assert.is_truthy(code:find("auto_attach%s*=%s*true"))
		assert.is_truthy(code:find('preference%s*=%s*%{%s*"vue_ls"%s*,%s*"vtsls"%s*%}'))
		assert.is_truthy(code:find("attach_navic%s*=%s*false"))
	end)
end)

describe("lsp-config spec", function()
	local src = table.concat(vim.fn.readfile("lua/plugins/lsp/lsp-config.lua"), "\n")
	local code = src:gsub("%-%-[^\n]*", "")

	-- Inlay hints are a real 0.12 capability that was simply never called. The
	-- wiring has three halves that must agree: the capability gate, the
	-- persisted setting it reads (so the <leader>lh toggle and the
	-- :NvSinnerMenu row are one switch), and the toggle itself.
	it("gates inlay hints on the server capability AND the persisted setting", function()
		assert.is_truthy(code:find('supports_method%("textDocument/inlayHint"%)'))
		assert.is_truthy(code:find("vim%.lsp%.inlay_hint%.enable"))
		assert.is_truthy(code:find('get%("inlay_hints"%)'), "must read the setting, not hardcode a default")
		assert.is_truthy(code:find('"<leader>lh"'), "the toggle keymap")
		assert.is_truthy(code:find('set%("inlay_hints"'), "the toggle must persist through core.settings")
	end)

	-- Guard against re-adding a call for something Neovim already does: 0.12
	-- enables document colors by default, and :h lsp-defaults only documents
	-- how to opt OUT. Enabling it again would be a no-op that reads as a feature.
	it("does not re-enable document colors, which 0.12 turns on by default", function()
		assert.is_nil(code:find("document_color%.enable"))
	end)

	it("uses the Vue 3 hybrid stack without a duplicate TypeScript client", function()
		local installed = assert(code:match("ensure_installed%s*=%s*%{(.-)%}"))
		local enabled = assert(code:match("vim%.lsp%.enable%(%{(.-)%}%)"))

		assert.is_truthy(installed:find('"vtsls"', 1, true))
		assert.is_truthy(installed:find('"vue_ls"', 1, true))
		assert.is_falsy(installed:find('"ts_ls"', 1, true), "ts_ls and vtsls must not both be installed")
		assert.is_truthy(enabled:find('"vtsls"', 1, true))
		assert.is_truthy(enabled:find('"vue_ls"', 1, true))
		assert.is_falsy(enabled:find('"ts_ls"', 1, true), "ts_ls and vtsls must not both attach")
		assert.is_truthy(code:find('vim%.lsp%.config%("vtsls"'))
		assert.is_truthy(code:find('name%s*=%s*"@vue/typescript%-plugin"'))
		assert.is_truthy(code:find("location%s*=%s*vue_language_server_path"))
		assert.is_truthy(code:find('languages%s*=%s*%{%s*"vue"%s*%}'))
		assert.is_truthy(code:find('filetypes%s*=%s*%{[^}]-"vue"'))
	end)

	it("only enables toolchain-gated servers when their binaries exist", function()
		local enabled = assert(code:match("vim%.lsp%.enable%(%{(.-)%}%)"))
		assert.is_falsy(enabled:find('"solargraph"', 1, true))
		assert.is_falsy(enabled:find('"gopls"', 1, true))
		assert.is_falsy(enabled:find('"rust_analyzer"', 1, true))
		assert.is_truthy(code:find('server%s*=%s*"solargraph"'))
		assert.is_truthy(code:find('server%s*=%s*"gopls"'))
		assert.is_truthy(code:find('server%s*=%s*"rust_analyzer"'))
		assert.is_truthy(code:find("vim%.fn%.executable%(optional%.binary%)%s*==%s*1"))
		assert.is_truthy(code:find("vim%.lsp%.enable%(optional%.server%)"))
	end)

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
