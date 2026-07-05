-- ─── Modal backdrop — dim the editor behind the NvSinner modals ─────────────
-- attach(winid) opens a full-screen, non-focusable float one zindex layer
-- BELOW the given modal window, washed with NvMenuBackdrop (carbon `backdrop`
-- black) at BLEND, so everything behind the modal dims and the modal pops as
-- its own layer (the same trick lazy.nvim's UI uses). The backdrop follows
-- terminal resizes and tears itself down automatically when the modal window
-- closes — callers never manage it. Shared by menu / help / prompts /
-- symbols / ai-ask.

local M = {}

local BLEND = 60 -- 0 = solid black wall, 100 = invisible

local function apply_hl()
	local c = require("core.carbon").colors()
	vim.api.nvim_set_hl(0, "NvMenuBackdrop", { bg = c.backdrop })
end
apply_hl()
vim.api.nvim_create_autocmd("ColorScheme", {
	group = vim.api.nvim_create_augroup("nv_backdrop_hl", { clear = true }),
	pattern = "*",
	callback = apply_hl,
})

-- Open a backdrop under `winid`; returns the backdrop window (test seam).
function M.attach(winid)
	if not (winid and vim.api.nvim_win_is_valid(winid)) then
		return nil
	end
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	local zindex = math.max(1, (vim.api.nvim_win_get_config(winid).zindex or 50) - 10)
	local win = vim.api.nvim_open_win(buf, false, {
		relative = "editor",
		row = 0,
		col = 0,
		width = vim.o.columns,
		height = vim.o.lines,
		style = "minimal",
		focusable = false,
		zindex = zindex,
		border = "none",
	})
	vim.wo[win].winhighlight = "Normal:NvMenuBackdrop"
	vim.wo[win].winblend = BLEND

	local group = vim.api.nvim_create_augroup("nv_backdrop_" .. win, { clear = true })
	vim.api.nvim_create_autocmd("WinClosed", {
		group = group,
		pattern = tostring(winid),
		once = true,
		callback = function()
			pcall(vim.api.nvim_del_augroup_by_id, group)
			if vim.api.nvim_win_is_valid(win) then
				pcall(vim.api.nvim_win_close, win, true)
			end
		end,
	})
	vim.api.nvim_create_autocmd("VimResized", {
		group = group,
		callback = function()
			if vim.api.nvim_win_is_valid(win) then
				pcall(vim.api.nvim_win_set_config, win, { width = vim.o.columns, height = vim.o.lines })
			end
		end,
	})
	return win
end

return M
