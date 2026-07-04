-- ─── AI edit highlights ─────────────────────────────────────────────────────
-- When the AI CLI in the terminal column rewrites an open file on disk (the
-- same external-write signal core/autoreload.lua uses for the 🤖 toast), the
-- lines it changed get a full-width background wash in the file pane —
-- gitsigns-style marks, but for "what the agent just did", tinted with the
-- user's accent (base09, follows the :NvSinnerMenu accent pack) blended into
-- the editor bg so it reads like a CursorLine that carries the accent hue.
--
-- Lifecycle: the marks appear on the silent autoread reload and survive while
-- you stay in the AI column reading the agent's summary; the moment you take
-- over the file — move the cursor in it or edit it — they clear. They are a
-- "what changed while I wasn't looking" cue, not a persistent diff (that's
-- <leader>gd / gitsigns).
--
-- How the changed lines are found: we keep a per-buffer snapshot of the last
-- content the USER blessed (first read, last save, last cleared mark set) and
-- vim.diff it against the reloaded buffer. Snapshotting on every BufReadPost
-- would break this — the autoread reload itself re-reads the buffer, and the
-- old content must still be around to diff against — so the snapshot is only
-- taken when we don't have one yet, on save, and after each mark/clear.

local M = {}

local ns = vim.api.nvim_create_namespace("nvsinner_ai_edits")
M._ns = ns -- test seam: specs read the extmarks in this namespace

-- Buffers larger than this are skipped (the snapshot is a full copy of the
-- buffer's lines; beyond this the cue isn't worth the memory/diff cost).
M.MAX_LINES = 20000

-- snapshots[buf] = array of lines as of the last user-blessed state.
local snapshots = {}
-- clear_groups[buf] = augroup id of the armed take-over autocmds.
local clear_groups = {}

-- Mix `fg` into `bg` at `alpha` (highlights have no real opacity, so the
-- "translucent" wash is computed: bg + (accent - bg) * alpha per channel).
local function mix(bg, fg, alpha)
	local function ch(i)
		local b = tonumber(bg:sub(i, i + 1), 16)
		local f = tonumber(fg:sub(i, i + 1), 16)
		return math.floor(b + (f - b) * alpha + 0.5)
	end
	return string.format("#%02x%02x%02x", ch(2), ch(4), ch(6))
end

-- CursorLine-style full-line wash in the USER'S accent (base09 follows the
-- :NvSinnerMenu accent pack), blended into the editor bg at low alpha so the
-- code text keeps its contrast — the same subtlety as the focused-line
-- CursorLine (base01), but carrying the accent hue. Re-applied on ColorScheme,
-- so an accent-pack switch retints the marks live. Roles only, never a raw hex.
local WASH_ALPHA = 0.18
local function apply_hl()
	local c = require("core.carbon").colors()
	vim.api.nvim_set_hl(0, "NvAiEdit", { bg = mix(c.base00, c.base09, WASH_ALPHA) })
end
apply_hl()
vim.api.nvim_create_autocmd("ColorScheme", { pattern = "*", callback = apply_hl })

local function eligible(buf)
	return vim.api.nvim_buf_is_valid(buf)
		and vim.bo[buf].buftype == ""
		and vim.api.nvim_buf_line_count(buf) <= M.MAX_LINES
end

local function snapshot(buf)
	if eligible(buf) then
		snapshots[buf] = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	end
end

-- Remove the marks and re-snapshot: from here on the buffer state is the
-- user's, so the next AI diff is relative to it.
function M.clear(buf)
	if not vim.api.nvim_buf_is_valid(buf) then
		snapshots[buf], clear_groups[buf] = nil, nil
		return
	end
	vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
	if clear_groups[buf] then
		pcall(vim.api.nvim_del_augroup_by_id, clear_groups[buf])
		clear_groups[buf] = nil
	end
	snapshot(buf)
end

-- Arm the take-over triggers: any cursor movement or edit IN the buffer wipes
-- the marks. Deferred one tick so the reload's own cursor restore can't clear
-- them in the same event burst that created them.
local function arm_clear(buf)
	vim.schedule(function()
		if not vim.api.nvim_buf_is_valid(buf) or clear_groups[buf] then
			return
		end
		local grp = vim.api.nvim_create_augroup("nv_ai_edits_clear_" .. buf, { clear = true })
		clear_groups[buf] = grp
		vim.api.nvim_create_autocmd({ "CursorMoved", "TextChanged", "TextChangedI", "InsertEnter" }, {
			group = grp,
			buffer = buf,
			callback = function()
				M.clear(buf)
			end,
		})
	end)
end

-- Diff the reloaded buffer against the snapshot and underline what changed.
-- Returns the number of lines marked (test seam). Deletion-only hunks have no
-- surviving line to underline and are skipped — the 🤖 toast still fires.
function M.mark(buf)
	if not eligible(buf) then
		return 0
	end
	local old = snapshots[buf]
	if not old then
		snapshot(buf) -- first sighting: nothing to diff against yet
		return 0
	end
	local new = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	local hunks = vim.diff(table.concat(old, "\n") .. "\n", table.concat(new, "\n") .. "\n", {
		result_type = "indices",
	})
	local marked = 0
	for _, h in ipairs(hunks or {}) do
		local start_new, count_new = h[3], h[4]
		for row = start_new - 1, start_new - 2 + count_new do
			-- line_hl_group: a full-width wash (like CursorLine), not just the text.
			vim.api.nvim_buf_set_extmark(buf, ns, row, 0, {
				line_hl_group = "NvAiEdit",
			})
			marked = marked + 1
		end
	end
	snapshots[buf] = new
	if marked > 0 then
		arm_clear(buf)
	end
	return marked
end

local grp = vim.api.nvim_create_augroup("nv_ai_edits", { clear = true })

-- First read of a file: baseline snapshot. Only when none exists — the
-- autoread reload also lands here on some paths and must NOT overwrite the
-- pre-reload content before mark() has diffed it.
vim.api.nvim_create_autocmd("BufReadPost", {
	group = grp,
	callback = function(args)
		if not snapshots[args.buf] then
			snapshot(args.buf)
		end
	end,
})

-- A save blesses the current content as the user's state.
vim.api.nvim_create_autocmd("BufWritePost", {
	group = grp,
	callback = function(args)
		snapshot(args.buf)
	end,
})

-- The external-write signal (same event the 🤖 toast uses: with autoread on
-- and the buffer unmodified, the silent reload fires only the Post event).
vim.api.nvim_create_autocmd("FileChangedShellPost", {
	group = grp,
	callback = function(args)
		M.mark(args.buf)
	end,
})

vim.api.nvim_create_autocmd("BufWipeout", {
	group = grp,
	callback = function(args)
		if clear_groups[args.buf] then
			pcall(vim.api.nvim_del_augroup_by_id, clear_groups[args.buf])
		end
		snapshots[args.buf], clear_groups[args.buf] = nil, nil
	end,
})

-- Baseline any files already open when the module loads (e.g. after :source).
for _, buf in ipairs(vim.api.nvim_list_bufs()) do
	if vim.api.nvim_buf_is_loaded(buf) and not snapshots[buf] then
		snapshot(buf)
	end
end

-- Test seam: drop all state between specs.
function M._reset()
	for buf in pairs(clear_groups) do
		pcall(vim.api.nvim_del_augroup_by_id, clear_groups[buf])
	end
	snapshots, clear_groups = {}, {}
end

return M
