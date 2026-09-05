-- Guard for nvim-cmp's kind chips.
--
-- The gap this closes: colors/carbon.lua has always defined all 25
-- `CmpItemKind*` groups as dark-text-on-accent chips, but completions.lua had
-- no `formatting` block, so nvim-cmp never rendered a kind and every one of
-- those 25 colors was dead weight — the popup came out uniformly gray.
--
-- The coherence assertion is the valuable half: a kind added to the palette
-- (or an icon dropped from the spec) without its counterpart is exactly the
-- drift that would silently bring the gray menu back for that kind.
--
-- cmp's `config` only runs on InsertEnter with the plugin loaded, and the test
-- harness loads no plugins — so this reads the source, the neotree_spec /
-- gitsigns_spec convention. Line comments are stripped first, or the prose
-- above a contract would be enough to satisfy the test.

local function source(path)
	local lines = vim.fn.readfile(path)
	for i, line in ipairs(lines) do
		lines[i] = line:gsub("%-%-.*$", "")
	end
	return table.concat(lines, "\n")
end

describe("nvim-cmp kind chips", function()
	local src = source("lua/plugins/lsp/completions.lua")

	it("renders a kind at all, with the chip leading the row", function()
		assert.is_truthy(src:find("formatting", 1, true), "no formatting block: the kind chips stay unused")
		assert.is_truthy(
			src:match('fields%s*=%s*{%s*"kind"'),
			"the kind field must come first — that is what makes the chip a square at the left edge"
		)
	end)

	it("has an icon for every CmpItemKind the colorscheme paints", function()
		local theme = source("colors/carbon.lua")
		local kinds = {}
		for kind in theme:gmatch("CmpItemKind(%a+)") do
			kinds[kind] = true
		end
		-- Sanity: the LSP kind set is 25 entries, so a broken scrape is visible
		-- here rather than passing vacuously with an empty table.
		local count = vim.tbl_count(kinds)
		assert.are.equal(25, count, "expected the 25 LSP completion kinds, scraped " .. count)

		for kind in pairs(kinds) do
			assert.is_truthy(src:match(kind .. '%s*=%s*"'), "no icon for CmpItemKind" .. kind)
		end
	end)
end)
