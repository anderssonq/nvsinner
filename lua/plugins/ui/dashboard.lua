-- Start screen ("NvSinner" dashboard) built on alpha-nvim.
--
-- Layout mirrors the classic alpha "dashboard" theme: centred block logo,
-- a column of shortcut buttons, and a footer tagline. The block logo spells
-- NVSINNER (small-caps, beveled) — an ASCII nod to the gothic "Sinner" mark.
--
-- Buttons are wired to THIS config's real features (telescope, neo-tree,
-- persistence, lazy) rather than the alpha defaults. See CLAUDE.md.

return {
	"goolord/alpha-nvim",
	-- Loads at startup so the start screen shows on an empty `nvim` invocation.
	event = "VimEnter",
	dependencies = {
		"nvim-tree/nvim-web-devicons",
	},

	config = function()
		local alpha = require("alpha")
		local dashboard = require("alpha.themes.dashboard")

		-- ── Block logo ───────────────────────────────────────────────────────
		-- Every line is padded to the same width so alpha (which centres each
		-- header line individually) keeps the block's left edge aligned.
		dashboard.section.header.val = {
			[[██   ██  ██   ██   ▟████▙  ██████  ██   ██  ██   ██  ██████  █████▙ ]],
			[[███  ██  ██   ██  ██▘        ██    ███  ██  ███  ██  ██      ██  ██ ]],
			[[██▟▙ ██  ██   ██  ▜████▙     ██    ██▟▙ ██  ██▟▙ ██  █████   █████▛ ]],
			[[██ ▜▙██  ▜█▖ ▗█▛      ▝██    ██    ██ ▜▙██  ██ ▜▙██  ██      ██ ▜▙  ]],
			[[██  ▜██   ▜█▙█▛   ▖   ▟█▘    ██    ██  ▜██  ██  ▜██  ██      ██  ▜▙ ]],
			[[██   ██    ▜█▛    ▜████▛   ██████  ██   ██  ██   ██  ██████  ██   ██]],
		}

		-- ── Palette + highlights ─────────────────────────────────────────────
		-- Monochrome top→bottom gradient on the logo to match the glass theme
		-- (theme.lua), with a single muted-crimson accent for the "Sinner"
		-- identity on shortcuts + footer.
		local gradient = {
			"#e8e8ee",
			"#c5c9d5",
			"#9aa0b4",
			"#737a8e",
			"#54546d",
			"#3c3c4e",
		}
		local CRIMSON = "#c4746e" -- kanagawa "dragonRed", the lone colour accent
		local FG = "#c5c9d5"

		local function apply_dashboard_hl()
			for i, color in ipairs(gradient) do
				vim.api.nvim_set_hl(0, "NvSinnerLogo" .. i, { fg = color, bold = true })
			end
			vim.api.nvim_set_hl(0, "NvSinnerKey", { fg = CRIMSON, italic = true })
			vim.api.nvim_set_hl(0, "NvSinnerItem", { fg = FG })
			vim.api.nvim_set_hl(0, "NvSinnerFooter", { fg = CRIMSON, italic = true })
		end
		apply_dashboard_hl()
		-- Re-assert after any colorscheme reload (mirrors theme.lua's pattern).
		vim.api.nvim_create_autocmd("ColorScheme", {
			callback = apply_dashboard_hl,
		})

		-- Per-line gradient: one highlight region spanning each logo line.
		-- NOTE: alpha's table-form `hl` path computes a negative end column from
		-- the line *count* (#el.val), so `-1` would not span a multi-line header.
		-- Use the line's byte length (#line) as an explicit end column instead.
		local header_hl = {}
		for i, line in ipairs(dashboard.section.header.val) do
			header_hl[i] = { { "NvSinnerLogo" .. i, 0, #line } }
		end
		dashboard.section.header.opts.hl = header_hl

		-- ── Buttons (wired to this config) ───────────────────────────────────
		local function button(sc, txt, keybind)
			local b = dashboard.button(sc, txt, keybind)
			b.opts.hl = "NvSinnerItem"
			b.opts.hl_shortcut = "NvSinnerKey"
			return b
		end

		local config_dir = vim.fn.stdpath("config")
		dashboard.section.buttons.val = {
			button("f", "  Find file", "<cmd>Telescope find_files<cr>"),
			button("n", "  New file", "<cmd>ene | startinsert<cr>"),
			button("r", "  Recent files", "<cmd>Telescope oldfiles<cr>"),
			button("g", "  Find text", "<cmd>Telescope live_grep<cr>"),
			button("e", "  File explorer", "<cmd>Neotree toggle left<cr>"),
			button("s", "  Restore session", "<cmd>lua require('persistence').load()<cr>"),
			button("c", "  Configuration", "<cmd>Telescope find_files cwd=" .. config_dir .. "<cr>"),
			button("l", "  Plugins (Lazy)", "<cmd>Lazy<cr>"),
			button("q", "  Quit", "<cmd>qa<cr>"),
		}

		-- ── Footer ───────────────────────────────────────────────────────────
		dashboard.section.footer.val = "⟡ Don't stop until you're proud — NvSinner by andersoftware.com ⟡"
		dashboard.section.footer.opts.hl = "NvSinnerFooter"

		-- A little breathing room above the logo.
		dashboard.config.layout[1].val = 4

		alpha.setup(dashboard.config)
	end,
}
