-- Source guards for Telescope's adaptive search surface. The plugin config is
-- lazy and does not execute in the minimal harness, so pin the load-bearing
-- layout and backdrop decisions here; core/backdrop_spec.lua covers the shared
-- backdrop's behavior with real windows.

describe("telescope spec", function()
	local src = table.concat(vim.fn.readfile("lua/plugins/navigation/telescope.lua"), "\n")
	local code = src:gsub("%-%-[^\n]*", "")

	it("uses a flex layout with the prompt above results at both widths", function()
		assert.is_truthy(code:find('layout_strategy%s*=%s*"flex"'))
		assert.is_truthy(code:find("horizontal%s*=%s*%{"))
		assert.is_truthy(code:find("vertical%s*=%s*%{"))
		assert.are.equal(2, select(2, code:gsub('prompt_position%s*=%s*"top"', "")))
		assert.is_truthy(code:find("preview_width%s*=%s*0%.58"))
		assert.is_truthy(code:find("preview_height%s*=%s*0%.58"))
		assert.is_truthy(code:find("mirror%s*=%s*true"), "vertical mode must keep the prompt above the preview")
	end)

	it("adds one backdrop only when a preview window exists", function()
		assert.is_truthy(code:find('pattern%s*=%s*%{%s*"TelescopeFindPre"%s*,%s*"TelescopePreviewerLoaded"'))
		assert.is_truthy(code:find('winhl:find%("TelescopePreviewNormal"'))
		assert.is_truthy(code:find('require%("core%.backdrop"%)%.attach%(win%)'))
		assert.is_truthy(code:find("nvsinner_telescope_backdrop"))
	end)

	it("keeps the small ui-select picker on the dropdown theme", function()
		assert.is_truthy(code:find('%["ui%-select"%]'))
		assert.is_truthy(code:find('require%("telescope%.themes"%)%.get_dropdown'))
	end)

	it("continues to include hidden files while excluding git internals", function()
		assert.is_truthy(code:find("hidden%s*=%s*true"))
		assert.is_truthy(code:find('file_ignore_patterns%s*=%s*%{%s*"%^%%%.git/"'))
	end)

	it("keeps the peek-pickers for LSP definitions mapped", function()
		assert.is_truthy(code:find('%"%<leader%>ld%"'))
		assert.is_truthy(code:find('%"%<leader%>lt%"'))
		-- Without this, telescope jumps directly to a single result instead of
		-- opening the picker (builtin/__lsp.lua), so the peek would silently
		-- degrade into gd whenever there is exactly one definition.
		assert.is_equal(2, select(2, code:gsub('jump_type%s*=%s*"never"', "")))
	end)
end)
