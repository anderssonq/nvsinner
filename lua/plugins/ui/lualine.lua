-- Carbon statusline: the oxocarbon mode→accent convention.
-- The mode block is a solid accent chip with dark text; every other section is
-- muted base04 text on the editor background, so the bar stays gray-dominant
-- and the mode color is the one meaningful moment of color.
return {
	"nvim-lualine/lualine.nvim",
	event = "VeryLazy",
	dependencies = { "nvim-tree/nvim-web-devicons" },
	config = function()
		-- Build + apply with FRESH carbon roles each time (single source:
		-- lua/core/carbon.lua) and re-run on ColorScheme, so a live dark↔light /
		-- accent switch (:NvSinnerMenu) restyles the bar instead of leaving it on
		-- the boot-time palette.
		local mark = require("core.statusmark")
		local function wide()
			return vim.o.columns >= mark.MIN_COLUMNS
		end

		local function apply()
			local c = require("core.carbon").colors()

			-- Mode → accent (map documented in lua/core/carbon.lua); base09 for
			-- Normal (the blue-forward identity accent) per the §6.2 convention.
			local function mode(accent)
				return {
					a = { fg = c.base00, bg = accent, gui = "bold" },
					b = { fg = c.base04, bg = c.base00 },
					c = { fg = c.base04, bg = c.base00 },
				}
			end
			local carbon = {
				normal = mode(c.base09),
				insert = mode(c.base12),
				visual = mode(c.base14),
				replace = mode(c.base08),
				command = mode(c.base13),
				terminal = mode(c.base11),
				inactive = {
					a = { fg = c.base03, bg = c.base01 },
					b = { fg = c.base03, bg = c.base00 },
					c = { fg = c.base03, bg = c.base00 },
				},
			}

			require("lualine").setup({
				options = {
					theme = carbon,
					component_separators = "",
					section_separators = "",
					globalstatus = true,
					-- No refresh override: lualine's default is event-driven
					-- (WinEnter/BufEnter/CursorMoved/ModeChanged/…, 16ms coalescing)
					-- with a 1s fallback timer. The 100ms override existed only to
					-- keep the removed AI badge counts live.
				},
				-- Shimmer: every gray text component carries `fmt = mark.fmt(<id>)`,
				-- which hands lualine a core/statusmark.lua expression instead of
				-- the text, so one subtle band can sweep the whole bar while an
				-- animation frame repaints one row instead of re-running lualine.
				-- The ids MUST ascend left→right (the module detects a new
				-- evaluation pass by an id that does not). The mode + location
				-- chips and diagnostics keep their semantic colors and are not
				-- wrapped; fmt runs before lualine adds the icon, so icons keep
				-- theirs too.
				sections = {
					lualine_a = { "mode" },
					lualine_b = {
						-- Clickable icons (not shimmer-wrapped): the terminal toggles
						-- horizontal terminal 1 like <leader>t; the robot opens the
						-- agent cockpit like <leader>xa. Glyphs as \u escapes so an
						-- editor can never strip the private-use codepoints.
						{
							function()
								return "\u{f489}" -- nf-oct-terminal
							end,
							color = { fg = c.base09 },
							on_click = mark.terminal_click,
						},
						{
							function()
								return "\u{f06a9}" -- nf-md-robot
							end,
							color = { fg = c.base09 },
							on_click = mark.agents_click,
						},
						{ "branch", fmt = mark.fmt(1) },
					},
					-- Project name (the cwd's root folder) ahead of the filename, so
					-- the bar answers "which project?" before "which file?". The name
					-- keeps the section's muted base04; only the folder icon carries
					-- the base09 identity accent — the same icon-colored/name-muted
					-- split core/filebadge.lua uses, so the bar stays gray-dominant.
					-- core/project.lua caches the lookup: this runs on every redraw.
					-- Narrow terminals only: from MIN_COLUMNS up the name moves into
					-- the centered mark below, so it is shown exactly once at any width.
					lualine_c = {
						{
							require("core.project").statusline,
							icon = { "󰉋", color = { fg = c.base09 } },
							cond = function()
								return not wide()
							end,
							fmt = mark.fmt(2),
						},
						{ "filename", fmt = mark.fmt(3) },
						-- Centered NvSinner identity mark. lualine emits exactly one `%=`
						-- ahead of the first non-empty x/y/z section, so this second one
						-- makes two separation points and Neovim splits the free space
						-- equally between them: the mark centres in whatever room the real
						-- sections leave, which is screen-centre only when the two sides
						-- weigh the same. Hidden under MIN_COLUMNS so it never crowds a
						-- narrow terminal.
						"%=",
						{
							-- "‹ NvSinner ▏<project> ›", shimmering with the rest of the
							-- bar. A left click opens the :NvSinnerHelp command palette.
							mark.text,
							padding = 0,
							cond = wide,
							fmt = mark.fmt(4),
							on_click = mark.click,
						},
					},
					lualine_x = { "diagnostics", { "filetype", fmt = mark.fmt(5) } },
					lualine_y = { { "progress", fmt = mark.fmt(6) } },
					lualine_z = { "location" },
				},
			})
		end
		apply()
		mark.start()
		vim.api.nvim_create_autocmd("ColorScheme", {
			group = vim.api.nvim_create_augroup("nv_lualine_carbon", { clear = true }),
			pattern = "*",
			callback = apply,
		})
	end,
}
