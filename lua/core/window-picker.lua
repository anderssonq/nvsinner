-- ─── Window picker (native) ──────────────────────────────────────────────────
-- Replaces nvim-window-picker: each candidate window gets a small centered
-- letter chip (a non-focusable float on the carbon accent); pressing that
-- letter returns the window. The only consumer is neo-tree's
-- `open_with_window_picker` (`w` in the tree), which does
-- `pcall(require, "window-picker")` → `picker.pick_window({})` — so this
-- module registers itself in `package.preload["window-picker"]` and neo-tree
-- keeps working with no config change.
--
-- The preload shim defers to the REAL plugin when its files are on the rtp
-- (i.e. the `enabled = false` stub in lua/plugins/navigation/ was flipped
-- back on), so the one-line revert stays a one-line revert.

local M = {}

M.CHARS = "FJDKSLAHGUEIRWO" -- home-row-first pick letters
M.FT_IGNORE = { ["neo-tree"] = true, ["neo-tree-popup"] = true, notify = true, noice = true }
M.BT_IGNORE = { terminal = true, prompt = true, quickfix = true }

local function apply_hl()
	local c = require("core.carbon").colors()
	vim.api.nvim_set_hl(0, "NvWinPick", { fg = c.base00, bg = c.base09, bold = true })
end
apply_hl()
vim.api.nvim_create_autocmd("ColorScheme", { pattern = "*", callback = apply_hl })

-- Non-floating windows of the current tabpage a file could be opened in.
function M._candidates()
	local wins = {}
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		if vim.api.nvim_win_get_config(win).relative == "" then
			local buf = vim.api.nvim_win_get_buf(win)
			if not M.BT_IGNORE[vim.bo[buf].buftype] and not M.FT_IGNORE[vim.bo[buf].filetype] then
				wins[#wins + 1] = win
			end
		end
	end
	return wins
end

-- Test seam: specs stub this instead of synthesizing a keypress.
function M._getchar()
	return vim.fn.getcharstr()
end

--- The nvim-window-picker API surface neo-tree consumes.
---@return integer|nil win the picked window id, nil when aborted
function M.pick_window(_)
	local wins = M._candidates()
	if #wins == 0 then
		return nil
	end
	if #wins == 1 then
		return wins[1] -- nothing to disambiguate
	end

	local by_char, overlays = {}, {}
	for i, win in ipairs(wins) do
		if i > #M.CHARS then
			break
		end
		local ch = M.CHARS:sub(i, i)
		by_char[ch] = win
		local buf = vim.api.nvim_create_buf(false, true)
		vim.bo[buf].bufhidden = "wipe"
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "       ", "   " .. ch .. "   ", "       " })
		local w = math.max(1, vim.api.nvim_win_get_width(win))
		local h = math.max(1, vim.api.nvim_win_get_height(win))
		local float = vim.api.nvim_open_win(buf, false, {
			relative = "win",
			win = win,
			width = math.min(7, w),
			height = math.min(3, h),
			row = math.max(0, math.floor((h - 3) / 2)),
			col = math.max(0, math.floor((w - 7) / 2)),
			style = "minimal",
			focusable = false,
			zindex = 300,
		})
		vim.wo[float].winhighlight = "Normal:NvWinPick,NormalFloat:NvWinPick"
		overlays[#overlays + 1] = float
	end

	vim.cmd.redraw()
	local ok, ch = pcall(M._getchar)
	for _, float in ipairs(overlays) do
		pcall(vim.api.nvim_win_close, float, true)
	end
	if not ok or not ch then
		return nil
	end
	return by_char[ch:upper()]
end

-- neo-tree calls setup() nowhere, but keep the plugin's public shape whole.
function M.setup(_) end

-- Serve `require("window-picker")`. If the real plugin is back on the rtp
-- (stub re-enabled), hand over to it instead of shadowing it.
package.preload["window-picker"] = function()
	local real = vim.api.nvim_get_runtime_file("lua/window-picker/init.lua", false)[1]
	if real then
		return dofile(real)
	end
	return M
end

return M
