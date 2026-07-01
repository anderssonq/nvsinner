-- Start screen ("NvSinner" dashboard) built on alpha-nvim.
--
-- Layout mirrors the classic alpha "dashboard" theme: centred block logo, a
-- muted subtitle, a column of shortcut buttons, and a footer. The footer rotates
-- a random dev quote on each launch, with a constant "andersoftware.com"
-- attribution line below it. The block logo spells NVSINNER (small-caps,
-- beveled) — an ASCII nod to the gothic "Sinner" mark.
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
			vim.api.nvim_set_hl(0, "NvSinnerSubtitle", { fg = "#9aa0b4", italic = true })
			vim.api.nvim_set_hl(0, "NvSinnerAttrib", { fg = "#7a7f8d", italic = true })
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
		-- A dev quote picked fresh on every launch (this config runs once per
		-- VimEnter), sitting above a CONSTANT attribution line — so the rotating
		-- quote changes but "andersoftware.com" is always shown.
		local quotes = {
			"Don't stop until you're proud",
			"Greatness is the orphan of urgency",
			"First, solve the problem. Then, write the code",
			"Clean code always looks like it was written by someone who cares",
			"Make it work, make it right, make it fast. — Kent Beck",
			"The best code is no code at all. — Jeff Atwood",
			"Simplicity is the soul of efficiency. — Austin Freeman",
			"Walking on water and developing software from a specification are easy if both are frozen. — Edward V. Berard",
		}
		math.randomseed(vim.uv.hrtime())
		local quote = quotes[math.random(#quotes)]

		dashboard.section.footer.val = "⟡ " .. quote .. " ⟡"
		dashboard.section.footer.opts.hl = "NvSinnerFooter"

		-- A little breathing room above the logo.
		dashboard.config.layout[1].val = 4

		-- Muted tagline under the logo. Inserted right after the header (its own
		-- centered element, so it centres on its own width like the attribution).
		table.insert(dashboard.config.layout, 3, {
			type = "text",
			val = "‹ the sinner's neovim ide ›",
			opts = { position = "center", hl = "NvSinnerSubtitle" },
		})
		table.insert(dashboard.config.layout, 3, { type = "padding", val = 1 })

		-- Attribution as its OWN centered element. alpha centers each element on
		-- its longest line, so keeping this short line out of the footer (which
		-- holds the wide, variable-length quote) lets it centre on the screen
		-- instead of left-aligning under the quote.
		table.insert(dashboard.config.layout, { type = "padding", val = 1 })
		table.insert(dashboard.config.layout, {
			type = "text",
			val = "NvSinner · andersoftware.com",
			opts = { position = "center", hl = "NvSinnerAttrib" },
		})

		-- ── Mouse: click a menu item to run it ───────────────────────────────
		-- alpha snaps the cursor to the nearest button and runs it on <CR>, but
		-- has no mouse handling. Add a click: jump to the clicked line, let alpha
		-- snap, and fire ONLY when the click actually landed on a button row (the
		-- snap kept the row) — so clicking the logo, quote or padding does nothing.
		local function press_under_mouse()
			local a = require("alpha")
			local win = vim.api.nvim_get_current_win()
			local m = vim.fn.getmousepos()
			if m.winid ~= win or m.line < 1 then
				return
			end
			pcall(vim.api.nvim_win_set_cursor, win, { m.line, math.max(m.column - 1, 0) })
			a.move_cursor(win)
			if vim.api.nvim_win_get_cursor(win)[1] == m.line then
				pcall(a.press)
			end
		end

		local function attach_click(buf)
			vim.keymap.set("n", "<LeftRelease>", press_under_mouse, {
				buffer = buf,
				silent = true,
				desc = "Dashboard: run the item under the mouse",
			})
		end

		-- Attach on every alpha buffer (FileType fires when alpha draws); also map
		-- the current buffer in case alpha already drew before this ran.
		vim.api.nvim_create_autocmd("FileType", {
			pattern = "alpha",
			callback = function(ev)
				attach_click(ev.buf)
			end,
		})
		if vim.bo.filetype == "alpha" then
			attach_click(0)
		end

		alpha.setup(dashboard.config)
	end,
}
