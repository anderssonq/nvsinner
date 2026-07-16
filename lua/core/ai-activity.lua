-- ─── AI / terminal activity indicator ──────────────────────────────────────
-- Shows whether a CLI agent (claude, kiro, opencode, …) — or any program in a
-- terminal — is actively working vs. idle. We attach to each terminal buffer
-- with nvim_buf_attach: its `on_lines` callback fires whenever output streams
-- in, so an agent that is thinking (animating its own spinner) or printing keeps
-- the buffer "busy"; when it finishes and waits at its prompt the callback goes
-- quiet and we flip back to "listo" after a short grace period.
--
-- on_lines is the reliable, CLI-agnostic signal: polling a terminal buffer's
-- changedtick is NOT dependable (Neovim doesn't materialise the buffer lines —
-- and so doesn't bump the tick — unless something is attached or it's rendered),
-- whereas an attached listener is always notified.
--
-- The per-buffer state is exposed as a winbar expression that `ui-touch.lua`
-- renders inside the terminal top bar it already draws. Busy state is drawn with
-- an inline accent chip (NvAiBusy) so it stays visible even when the terminal is
-- UNFOCUSED (the unfocused bar highlight, NvTermBarDim, is dim); idle inherits
-- that focus-aware bar highlight. Generic on purpose: the vertical AI columns AND
-- the horizontal <leader>t terminals light up (a long build shows "working…" too).

local M = {}

local uv = vim.uv or vim.loop

-- Tunables.
local POLL_MS = 120 -- spinner frame rate + idle-flip check cadence
local IDLE_MS = 1200 -- quiet time before "working" flips back to "idle"
local SPINNER = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local LABEL_BUSY = "working…"
local LABEL_IDLE = "idle"
local LABEL_AWAIT = "needs input"
local DOT_IDLE = "●"
local DOT_AWAIT = "◆"

-- The "working" chip's highlight, re-applied on ColorScheme so it survives a
-- colorscheme reload. Carbon pink (base12) chip with dark (base00) text — the
-- same dark-text-on-accent chip language as the statusline mode blocks — so it
-- reads in any focus state, including on the bright base11 focused bar.
local function apply_hl()
	local c = require("core.carbon").colors()
	vim.api.nvim_set_hl(0, "NvAiBusy", { fg = c.base00, bg = c.base12, bold = true })
	-- "Needs input" chip: base10 magenta — carbon's attention/modified accent —
	-- because a prompt waiting on the user IS the attention case.
	vim.api.nvim_set_hl(0, "NvAiAwait", { fg = c.base00, bg = c.base10, bold = true })
end
apply_hl()
vim.api.nvim_create_autocmd("ColorScheme", { pattern = "*", callback = apply_hl })

-- Per-terminal-buffer state, keyed by bufnr:
--   busy = currently producing output, last = uv.now() of the last on_lines,
--   attached = whether nvim_buf_attach is wired up for it.
local state = {}
local frame = 1

local function is_term(buf)
	return vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == "terminal"
end

-- Winbar expression: `ui-touch.lua` bakes the buffer number into the per-window
-- string (`winbar(<buf>)`), so we take it as an argument. We do NOT use
-- `vim.g.statusline_winid`: it is NOT populated while a *winbar* expression is
-- evaluated (verified — only for 'statusline'), which left this returning "".
-- Centered. Busy is wrapped in the NvAiBusy chip so it shows even on an unfocused
-- (dim) bar; idle is plain text and inherits the focus-aware WinBar highlight.
function M.winbar(buf)
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return ""
	end
	-- Optional per-terminal label (e.g. "AI · 3"), tagged on the buffer by
	-- toggleterm.lua; absent for plain `:terminal` buffers.
	local label = vim.b[buf].nv_term_label
	local prefix = (label and label ~= "") and (label .. " ") or ""
	local s = state[buf]
	if s and s.busy then
		return "%=%#NvAiBusy# " .. prefix .. SPINNER[frame] .. " " .. LABEL_BUSY .. " %*%="
	end
	if s and s.awaiting then
		return "%=%#NvAiAwait# " .. prefix .. DOT_AWAIT .. " " .. LABEL_AWAIT .. " %*%="
	end
	return "%=" .. prefix .. DOT_IDLE .. " " .. LABEL_IDLE .. "%="
end

-- Public cockpit API: coarse status of a tracked terminal buffer.
-- Returns "working" | "awaiting" | "idle", or nil for untracked buffers.
function M.status(buf)
	local s = buf and state[buf]
	if not s then
		return nil
	end
	if s.busy then
		return "working"
	end
	if s.awaiting then
		return "awaiting"
	end
	return "idle"
end

-- Busy-gating: the poll timer runs ONLY while at least one terminal is busy.
-- on_lines starts it with the first output chunk; tick() stops it once nothing
-- is busy anymore, right after the idle-flip's final redraw. Idle terminals
-- and an empty editor cost ZERO wakeups. M._ticking is the "loop is running"
-- flag (and the test seam pinning start/stop).
M._ticking = false
local ensure_ticking -- defined below tick(), which it schedules

-- Attach the output listener to a terminal buffer (idempotent).
local function attach(buf)
	if not is_term(buf) then
		return
	end
	if state[buf] and state[buf].attached then
		return
	end
	state[buf] = state[buf] or { busy = false, last = uv.now() }
	state[buf].attached = true
	vim.api.nvim_buf_attach(buf, false, {
		-- FAST event context: only the plain Lua table write, uv.now(), and
		-- uv timer ops here (all fast-context legal — the restriction is
		-- vim.api/vim.fn). The timer does the redraw.
		on_lines = function(_, b)
			local s = state[b]
			if s then
				-- Fresh output always trumps a stale "needs input" prompt mark.
				s.busy, s.last, s.awaiting = true, uv.now(), false
				ensure_ticking()
			end
		end,
		on_detach = function(_, b)
			state[b] = nil
		end,
	})
end

local function tick()
	-- Don't redraw while a command line is being typed — it's disruptive there.
	if vim.fn.mode() == "c" then
		return
	end
	frame = frame % #SPINNER + 1
	local now = uv.now()
	local any_busy, changed = false, false
	for buf, s in pairs(state) do
		if not vim.api.nvim_buf_is_valid(buf) then
			state[buf] = nil
		else
			if s.busy and (now - s.last) > IDLE_MS then
				s.busy, changed = false, true
			end
			any_busy = any_busy or s.busy
		end
	end
	-- Redraw winbars only while something animates (busy) or a state just
	-- flipped — keeps the spinner moving without burning redraws when idle.
	-- IMPORTANT: use nvim__redraw with winbar+flush, NOT `:redrawstatus`. When the
	-- focus is INSIDE a terminal (the usual case while watching an agent work)
	-- `:redrawstatus` does not repaint the winbar, so the spinner looked frozen /
	-- empty; nvim__redraw re-evaluates and flushes the winbar in that mode too.
	if any_busy or changed then
		if not pcall(vim.api.nvim__redraw, { statusline = true, winbar = true, flush = true }) then
			vim.cmd("redrawstatus!")
		end
	end
	-- Nothing busy → nothing animates and no idle-flip is pending: stop waking
	-- up. This runs AFTER the redraw above, so the idle-flip's final repaint
	-- always lands. The next output chunk restarts the loop from on_lines;
	-- "awaiting" needs no ticks (_on_osc repaints on its own).
	if not any_busy then
		M._timer:stop()
		M._ticking = false
	end
end

function ensure_ticking()
	if M._ticking then
		return
	end
	M._ticking = true
	M._timer:start(POLL_MS, POLL_MS, vim.schedule_wrap(tick))
end

-- ─── "Needs input" via OSC sequences (opportunistic) ────────────────────────
-- Programs that emit shell-integration prompt marks (OSC 133) or terminal
-- notifications (OSC 9 / OSC 777) tell us they are sitting at a prompt; we
-- surface that as a third state between working and idle. HONEST LIMITS: this
-- only lights up for emitters — OSC-133-integrated shells and CLIs that send
-- notification sequences. CLIs that emit nothing (unverified for claude) just
-- fall back to the 1.2s idle heuristic, which stays the primary signal.
-- Probed on NVIM 0.12.3 (2026-07): TermRequest's ev.data is a TABLE
-- { sequence = "\27]133;B" } (string on 0.11), and the callback is NOT a fast
-- event context — vim.* calls are safe there.
function M._on_osc(buf, seq)
	local s = state[buf]
	if not s or type(seq) ~= "string" then
		return
	end
	local mark = seq:match("133;([A-D])")
	if mark == "B" then
		-- Prompt-input start (fires AFTER the prompt is drawn, so the prompt's
		-- own rendering can't clobber it via on_lines) → wants the user.
		s.awaiting, s.busy = true, false
	elseif mark == "C" then
		-- Command execution started → no longer waiting on the user.
		s.awaiting = false
	elseif seq:match("^\27%]9;") or seq:match("^\27%]777;") then
		-- Terminal notification → treat as "wants attention / input".
		s.awaiting, s.busy = true, false
	else
		return
	end
	-- The tick() loop skips redraws while everything is idle, so repaint the
	-- winbar here (same nvim__redraw path — :redrawstatus misses winbars).
	if not pcall(vim.api.nvim__redraw, { statusline = true, winbar = true, flush = true }) then
		vim.cmd("redrawstatus!")
	end
end

-- Wire up terminals as they open (and any already alive, e.g. after :source).
vim.api.nvim_create_autocmd("TermOpen", {
	group = vim.api.nvim_create_augroup("nv_ai_activity", { clear = true }),
	callback = function(args)
		attach(args.buf)
	end,
})
vim.api.nvim_create_autocmd("TermRequest", {
	group = "nv_ai_activity",
	callback = function(args)
		-- Normalize the payload shape across 0.11 (string) / 0.12 (table).
		local seq = type(args.data) == "table" and args.data.sequence or args.data
		M._on_osc(args.buf, seq)
	end,
})
for _, buf in ipairs(vim.api.nvim_list_bufs()) do
	attach(buf)
end

-- Kept on M so the handle is never garbage-collected (an unreferenced active luv
-- timer can be reaped and silently stop animating). Deliberately NOT started
-- here: the loop is busy-gated — on_lines starts it with the first output
-- chunk, tick() stops it once nothing is busy (see ensure_ticking above).
M._timer = assert(uv.new_timer())

return M
