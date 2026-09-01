-- Tests for the treesitter query-API compat shim (lua/core/ts-compat.lua).
--
-- The important assertion in this file is the FIRST one: it pins the Neovim
-- query-API contract itself, with no plugin involved. The incident this module
-- exists for went undiagnosed for months precisely because nothing in the suite
-- asserted what `match[id]` actually is — the failure surfaced as "markdown
-- crashes Neovim", three abstraction layers away from the cause. If a future
-- Neovim flips this back, that test fails loudly and points here.
--
-- Everything runs against bundled parsers (markdown ships with Neovim 0.12), so
-- this file needs no plugins and runs anywhere, including CI and `-u NONE`.

local compat = require("core.ts-compat")

describe("core.ts-compat", function()
	after_each(function()
		compat._reset()
	end)

	-- Drives the real `#set-lang-from-info-string!` handler over a markdown fence
	-- and returns what it wrote into `metadata["injection.language"]`. Asserting
	-- the directive's OUTPUT (not the resulting injected tree) keeps this
	-- deterministic: whether a child LanguageTree has materialised by the time
	-- `for_each_tree` runs varies inside plenary's busted child, for reasons
	-- unrelated to this module.
	local function resolve_fence_language(lang)
		local buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "```" .. lang, "x = 1", "```" })
		local q = vim.treesitter.query.parse(
			"markdown",
			[[(fenced_code_block
			     (info_string (language) @lang)
			     (#set-lang-from-info-string! @lang))]]
		)
		local parser = vim.treesitter.get_parser(buf, "markdown")
		local out
		for _, _, meta in q:iter_matches(parser:parse()[1]:root(), buf, 0, -1) do
			out = meta["injection.language"]
		end
		return out
	end

	-- THE contract test. Nothing else in this suite pins a Neovim API shape.
	it("pins the 0.12 contract: a directive's match[id] is a LIST of nodes", function()
		local seen
		vim.treesitter.query.add_directive("nvsinner_contract_probe!", function(match, _, _, pred)
			seen = match[pred[2]]
		end, { force = true })

		local buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "```lua", "local a = 1", "```" })
		local q = vim.treesitter.query.parse(
			"markdown",
			"(fenced_code_block (info_string (language) @lang) (#nvsinner_contract_probe! @lang))"
		)
		local parser = vim.treesitter.get_parser(buf, "markdown")
		for _, _, _ in q:iter_matches(parser:parse()[1]:root(), buf, 0, -1) do
		end

		assert.are.equal("table", type(seen), "match[id] must be a table on this Neovim")
		assert.is_true(vim.islist(seen), "match[id] must be a LIST")
		assert.is_true(#seen >= 1, "match[id] must hold at least one node")
		assert.are.equal("userdata", type(seen[1]), "match[id][1] must be the TSNode")
	end)

	it("applies, reports success, and is idempotent", function()
		assert.is_false(compat._applied)
		assert.is_true(compat.apply())
		assert.is_true(compat._applied)
		-- A second config() run (reload, test) must be a cheap no-op.
		assert.is_true(compat.apply())
	end)

	-- The whole point of the shim: the directive must RESOLVE THE LANGUAGE, not
	-- merely stop throwing. Asserting "no error" alone would pass for a shim
	-- that returns early on every match — the old workaround in disguise.
	--
	-- This asserts the directive's own output (`metadata["injection.language"]`)
	-- rather than the resulting injected tree. That is the contract the shim
	-- actually owns, and it is deterministic: whether a child LanguageTree has
	-- materialised by the time `for_each_tree` runs varies inside plenary's
	-- busted child, which would make a tree-shaped assertion flaky for reasons
	-- that have nothing to do with this module.
	it("resolves a markdown fence language (the directive's real contract)", function()
		compat.apply()
		local ok, resolved = pcall(resolve_fence_language, "lua")
		assert.is_true(ok, "the directive must not throw on 0.12's list form: " .. tostring(resolved))
		assert.are.equal("lua", resolved, "the ```lua fence must resolve to the lua parser")
	end)

	-- The same defect broke HTML <script type=...> injections silently — no crash
	-- was ever reported against them, so nobody looked. The html parser is not
	-- bundled with Neovim (it comes from the plugin, absent in this harness), so
	-- the directive is driven over a markdown node instead: it only reads the
	-- node's text, and does not care which grammar produced it.
	local function resolve_mimetype(text)
		compat.apply()
		local buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "```" .. text, "x", "```" })
		local q = vim.treesitter.query.parse(
			"markdown",
			[[(fenced_code_block
			     (info_string (language) @t)
			     (#set-lang-from-mimetype! @t))]]
		)
		local parser = vim.treesitter.get_parser(buf, "markdown")
		local out
		for _, _, meta in q:iter_matches(parser:parse()[1]:root(), buf, 0, -1) do
			out = meta["injection.language"]
		end
		return out
	end

	it("resolves an HTML script mimetype through the split fallback", function()
		-- `text/javascript` is deliberately absent from the lookup table upstream:
		-- splitting on "/" already yields the right answer. Mirroring that exactly
		-- is what makes this a compat shim rather than a fork.
		assert.are.equal("javascript", resolve_mimetype("text/javascript"))
	end)

	it("resolves an HTML script mimetype through the lookup table", function()
		-- These four cannot be derived by splitting, which is why the table exists.
		assert.are.equal("javascript", resolve_mimetype("application/ecmascript"))
		assert.are.equal("json", resolve_mimetype("importmap"))
	end)

	-- Guards the load-order trap that would have burned the first implementation:
	-- the shim is worthless unless it registers AFTER the plugin's own handler.
	-- Simulate the plugin registering first, then apply(), then drive a query
	-- that actually invokes the directive — going through the runtime injections
	-- query instead would prove nothing, since it calls no directive at all.
	it("overrides a handler registered before it", function()
		local stale_ran = false
		vim.treesitter.query.add_directive("set-lang-from-info-string!", function(match, _, bufnr, pred, metadata)
			stale_ran = true
			-- Exactly the pre-0.12 shape the frozen plugin still uses: passing
			-- the list where a node is expected, which is what throws.
			metadata["injection.language"] = vim.treesitter.get_node_text(match[pred[2]], bufnr)
		end, { force = true })

		compat.apply()

		assert.are.equal("lua", resolve_fence_language("lua"), "apply() must win over the earlier registration")
		assert.is_false(stale_ran, "the overridden handler must not run")
	end)

	it("survives a failure without breaking the caller", function()
		-- apply() is pcall-guarded, so even a hostile API returns false, never
		-- an error that would abort the treesitter spec's config().
		local real = vim.treesitter.query.add_directive
		vim.treesitter.query.add_directive = function()
			error("boom")
		end
		local ok, result = pcall(compat.apply)
		vim.treesitter.query.add_directive = real
		assert.is_true(ok, "apply() must never propagate an error")
		assert.is_false(result, "a failed apply() reports false")
		assert.is_false(compat._applied, "a failed apply() must not latch")
	end)
end)
