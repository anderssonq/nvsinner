-- ─── Carbon palette ─────────────────────────────────────────────────────────
-- The base16 role palette of NvSinner's "carbon" theme — a self-contained port
-- of oxocarbon.nvim (Nyoom Engineering / Shaun Singh), itself inspired by the
-- IBM Carbon Design System. This file is the design doc of record AND the
-- SINGLE SOURCE OF TRUTH for every color in the config: colors/carbon.lua (the
-- colorscheme), the core modules (ui-touch, ai-activity), and the UI chrome
-- plugin specs all pull ROLES from here — never raw hexes — so the dark and
-- light variants share one code path and the palette can never drift out of
-- sync between files.
--
-- Design philosophy (what makes it read as carbon, not "another dark theme"):
--   * Industrial grayscale core — most of any screen is neutral gray; color is
--     used sparingly and always MEANS something (error, string, active, busy).
--   * Blue-forward accent family — centered on vibrant blues; even the pinks
--     lean blue.
--   * Body text is base04, never pure white; base06 white is reserved for
--     delimiters. Comments are dim base03, italic. Syntax fg-only (bg = NONE).
--   * Floats sit on the recessed `blend` surface, BELOW the editor, borderless.
--
-- Role convention:
--   base00–base05  monochrome ramp, background → foreground
--   base06         pure foreground extreme (white in dark)
--   base07–base15  the accents (teal, aqua, blues, magenta/pinks, green, purple)
--   blend          recessed float surface (darker than base00 on purpose)
--   lift           focused-pane surface (between base00 and base01; NvSinner's
--                  focus-glow needs a step the stock ramp doesn't have)
--   diff_*         the four hand-tuned diff washes
--
-- Statusline mode → accent map (implemented in lua/plugins/ui/lualine.lua):
-- normal base09 · insert base12 · visual base14 · replace base08 ·
-- command base13 · terminal base11 — dark base00 text on a solid accent chip.

local M = {}

-- Dark variant (primary). Upstream hardcodes only base00/base06/base09 and
-- derives the gray ramp by blending base00→base06 in HSLuv (perceptually
-- uniform) space at 0.085 / 0.18 / 0.30 / 0.82 / 0.95; the resolved hexes are
-- inlined here so no color math is needed at runtime.
M.dark = {
	base00 = "#161616", -- editor background
	base01 = "#262626", -- panels: CursorLine, Pmenu, dim bars, Folded
	base02 = "#393939", -- Visual, MatchParen, borders, prompt panels
	base03 = "#525252", -- comments (italic), LineNr, muted/inactive text
	base04 = "#d0d0d0", -- main foreground / body text (NOT pure white)
	base05 = "#f2f2f2", -- brightest fg: float text, completion match
	base06 = "#ffffff", -- pure white: delimiters, IncSearch fg
	base07 = "#08bdba", -- teal: DiffAdded, @method, @namespace, macros
	base08 = "#3ddbd9", -- aqua: Function, punctuation, Directory, Search bg
	base09 = "#78a9ff", -- blue: keywords, Type, operators — THE carbon accent
	base10 = "#ee5396", -- magenta: errors, markdown headings, modified marks
	base11 = "#33b1ff", -- light blue: terminal-mode block, CurSearch
	base12 = "#ff7eb6", -- pink: @function, insert-mode block, busy chip
	base13 = "#42be65", -- green: Todo, HealthSuccess, command-mode block
	base14 = "#be95ff", -- purple: strings, DiagnosticWarn, visual-mode block
	base15 = "#82cfff", -- pale blue: numbers, normal-mode block
	blend = "#131313", -- recessed float/panel bg (floats sit BELOW the editor)
	lift = "#1c1c1c", -- focused-pane lift (base00 ↔ base01 midpoint)
	none = "NONE",
	-- Diff washes: desaturated/darkened accents, the only hand-tuned hexes in
	-- the highlight rules.
	diff_add = "#122f2f",
	diff_change = "#222a39",
	diff_text = "#2f3f5c",
	diff_delete = "#361c28",
}

-- Light variant. Same role slots, higher-contrast accents suited to white.
M.light = {
	base00 = "#ffffff",
	base01 = "#f2f2f2",
	base02 = "#d0d0d0",
	base03 = "#161616",
	base04 = "#37474F",
	base05 = "#90A4AE",
	base06 = "#525252",
	base07 = "#08bdba",
	base08 = "#ff7eb6",
	base09 = "#ee5396",
	base10 = "#FF6F00",
	base11 = "#0f62fe",
	base12 = "#673AB7",
	base13 = "#42be65",
	base14 = "#be95ff",
	base15 = "#FFAB91",
	blend = "#FAFAFA",
	lift = "#f7f7f7",
	none = "NONE",
	-- Pale tints of the dark washes so diffs read as tinted panels on white.
	diff_add = "#dcf3ec",
	diff_change = "#dfe7f5",
	diff_text = "#cddcf5",
	diff_delete = "#f7dfe8",
}

-- Roles for the background currently in effect (vim.o.background).
function M.colors()
	return (vim.o.background == "light") and M.light or M.dark
end

-- ─── Feature flags ───────────────────────────────────────────────────────────
-- Read at startup by theme.lua and on every (re)apply by colors/carbon.lua and
-- ui-touch.lua. Two ways to set each flag:
--   * persistently: `vim.g.nvsinner_background = "light"` /
--     `vim.g.nvsinner_transparent = true` early in lua/core/options.lua
--   * per launch:   `NVSINNER_BACKGROUND=light NVSINNER_TRANSPARENT=1 nvsinner`
-- The vim.g value wins over the environment variable when both are set.

-- Which variant to boot into: "dark" (default) or "light".
function M.background()
	local bg = vim.g.nvsinner_background or vim.env.NVSINNER_BACKGROUND
	return bg == "light" and "light" or "dark"
end

-- Transparent mode: the colorscheme drops every full-surface background
-- (editor, floats, statusline, panels) so the terminal's own background shows
-- through; small chips/bars (mode block, busy chip, terminal focus bar) keep
-- their solid accent so the UI stays legible.
function M.transparent()
	local t = vim.g.nvsinner_transparent
	if t == nil then
		t = vim.env.NVSINNER_TRANSPARENT
	end
	return t == true or t == 1 or t == "1" or t == "true"
end

return M
