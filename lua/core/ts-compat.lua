-- ─── Treesitter query-API compat shim (native) ───────────────────────────────
-- Re-registers nvim-treesitter's query DIRECTIVES for Neovim 0.12's query API.
--
-- WHY THIS EXISTS. Neovim 0.12 changed the predicate/directive contract to
--   fun(match: table<integer, TSNode[]>, ...)
-- — `match[capture_id]` is now a LIST of nodes, never a single node. The plugin
-- is pinned to `branch = "master"` (frozen at cf12346a, 2026-03-23, archived
-- upstream) and still treats it as one node; its `query_predicates.lua:19`
-- passes `{ force = true, all = false }`, and on 0.12 `all` no longer exists and
-- is silently ignored. So every handler receives a list and every
-- `get_node_text(match[id])` throws
--   runtime/lua/vim/treesitter.lua:197: attempt to call method 'range' (a nil value)
--
-- That is the bug this repo spent months calling "the 0.12.x markdown treesitter
-- crash". It is NOT a Neovim defect. Probed 2026-08-31 on 0.12.3 — full evidence
-- in the `nvsinner-empirical-verification` skill, Recipe 7. It also silently
-- broke HTML (<script type=...>) and bash (heredoc) injections; only markdown
-- was ever reported, because only markdown had a label attached to it.
--
-- WHY A SHIM AND NOT A BRANCH MIGRATION. nvim-treesitter's `main` needs the
-- tree-sitter CLI on PATH (a new hard dependency across install.sh / health /
-- CI) and re-enters FA-24's parser-build failure surface — to fix a handful of
-- lines. Dropping the plugin is not an option either: $VIMRUNTIME ships queries
-- for only 7 languages (c lua markdown markdown_inline query vim vimdoc) and
-- none for typescript/javascript/vue/html/css. The plugin is kept for its
-- QUERIES, not its parsers (0.12 bundles those). Patching a frozen, doubly
-- pinned dependency is more stable here than upgrading it: the target cannot
-- move. This module is the compensating control for the `branch = "master"`
-- pin — remove one and you must remove the other.
--
-- SCOPE. Only the three directives any shipped query actually uses are
-- re-registered:
--     #set-lang-from-mimetype!     html_tags/injections.scm
--     #set-lang-from-info-string!  markdown/, hurl/injections.scm
--     #downcase!                   bash/, hcl/, php_only/, ruby/injections.scm
-- The plugin also registers `nth?`, `is?` and `kind-eq?`, which carry the same
-- defect but are referenced by ZERO query files in this pin — an unused handler
-- cannot crash, and re-registering `is?` would mean reimplementing the plugin's
-- locals machinery. Stubbing them would invent behaviour, so they are left
-- alone. Re-check with:
--     grep -rl '#nth?\|#is?\|#kind-eq?' <lazy>/nvim-treesitter/queries
--
-- LOAD ORDER IS LOAD-BEARING. `apply()` must run AFTER nvim-treesitter has
-- registered its own handlers, so it is called from that plugin's spec `config`
-- (right after `configs.setup{}`) and NOT from init.lua. Verified: registering
-- the shim pre-lazy and letting the plugin load afterwards lets its
-- `add_directive` silently overwrite ours — the shim never runs and the crash
-- returns. Do not reason from `core/markdown.lua`, whose pre-lazy patch survives
-- only because it sets a *query*, which is a different mechanism.

local M = {}

-- Idempotence guard: `config()` can run more than once (a reload, a test).
M._applied = false

-- 0.12 hands every handler a list of nodes. Take the strict list form on
-- purpose: a `type(v) == "table"` dual-mode guard would let a future API flip
-- pass silently, which is exactly the failure mode that produced this incident.
-- If Neovim changes this again, tests/core/ts_compat_spec.lua fails loudly and
-- points here, instead of surfacing as "markdown crashes" three layers away.
local function first(match, id)
	local nodes = match[id]
	if not nodes or #nodes == 0 then
		return nil
	end
	return nodes[1]
end

-- The two lookup tables below mirror nvim-treesitter's own, verbatim. The shim
-- fixes HOW the node is read, never WHAT the directive decides — keeping the
-- semantics identical is what makes this a compat shim rather than a fork.

-- `<script type="...">` values that don't resolve by splitting on "/".
-- (`text/javascript` is deliberately absent upstream: the split fallback below
-- already yields "javascript" for it.)
local HTML_SCRIPT_TYPE_LANGUAGES = {
	["importmap"] = "json",
	["module"] = "javascript",
	["application/ecmascript"] = "javascript",
	["text/ecmascript"] = "javascript",
}

-- Markdown fence aliases that `vim.filetype.match` cannot resolve on its own.
local NON_FILETYPE_MATCH_ALIASES = {
	ex = "elixir",
	pl = "perl",
	sh = "bash",
	uxn = "uxntal",
	ts = "typescript",
}

local function parser_from_info_string(alias)
	local matched = vim.filetype.match({ filename = "a." .. alias })
	return matched or NON_FILETYPE_MATCH_ALIASES[alias] or alias
end

function M.apply()
	if M._applied then
		return true
	end

	local ok, err = pcall(function()
		local query = vim.treesitter.query
		local get_text = vim.treesitter.get_node_text
		-- `all` is gone on 0.12; passing it would be ignored, so don't.
		local opts = { force = true }

		query.add_directive("set-lang-from-mimetype!", function(match, _, bufnr, pred, metadata)
			local node = first(match, pred[2])
			if not node then
				return
			end
			local type_attr_value = get_text(node, bufnr)
			local configured = HTML_SCRIPT_TYPE_LANGUAGES[type_attr_value]
			if configured then
				metadata["injection.language"] = configured
			else
				local parts = vim.split(type_attr_value, "/", {})
				metadata["injection.language"] = parts[#parts]
			end
		end, opts)

		query.add_directive("set-lang-from-info-string!", function(match, _, bufnr, pred, metadata)
			local node = first(match, pred[2])
			if not node then
				return
			end
			metadata["injection.language"] = parser_from_info_string(get_text(node, bufnr):lower())
		end, opts)

		query.add_directive("downcase!", function(match, _, bufnr, pred, metadata)
			local id = pred[2]
			local node = first(match, id)
			if not node then
				return
			end
			local text = get_text(node, bufnr, { metadata = metadata[id] }) or ""
			if not metadata[id] then
				metadata[id] = {}
			end
			metadata[id].text = text:lower()
		end, opts)
	end)

	if not ok then
		-- Never break boot over this: warn and leave the plugin's handlers in
		-- place (those injections stay broken; everything else keeps working).
		vim.notify("NvSinner: treesitter compat shim failed to apply — " .. tostring(err), vim.log.levels.WARN)
		return false
	end

	M._applied = true
	return true
end

-- Test seam: forget that we applied, so a spec can re-run apply().
function M._reset()
	M._applied = false
end

return M
