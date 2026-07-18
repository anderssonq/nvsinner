-- Start screen ("NvSinner" dashboard) built on alpha-nvim.
--
-- Layout mirrors the classic alpha "dashboard" theme: centred logo, a muted
-- subtitle, a column of shortcut buttons, and a footer. The footer rotates
-- a random dev quote on each launch, with a constant "andersoftware.com"
-- attribution line below it. The logo is the distressed shade-block NVSINNER
-- mark — the same ASCII art as the README header (one identity everywhere).
--
-- Buttons are wired to THIS config's real features (telescope, neo-tree,
-- the native core/sessions, lazy) rather than the alpha defaults. Menu items are also
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

		-- ── Logo ─────────────────────────────────────────────────────────────
		-- The distressed shade-block NVSINNER mark — the SAME ASCII art as the
		-- README header, so the terminal start screen and the repo front page
		-- share one identity. It's plain text (█▓▒░ shade blocks), so it renders
		-- in any terminal exactly like the README code block does. Lines are
		-- padded programmatically to one display width because alpha centres
		-- each header line individually — unequal widths would skew the block.
		local logo = {
			[[██▄   ██ ░▒    ░      ▄███▓▒░ ░█ ██▄   ██ ██▄   ██ ░▒▓██ ▒▄   █████░▄]],
			[[█▓░▒▄ ▀█ ▒▓    ▒░    ▀█▀ ▄    ██ █▓░▒▄ ▀█ █▓░▒▄ ▀█    ░  ▀▓░▄ ██   ▀░▒▄]],
			[[▓▒ ▀▓▒▄░ ▐█▌   ▓▒       ▀░▒▄  ██ ▓▒ ▀▓▒▄░ ▓▒ ▀▓▒▄░   ░▒▀  ▀▀  ▓█▄█▄░▄▒▓▀]],
			[[▒░   ▀▓█  ░▒▄ ▄█▌        ▄▒▓▀ █▓ ▒░   ▀▓█ ▒░   ▀▓█   ▒▓   ▄▀▀ ▒▓ ▀██░▀]],
			[[░     ▒▓   ▀▓▒░▀  ░▒▓███░░▀   ▓▒ ░     ▒▓ ░     ▒▓ ░▒▓███ ░▀▀ ░▒   ▀██▄]],
			[[      ░▒     ▀                ▒░       ░▒       ░▒             ░     ▀█▀]],
			[[                              ░]],
		}
		local logo_width = 0
		for _, line in ipairs(logo) do
			logo_width = math.max(logo_width, vim.fn.strdisplaywidth(line))
		end
		for i, line in ipairs(logo) do
			logo[i] = line .. string.rep(" ", logo_width - vim.fn.strdisplaywidth(line))
		end
		dashboard.section.header.val = logo

		-- ── Palette + highlights ─────────────────────────────────────────────
		-- Monochrome top→bottom gradient on the logo (evenly spaced steps of
		-- the carbon gray ramp, base05 → base03), with the identity accent
		-- (base09) for the "Sinner" identity on shortcuts + footer. Roles are
		-- resolved INSIDE the applier so a live dark↔light / accent switch
		-- (:NvSinnerMenu) recolors the dashboard too.
		local function apply_dashboard_hl()
			local c = require("core.carbon").colors()
			local gradient = {
				c.base05,
				c.base04,
				"#b6b6b6", -- ramp midpoints between base04 and base03
				"#9c9c9c",
				"#838383",
				"#6a6a6a",
				c.base03,
			}
			for i, color in ipairs(gradient) do
				vim.api.nvim_set_hl(0, "NvSinnerLogo" .. i, { fg = color, bold = true })
			end
			vim.api.nvim_set_hl(0, "NvSinnerKey", { fg = c.base09, italic = true })
			vim.api.nvim_set_hl(0, "NvSinnerItem", { fg = c.base04 })
			vim.api.nvim_set_hl(0, "NvSinnerFooter", { fg = c.base09, italic = true })
			-- base04 (body text): the subtitle reads brighter than the base03
			-- attribution line below it, and the role adapts to the light variant
			-- (the old hardcoded #a2a9b0 was off-palette and dark-only).
			vim.api.nvim_set_hl(0, "NvSinnerSubtitle", { fg = c.base04, italic = true })
			vim.api.nvim_set_hl(0, "NvSinnerAttrib", { fg = c.base03, italic = true })
			-- Hover "pill" on the focused menu item (panel lift + brighter text).
			vim.api.nvim_set_hl(0, "NvSinnerHover", { fg = c.base05, bg = c.base02, bold = true })
			-- Version-check footer states (core/version.lua): muted for the
			-- spinner + "up to date" line (NvSinnerAttrib tone), the attention
			-- accent for the update prompt.
			vim.api.nvim_set_hl(0, "NvSinnerVersion", { fg = c.base03, italic = true })
			vim.api.nvim_set_hl(0, "NvSinnerUpdateAvail", { fg = c.base10, italic = true })
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
			button("s", "  Restore session", "<cmd>NvSinnerSessionLoad<cr>"),
			button("c", "  Configuration", "<cmd>Telescope find_files cwd=" .. config_dir .. "<cr>"),
			button("l", "  Plugins (Lazy)", "<cmd>Lazy<cr>"),
			button("q", "  Quit", "<cmd>qa<cr>"),
		}

		-- ── Footer ───────────────────────────────────────────────────────────
		-- A dev quote picked fresh on every launch (this config runs once per
		-- VimEnter), sitting above a CONSTANT attribution line — so the rotating
		-- quote changes but "andersoftware.com" is always shown. The quote area
		-- doubles as the version-check surface (core/version.lua): a spinner
		-- while the once-per-session check is in flight, the :NvSinnerUpdate
		-- prompt when an update is available, the quote plus a muted "up to
		-- date" line when current, and the plain quote on idle/error.
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
		local quote = "⟡ " .. quotes[math.random(#quotes)] .. " ⟡"

		local SPIN = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
		-- Anchored via the footer.val closure (held by alpha's config for the
		-- session), so luv can't GC an active timer handle.
		local spin = { frame = 1, timer = nil }

		local function any_alpha_win()
			for _, w in ipairs(vim.api.nvim_list_wins()) do
				if vim.bo[vim.api.nvim_win_get_buf(w)].filetype == "alpha" then
					return true
				end
			end
			return false
		end

		local function stop_spinner() -- idempotent
			if spin.timer then
				pcall(function()
					spin.timer:stop()
					spin.timer:close()
				end)
				spin.timer = nil
			end
		end

		-- Animate the "checking" line; self-stops once the check resolves or
		-- the dashboard closes (the resolution redraw arrives via on_change
		-- below, so the last tick never paints a stale frame).
		local function ensure_spinner()
			if spin.timer then
				return
			end
			spin.timer = vim.uv.new_timer()
			spin.timer:start(
				120,
				120,
				vim.schedule_wrap(function()
					if require("core.version").status() ~= "checking" or not any_alpha_win() then
						stop_spinner()
						return
					end
					spin.frame = spin.frame % #SPIN + 1
					pcall(require("alpha").redraw)
				end)
			)
		end

		-- Per-line highlights with explicit byte ends (same idiom as the header
		-- gradient above; offsets are relative to the unpadded line — alpha adds
		-- the centering offset itself).
		local function line_hl(rows)
			local hl = {}
			for i, row in ipairs(rows) do
				hl[i] = { { row[1], 0, #row[2] } }
			end
			return hl
		end

		-- footer.val is a FUNCTION: alpha re-resolves it on every draw, so the
		-- async check swaps states by just redrawing. It must return a TABLE of
		-- lines — alpha renders a "\n" string as multiple screen lines but
		-- advances its line accounting by only 1, corrupting every later
		-- element's highlights (verified in alpha's layout_element.text).
		dashboard.section.footer.val = function()
			local v = require("core.version")
			v.check() -- first draw == dashboard actually shown; the once-guard makes redraw re-calls free
			local st = v.status()
			local rows
			if st == "checking" then
				ensure_spinner()
				rows = { { "NvSinnerVersion", SPIN[spin.frame] .. "  checking for updates…" } }
			elseif st == "outdated" then
				rows = {
					{
						"NvSinnerUpdateAvail",
						"A new version of NvSinner is available ("
							.. v.display(v.latest())
							.. ") — update with :NvSinnerUpdate",
					},
				}
			elseif st == "latest" then
				rows = {
					{ "NvSinnerFooter", quote },
				}
			else -- idle | error → the plain quote (an error already warned via :messages)
				rows = { { "NvSinnerFooter", quote } }
			end
			dashboard.section.footer.opts.hl = line_hl(rows)
			local lines = {}
			for i, row in ipairs(rows) do
				lines[i] = row[2]
			end
			return lines
		end

		-- Redraw when the check resolves; a closed dashboard is skipped (and
		-- alpha.redraw itself bails with no alpha window, pcall for the rest).
		require("core.version").on_change(function()
			if any_alpha_win() then
				pcall(require("alpha").redraw)
			end
		end)

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

		-- "NvSinner is up to date" as its OWN centered element. alpha centers
		-- each element on its longest line, so a short line riding inside the
		-- footer (which holds the wide, variable-length quote) would
		-- left-align under the quote. Keeping it on its own line lets it centre
		-- on the screen. The `val` function (re-resolved on every redraw, like
		-- the footer) only paints when the version check resolved to "latest".
		table.insert(dashboard.config.layout, {
			type = "text",
			val = function()
				if require("core.version").status() == "latest" then
					return "NvSinner is up to date"
				end
				return ""
			end,
			opts = { position = "center", hl = "NvSinnerVersion" },
		})
		-- Attribution as its OWN centered element. alpha centers each element on
		-- its longest line, so keeping this short line out of the footer (which
		-- holds the wide, variable-length quote) lets it centre on the screen
		-- instead of left-aligning under the quote.
		table.insert(dashboard.config.layout, { type = "padding", val = 1 })
		table.insert(dashboard.config.layout, {
			type = "text",
			val = "andersoftware.com · github.com/anderssonq/nvsinner",
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
			vim.keymap.set(
				"n",
				"<LeftRelease>",
				press_under_mouse,
				vim.tbl_extend("force", opts, { desc = "Dashboard: run the item under the mouse" })
			)
			vim.keymap.set(
				"n",
				"<MouseMove>",
				hover_under_mouse,
				vim.tbl_extend("force", opts, { desc = "Dashboard: hover the item under the mouse" })
			)

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
