-- Tests for the carbon palette + its feature flags (lua/core/carbon.lua) and
-- the colorscheme honoring them (colors/carbon.lua): the named background
-- themes, the theme/background/transparency flags (vim.g + env), and
-- :colorscheme carbon resolving through the active theme.

describe("core.carbon", function()
	local carbon = require("core.carbon")

	-- Every spec restores the flag/option state it touches.
	before_each(function()
		vim.g.nvsinner_theme = nil
		vim.g.nvsinner_background = nil
		vim.g.nvsinner_transparent = nil
		vim.env.NVSINNER_THEME = nil
		vim.env.NVSINNER_BACKGROUND = nil
		vim.env.NVSINNER_TRANSPARENT = nil
		vim.o.background = "dark"
	end)

	it("resolves the carbon role table by default and a named theme via the flag", function()
		assert.are.equal("#161616", carbon.colors().base00)
		vim.g.nvsinner_theme = "fjord"
		assert.are.equal("#2e3440", carbon.colors().base00)
		vim.g.nvsinner_theme = "moon"
		assert.are.equal("#ffffff", carbon.colors().base00)
	end)

	it("theme(): defaults to carbon, honors vim.g/env, unknown values fall back", function()
		assert.are.equal("carbon", carbon.theme())
		vim.env.NVSINNER_THEME = "mocha"
		assert.are.equal("mocha", carbon.theme())
		-- vim.g wins over the environment; invalid values fall back to carbon.
		vim.g.nvsinner_theme = "kyoto"
		assert.are.equal("kyoto", carbon.theme())
		vim.g.nvsinner_theme = "solarized"
		assert.are.equal("carbon", carbon.theme())
	end)

	it("theme(): honors the legacy background flag when no theme flag is set", function()
		vim.env.NVSINNER_BACKGROUND = "light"
		assert.are.equal("moon", carbon.theme())
		vim.g.nvsinner_background = "dark" -- vim.g wins over the env var
		assert.are.equal("carbon", carbon.theme())
		vim.g.nvsinner_theme = "fjord" -- and the theme flag wins over both
		assert.are.equal("fjord", carbon.theme())
	end)

	it("every named theme fills the full role set and registers coherently", function()
		local names = {}
		for _, name in ipairs(carbon.theme_names) do
			names[name] = true
			local entry = carbon.themes[name]
			assert.is_table(entry, name)
			assert.is_truthy(entry.variant == "dark" or entry.variant == "light", name .. ".variant")
			local palette = carbon[entry.palette]
			assert.is_table(palette, name .. " must point at a role table")
			for role, value in pairs(carbon.dark) do
				assert.are.equal(type(value), type(palette[role]), name .. " missing role " .. role)
			end
			for role in pairs(palette) do
				assert.is_not_nil(carbon.dark[role], name .. " has extra role " .. role)
			end
		end
		for name in pairs(carbon.themes) do
			assert.is_true(names[name] == true, name .. " missing from theme_names")
		end
	end)

	it("background(): derives the variant from the active theme", function()
		assert.are.equal("dark", carbon.background())
		vim.g.nvsinner_theme = "moon"
		assert.are.equal("light", carbon.background())
		vim.g.nvsinner_theme = "monolith"
		assert.are.equal("dark", carbon.background())
		vim.g.nvsinner_theme = nil
		vim.env.NVSINNER_BACKGROUND = "light" -- legacy flag still boots moon
		assert.are.equal("light", carbon.background())
	end)

	it("transparent(): defaults to false, honors the vim.g flag and the env var", function()
		assert.is_false(carbon.transparent())
		vim.g.nvsinner_transparent = true
		assert.is_true(carbon.transparent())
		vim.g.nvsinner_transparent = nil
		vim.env.NVSINNER_TRANSPARENT = "1"
		assert.is_true(carbon.transparent())
		vim.env.NVSINNER_TRANSPARENT = "0"
		assert.is_false(carbon.transparent())
	end)

	it("colorscheme carbon paints opaque surfaces by default", function()
		vim.cmd.colorscheme("carbon")
		assert.are.equal("carbon", vim.g.colors_name)
		local normal = vim.api.nvim_get_hl(0, { name = "Normal" })
		assert.are.equal(0x161616, normal.bg)
		assert.are.equal(0x131313, vim.api.nvim_get_hl(0, { name = "NormalFloat" }).bg)
	end)

	it("colorscheme carbon drops surface backgrounds in transparent mode", function()
		vim.g.nvsinner_transparent = true
		vim.cmd.colorscheme("carbon")
		assert.is_nil(vim.api.nvim_get_hl(0, { name = "Normal" }).bg)
		assert.is_nil(vim.api.nvim_get_hl(0, { name = "NormalFloat" }).bg)
		-- Chips stay solid so the UI remains legible on any terminal bg.
		assert.are.equal(0x33b1ff, vim.api.nvim_get_hl(0, { name = "StatusTerminal" }).bg)
		-- Restore the opaque scheme for any spec running after this one.
		vim.g.nvsinner_transparent = nil
		vim.cmd.colorscheme("carbon")
	end)

	it("named themes resolve through the same colorscheme", function()
		vim.g.nvsinner_theme = "moon"
		vim.cmd.colorscheme("carbon")
		assert.are.equal(0xffffff, vim.api.nvim_get_hl(0, { name = "Normal" }).bg)
		vim.g.nvsinner_theme = "kyoto"
		vim.cmd.colorscheme("carbon")
		assert.are.equal(0x1a1b26, vim.api.nvim_get_hl(0, { name = "Normal" }).bg)
		vim.g.nvsinner_theme = nil
		vim.cmd.colorscheme("carbon")
	end)
end)
