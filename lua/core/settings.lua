-- ─── Persistent user settings ────────────────────────────────────────────────
-- The storage + apply layer behind :NvSinnerMenu (lua/core/menu.lua). One JSON
-- file in the distro's settings/ folder (stdpath("config")/settings — next to
-- the :NvSinnerPrompts library, so all user-tweakable state sits in one place;
-- this cache is gitignored, prompts.json is committed) holds the user's
-- choices; this module loads it at startup (required from init.lua right after
-- core.options, so the theme flags land BEFORE lazy.setup applies the
-- colorscheme), exposes get/set, and knows how to apply each setting live.
-- A pre-settings/ cache under stdpath("data") is migrated on first load.
--
-- Precedence contract (documented in lua/core/carbon.lua): vim.g wins over the
-- environment. This module only SEEDS vim.g when neither vim.g nor the env var
-- is set, so `NVSINNER_THEME=fjord nvsinner` still overrides a persisted
-- choice for that launch.
--
-- Settings that other modules consume:
--   * theme / transparent / accent / folder / notif / variables /
--     strings / functions → carbon flags (theme.lua, colors/carbon.lua)
--   * tree_side → neo-tree position (lua/plugins/navigation/neo-tree.lua)
--   * ai_side   → AI/vertical terminal column side (lua/plugins/terminal/toggleterm.lua)
--   * ai_complete → inline AI completion on/off (lua/core/ai-complete.lua)
--   * ai_model   → inline-completion model (lua/core/ai-complete.lua; :NvSinnerIA)
--   * quiet     → mute info-level vim.notify toasts (warnings/errors still show)
-- Every M.set fires `User NvSinnerSetting` (data = { key, value }) so lazy
-- specs can react without requiring this module eagerly.

local M = {}

M.defaults = {
	theme = "carbon", -- background theme: key into require("core.carbon").themes
	transparent = false, -- drop full-surface backgrounds
	accent = "blue", -- key into require("core.carbon").accents
	folder = "accent", -- neo-tree folder color: key into require("core.carbon").folders
	notif = "default", -- info-toast accent: "default" | key into carbon.slot_choices
	variables = "default", -- syntax variables/params/fields accent (same choices)
	strings = "default", -- syntax strings accent (same choices)
	functions = "default", -- syntax functions/methods accent (same choices)
	tree_side = "left", -- neo-tree column: "left" | "right"
	ai_side = "right", -- AI / vertical terminal columns: "left" | "right"
	ai_complete = true, -- inline AI completion (ghost text) on/off; no-ops without $OPENCODE_API_KEY
	ai_model = "minimax-m2.5", -- inline-completion model (:NvSinnerIA picker; fastest verified OpenCode Zen id); $OPENCODE_MODEL still overrides
	quiet = false, -- true → hide INFO/DEBUG notifications (WARN+ still show)
}

local legacy_file = vim.fn.stdpath("data") .. "/nvsinner-settings.json" -- pre-settings/ location
local file = vim.fn.stdpath("config") .. "/settings/nvsinner-settings.json"
local data = vim.deepcopy(M.defaults)

-- ─── Persistence ─────────────────────────────────────────────────────────────

-- Load the JSON file (missing/corrupt → defaults). `opts.file` is a test seam
-- (mirrors update.lua's { dir = … } and health.lua's { marker = … }).
function M.load(opts)
	if opts and opts.file then
		file = opts.file
	end
	data = vim.deepcopy(M.defaults)
	local fd = io.open(file, "r")
	local migrating = false
	if not fd and not (opts and opts.file) then
		-- One-time migration: fall back to the old stdpath("data") cache and
		-- re-save it into settings/ below (never when a test seam is in play).
		fd = io.open(legacy_file, "r")
		migrating = fd ~= nil
	end
	if not fd then
		return data
	end
	local raw = fd:read("*a")
	fd:close()
	local ok, decoded = pcall(vim.json.decode, raw)
	if ok and type(decoded) == "table" then
		for k in pairs(M.defaults) do
			if decoded[k] ~= nil then
				data[k] = decoded[k]
			end
		end
		-- Migration: the pre-themes "background" ("dark"|"light") key becomes
		-- the equivalent named theme; the stale key drops on the next save.
		if decoded.theme == nil and decoded.background ~= nil then
			data.theme = (decoded.background == "light") and "moon" or "carbon"
		end
	end
	if migrating then
		M.save()
	end
	return data
end

function M.save()
	vim.fn.mkdir(vim.fn.fnamemodify(file, ":h"), "p")
	local fd = io.open(file, "w")
	if not fd then
		return false
	end
	fd:write(vim.json.encode(data))
	fd:close()
	return true
end

function M.get(key)
	return data[key]
end

-- ─── Appliers ────────────────────────────────────────────────────────────────

-- Re-apply the colorscheme so colors/carbon.lua + every ColorScheme-hooked
-- consumer (ui-touch, ai-activity, chrome specs) re-resolve the carbon roles.
local function reapply_theme()
	vim.o.background = require("core.carbon").background()
	pcall(vim.cmd.colorscheme, "carbon")
end

-- Mute or restore vim.notify. Installed lazily (User VeryLazy) so it wraps
-- whatever ends up being the live notify — noice replaces vim.notify when it
-- loads, and wrapping earlier would be clobbered. WARN and ERROR always pass.
local wrapped_inner = nil
function M.apply_quiet()
	if data.quiet and not wrapped_inner then
		wrapped_inner = vim.notify
		vim.notify = function(msg, level, o)
			if (level or vim.log.levels.INFO) >= vim.log.levels.WARN then
				return wrapped_inner(msg, level, o)
			end
		end
	elseif not data.quiet and wrapped_inner then
		vim.notify = wrapped_inner
		wrapped_inner = nil
	end
end

local apply = {
	theme = function(v)
		vim.g.nvsinner_theme = v
		reapply_theme()
	end,
	transparent = function(v)
		vim.g.nvsinner_transparent = v
		reapply_theme()
	end,
	accent = function(v)
		vim.g.nvsinner_accent = v
		reapply_theme()
	end,
	folder = function(v)
		vim.g.nvsinner_folder = v
		reapply_theme()
	end,
	notif = function(v)
		vim.g.nvsinner_notif = v
		reapply_theme()
	end,
	variables = function(v)
		vim.g.nvsinner_variables = v
		reapply_theme()
	end,
	strings = function(v)
		vim.g.nvsinner_strings = v
		reapply_theme()
	end,
	functions = function(v)
		vim.g.nvsinner_functions = v
		reapply_theme()
	end,
	quiet = function()
		M.apply_quiet()
	end,
	tree_side = function()
		-- The <leader>e keymap reads the side on every open; just close a tree
		-- that is already showing on the old side.
		if package.loaded["neo-tree"] then
			pcall(vim.cmd, "Neotree close")
		end
	end,
	ai_side = function() end, -- toggleterm listens on User NvSinnerSetting
	ai_complete = function(v)
		pcall(function()
			require("core.ai-complete").set_enabled(v)
		end)
	end,
	ai_model = function() end, -- read at request time by ai-complete.M.model(); nothing to apply live
}

-- Set + persist + apply live + broadcast.
function M.set(key, value)
	if M.defaults[key] == nil then
		return
	end
	data[key] = value
	M.save()
	apply[key](value)
	vim.api.nvim_exec_autocmds("User", {
		pattern = "NvSinnerSetting",
		data = { key = key, value = value },
	})
end

-- ─── Startup ─────────────────────────────────────────────────────────────────

-- Seed the carbon vim.g flags from the persisted values — but only when the
-- flag is not already set by the user (vim.g) or the launch environment, so
-- the documented precedence (vim.g > env > persisted) holds.
local function seed_flag(g, env, value)
	if vim.g[g] == nil and vim.env[env] == nil then
		vim.g[g] = value
	end
end

function M.setup(opts)
	M.load(opts)
	-- The legacy NVSINNER_BACKGROUND env var still overrides (carbon.theme()
	-- falls back to it when the theme flag is unset), so don't seed over it.
	if vim.env.NVSINNER_BACKGROUND == nil then
		seed_flag("nvsinner_theme", "NVSINNER_THEME", data.theme)
	end
	seed_flag("nvsinner_transparent", "NVSINNER_TRANSPARENT", data.transparent)
	seed_flag("nvsinner_accent", "NVSINNER_ACCENT", data.accent)
	seed_flag("nvsinner_folder", "NVSINNER_FOLDER", data.folder)
	seed_flag("nvsinner_notif", "NVSINNER_NOTIF", data.notif)
	seed_flag("nvsinner_variables", "NVSINNER_VARIABLES", data.variables)
	seed_flag("nvsinner_strings", "NVSINNER_STRINGS", data.strings)
	seed_flag("nvsinner_functions", "NVSINNER_FUNCTIONS", data.functions)
	-- Defer the notify wrap until noice/notify have installed their handlers.
	vim.api.nvim_create_autocmd("User", {
		pattern = "VeryLazy",
		once = true,
		group = vim.api.nvim_create_augroup("nv_settings_quiet", { clear = true }),
		callback = function()
			M.apply_quiet()
		end,
	})
end

M.setup()

return M
