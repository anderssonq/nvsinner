-- ─── Copy on select ──────────────────────────────────────────────────────────
-- herdr-style mouse selection: sweep text with the mouse (drag, double-click a
-- word, triple-click a line) and it lands in the system clipboard the moment
-- the button is released — no `y`. The selection stays on screen, so a
-- keyboard operator can still act on it afterwards.
--
-- Observed, never mapped: the trigger is `vim.on_key`, not a <LeftRelease>
-- map. A global Visual-mode release map would sit under every buffer-local
-- <LeftRelease> map (prompts, symbols, agents, both explorers) and fight Vim's
-- own selection finalisation on the release (see the coupling note on
-- core.mouse.lock_selection). Watching the key stream leaves every existing
-- mouse behaviour byte-for-byte unchanged.
--
-- The gate is "a release that leaves Visual mode active". Verified with an
-- `--embed` child driven by nvim_input_mouse: a plain click releases in Normal
-- mode (it even ends an existing Visual selection), while a drag releases as
-- <LeftRelease> and a double/triple-click as <2-LeftRelease>/<3-LeftRelease>,
-- each with Visual already active. So no separate "did it drag" flag is
-- needed — a keyboard-made selection is never followed by a release.
--
-- The text is read with getregion() and written with setreg("+"), so no `y` is
-- fed (cursor and selection stay put) and it goes through 'clipboard' /
-- vim.g.clipboard — pbcopy locally, OSC 52 over SSH (core/options.lua).
-- Gated live on the `copy_on_select` setting (:NvSinnerMenu → "Copy on select").
-- Required from init.lua (core).

local M = {}

-- Every release that can end a mouse selection: a drag ends on the plain
-- release, multi-click selects on their counted variants (4 = blockwise).
local RELEASE = {}
for _, k in ipairs({ "<LeftRelease>", "<2-LeftRelease>", "<3-LeftRelease>", "<4-LeftRelease>" }) do
	RELEASE[vim.keycode(k)] = true
end

local VISUAL = { v = true, V = true, ["\22"] = true }

local function enabled()
	local ok, settings = pcall(require, "core.settings")
	return not ok or settings.get("copy_on_select") ~= false
end

--- Copy the active Visual selection to the + register. Returns the copied
--- lines, or nil when there was nothing to copy (not in Visual mode).
--- @return string[]|nil
function M.copy()
	local mode = vim.fn.mode()
	if not VISUAL[mode] then
		return nil
	end
	local ok, lines = pcall(vim.fn.getregion, vim.fn.getpos("v"), vim.fn.getpos("."), { type = mode })
	if not ok or #lines == 0 then
		return nil
	end
	local regtype = mode == "V" and "l" or mode == "v" and "c" or "b"
	if not pcall(vim.fn.setreg, "+", lines, regtype) then
		return nil
	end
	if #lines > 1 then
		vim.notify("📋 Copied " .. #lines .. " lines", vim.log.levels.INFO)
	else
		vim.notify("📋 Copied " .. vim.fn.strchars(lines[1]) .. " chars", vim.log.levels.INFO)
	end
	return lines
end

-- on_key runs BEFORE the key is processed; the schedule lands after Vim has
-- finalised the selection on the release.
local function on_key(key)
	if RELEASE[key] and enabled() then
		vim.schedule(M.copy)
	end
end

M.ns = vim.on_key(on_key, vim.api.nvim_create_namespace("nvsinner_copy_on_select"))

return M
