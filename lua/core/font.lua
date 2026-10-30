-- ─── Font family (the :NvSinnerMenu "Font" row) ──────────────────────────────
-- Switches the editor font between the two families NvSinner bundles in fonts/
-- ("FiraCode Nerd Font", "Maple Mono NF"); "terminal" (the default) means
-- NvSinner leaves the font alone and nothing is written or spawned.
--
--   * Ghostty ($TERM_PROGRAM == "ghostty" or $GHOSTTY_RESOURCES_DIR; both
--     survive a multiplexer like herdr): the family is written to ONE
--     NvSinner-owned file, <config home>/ghostty/nvsinner-font, then Ghostty's
--     `reload_config` action is triggered through an async `osascript`. The
--     user's own Ghostty config is NEVER edited: when it does not include the
--     file, a notice prints the exact `config-file = …` line to add. Ghostty
--     has no per-surface family, so the change applies to ALL Ghostty windows
--     (said in the notice).
--   * Neovide (vim.g.neovide): 'guifont', live.
--   * Any other terminal: one INFO notice, no process spawned.
--
-- Test seams (every process call and path goes through these, so specs never
-- touch the real Ghostty config or run osascript): M._run (async runner),
-- M._config_home / M._home (path bases), M._getenv, M._is_mac.

local M = {}

M.FAMILIES = { "terminal", "FiraCode Nerd Font", "Maple Mono NF" }

function M.valid(family)
	return vim.tbl_contains(M.FAMILIES, family)
end

-- Seam: async command runner. cb(ok, detail) is always called on the main loop.
function M._run(cmd, cb)
	local started, err = pcall(vim.system, cmd, { text = true }, function(res)
		vim.schedule(function()
			cb(res.code == 0, (res.stderr and res.stderr ~= "") and res.stderr or ("exit " .. tostring(res.code)))
		end)
	end)
	if not started then
		vim.schedule(function()
			cb(false, tostring(err))
		end)
	end
end

-- Seams: environment + path bases (nil → derived from the real environment).
M._getenv = function(name)
	local v = vim.env[name]
	return (v ~= nil and v ~= "") and v or nil
end
M._is_mac = function()
	return vim.fn.has("mac") == 1
end
M._home = nil
M._config_home = nil

local function home()
	return M._home or M._getenv("HOME") or vim.uv.os_homedir()
end

local function config_home()
	return M._config_home or M._getenv("XDG_CONFIG_HOME") or (home() .. "/.config")
end

-- The single file NvSinner ever writes for Ghostty.
function M.owned_file()
	return config_home() .. "/ghostty/nvsinner-font"
end

-- The line the user's Ghostty config needs. Absolute on purpose: a relative
-- `config-file` resolves against the INCLUDING file, and the config may live
-- in ~/Library/Application Support (macOS) rather than ~/.config/ghostty.
function M.include_line()
	return "config-file = ?" .. M.owned_file()
end

-- The Ghostty config files Ghostty itself reads, in precedence order.
local function ghostty_configs()
	local cfg = config_home() .. "/ghostty/"
	local mac = home() .. "/Library/Application Support/com.mitchellh.ghostty/"
	return { cfg .. "config.ghostty", cfg .. "config", mac .. "config.ghostty", mac .. "config" }
end

local function is_ghostty()
	return M._getenv("TERM_PROGRAM") == "ghostty" or M._getenv("GHOSTTY_RESOURCES_DIR") ~= nil
end

local function is_neovide()
	return vim.g.neovide ~= nil and vim.g.neovide ~= false
end

-- Resolve a `config-file` value the way Ghostty does: strip a leading `?`
-- (optional) and quotes, expand `~`, and resolve a relative path against the
-- INCLUDING file's directory.
local function resolve_include(value, including)
	local v = value:gsub('^"(.*)"$', "%1"):gsub("^%?", "")
	v = v:gsub('^"(.*)"$', "%1")
	if v:sub(1, 2) == "~/" then
		v = home() .. v:sub(2)
	elseif v:sub(1, 1) ~= "/" then
		v = vim.fn.fnamemodify(including, ":h") .. "/" .. v
	end
	return vim.fs.normalize(v)
end

-- Read-only: does any Ghostty config include the owned file? Returns
-- (included, first_existing_config_path_or_nil). Commented lines are ignored.
function M.includes_owned_file()
	local first
	local owned = vim.fs.normalize(M.owned_file())
	for _, path in ipairs(ghostty_configs()) do
		local fd = io.open(path, "r")
		if fd then
			first = first or path
			for line in fd:lines() do
				local value = line:match("^%s*config%-file%s*=%s*(.-)%s*$")
				if value and resolve_include(value, path) == owned then
					fd:close()
					return true, first
				end
			end
			fd:close()
		end
	end
	return false, first
end

-- Pure: the owned file's content. "terminal" → empty (Ghostty falls back to
-- its own config). The reset line makes the family REPLACE a user-set
-- `font-family` instead of being appended as a fallback.
function M.render(family)
	if family == "terminal" or family == nil then
		return ""
	end
	if not M.valid(family) then
		return nil
	end
	return string.format('font-family = ""\nfont-family = "%s"\n', family)
end

-- Pure: the AppleScript that asks Ghostty to reload its config.
local function reload_script()
	return 'tell application "Ghostty" to perform action "reload_config" on focused terminal of selected tab of front window'
end

local function notify(msg, level)
	vim.notify(msg, level or vim.log.levels.INFO, { title = "NvSinner · Font" })
end

local function write_owned(family)
	local content = M.render(family)
	if content == nil then
		return false, "unknown font family"
	end
	local path = M.owned_file()
	vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
	local fd, err = io.open(path, "w")
	if not fd then
		return false, err
	end
	fd:write(content)
	fd:close()
	return true
end

local function apply_ghostty(family)
	local ok, err = write_owned(family)
	if not ok then
		notify("Could not write " .. M.owned_file() .. ": " .. tostring(err), vim.log.levels.WARN)
		return
	end
	local included, cfg = M.includes_owned_file()
	if not included then
		notify(
			("Add this line to your Ghostty config%s, then reload it:\n  %s"):format(
				cfg and (" (" .. cfg .. ")") or "",
				M.include_line()
			),
			vim.log.levels.WARN
		)
		return
	end
	local label = family == "terminal" and "the terminal's own font" or family
	if not M._is_mac() then
		notify(label .. ": reload the Ghostty config to apply it (applies to all Ghostty windows).")
		return
	end
	M._run({ "osascript", "-e", reload_script() }, function(done, detail)
		if done then
			notify("Font: " .. label .. " (applies to all Ghostty windows).")
		else
			notify(
				"Saved, but Ghostty did not reload (" .. vim.trim(detail) .. "). Reload the config manually.",
				vim.log.levels.WARN
			)
		end
	end)
end

-- 'guifont' as it was before NvSinner first changed it (restored on "terminal").
M._orig_guifont = nil

local function neovide_font(family)
	-- Keep a size the user already set ("…:h14", "…:h13.5"); family only otherwise.
	local size = vim.o.guifont:match(":h(%d+%.?%d*)")
	local name = vim.fn.escape(family, " ,\\")
	return size and (name .. ":h" .. size) or name
end

local function set_neovide(family)
	if family == "terminal" then
		if M._orig_guifont ~= nil then
			vim.o.guifont = M._orig_guifont
			M._orig_guifont = nil
		end
		return
	end
	if M._orig_guifont == nil then
		M._orig_guifont = vim.o.guifont
	end
	vim.o.guifont = neovide_font(family)
end

-- Apply a family live (called by core/settings on every change).
function M.apply(family)
	if family ~= "terminal" and not M.valid(family) then
		notify("unknown font family " .. vim.inspect(family) .. "; nothing changed", vim.log.levels.WARN)
		return
	end
	if is_neovide() then
		set_neovide(family)
	elseif is_ghostty() then
		apply_ghostty(family)
	else
		notify("font settings apply to Ghostty and Neovide only")
	end
end

-- Startup: only Neovide needs re-applying (its guifont is not persisted). The
-- Ghostty file persists on disk on its own, so boot never spawns osascript.
function M.boot(family)
	if is_neovide() and family and family ~= "terminal" and M.valid(family) then
		set_neovide(family)
	end
end

return M
