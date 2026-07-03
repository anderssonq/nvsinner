-- Start screen ("NvSinner" dashboard) built on alpha-nvim.
--
-- Layout mirrors the classic alpha "dashboard" theme: centred block logo, a
-- muted subtitle, a column of shortcut buttons, and a footer. The footer rotates
-- a random dev quote on each launch, with a constant "andersoftware.com"
-- attribution line below it. The block logo spells NVSINNER (small-caps,
-- beveled) — an ASCII nod to the gothic "Sinner" mark.
--
-- Buttons are wired to THIS config's real features (telescope, neo-tree,
-- persistence, lazy) rather than the alpha defaults. Menu items are also
-- mouse-aware: hovering highlights the item (a "pill") and a click runs it.
-- See CLAUDE.md.

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
		-- Monochrome top→bottom gradient on the logo (evenly spaced steps of
		-- the carbon gray ramp, base05 → base03), with the blue identity accent
		-- (base09) for the "Sinner" identity on shortcuts + footer.
		local c = require("core.carbon").colors()
		local gradient = {
			c.base05,
			c.base04,
			"#aeaeae", -- ramp midpoints between base04 and base03
			"#8d8d8d",
			"#6f6f6f",
			c.base03,
		}
		local ACCENT = c.base09 -- carbon blue, the identity accent
		local FG = c.base04

		local function apply_dashboard_hl()
			for i, color in ipairs(gradient) do
				vim.api.nvim_set_hl(0, "NvSinnerLogo" .. i, { fg = color, bold = true })
			end
			vim.api.nvim_set_hl(0, "NvSinnerKey", { fg = ACCENT, italic = true })
			vim.api.nvim_set_hl(0, "NvSinnerItem", { fg = FG })
			vim.api.nvim_set_hl(0, "NvSinnerFooter", { fg = ACCENT, italic = true })
			vim.api.nvim_set_hl(0, "NvSinnerSubtitle", { fg = "#a2a9b0", italic = true })
			vim.api.nvim_set_hl(0, "NvSinnerAttrib", { fg = c.base03, italic = true })
			-- Hover "pill" on the focused menu item (panel lift + brighter text).
			vim.api.nvim_set_hl(0, "NvSinnerHover", { fg = c.base05, bg = c.base02, bold = true })
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

		-- ── Mouse & hover: highlight and click menu items ────────────────────
		-- alpha keeps the cursor on the nearest button and runs it on <CR>, but has
		-- no mouse/hover feedback. Add: a "pill" highlight on the button the cursor
		-- is on (follows j/k, clicks AND mouse hover), <MouseMove> to move onto the
		-- button under the pointer, and <LeftRelease> to run it.
		local hover_ns = vim.api.nvim_create_namespace("nvsinner_dashboard_hover")

		-- Paint the pill on the button under the cursor. A button line is the only
		-- one whose label is followed by a right-aligned shortcut — i.e. a run of
		-- ≥2 spaces after its first word block — so requiring that gap skips the
		-- logo/subtitle/quote/attribution. The pill spans label → before the gap.
		local function render_hover(win, buf)
			if not (vim.api.nvim_win_is_valid(win) and vim.api.nvim_buf_is_valid(buf)) then
				return
			end
			vim.api.nvim_buf_clear_namespace(buf, hover_ns, 0, -1)
			local row = vim.api.nvim_win_get_cursor(win)[1]
			local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1]
			if not line then
				return
			end
			local s = line:find("%S") -- first non-space (skips the centering padding)
			local gap = s and line:find("  ", s, true) -- right-align padding after the label
			if not (s and gap) then
				return
			end
			vim.api.nvim_buf_set_extmark(buf, hover_ns, row - 1, s - 1, {
				end_col = gap - 1,
				hl_group = "NvSinnerHover",
				priority = 1000,
			})
		end

		-- <MouseMove>: put the cursor on the button under the pointer (let alpha
		-- snap; if the pointer isn't over a button, keep the selection where it is).
		local last_hover_line = -1
		local function hover_under_mouse()
			local a = require("alpha")
			local win = vim.api.nvim_get_current_win()
			local m = vim.fn.getmousepos()
			if m.winid ~= win or m.line < 1 or m.line == last_hover_line then
				return
			end
			last_hover_line = m.line
			local buf = vim.api.nvim_win_get_buf(win)
			if vim.api.nvim_win_get_cursor(win)[1] ~= m.line then
				local prev = vim.api.nvim_win_get_cursor(win)
				pcall(vim.api.nvim_win_set_cursor, win, { m.line, 0 })
				a.move_cursor(win)
				if vim.api.nvim_win_get_cursor(win)[1] ~= m.line then
					pcall(vim.api.nvim_win_set_cursor, win, prev) -- not a button: restore
					a.move_cursor(win)
				end
			end
			-- Repaint directly: an API cursor move doesn't fire CursorMoved, so we
			-- can't lean on that autocmd here (it covers keyboard j/k instead).
			render_hover(win, buf)
		end

		-- <LeftRelease>: run the button under the pointer, but only if the click
		-- actually landed on a button row (the snap kept the row) — so clicking the
		-- logo, quote or padding does nothing.
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

		local function attach_mouse(buf)
			if vim.b[buf].nvsinner_dash_mouse then
				return -- already wired (avoid duplicate CursorMoved autocmds)
			end
			vim.b[buf].nvsinner_dash_mouse = true

			local opts = { buffer = buf, silent = true }
			vim.keymap.set("n", "<LeftRelease>", press_under_mouse,
				vim.tbl_extend("force", opts, { desc = "Dashboard: run the item under the mouse" }))
			vim.keymap.set("n", "<MouseMove>", hover_under_mouse,
				vim.tbl_extend("force", opts, { desc = "Dashboard: hover the item under the mouse" }))

			-- Repaint the pill whenever the cursor lands on a button. Scheduled so
			-- it reads the position AFTER alpha's own CursorMoved snap.
			vim.api.nvim_create_autocmd("CursorMoved", {
				buffer = buf,
				callback = function()
					local win = vim.api.nvim_get_current_win()
					vim.schedule(function()
						render_hover(win, buf)
					end)
				end,
			})
			-- Initial paint (cursor starts on the first button once alpha draws).
			local win = vim.api.nvim_get_current_win()
			vim.schedule(function()
				render_hover(win, buf)
			end)
		end

		-- Attach on every alpha buffer (FileType fires when alpha draws); also wire
		-- the current buffer in case alpha already drew before this ran.
		vim.api.nvim_create_autocmd("FileType", {
			pattern = "alpha",
			callback = function(ev)
				attach_mouse(ev.buf)
			end,
		})
		if vim.bo.filetype == "alpha" then
			attach_mouse(0)
		end

		alpha.setup(dashboard.config)
	end,
}
