-- ─── Persistent user settings ────────────────────────────────────────────────
-- The storage + apply layer behind :NvSinnerMenu (lua/core/menu.lua). One JSON
-- file under stdpath("data") holds the user's choices; this module loads it at
-- startup (required from init.lua right after core.options, so the theme flags
-- land BEFORE lazy.setup applies the colorscheme), exposes get/set, and knows
-- how to apply each setting live.
--
-- Precedence contract (documented in lua/core/carbon.lua): vim.g wins over the
-- environment. This module only SEEDS vim.g when neither vim.g nor the env var
-- is set, so `NVSINNER_BACKGROUND=light nvsinner` still overrides a persisted
-- choice for that launch.
--
-- Settings that other modules consume:
--   * background / transparent / accent → carbon flags (theme.lua, colors/carbon.lua)
--   * tree_side → neo-tree position (lua/plugins/navigation/neo-tree.lua)
--   * ai_side   → AI/vertical terminal column side (lua/plugins/terminal/toggleterm.lua)
--   * quiet     → mute info-level vim.notify toasts (warnings/errors still show)
-- Every M.set fires `User NvSinnerSetting` (data = { key, value }) so lazy
-- specs can react without requiring this module eagerly.

local M = {}

M.defaults = {
	background = "dark", -- "dark" | "light"
	transparent = false, -- drop full-surface backgrounds
	accent = "blue", -- key into require("core.carbon").accents
	tree_side = "left", -- neo-tree column: "left" | "right"
	ai_side = "right", -- AI / vertical terminal columns: "left" | "right"
	quiet = false, -- true → hide INFO/DEBUG notifications (WARN+ still show)
}

local file = vim.fn.stdpath("data") .. "/nvsinner-settings.json"
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
	vim.o.background = data.background
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
	background = function(v)
		vim.g.nvsinner_background = v
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
	seed_flag("nvsinner_background", "NVSINNER_BACKGROUND", data.background)
	seed_flag("nvsinner_transparent", "NVSINNER_TRANSPARENT", data.transparent)
	seed_flag("nvsinner_accent", "NVSINNER_ACCENT", data.accent)
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
