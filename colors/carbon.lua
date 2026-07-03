-- ─── carbon — oxocarbon / IBM Carbon colorscheme, self-contained port ───────
-- Ported from oxocarbon.nvim (Nyoom Engineering / Shaun Singh), inspired by
-- the IBM Carbon Design System. Roles come from lua/core/carbon.lua — the one
-- palette (and design doc) shared with the core modules and the UI chrome specs. Applied with
-- `:colorscheme carbon`; respects vim.o.background ("dark" is the reference
-- variant, "light" swaps the palette through the same code path).
--
-- Design discipline (see lua/core/carbon.lua): gray-dominant surfaces, base04 body text
-- (not white), italic base03 comments, syntax bg = NONE, floats recessed on
-- `blend`, accents used sparingly for meaning.

vim.cmd("highlight clear")
if vim.fn.exists("syntax_on") == 1 then
	vim.cmd("syntax reset")
end
vim.g.colors_name = "carbon"
vim.o.termguicolors = true

local carbon = require("core.carbon")
local c = carbon.colors()
local set = vim.api.nvim_set_hl

-- Transparent mode (vim.g.nvsinner_transparent / $NVSINNER_TRANSPARENT): drop
-- every full-surface background so the terminal shows through. Chips and bars
-- (mode block, busy chip, terminal focus bar, prompt panels) keep their solid
-- color for legibility. `edge` replaces the blend-on-blend "invisible" borders:
-- with no float surface a border needs a faint line to delimit the float.
local transparent = carbon.transparent()
local bg0 = transparent and c.none or c.base00 -- editor / panel surfaces
local bgf = transparent and c.none or c.blend -- float surfaces
local edge = transparent and c.base01 or c.blend -- float border lines
local folder = carbon.folder_colors() -- neo-tree folder pack (:NvSinnerMenu)
-- Single-role color slots (:NvSinnerMenu): nil = keep the stock roles below.
local notif = carbon.slot_color("notif")
local vars = carbon.slot_color("variables")
local strs = carbon.slot_color("strings")
local funcs = carbon.slot_color("functions")

local hl = {
	-- ── Core editor UI (§5.1) ────────────────────────────────────────────────
	Normal = { fg = c.base04, bg = bg0 },
	NormalNC = { fg = c.base04, bg = bg0 },
	NormalFloat = { fg = c.base05, bg = bgf },
	FloatBorder = { fg = edge, bg = bgf }, -- borderless, recessed look
	FloatTitle = { fg = c.base05, bg = bgf, bold = true },
	LineNr = { fg = c.base03, bg = bg0 },
	CursorLineNr = { fg = c.base04 },
	CursorLine = { bg = c.base01 },
	CursorColumn = { bg = c.base01 },
	ColorColumn = { bg = c.base01 },
	QuickFixLine = { bg = c.base01 },
	Cursor = { fg = c.base00, bg = c.base04 },
	TermCursor = { fg = c.base00, bg = c.base04 },
	Visual = { bg = c.base02 },
	VisualNOS = { bg = c.base02 },
	Pmenu = { fg = c.base04, bg = c.base01 },
	PmenuSel = { fg = c.base08, bg = c.base02 },
	PmenuSbar = { bg = c.base01 },
	PmenuThumb = { fg = c.base08, bg = c.base02 },
	Search = { fg = c.base01, bg = c.base08 },
	IncSearch = { fg = c.base06, bg = c.base10 },
	CurSearch = { fg = c.base01, bg = c.base11 },
	MatchParen = { bg = c.base02, underline = true },
	Folded = { fg = c.base02, bg = c.base01 },
	FoldColumn = { fg = c.base01, bg = bg0 },
	SignColumn = { fg = c.base01, bg = bg0 },
	WinSeparator = { fg = c.base01, bg = bg0 }, -- near-invisible split
	VertSplit = { link = "WinSeparator" },
	NonText = { fg = c.base02 },
	Whitespace = { fg = c.base02 },
	EndOfBuffer = { fg = c.base01, bg = bg0 },
	Directory = { fg = c.base08 },
	Title = { fg = c.base04 },
	WinBar = { fg = c.base04, bg = bg0 },
	WinBarNC = { fg = c.base03, bg = bg0 },
	ErrorMsg = { fg = c.base10 },
	WarningMsg = { fg = c.base14 },
	MoreMsg = { fg = c.base08 },
	Question = { fg = c.base09 },
	ModeMsg = { fg = c.base04 },
	SpellBad = { undercurl = true, sp = c.base10 },
	SpellCap = { undercurl = true, sp = c.base14 },
	SpellLocal = { undercurl = true, sp = c.base09 },
	SpellRare = { undercurl = true, sp = c.base15 },

	-- ── Syntax, classic groups (§5.2) — syntax bg stays NONE ─────────────────
	Comment = { fg = c.base03, italic = true },
	Constant = { fg = c.base04 },
	Identifier = { fg = vars or c.base04 },
	Special = { fg = c.base04 },
	Tag = { fg = c.base04 },
	Statement = { fg = c.base09 },
	Keyword = { fg = c.base09 },
	Conditional = { fg = c.base09 },
	Repeat = { fg = c.base09 },
	Operator = { fg = c.base09 },
	PreProc = { fg = c.base09 },
	Include = { fg = c.base09 },
	Define = { fg = c.base09 },
	Exception = { fg = c.base09 },
	StorageClass = { fg = c.base09 },
	Structure = { fg = c.base09 },
	Type = { fg = c.base09 },
	Typedef = { fg = c.base09 },
	Label = { fg = c.base09 },
	Boolean = { fg = c.base09 },
	Function = { fg = funcs or c.base08 },
	String = { fg = strs or c.base14 },
	Character = { fg = strs or c.base14 },
	Number = { fg = c.base15 },
	Float = { link = "Number" },
	Decorator = { fg = c.base12 },
	Delimiter = { fg = c.base06 },
	Todo = { fg = c.base13 },
	Debug = { fg = c.base13 },
	SpecialComment = { fg = c.base08 },
	Error = { fg = c.base10, bg = c.base01 },

	-- ── Treesitter captures (§5.3), incl. the modern @markup/@variable names ─
	-- The "Functions" slot paints the whole family in one accent when set;
	-- stock is a deliberate mix (base12 defs / base07 methods / base08 :h).
	["@function"] = { fg = funcs or c.base12, bold = true },
	["@function.builtin"] = { fg = funcs or c.base12 },
	["@function.macro"] = { fg = funcs or c.base07 },
	["@function.method"] = { fg = funcs or c.base07 },
	["@method"] = { fg = funcs or c.base07 },
	["@constant.builtin"] = { fg = c.base07 },
	["@constant.macro"] = { fg = c.base07 },
	["@namespace"] = { fg = c.base07 },
	["@module"] = { fg = c.base07 },
	["@constructor"] = { fg = c.base09 },
	["@keyword"] = { fg = c.base09 },
	["@conditional"] = { fg = c.base09 },
	["@keyword.conditional"] = { fg = c.base09 },
	["@repeat"] = { fg = c.base09 },
	["@keyword.repeat"] = { fg = c.base09 },
	["@include"] = { fg = c.base09 },
	["@keyword.import"] = { fg = c.base09 },
	["@tag"] = { fg = c.base09 },
	["@keyword.function"] = { fg = c.base08 },
	["@keyword.operator"] = { fg = c.base08 },
	["@punctuation.delimiter"] = { fg = c.base08 },
	["@punctuation.bracket"] = { fg = c.base08 },
	["@punctuation.special"] = { fg = c.base08 },
	["@string"] = { link = "String" },
	["@string.regex"] = { fg = c.base07 },
	["@string.regexp"] = { fg = c.base07 },
	["@string.escape"] = { fg = c.base15 },
	["@label"] = { fg = c.base15 },
	["@attribute"] = { fg = c.base15 },
	["@exception"] = { fg = c.base15 },
	["@keyword.exception"] = { fg = c.base15 },
	["@tag.attribute"] = { fg = c.base15 },
	["@tag.delimiter"] = { fg = c.base15 },
	["@constant"] = { fg = c.base14 },
	["@variable"] = { fg = vars or c.base04 },
	["@variable.builtin"] = { fg = vars or c.base04 },
	["@parameter"] = { fg = vars or c.base04 },
	["@variable.parameter"] = { fg = vars or c.base04 },
	["@field"] = { fg = vars or c.base04 },
	["@variable.member"] = { fg = vars or c.base04 },
	["@text"] = { fg = c.base04 },
	["@property"] = { fg = c.base10 },
	["@symbol"] = { fg = c.base15, bold = true },
	["@string.special.symbol"] = { fg = c.base15, bold = true },
	["@error"] = { fg = c.base11 },
	["@operator"] = { link = "Operator" },
	["@type"] = { link = "Type" },
	["@number"] = { link = "Number" },
	["@boolean"] = { fg = c.base09 },
	["@comment"] = { link = "Comment" },

	-- ── Diagnostics & health (§5.4) ──────────────────────────────────────────
	DiagnosticError = { fg = c.base10 },
	DiagnosticWarn = { fg = c.base14 },
	DiagnosticInfo = { fg = c.base09 },
	DiagnosticHint = { fg = c.base04 },
	DiagnosticOk = { fg = c.base13 },
	DiagnosticUnderlineError = { undercurl = true, sp = c.base10 },
	DiagnosticUnderlineWarn = { undercurl = true, sp = c.base14 },
	DiagnosticUnderlineInfo = { undercurl = true, sp = c.base09 },
	DiagnosticUnderlineHint = { undercurl = true, sp = c.base04 },
	["health.Success"] = { fg = c.base13 },
	healthSuccess = { fg = c.base13 },
	healthWarning = { fg = c.base14 },
	healthError = { fg = c.base10 },

	-- ── Diff / git (§5.5) — washes are the only hand-tuned hexes ─────────────
	DiffAdd = { bg = c.diff_add },
	DiffChange = { bg = c.diff_change },
	DiffText = { bg = c.diff_text },
	DiffDelete = { bg = c.diff_delete },
	DiffAdded = { fg = c.base07 },
	DiffChanged = { fg = c.base09 },
	DiffRemoved = { fg = c.base10 },
	diffAdded = { fg = c.base07 },
	diffChanged = { fg = c.base09 },
	diffRemoved = { fg = c.base10 },
	GitSignsAdd = { fg = c.base07 },
	GitSignsChange = { fg = c.base09 },
	GitSignsDelete = { fg = c.base10 },
	GitSignsCurrentLineBlame = { link = "Comment" },

	-- ── Markdown / prose (§5.6): headings are the loudest element ────────────
	markdownH1 = { fg = c.base10, bold = true },
	markdownH2 = { fg = c.base10, bold = true },
	markdownH3 = { fg = c.base10 },
	markdownH4 = { fg = c.base10 },
	markdownH5 = { fg = c.base10 },
	markdownH6 = { fg = c.base10 },
	markdownHeadingDelimiter = { fg = c.base10 },
	markdownRule = { fg = c.base10 },
	markdownUrl = { fg = c.base14, underline = true },
	markdownCode = { link = "String" },
	markdownCodeBlock = { link = "String" },
	markdownListMarker = { fg = c.base08 },
	markdownBlockquote = { fg = c.base08 },
	["@markup.heading"] = { fg = c.base10, bold = true },
	["@markup.link"] = { fg = c.base14, underline = true },
	["@markup.link.url"] = { fg = c.base14, underline = true },
	["@markup.link.label"] = { fg = c.base14 },
	["@markup.raw"] = { link = "String" },
	["@markup.raw.block"] = { link = "String" },
	["@markup.list"] = { fg = c.base08 },
	["@markup.quote"] = { fg = c.base08 },
	["@markup.italic"] = { italic = true },
	["@markup.strong"] = { bold = true },
	["@markup.strikethrough"] = { strikethrough = true },
	["@text.title"] = { fg = c.base10, bold = true },
	["@text.uri"] = { fg = c.base14, underline = true },
	["@text.literal"] = { link = "String" },

	-- ── Statusline mode blocks (§6.1): dark text on a solid accent chip ──────
	StatusLine = { fg = c.base04, bg = bg0 },
	StatusLineNC = { fg = c.base04, bg = c.base01 },
	StatusNormal = { fg = c.base00, bg = c.base15 },
	StatusInsert = { fg = c.base00, bg = c.base12 },
	StatusVisual = { fg = c.base00, bg = c.base14 },
	StatusReplace = { fg = c.base00, bg = c.base08 },
	StatusCommand = { fg = c.base00, bg = c.base13 },
	StatusTerminal = { fg = c.base00, bg = c.base11 },
	StatusLineDiagnosticWarn = { fg = c.base14, bg = c.base00, bold = true },
	StatusLineDiagnosticError = { fg = c.base10, bg = c.base00, bold = true },

	-- ── Telescope (§7): borderless + recessed; the prompt is a lighter panel ─
	TelescopeNormal = { fg = c.base04, bg = bgf },
	TelescopeBorder = { fg = edge, bg = bgf },
	TelescopeResultsNormal = { fg = c.base04, bg = bgf },
	TelescopeResultsTitle = { fg = edge, bg = bgf },
	TelescopePreviewNormal = { fg = c.base04, bg = bgf },
	TelescopePreviewBorder = { fg = edge, bg = bgf },
	TelescopePreviewTitle = { fg = c.base00, bg = c.base12, bold = true },
	TelescopePromptNormal = { fg = c.base05, bg = c.base02 },
	TelescopePromptBorder = { fg = c.base02, bg = c.base02 },
	TelescopePromptTitle = { fg = c.base00, bg = c.base11, bold = true },
	TelescopePromptPrefix = { fg = c.base09, bg = c.base02 },
	TelescopeSelection = { bg = c.base02 },
	TelescopeMatching = { fg = c.base08, bold = true, italic = true },

	-- ── nvim-cmp (§7): kind icons as dark-text-on-accent chips ───────────────
	CmpItemAbbr = { fg = c.base04 },
	CmpItemAbbrMatch = { fg = c.base05, bold = true },
	CmpItemAbbrMatchFuzzy = { fg = c.base05, bold = true },
	CmpItemMenu = { fg = c.base03 },
	CmpItemKindInterface = { fg = c.base01, bg = c.base08 },
	CmpItemKindColor = { fg = c.base01, bg = c.base08 },
	CmpItemKindText = { fg = c.base01, bg = c.base09 },
	CmpItemKindEnum = { fg = c.base01, bg = c.base09 },
	CmpItemKindKeyword = { fg = c.base01, bg = c.base09 },
	CmpItemKindConstant = { fg = c.base01, bg = c.base10 },
	CmpItemKindConstructor = { fg = c.base01, bg = c.base10 },
	CmpItemKindReference = { fg = c.base01, bg = c.base10 },
	CmpItemKindFunction = { fg = c.base01, bg = c.base11 },
	CmpItemKindStruct = { fg = c.base01, bg = c.base11 },
	CmpItemKindClass = { fg = c.base01, bg = c.base11 },
	CmpItemKindModule = { fg = c.base01, bg = c.base11 },
	CmpItemKindOperator = { fg = c.base01, bg = c.base11 },
	CmpItemKindField = { fg = c.base01, bg = c.base12 },
	CmpItemKindProperty = { fg = c.base01, bg = c.base12 },
	CmpItemKindEvent = { fg = c.base01, bg = c.base12 },
	CmpItemKindUnit = { fg = c.base01, bg = c.base13 },
	CmpItemKindSnippet = { fg = c.base01, bg = c.base13 },
	CmpItemKindFolder = { fg = c.base01, bg = c.base13 },
	CmpItemKindVariable = { fg = c.base01, bg = c.base14 },
	CmpItemKindFile = { fg = c.base01, bg = c.base14 },
	CmpItemKindMethod = { fg = c.base01, bg = c.base15 },
	CmpItemKindValue = { fg = c.base01, bg = c.base15 },
	CmpItemKindEnumMember = { fg = c.base01, bg = c.base15 },
	CmpItemKindTypeParameter = { fg = c.base01, bg = c.base07 },

	-- ── nvim-notify (§7): border/icon/title per level ────────────────────────
	NotifyERRORBorder = { fg = c.base08, bg = bgf },
	NotifyERRORIcon = { fg = c.base08 },
	NotifyERRORTitle = { fg = c.base08 },
	NotifyWARNBorder = { fg = c.base14, bg = bgf },
	NotifyWARNIcon = { fg = c.base14 },
	NotifyWARNTitle = { fg = c.base14 },
	-- The "Notif color" slot recolors everyday INFO toasts only; WARN/ERROR/
	-- DEBUG keep their semantic colors (warnings must stay warnings).
	NotifyINFOBorder = { fg = notif or c.base05, bg = bgf },
	NotifyINFOIcon = { fg = notif or c.base05 },
	NotifyINFOTitle = { fg = notif or c.base05 },
	NotifyDEBUGBorder = { fg = c.base13, bg = bgf },
	NotifyDEBUGIcon = { fg = c.base13 },
	NotifyDEBUGTitle = { fg = c.base13 },
	NotifyTRACEBorder = { fg = c.base13, bg = bgf },
	NotifyTRACEIcon = { fg = c.base13 },
	NotifyTRACETitle = { fg = c.base13 },
	NotifyBackground = { bg = bgf },

	-- ── Neo-tree (§7, NvimTree mapping carried over) ─────────────────────────
	NeoTreeNormal = { fg = c.base04, bg = bg0 },
	NeoTreeNormalNC = { fg = c.base04, bg = bg0 },
	-- Folder colors come from the "Folder color" pack (:NvSinnerMenu); the
	-- stock pack resolves to the old look (name base09 / icon base12).
	NeoTreeDirectoryName = { fg = folder.name },
	NeoTreeDirectoryIcon = { fg = folder.icon },
	NeoTreeRootName = { fg = c.base04, bold = true },
	NeoTreeFileName = { fg = c.base04 },
	NeoTreeIndentMarker = { fg = c.base02 },
	NeoTreeGitAdded = { fg = c.base07 },
	NeoTreeGitModified = { fg = c.base09 },
	NeoTreeGitDeleted = { fg = c.base10 },
	NeoTreeGitUntracked = { fg = c.base14 },
	NeoTreeWinSeparator = { fg = transparent and c.base01 or c.base00, bg = bg0 }, -- seamless panel

	-- ── which-key ────────────────────────────────────────────────────────────
	WhichKey = { fg = c.base08 },
	WhichKeyGroup = { fg = c.base09 },
	WhichKeyDesc = { fg = c.base04 },
	WhichKeySeparator = { fg = c.base03 },
	WhichKeyNormal = { bg = bgf },
}

for group, spec in pairs(hl) do
	set(0, group, spec)
end

-- Terminal ANSI palette (§2.3) so the built-in terminal matches the theme.
local t = {
	c.base01,
	c.base11,
	c.base14,
	c.base13,
	c.base09,
	c.base15,
	c.base08,
	c.base05,
	c.base03,
	c.base11,
	c.base14,
	c.base13,
	c.base09,
	c.base15,
	c.base07,
	c.base06,
}
for i, col in ipairs(t) do
	vim.g["terminal_color_" .. (i - 1)] = col
end
