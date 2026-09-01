-- Behavioural guard for the treesitter query-API shim, WITH the real plugin.
--
-- tests/core/ts_compat_spec.lua pins the Neovim-side contract using bundled
-- parsers only. This file closes the other half: that nvim-treesitter's own
-- queries — the ones that actually shadow Neovim's on the runtimepath and
-- carry `#set-lang-from-info-string!` / `#set-lang-from-mimetype!` — parse
-- cleanly once `core.ts-compat` has re-registered the handlers.
--
-- It needs the installed plugin, so it `pending()`s when absent rather than
-- failing: a fresh clone with no plugins must not go red.

local compat = require("core.ts-compat")

local function plugin_dir()
	for _, root in ipairs({ vim.fn.stdpath("data"), vim.fn.expand("~/.local/share/nvsinner") }) do
		local dir = root .. "/lazy/nvim-treesitter"
		if vim.fn.isdirectory(dir) == 1 then
			return dir
		end
	end
	return nil
end

describe("nvim-treesitter query predicates", function()
	local dir = plugin_dir()

	-- Read the plugin's ACTUAL injections query off disk and parse it directly,
	-- rather than relying on runtimepath shadowing. `vim.treesitter.query.get`
	-- memoises per (lang, kind), and inside plenary's busted child the runtime
	-- query is often already cached before this spec can prepend the plugin —
	-- which silently made an earlier version of this test vacuous: it passed
	-- with the shim removed. Parsing the text is cache-proof and is the claim
	-- we actually care about: THIS query + the shim = no crash.
	local function plugin_markdown_injections()
		local f = dir .. "/queries/markdown/injections.scm"
		if vim.fn.filereadable(f) ~= 1 then
			return nil
		end
		return table.concat(vim.fn.readfile(f), "\n")
	end

	local function run_injections(text)
		local buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "# t", "", "```lua", "local a = 1", "```", "" })
		local q = vim.treesitter.query.parse("markdown", text)
		local parser = vim.treesitter.get_parser(buf, "markdown")
		local langs = {}
		for _, _, meta in q:iter_matches(parser:parse()[1]:root(), buf, 0, -1) do
			if meta["injection.language"] then
				langs[meta["injection.language"]] = true
			end
		end
		return langs
	end

	it("parses the plugin's own markdown injections query without throwing", function()
		if not dir then
			pending("nvim-treesitter not installed")
			return
		end
		vim.opt.runtimepath:prepend(dir)
		-- The plugin registers its pre-0.12 handlers; its query invokes them.
		require("nvim-treesitter.query_predicates")

		local text = plugin_markdown_injections()
		assert.is_truthy(text, "the plugin must ship queries/markdown/injections.scm")
		assert.is_truthy(
			text:find("set%-lang%-from%-info%-string!"),
			"this guard is only meaningful while the query still uses the broken directive"
		)

		compat.apply()

		local ok, langs = pcall(run_injections, text)
		assert.is_true(ok, "the plugin's markdown injections query must not throw: " .. tostring(langs))
		assert.is_true(langs.lua, "the ```lua fence must resolve to lua, got " .. vim.inspect(vim.tbl_keys(langs)))
	end)
end)

describe("nvim-treesitter spec", function()
	-- Source-level guards: `config` never runs headless, so read the file.
	-- Line comments are stripped first — this repo documents its contracts in
	-- prose, and raw-text matching once let a comment satisfy a test
	-- (see tests/plugins/neotree_spec.lua for where that lesson came from).
	local src = table.concat(vim.fn.readfile("lua/plugins/editor/nvim-treesitter.lua"), "\n")
	local code = src:gsub("%-%-[^\n]*", "")

	it("applies the compat shim from config()", function()
		assert.is_truthy(
			code:find('require%("core%.ts%-compat"%)%.apply%(%)'),
			"config() must call require('core.ts-compat').apply() — without it every markdown fence, "
				.. "HTML <script type=…> and bash heredoc throws on Neovim 0.12"
		)
	end)

	it("keeps the shim AFTER configs.setup{}", function()
		local setup_at = code:find("nvim%-treesitter%.configs")
		local shim_at = code:find("core%.ts%-compat")
		assert.is_truthy(setup_at and shim_at, "both calls must be present")
		assert.is_true(
			shim_at > setup_at,
			"apply() must run AFTER configs.setup{} — registering first lets the plugin's "
				.. "own add_directive silently overwrite the shim"
		)
	end)

	it("keeps the master branch pin the shim compensates for", function()
		assert.is_truthy(code:find('branch = "master"'), "the pin and the shim live and die together (FA-24)")
	end)
end)
