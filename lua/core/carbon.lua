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
-- Light-variant contract (every theme whose registry entry says
-- variant = "light"). The role NAMES are identical, but the ramp walks toward
-- a dark extreme instead of a white one, so above base02 the meaning inverts:
--   base00–base02  surfaces, lightest → darkest (bg, panels, Visual/borders)
--   base03         the LIGHTEST foreground: muted comments — never darker
--                  than body text, or comments shout over the code
--   base04         body text
--   base05         strongest fg: float text, completion match — DARKER than
--                  base04, because it must read on the recessed `blend`
--   base06         the dark extreme: delimiters, IncSearch fg
--   blend/shade    still recessed, i.e. DARKER than base00 (not lighter)
--   lift           still between base00 and base01
-- Accents keep their carbon roles, but a light port may darken one a step: the
-- statusline mode chips paint base00 text on a solid accent, and base00 is
-- near-white here, so a pastel accent would swallow the label.
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
	shade = "#0d0d0d", -- modal surface: darker than blend so the NvSinner modals contrast with the editor
	backdrop = "#000000", -- dimming overlay behind the modals (blended via winblend)
	lift = "#1c1c1c", -- focused-pane lift (base00 ↔ base01 midpoint)
	none = "NONE",
	-- Diff washes: desaturated/darkened accents, the only hand-tuned hexes in
	-- the highlight rules.
	diff_add = "#122f2f",
	diff_change = "#222a39",
	diff_text = "#2f3f5c",
	diff_delete = "#361c28",
}

-- Light variant ("carbon-light"). Same role slots, accents re-picked for white.
-- Note the ramp INVERTS above base02: on a light background the "extreme" the
-- ramp walks toward is black, not white, so base03 is the LIGHTEST foreground
-- (muted comments) and base06 the darkest (delimiters). See the light-variant
-- role contract in the header.
M.light = {
	base00 = "#ffffff",
	base01 = "#f2f2f2",
	base02 = "#d0d0d0",
	base03 = "#6f6f6f", -- muted comments (carbon gray-60), NOT darker than body text
	base04 = "#37474F", -- body text
	base05 = "#263238", -- strongest fg: float text, completion match
	base06 = "#161616", -- the dark extreme: delimiters, IncSearch fg
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
	shade = "#ececec", -- modal surface: darker than blend so the modals contrast on white
	backdrop = "#000000", -- dimming overlay behind the modals (black works on white too)
	lift = "#f7f7f7",
	none = "NONE",
	-- Pale tints of the dark washes so diffs read as tinted panels on white.
	diff_add = "#dcf3ec",
	diff_change = "#dfe7f5",
	diff_text = "#cddcf5",
	diff_delete = "#f7dfe8",
}

-- ─── Background themes ───────────────────────────────────────────────────────
-- Named, user-selectable palettes (:NvSinnerMenu "Background theme"). Each is
-- named after the scheme it ports, and fills the exact same role slots as
-- M.dark, so every consumer works unchanged; the role SEMANTICS (base09
-- identity, base10 attention, base12 busy, …) are carbon's, only the hues
-- change. Hexes are hand-derived from each upstream's public palette and tuned
-- to the carbon role contract (body text base04 never pure white, blend below
-- base00, lift between base00/base01) — these are ports, not byte-for-byte
-- copies, and a port may darken an accent one step so the solid mode chips
-- keep legible text.
--
-- The two historic names are aliases now: "moon" is "carbon-light" and the
-- eight invented names ("onedusk", "kyoto", …) map to the real scheme names
-- via M.theme_aliases below, so persisted choices and $NVSINNER_THEME keep
-- working.

-- "onedark" — One Dark Pro (Atom's One Dark).
M.onedark = {
	base00 = "#282c34",
	base01 = "#31353f",
	base02 = "#3e4451",
	base03 = "#5c6370",
	base04 = "#abb2bf",
	base05 = "#c8cdd5",
	base06 = "#e6e6e6",
	base07 = "#2bbac5", -- teal
	base08 = "#56b6c2", -- cyan: functions/punctuation
	base09 = "#61afef", -- One Dark blue — the identity accent
	base10 = "#e06c75", -- red: errors/attention
	base11 = "#528bff", -- vivid blue: terminal-mode
	base12 = "#d19a66", -- orange: insert-mode block, busy chip
	base13 = "#98c379", -- green
	base14 = "#c678dd", -- purple: strings
	base15 = "#8cc2f0", -- pale companion of base09
	blend = "#23272e",
	shade = "#1e2227",
	backdrop = "#000000",
	lift = "#2c313a",
	none = "NONE",
	diff_add = "#2b3a30",
	diff_change = "#2b3440",
	diff_text = "#32405a",
	diff_delete = "#3b2d34",
}

-- "catppuccin-mocha" — Catppuccin's darkest flavour.
M.catppuccin_mocha = {
	base00 = "#1e1e2e",
	base01 = "#313244",
	base02 = "#45475a",
	base03 = "#6c7086",
	base04 = "#cdd6f4",
	base05 = "#dee3f8",
	base06 = "#f5f7ff",
	base07 = "#94e2d5", -- teal
	base08 = "#89dceb", -- sky
	base09 = "#89b4fa", -- Mocha blue — the identity accent
	base10 = "#f38ba8", -- red: errors/attention
	base11 = "#74c7ec", -- sapphire: terminal-mode
	base12 = "#f5c2e7", -- pink: insert-mode block, busy chip
	base13 = "#a6e3a1", -- green
	base14 = "#cba6f7", -- mauve: strings
	base15 = "#b4befe", -- lavender: pale companion
	blend = "#181825", -- mantle
	shade = "#11111b", -- crust
	backdrop = "#000000",
	lift = "#232338",
	none = "NONE",
	diff_add = "#283b33",
	diff_change = "#262f47",
	diff_text = "#2f3e63",
	diff_delete = "#3c2a3c",
}

-- "tokyonight" — Tokyo Night (folke/tokyonight.nvim), its "night" variant.
M.tokyonight = {
	base00 = "#1a1b26",
	base01 = "#24283b",
	base02 = "#343a55",
	base03 = "#565f89",
	base04 = "#c0caf5",
	base05 = "#d9e0fb",
	base06 = "#edf1fe",
	base07 = "#73daca", -- teal
	base08 = "#7dcfff", -- cyan
	base09 = "#7aa2f7", -- Tokyo Night blue — the identity accent
	base10 = "#f7768e", -- red: errors/attention
	base11 = "#2ac3de", -- bright cyan: terminal-mode
	base12 = "#ff9e64", -- orange: insert-mode block, busy chip
	base13 = "#9ece6a", -- green
	base14 = "#bb9af7", -- purple: strings
	base15 = "#a9c3ff", -- pale companion of base09
	blend = "#16161e",
	shade = "#101016",
	backdrop = "#000000",
	lift = "#1f2030",
	none = "NONE",
	diff_add = "#20362f",
	diff_change = "#222f45",
	diff_text = "#2c3f66",
	diff_delete = "#37222c",
}

-- "tokyonight-day" — Tokyo Night's light "day" variant. The fg ramp inverts
-- (base03 lightest → base06 darkest); accents come straight from upstream's
-- day palette, which is already tuned for contrast on a light surface.
M.tokyonight_day = {
	base00 = "#e1e2e7", -- bg
	base01 = "#d6d8e3", -- panels: CursorLine, Pmenu, Folded
	base02 = "#c4c8da", -- Visual, MatchParen, borders
	base03 = "#848cb5", -- comments (upstream's day comment)
	base04 = "#3760bf", -- body text (upstream fg)
	base05 = "#2c4b9c", -- strongest fg: float text
	base06 = "#1c3578", -- the dark extreme: delimiters
	base07 = "#118c74", -- teal
	base08 = "#007197", -- cyan: functions/punctuation
	base09 = "#2e7de9", -- Tokyo Night Day blue — the identity accent
	base10 = "#f52a65", -- red: errors/attention
	base11 = "#006a83", -- deep cyan: terminal-mode
	base12 = "#b15c00", -- orange: insert-mode block, busy chip
	base13 = "#587539", -- green
	base14 = "#7847bd", -- purple: strings
	base15 = "#5f77c9", -- muted indigo: companion of base09
	blend = "#d9dbe4", -- recessed float surface (darker than base00)
	shade = "#ced2e0", -- modal surface: darker still
	backdrop = "#000000",
	lift = "#dcdde4", -- focused-pane lift (base00 ↔ base01)
	none = "NONE",
	diff_add = "#d7e8d5",
	diff_change = "#d5dff0",
	diff_text = "#c2d3ee",
	diff_delete = "#f0d5dd",
}

-- "nord" — Nord (Arctic Ice Studio).
M.nord = {
	base00 = "#2e3440",
	base01 = "#3b4252",
	base02 = "#434c5e",
	base03 = "#616e88", -- nord3 brightened for legible comments
	base04 = "#d8dee9",
	base05 = "#e5e9f0",
	base06 = "#eceff4",
	base07 = "#8fbcbb", -- frost teal
	base08 = "#81a1c1", -- frost gray-blue: functions
	base09 = "#88c0d0", -- Nord frost cyan — the identity accent
	base10 = "#bf616a", -- aurora red: errors/attention
	base11 = "#5e81ac", -- deep frost: terminal-mode
	base12 = "#d08770", -- aurora orange: insert-mode block, busy chip
	base13 = "#a3be8c", -- aurora green
	base14 = "#b48ead", -- aurora purple: strings
	base15 = "#a1ccdb", -- pale companion of base09
	blend = "#292e38",
	shade = "#232732",
	backdrop = "#000000",
	lift = "#333947",
	none = "NONE",
	diff_add = "#3a4a41",
	diff_change = "#3a4456",
	diff_text = "#45536e",
	diff_delete = "#4a353c",
}

-- "monokai" — Monokai (Wimer Hazenberg's original, via Monokai Pro's tones).
M.monokai = {
	base00 = "#272822",
	base01 = "#33342b",
	base02 = "#49483e",
	base03 = "#75715e",
	base04 = "#f8f8f2",
	base05 = "#fcfcf7",
	base06 = "#ffffff",
	base07 = "#78dce8", -- soft cyan
	base08 = "#a6e22e", -- Monokai green: functions
	base09 = "#66d9ef", -- Monokai cyan-blue — the identity accent
	base10 = "#f92672", -- Monokai pink-red: errors/attention
	base11 = "#8ce0f0", -- light cyan: terminal-mode
	base12 = "#fd971f", -- orange: insert-mode block, busy chip
	base13 = "#b6e354", -- bright green
	base14 = "#ae81ff", -- purple: strings
	base15 = "#a1e7f5", -- pale companion of base09
	blend = "#22231d",
	shade = "#1c1d17",
	backdrop = "#000000",
	lift = "#2c2d27",
	none = "NONE",
	diff_add = "#343e20",
	diff_change = "#2c3a3d",
	diff_text = "#39525c",
	diff_delete = "#452430",
}

-- "rose-pine" — Rosé Pine (its darkest "main" variant). Rose, iris and gold
-- over a deep plum base; base05/base06, the pale iris companion and the diff
-- washes are derived, the rest are upstream roles.
M.rose_pine = {
	base00 = "#191724", -- base
	base01 = "#1f1d2e", -- surface
	base02 = "#403d52", -- highlight_med: Visual, borders
	base03 = "#6e6a86", -- muted: comments
	base04 = "#e0def4", -- text
	base05 = "#eceafa",
	base06 = "#f7f5ff",
	base07 = "#9ccfd8", -- foam: teal
	base08 = "#ebbcba", -- rose: functions/punctuation
	base09 = "#c4a7e7", -- iris — the identity accent
	base10 = "#eb6f92", -- love: errors/attention
	base11 = "#3e8fb0", -- brightened pine: terminal-mode
	base12 = "#ea9a97", -- warm rose: insert-mode block, busy chip
	base13 = "#95b1ac", -- leaf: Todo/success
	base14 = "#f6c177", -- gold: strings, DiagnosticWarn
	base15 = "#d7c4f0", -- pale iris: companion of base09
	blend = "#16141f", -- rose-pine's own inactive-window bg
	shade = "#12101a",
	backdrop = "#000000",
	lift = "#1c1a29",
	none = "NONE",
	diff_add = "#22302c",
	diff_change = "#262b3d",
	diff_text = "#343c58",
	diff_delete = "#3a2330",
}

-- "everforest" — Everforest (sainnhe/everforest), dark medium contrast.
-- Upstream ships its own bg_green/bg_blue/bg_red washes, so three of the four
-- diff slots are verbatim; base05/base06, base11, base13 and base15 are derived.
M.everforest = {
	base00 = "#2d353b", -- bg0
	base01 = "#343f44", -- bg1: CursorLine, Pmenu
	base02 = "#475258", -- bg3: Visual, borders
	base03 = "#7a8478", -- grey0: comments
	base04 = "#d3c6aa", -- fg
	base05 = "#e3d9c3",
	base06 = "#f2ead6",
	base07 = "#83c092", -- aqua: teal
	base08 = "#7fbbb3", -- blue: functions/punctuation
	base09 = "#a7c080", -- green — the identity accent
	base10 = "#e67e80", -- red: errors/attention
	base11 = "#9acdc6", -- pale blue: terminal-mode
	base12 = "#e69875", -- orange: insert-mode block, busy chip
	base13 = "#b6d18c", -- brighter green (base09 owns the signature one)
	base14 = "#d699b6", -- purple: strings, DiagnosticWarn
	base15 = "#c3d9a4", -- pale green: companion of base09
	blend = "#232a2e", -- bg_dim
	shade = "#1e2326", -- the hard variant's bg_dim
	backdrop = "#000000",
	lift = "#313940",
	none = "NONE",
	diff_add = "#3c4841", -- bg_green
	diff_change = "#3a515d", -- bg_blue
	diff_text = "#45606d",
	diff_delete = "#514045", -- bg_red
}

-- "everforest-light" — Everforest light, medium contrast: the same forest
-- accents over upstream's warm paper bg0. Accents are darkened one step from
-- the light palette so the solid mode chips (base00 text on the accent) stay
-- legible; the fg ramp inverts (base03 lightest → base06 darkest).
M.everforest_light = {
	base00 = "#fdf6e3", -- bg0: warm paper
	base01 = "#efebd4", -- bg2: CursorLine, Pmenu, Folded
	base02 = "#e0dcc7", -- bg4: Visual, MatchParen, borders
	base03 = "#939f91", -- grey1: comments
	base04 = "#5c6a72", -- fg
	base05 = "#4a5860", -- strongest fg: float text
	base06 = "#384850", -- the dark extreme: delimiters
	base07 = "#1f9e6e", -- aqua: teal
	base08 = "#2b7fa8", -- blue: functions/punctuation
	base09 = "#6c8000", -- green — the identity accent
	base10 = "#e0443f", -- red: errors/attention
	base11 = "#2d8bb0", -- blue: terminal-mode
	base12 = "#cf6a15", -- orange: insert-mode block, busy chip
	base13 = "#4f8c2a", -- deeper green: Todo/success, command-mode
	base14 = "#c4569f", -- purple: strings, DiagnosticWarn
	base15 = "#8a9c3a", -- olive: companion of base09
	blend = "#f4f0d9", -- bg1: recessed float surface
	shade = "#eae6cf", -- modal surface: darker still
	backdrop = "#000000",
	lift = "#f7f2de", -- focused-pane lift (base00 ↔ base01)
	none = "NONE",
	diff_add = "#e3ecd0",
	diff_change = "#dfe9ef",
	diff_text = "#cfe0ea",
	diff_delete = "#f4dcd8",
}

-- "nightfox" — Nightfox (EdenEast/nightfox.nvim), the flagship dark variant.
M.nightfox = {
	base00 = "#192330", -- bg1: Normal
	base01 = "#212e3f", -- bg2: CursorLine, Pmenu, Folded
	base02 = "#29394f", -- bg3: Visual, MatchParen, borders
	base03 = "#738091", -- comment
	base04 = "#cdcecf", -- fg1: body text
	base05 = "#d6d6d7", -- fg0
	base06 = "#e4e4e5", -- bright white: delimiters
	base07 = "#63cdcf", -- cyan: teal
	base08 = "#7ad5d6", -- bright cyan: functions/punctuation
	base09 = "#719cd6", -- Nightfox blue — the identity accent
	base10 = "#c94f6d", -- red: errors/attention
	base11 = "#86abdc", -- bright blue: terminal-mode
	base12 = "#f4a261", -- orange: insert-mode block, busy chip
	base13 = "#81b29a", -- green: Todo/success
	base14 = "#9d79d6", -- magenta: strings, DiagnosticWarn
	base15 = "#a6c6ea", -- pale blue: companion of base09
	blend = "#131a24", -- bg0: recessed float surface
	shade = "#0f151d",
	backdrop = "#000000",
	lift = "#1d2937", -- focused-pane lift (base00 ↔ base01)
	none = "NONE",
	diff_add = "#26332c",
	diff_change = "#22303f",
	diff_text = "#2c405a",
	diff_delete = "#33222a",
}

-- "dayfox" — Dayfox, Nightfox's light sibling: warm paper with earthy, already
-- dark accents (upstream tunes them for a light surface, so no extra darkening
-- is needed). The fg ramp inverts (base03 lightest → base06 darkest).
M.dayfox = {
	base00 = "#f6f2ee", -- bg1: warm paper
	base01 = "#eae1d9", -- bg2: CursorLine, Pmenu, Folded
	base02 = "#ded2c6", -- bg3: Visual, MatchParen, borders
	base03 = "#8b7d6f", -- muted warm gray: comments
	base04 = "#352c24", -- body text
	base05 = "#2a231c", -- strongest fg: float text
	base06 = "#1d1913", -- the dark extreme: delimiters
	base07 = "#1d8b7a", -- teal
	base08 = "#2a7ba8", -- blue: functions/punctuation
	base09 = "#2848a9", -- Dayfox blue — the identity accent
	base10 = "#a5222f", -- red: errors/attention
	base11 = "#287980", -- cyan: terminal-mode
	base12 = "#a8521a", -- burnt orange: insert-mode block, busy chip
	base13 = "#396847", -- green: Todo/success, command-mode
	base14 = "#6e33ce", -- magenta: strings, DiagnosticWarn
	base15 = "#4c6da8", -- muted blue: companion of base09
	blend = "#efe9e3", -- recessed float surface (darker than base00)
	shade = "#e4dcd4", -- bg0: modal surface, darker still
	backdrop = "#000000",
	lift = "#f2ede7", -- focused-pane lift (base00 ↔ base01)
	none = "NONE",
	diff_add = "#dfe9dc",
	diff_change = "#dde3ef",
	diff_text = "#cbd6ea",
	diff_delete = "#f0dcdc",
}

-- "cyberdream" — cyberdream: electric accents on near-black. Body text is
-- pulled off pure white (base06's job per the role contract) and base07/base11/
-- base15 are derived inside the palette's own hue family.
M.cyberdream = {
	base00 = "#16181a", -- bg
	base01 = "#1e2124", -- bg_alt
	base02 = "#3c4048", -- bg_highlight: Visual, borders
	base03 = "#7b8496", -- grey: comments
	base04 = "#f0f2f4", -- body text (upstream fg is pure white; base06 keeps that)
	base05 = "#f8f9fa",
	base06 = "#ffffff",
	base07 = "#5effc0", -- spring teal
	base08 = "#5ef1ff", -- cyan: functions/punctuation
	base09 = "#5ea1ff", -- blue — the identity accent
	base10 = "#ff6e5e", -- red: errors/attention
	base11 = "#5ecdff", -- light blue: terminal-mode
	base12 = "#ff5ea0", -- pink: insert-mode block, busy chip
	base13 = "#5eff6c", -- green: Todo/success
	base14 = "#bd5eff", -- purple: strings, DiagnosticWarn
	base15 = "#9fc6ff", -- pale blue: companion of base09
	blend = "#121415",
	shade = "#0d0f10",
	backdrop = "#000000",
	lift = "#1a1c1f",
	none = "NONE",
	diff_add = "#133024",
	diff_change = "#12283f",
	diff_text = "#1a3a5c",
	diff_delete = "#3a1a18",
}

-- Registry: theme name → which role table it uses and which vim.o.background
-- variant it belongs to (the variant also picks the accent-pack overrides).
-- Public names carry hyphens; the role tables above use underscores, because a
-- hyphen is not a Lua identifier — `palette` bridges the two.
M.themes = {
	-- dark
	carbon = { palette = "dark", variant = "dark" },
	onedark = { palette = "onedark", variant = "dark" },
	["catppuccin-mocha"] = { palette = "catppuccin_mocha", variant = "dark" },
	tokyonight = { palette = "tokyonight", variant = "dark" },
	nord = { palette = "nord", variant = "dark" },
	monokai = { palette = "monokai", variant = "dark" },
	["rose-pine"] = { palette = "rose_pine", variant = "dark" },
	everforest = { palette = "everforest", variant = "dark" },
	cyberdream = { palette = "cyberdream", variant = "dark" },
	nightfox = { palette = "nightfox", variant = "dark" },
	-- light
	["carbon-light"] = { palette = "light", variant = "light" },
	["tokyonight-day"] = { palette = "tokyonight_day", variant = "light" },
	["everforest-light"] = { palette = "everforest_light", variant = "light" },
	dayfox = { palette = "dayfox", variant = "light" },
}

-- Retired names → the real scheme names that replaced them. Resolved by
-- M.theme(), so a persisted choice, a `vim.g.nvsinner_theme` set by hand and
-- `NVSINNER_THEME=kyoto nvsinner` all keep working; lua/core/settings.lua
-- rewrites the persisted value on load so the JSON heals itself.
M.theme_aliases = {
	moon = "carbon-light",
	onedusk = "onedark",
	mocha = "catppuccin-mocha",
	kyoto = "tokyonight",
	fjord = "nord",
	monolith = "monokai",
	briar = "rose-pine",
	grove = "everforest",
	neon = "cyberdream",
}

-- Menu/cycle order (:NvSinnerMenu reads this — pairs() order would jitter).
-- Dark themes first, then light, so cycling with h/l does not flash the
-- background back and forth on the way past.
M.theme_names = {
	"carbon",
	"onedark",
	"catppuccin-mocha",
	"tokyonight",
	"nord",
	"monokai",
	"rose-pine",
	"everforest",
	"cyberdream",
	"nightfox",
	"carbon-light",
	"tokyonight-day",
	"everforest-light",
	"dayfox",
}

-- Resolve a raw theme value (possibly a retired name) to a registered one, or
-- nil when it names nothing at all.
function M.resolve_theme(name)
	if name == nil then
		return nil
	end
	name = M.theme_aliases[name] or name
	return M.themes[name] and name or nil
end

-- Which background theme is active: "carbon" (default) or a key of M.themes.
-- Same flag convention as accent()/transparent(): vim.g.nvsinner_theme wins
-- over $NVSINNER_THEME; anything unknown → "carbon". The legacy binary
-- background flag (vim.g.nvsinner_background / $NVSINNER_BACKGROUND) is still
-- honored when no theme flag is set, so `NVSINNER_BACKGROUND=light nvsinner`
-- keeps booting the light palette (now named "carbon-light").
function M.theme()
	local t = M.resolve_theme(vim.g.nvsinner_theme or vim.env.NVSINNER_THEME)
	if t then
		return t
	end
	local bg = vim.g.nvsinner_background or vim.env.NVSINNER_BACKGROUND
	return bg == "light" and "carbon-light" or "carbon"
end

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

-- Roles for the active background theme (M.theme()), with the active accent
-- pack's overrides applied on top (packs are keyed by the theme's dark/light
-- variant; the default "blue" pack is empty, so each theme's own signature
-- accent shows). Consumers re-resolve this on every ColorScheme re-apply, so
-- switching the theme/accent + `:colorscheme carbon` restyles the whole UI.
function M.colors()
	local theme = M.themes[M.theme()]
	local base = M[theme.palette]
	local pack = M.accents[M.accent()][theme.variant]
	if next(pack) == nil then
		return base
	end
	return vim.tbl_extend("force", {}, base, pack)
end

-- ─── Feature flags ───────────────────────────────────────────────────────────
-- Read at startup by theme.lua and on every (re)apply by colors/carbon.lua and
-- ui-touch.lua. Three ways to set each flag (first match wins):
--   * vim.g (set by :NvSinnerMenu via lua/core/settings.lua, or by hand)
--   * environment: `NVSINNER_THEME=nord NVSINNER_TRANSPARENT=1
--     NVSINNER_ACCENT=green nvsinner` (per launch)
--   * the persisted defaults lua/core/settings.lua seeds vim.g with at boot
-- The vim.g value wins over the environment variable when both are set;
-- settings.lua only seeds vim.g when NEITHER is set, so env overrides survive.

-- Which vim.o.background variant the active theme belongs to: "dark" or
-- "light". theme.lua reads this at boot; settings.lua on every theme change.
function M.background()
	return M.themes[M.theme()].variant
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
