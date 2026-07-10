-- ─── Modal backdrop — dim the editor behind the NvSinner modals ─────────────
-- attach(winid) opens a full-screen, non-focusable float one zindex layer
-- BELOW the given modal window, washed with NvMenuBackdrop (carbon `backdrop`
-- black) at BLEND, so everything behind the modal dims and the modal pops as
-- its own layer (the same trick lazy.nvim's UI uses). The backdrop follows
-- terminal resizes and tears itself down automatically when the modal window
-- closes — callers never manage it. Shared by menu / help / prompts /
-- symbols / ai-ask / ia.
--
-- The backdrop is also the modals' INTERACTION GUARD: while a modal is open
-- the editor behind it must not be reachable — the user closes the modal to
-- continue. Two mechanisms, both torn down with the backdrop:
--   * `mouse = true` on the backdrop float: with `focusable = false` alone,
--     mouse events PASS THROUGH a float to the window beneath (the config
--     field defaults to the focusable value), so clicks/scroll on the dimmed
--     area would still hit the editor. mouse = true makes the backdrop consume
--     them — clicking the dim does nothing; only the modal above reacts.
--   * A WinEnter focus trap: focus escaping to a NON-floating window
--     (<C-w>w, a plugin jumping windows, …) is bounced back to the modal on
--     the next tick. Floats are exempt on purpose — the modals layer
--     vim.ui.select/input pickers (telescope, noice) on top of themselves,
--     and every modal action that must land elsewhere closes the modal FIRST
--     (help.run, ia actions, symbols.run, prompts.edit), which deletes the
--     trap before the jump. The bounce is scheduled so a plugin's transient
--     window dance (toggleterm re-asserting the AI-column layout after an
--     ai_side change) finishes before focus is restored.

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
		mouse = true, -- consume clicks/scroll on the dim (see header) instead of passing through
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
	-- Focus trap: bounce focus that lands in a non-floating window back to the
	-- modal (see header for the float exemption + why the bounce is scheduled).
	vim.api.nvim_create_autocmd("WinEnter", {
		group = group,
		callback = function()
			if not vim.api.nvim_win_is_valid(winid) then
				return
			end
			local cur = vim.api.nvim_get_current_win()
			if cur == winid or not vim.api.nvim_win_is_valid(cur) then
				return
			end
			if vim.api.nvim_win_get_config(cur).relative ~= "" then
				return -- a float (vim.ui.select/input over the modal) may take focus
			end
			vim.schedule(function()
				if not vim.api.nvim_win_is_valid(winid) then
					return
				end
				local now = vim.api.nvim_get_current_win()
				if now == winid or not vim.api.nvim_win_is_valid(now) then
					return
				end
				if vim.api.nvim_win_get_config(now).relative ~= "" then
					return -- something legitimate (a picker) grabbed focus meanwhile
				end
				pcall(vim.api.nvim_set_current_win, winid)
			end)
		end,
	})
	return win
end

return M
