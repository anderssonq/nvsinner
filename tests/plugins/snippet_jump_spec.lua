-- Guards for snippet placeholder navigation.
--
-- The bug this pins: expanding a snippet used to trap you on the first
-- placeholder. Neovim 0.11+ ships default <Tab>/<S-Tab> jump maps, but they
-- drive `vim.snippet`, while lua/plugins/lsp/completions.lua expands through
-- LuaSnip -- so `vim.snippet.active()` stays false, the builtin maps fall
-- through to a literal Tab, and nothing else was bound. You could expand a
-- snippet and never reach `${2:...}`.
--
-- The behavioural half below is the crux and runs headless. The *keys* cannot
-- be: a placeholder is SELECTED after an expand, so pressing <Tab> goes through
-- select mode, which needs a real PTY. Those are covered by source guards, the
-- neotree_spec / gitsigns_spec convention.
--
-- Verified by hand in a real PTY (2026-09-01, 0.12.3), and worth recording
-- because a naive assertion passes without the fix: pressing <Tab> in insert
-- mode moves the cursor EITHER WAY -- with the fix it jumps, without it a
-- literal tab is inserted and the cursor moves as a side effect. The honest
-- discriminator is the buffer text:
--     with the fix:    "local xy = BBB"     (clean jump, lands in select mode)
--     without the fix: "local xy   = BBB"   (a tab got typed into your code)

local function luasnip()
	local ok, ls = pcall(require, "luasnip")
	if ok then
		return ls
	end
	for _, root in ipairs({ vim.fn.stdpath("data"), vim.fn.expand("~/.local/share/nvsinner") }) do
		local dir = root .. "/lazy/LuaSnip"
		if vim.fn.isdirectory(dir) == 1 then
			vim.opt.runtimepath:prepend(dir)
			local ok2, ls2 = pcall(require, "luasnip")
			if ok2 then
				return ls2
			end
		end
	end
	return nil
end

describe("snippet placeholder navigation", function()
	it("proves the builtin jump maps cannot see a LuaSnip session", function()
		local ls = luasnip()
		if not ls then
			pending("LuaSnip not installed")
			return
		end
		local buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_set_current_buf(buf)
		ls.lsp_expand("local ${1:name} = ${2:value}")

		assert.is_true(ls.jumpable(1), "LuaSnip must report a placeholder ahead")
		-- THE bug, in one line: Neovim's default <Tab>/<S-Tab> maps are guarded
		-- on this, so with LuaSnip doing the expanding they are inert. If a
		-- future change moves expansion to `vim.snippet.expand`, this flips and
		-- the explicit maps become redundant — which is the moment to delete them.
		assert.is_false(
			vim.snippet.active(),
			"expansion goes through LuaSnip, so vim.snippet must be inactive — "
				.. "if this is now true, the builtin jump maps work and ours are dead weight"
		)
	end)
end)

describe("snippet jump keymaps", function()
	local comp = table.concat(vim.fn.readfile("lua/plugins/lsp/completions.lua"), "\n"):gsub("%-%-[^\n]*", "")
	local ai = table.concat(vim.fn.readfile("lua/core/ai-complete.lua"), "\n"):gsub("%-%-[^\n]*", "")

	it("binds the select-mode half, which is the one that actually fires", function()
		-- After an expand the placeholder is selected, so <Tab> arrives in select
		-- mode. Without this map the PTY run shows cursor 6 -> 6: stuck.
		assert.is_truthy(comp:find('vim%.keymap%.set%("s", "<Tab>"'), "select-mode <Tab> must jump forward")
		assert.is_truthy(
			comp:find('vim%.keymap%.set%({ "i", "s" }, "<S%-Tab>"'),
			"<S-Tab> must go backwards in both insert and select mode"
		)
		assert.is_truthy(comp:find("jumpable%(%-1%)") and comp:find("jump%(%-1%)"), "backward jump must be guarded")
	end)

	it("leaves insert-mode <Tab> to the arbiter in core/ai-complete", function()
		-- Mapping it here would silently REPLACE the chain that also handles
		-- cmp and the AI ghost — last map wins.
		assert.is_falsy(
			comp:find('keymap%.set%("i", "<Tab>"') or comp:find('keymap%.set%({ "i" }, "<Tab>"'),
			"completions.lua must not map insert-mode <Tab>"
		)
		assert.is_truthy(ai:find("luasnip_jumpable%(1%)"), "the arbiter must carry the forward-jump branch")
	end)

	it("keeps the arbiter's priority: ghost accept before snippet jump", function()
		local ghost = ai:find("_pending%(%)")
		local snip = ai:find("luasnip_jumpable%(1%)")
		assert.is_truthy(ghost and snip)
		assert.is_true(
			ghost < snip,
			"an AI ghost only exists because the user pressed <C-l>, so that explicit "
				.. "request must outrank an implicit placeholder jump"
		)
	end)
end)
