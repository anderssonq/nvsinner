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
		-- Search is a modal reading surface: results and preview deliberately
		-- remain solid while the editor around them becomes transparent.
		assert.are.equal(0x131313, vim.api.nvim_get_hl(0, { name = "TelescopeResultsNormal" }).bg)
		assert.are.equal(0x0d0d0d, vim.api.nvim_get_hl(0, { name = "TelescopePreviewNormal" }).bg)
		assert.are.equal(0x0d0d0d, vim.api.nvim_get_hl(0, { name = "TelescopePreviewBorder" }).bg)
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
		vim.g.nvsinner_theme = "briar"
		vim.cmd.colorscheme("carbon")
		assert.are.equal(0x191724, vim.api.nvim_get_hl(0, { name = "Normal" }).bg)
		vim.g.nvsinner_theme = "grove"
		vim.cmd.colorscheme("carbon")
		assert.are.equal(0x2d353b, vim.api.nvim_get_hl(0, { name = "Normal" }).bg)
		vim.g.nvsinner_theme = "neon"
		vim.cmd.colorscheme("carbon")
		assert.are.equal(0x16181a, vim.api.nvim_get_hl(0, { name = "Normal" }).bg)
		vim.g.nvsinner_theme = nil
		vim.cmd.colorscheme("carbon")
	end)

	-- Groups Neovim (or a plugin) ships with a hardcoded off-palette color, or
	-- with none at all. Each value below was MEASURED as wrong/absent before it
	-- was mapped, so this is the guard against drifting back to stock.
	it("claims the groups that otherwise arrive off-palette", function()
		vim.cmd.colorscheme("carbon")
		local c = carbon.colors()
		local function rgb(role)
			return tonumber(c[role]:sub(2), 16)
		end
		local function fg(group)
			return vim.api.nvim_get_hl(0, { name = group, link = false }).fg
		end
		local function bg(group)
			return vim.api.nvim_get_hl(0, { name = group, link = false }).bg
		end

		-- Shipped as Neovim's own pastels (#b3f6c0 / #8cf8f7 / #ffc0b9);
		-- @diff.plus/minus/delta default-link here, so these cover all six.
		assert.are.equal(rgb("base07"), fg("Added"))
		assert.are.equal(rgb("base09"), fg("Changed"))
		assert.are.equal(rgb("base10"), fg("Removed"))
		assert.are.equal(rgb("base07"), fg("@diff.plus"))

		-- Shipped with a gray of its own, off the monochrome ramp.
		assert.are.equal(rgb("base02"), fg("Conceal"))

		-- Undefined upstream: the active tab (visible in every diffview
		-- session) and the builtin popup's fuzzy-match run.
		assert.are.equal(rgb("base09"), bg("TabLineSel"))
		assert.is_not_nil(fg("PmenuMatch"))
		assert.is_not_nil(fg("MsgArea") or bg("MsgArea"))

		-- Plugin UIs that hardcode literal hexes rather than link.
		assert.are.equal(rgb("base09"), bg("MasonHeader"), "mason ships #DCA561")
		assert.are.equal(rgb("base09"), bg("LeapLabel"), "leap ships #ffaf3f")

		-- The graded heading ramp must match what the reading view paints, so a
		-- markdown buffer looks the same with core/markdown.lua on or off.
		local reader = { base10 = 1, base09 = 2, base12 = 3, base14 = 4, base08 = 5, base07 = 6 }
		for role, level in pairs(reader) do
			assert.are.equal(rgb(role), fg("@markup.heading." .. level), "heading level " .. level)
		end
	end)
end)
