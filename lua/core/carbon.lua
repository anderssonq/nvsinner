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

-- ─── Accent packs ────────────────────────────────────────────────────────────
-- Four selectable identity accents. A pack swaps ONLY the identity accent pair
-- (base09 — THE carbon accent: keywords/types/operators, active markers,
-- breadcrumb icons — and its pale companion base15: numbers, escapes). All
-- gray surfaces (base00/base01/base02, blend, lift) are untouched, so the pack
-- recolors text accents, never the background. Hues are IBM Carbon tones
-- (40/30 tier on dark, 60/50 tier on light for contrast on white).
M.accents = {
	blue = { dark = {}, light = {} }, -- stock carbon (base09 #78a9ff / #ee5396)
	magenta = {
		dark = { base09 = "#ff7eb6", base15 = "#ffafd2" },
		light = { base09 = "#d02670", base15 = "#ee5396" },
	},
	green = {
		dark = { base09 = "#42be65", base15 = "#6fdc8c" },
		light = { base09 = "#198038", base15 = "#24a148" },
	},
	purple = {
		dark = { base09 = "#a56eff", base15 = "#d4bbff" },
		light = { base09 = "#8a3ffc", base15 = "#a56eff" },
	},
}

-- Which accent pack is active: "blue" (default) | "magenta" | "green" |
-- "purple". Same flag convention as background()/transparent() below:
-- vim.g.nvsinner_accent wins over $NVSINNER_ACCENT; anything unknown → "blue".
function M.accent()
	local a = vim.g.nvsinner_accent or vim.env.NVSINNER_ACCENT
	return (a and M.accents[a]) and a or "blue"
end

-- ─── Folder color packs ──────────────────────────────────────────────────────
-- Which accent paints neo-tree's folders (:NvSinnerMenu "Folder color"). The
-- values are ROLE NAMES, not hexes, so one table serves both variants and
-- every accent pack: the pair is resolved through colors() at apply time.
-- "accent" is the stock carbon look — folder names on the identity accent
-- (base09, so they follow the accent pack) with the pink base12 icon; every
-- other pack paints name + icon in one fixed accent. Like accent packs, this
-- only recolors text accents — gray surfaces never change.
M.folders = {
	accent = { name = "base09", icon = "base12" }, -- stock (follows the accent pack)
	teal = { name = "base07", icon = "base07" },
	aqua = { name = "base08", icon = "base08" },
	pink = { name = "base12", icon = "base12" },
	green = { name = "base13", icon = "base13" },
	purple = { name = "base14", icon = "base14" },
	gray = { name = "base04", icon = "base03" }, -- monochrome tree
}

-- Which folder pack is active: "accent" (default) or a key of M.folders.
-- Same flag convention: vim.g.nvsinner_folder wins over $NVSINNER_FOLDER.
function M.folder()
	local f = vim.g.nvsinner_folder or vim.env.NVSINNER_FOLDER
	return (f and M.folders[f]) and f or "accent"
end

-- Resolved hex pair for the active folder pack, over the active variant AND
-- accent pack: { name = "#…", icon = "#…" }. colors/carbon.lua reads this on
-- every apply, so `:colorscheme carbon` restyles the tree live.
function M.folder_colors()
	local roles = M.folders[M.folder()]
	local c = M.colors()
	return { name = c[roles.name], icon = c[roles.icon] }
end

-- ─── Single-role color slots ─────────────────────────────────────────────────
-- Generic version of the folder packs for element classes that take ONE color:
-- each slot (:NvSinnerMenu row) recolors a whole class — info notifications,
-- syntax variables, strings, functions. "default" keeps the stock carbon look
-- (colors/carbon.lua's original per-group roles, which for functions is a MIX
-- of roles — that's why stock can't be expressed as a single choice); any
-- other value paints the entire class in that one accent. Choices are ROLE
-- NAMES resolved through colors(), so "accent" follows the accent pack and
-- every choice adapts to the light variant automatically.
M.slot_choices = {
	accent = "base09", -- the identity accent (follows the accent pack)
	teal = "base07",
	aqua = "base08",
	magenta = "base10",
	pink = "base12",
	green = "base13",
	purple = "base14",
	plain = "base04", -- body-text gray
}

-- The slots and their flags (same vim.g > env > persisted convention).
M.slots = {
	notif = { g = "nvsinner_notif", env = "NVSINNER_NOTIF" }, -- NotifyINFO* accent
	variables = { g = "nvsinner_variables", env = "NVSINNER_VARIABLES" },
	strings = { g = "nvsinner_strings", env = "NVSINNER_STRINGS" },
	functions = { g = "nvsinner_functions", env = "NVSINNER_FUNCTIONS" },
}

-- Active choice for a slot: "default" or a key of M.slot_choices.
function M.slot(name)
	local s = M.slots[name]
	local v = vim.g[s.g] or vim.env[s.env]
	return (v and M.slot_choices[v]) and v or "default"
end

-- Resolved hex for a slot, or nil when "default" (caller keeps stock roles).
function M.slot_color(name)
	local choice = M.slot(name)
	if choice == "default" then
		return nil
	end
	return M.colors()[M.slot_choices[choice]]
end

-- Roles for the background currently in effect (vim.o.background), with the
-- active accent pack's overrides applied on top. Consumers re-resolve this on
-- every ColorScheme re-apply, so switching the accent + `:colorscheme carbon`
-- restyles the whole UI.
function M.colors()
	local variant = (vim.o.background == "light") and "light" or "dark"
	local base = M[variant]
	local pack = M.accents[M.accent()][variant]
	if next(pack) == nil then
		return base
	end
	return vim.tbl_extend("force", {}, base, pack)
end

-- ─── Feature flags ───────────────────────────────────────────────────────────
-- Read at startup by theme.lua and on every (re)apply by colors/carbon.lua and
-- ui-touch.lua. Three ways to set each flag (first match wins):
--   * vim.g (set by :NvSinnerMenu via lua/core/settings.lua, or by hand)
--   * environment: `NVSINNER_BACKGROUND=light NVSINNER_TRANSPARENT=1
--     NVSINNER_ACCENT=green nvsinner` (per launch)
--   * the persisted defaults lua/core/settings.lua seeds vim.g with at boot
-- The vim.g value wins over the environment variable when both are set;
-- settings.lua only seeds vim.g when NEITHER is set, so env overrides survive.

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
