return {
	"akinsho/toggleterm.nvim",
	version = "*",
	-- Eager ON PURPOSE (a documented exception to the lazy-load convention):
	-- the <leader>t*/<leader>j*/<M-J>/<D-M-j> keymaps are defined inside
	-- config() as closures over the memoised panel tables, so the plugin must
	-- load at startup for those maps to exist at all. Moving them to a `keys`
	-- spec would mean restructuring the panel memoisation — do that if this
	-- ever shows up in startup profiles.
	lazy = false,
	config = function()
		require("toggleterm").setup({
			-- Global default for the <leader>t terminals: ALWAYS horizontal (bottom).
			direction = "horizontal",
			size = function()
				return math.floor(vim.o.lines * 0.20)
			end,
		})
		local opts = {}
		local Terminal = require("toggleterm.terminal").Terminal

		-- ─── Shared layout ─────────────────────────────────────────────────────
		-- Two kinds of panels coexist: horizontal terminals at the bottom and AI
		-- columns on the right. toggleterm's open_split places a NEW terminal
		-- *beside* whatever toggleterm window is already open, so the final layout
		-- otherwise depends on the order panels were opened (a horizontal terminal
		-- opened while an AI column is up gets a "rightbelow vsplit" — a vertical
		-- split next to the column — see split_commands.horizontal.existing in
		-- toggleterm/ui.lua, while the reverse order leaves the column full-height).
		-- `restore_layout()` makes the result deterministic regardless of order:
		-- every horizontal terminal is forced to the bottom (`wincmd J`), then
		-- every AI column is forced to a full-height side column (`wincmd L`/`H`,
		-- side from the persisted `ai_side` setting — :NvSinnerMenu) LAST, so the
		-- columns always win their edge and the horizontals tuck into the bottom.
		-- Each panel keeps its own size, so the two never collide and the margins
		-- stay put (AI columns AI_WIDTH wide, horizontals 20% of the screen tall).
		local AI_WIDTH = 50
		local function ai_side()
			return require("core.settings").get("ai_side") == "left" and "left" or "right"
		end
		local function h_height()
			return math.floor(vim.o.lines * 0.20)
		end
		local h_panels = {}
		local ai_panels = {}
		local function restore_layout()
			for _, t in pairs(h_panels) do
				if t:is_open() then
					vim.api.nvim_set_current_win(t.window)
					vim.cmd("wincmd J")
					vim.cmd("resize " .. h_height())
				end
			end
			for _, t in pairs(ai_panels) do
				if t:is_open() then
					vim.api.nvim_set_current_win(t.window)
					vim.cmd(ai_side() == "left" and "wincmd H" or "wincmd L")
					vim.cmd("vertical resize " .. AI_WIDTH)
				end
			end
		end
		-- Re-assert the layout after any panel opens, then hand focus + insert
		-- mode back to the panel that was just opened.
		local function on_panel_open(term)
			restore_layout()
			-- Tag the terminal buffer with a winbar label read by
			-- core/ai-activity.lua (e.g. "AI · 3 ⠹ working…"). AI panels use the
			-- reserved ids 100+ (session = id - 99); the <leader>t terminals use 1–9.
			local buf = term.bufnr or vim.api.nvim_get_current_buf()
			if buf and vim.api.nvim_buf_is_valid(buf) then
				local id = term.id or 0
				-- __nv_label overrides the id-derived label: an AI column opened as a
				-- plain terminal (CLI picker → "plain terminal") is titled "term",
				-- like the horizontals, instead of "AI · N".
				vim.b[buf].nv_term_label = term.__nv_label or (id >= 100 and ("AI · " .. (id - 99)) or ("term " .. id))
			end
			-- Bump the session's MRU stamp so the send-to-AI bridge targets the
			-- panel the user opened last (AI ids are 100+; session = id - 99).
			if (term.id or 0) >= 100 then
				require("core.ai-sessions").touch(term.id - 99)
			end
			if term.window and vim.api.nvim_win_is_valid(term.window) then
				vim.api.nvim_set_current_win(term.window)
			end
			vim.cmd("startinsert!")
		end

		-- ─── Horizontal terminals (bottom) ───
		-- Custom Terminal objects (created lazily and memoised by number) so they
		-- run on_panel_open; without it a <leader>t terminal opened over an AI
		-- column would land as a vertical split next to it (see above).
		local function get_h_panel(n)
			if not h_panels[n] then
				h_panels[n] = Terminal:new({
					id = n, -- low ids 1–9 (AI panels reserve 100+; no collision)
					direction = "horizontal",
					size = h_height,
					on_open = on_panel_open,
				})
			end
			return h_panels[n]
		end

		-- <leader>t opens/hides horizontal terminal 1 (bottom). (Moved off <C-t>
		-- to <leader>t to avoid the Ctrl+T conflict.)
		vim.keymap.set("n", "<leader>t", function()
			get_h_panel(1):toggle()
		end, { desc = "Horizontal terminal 1" })
		-- <leader>t2 .. <leader>t9 -> additional independent horizontal terminals.
		-- (<leader>t is a prefix of <leader>t2.., so a bare <leader>t waits one
		-- 'timeoutlen' — which-key shows the menu — before falling back to
		-- terminal 1. Press a digit right after <leader>t to jump straight to it.)
		for n = 2, 9 do
			vim.keymap.set("n", "<leader>t" .. n, function()
				get_h_panel(n):toggle()
			end, { desc = "Horizontal terminal " .. n })
		end
		vim.keymap.set("t", "<esc>", [[<C-\><C-n>]], opts)
		vim.keymap.set("t", "jk", [[<C-\><C-n>]], opts)
		vim.keymap.set("t", "<C-h>", [[<Cmd>wincmd h<CR>]], opts)
		vim.keymap.set("t", "<C-j>", [[<Cmd>wincmd j<CR>]], opts)
		vim.keymap.set("t", "<C-k>", [[<Cmd>wincmd k<CR>]], opts)
		vim.keymap.set("t", "<C-l>", [[<Cmd>wincmd l<CR>]], opts)
		vim.keymap.set("t", "<C-w>", [[<C-\><C-n><C-w>]], opts)

		-- ─── AI terminal panels (multiple Cursor-style columns on the right) ───
		-- Several persistent AI sessions, each its own vertical column on the
		-- right, to run any AI CLI (claude, opencode, ollama, …). Toggling HIDES
		-- a session without killing its process: the CLI stays alive underneath.
		--
		--   <leader>j         -> toggle AI session 1 (the default)
		--   <leader>j2 .. j9  -> toggle AI sessions 2..9 (each independent)
		--
		-- <leader>j is also a prefix of <leader>j2.., so a bare <leader>j waits
		-- one 'timeoutlen' (which-key shows the menu) before falling back to
		-- session 1. Press a digit right after <leader>j to jump straight to it.
		-- (Terminal, ai_panels and on_panel_open are declared near the top, with
		-- the shared layout helpers.)

		-- Panels are created lazily and memoised by session number, so a session
		-- only spawns its process the first time it is opened — and the FIRST open
		-- asks (in the column's own space) which CLI to run, via the picker below.
		local function create_ai_panel(n, choice)
			ai_panels[n] = Terminal:new({
				-- Reserved ids (100+) so they never collide with the <leader>t
				-- horizontal terminals, which use the low ids 1–9. Session 1
				-- keeps its historical id 100; session N gets 99 + N.
				id = 99 + n,
				cmd = choice and choice.cmd or nil, -- nil → the default shell
				direction = "vertical", -- splitright is on -> opens on the right
				size = AI_WIDTH, -- fixed column width (not percentual): a compact AI column
				hidden = true, -- "custom" terminal: not part of the <leader>t list
				close_on_exit = false, -- if the CLI/shell dies, don't auto-close
				-- on_panel_open forces the column full-height on the configured
				-- side and re-tucks any horizontal terminal bottom-left.
				on_open = on_panel_open,
				-- Drop the session from the bridge registry when its CLI dies.
				on_exit = function()
					require("core.ai-sessions").unregister(n)
				end,
			})
			-- Winbar title: plain-terminal sessions read "term" (like the
			-- horizontals); CLI sessions keep the "AI · N" identity.
			ai_panels[n].__nv_label = (choice and choice.plain) and "term" or nil
			-- Register with the core session registry (send-to-AI bridge +
			-- cockpit). Plain-terminal sessions register too: piping text into
			-- a shell is just as useful.
			require("core.ai-sessions").register(n, ai_panels[n])
			return ai_panels[n]
		end

		-- ─── First-open CLI picker ─────────────────────────────────────────────
		-- Shown in the same space the column will occupy: a full-height side
		-- split listing the known AI CLIs plus "plain terminal — no AI". Keyboard
		-- (j/k move, <CR> launch, 1-4 jump, q/<Esc> cancel) and mouse (click a
		-- row to launch it). Styled with the NvMenu* carbon groups defined by
		-- lua/core/menu.lua so the picker and :NvSinnerMenu read as one component.
		local AI_CLIS = { "claude", "kiro-cli", "opencode" }
		local picker_ns = vim.api.nvim_create_namespace("nvsinner_ai_picker")

		local function pick_ai_cmd(n, on_choice)
			local entries = {}
			for _, cli in ipairs(AI_CLIS) do
				table.insert(entries, { cmd = cli, name = cli, ok = vim.fn.executable(cli) == 1 })
			end
			table.insert(entries, { cmd = nil, name = "plain terminal — no AI", ok = true, plain = true })

			vim.cmd(ai_side() == "left" and "topleft vsplit" or "botright vsplit")
			local win = vim.api.nvim_get_current_win()
			vim.api.nvim_win_set_width(win, AI_WIDTH)
			local buf = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_win_set_buf(win, buf)
			vim.bo[buf].buftype = "nofile" -- also keeps ui-touch's focus styling away
			vim.bo[buf].bufhidden = "wipe"
			vim.bo[buf].filetype = "nvsinner-picker"
			vim.wo[win].winhighlight = "Normal:NormalFloat"
			vim.wo[win].number = false
			vim.wo[win].relativenumber = false
			vim.wo[win].signcolumn = "no"

			local sel = 1
			local TOP = 2 -- blank + title line above the first entry
			local function render()
				local lines, spans = { "", ("  AI · %d — launch:"):format(n), "" }, {}
				for i, e in ipairs(entries) do
					local head = string.format(" %s %d  ", (i == sel) and "▸" or " ", i)
					local note = e.ok and "" or "  (not installed)"
					spans[i] = { head = #head, name = #head + #e.name, total = #head + #e.name + #note }
					table.insert(lines, head .. e.name .. note)
				end
				table.insert(lines, "")
				table.insert(lines, "  j/k move · ⏎ launch · 1-4 jump · q cancel")
				vim.bo[buf].modifiable = true
				vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
				vim.bo[buf].modifiable = false
				vim.api.nvim_buf_clear_namespace(buf, picker_ns, 0, -1)
				local ext = vim.api.nvim_buf_set_extmark
				ext(buf, picker_ns, 1, 0, { end_col = #lines[2], hl_group = "NvMenuLabel" })
				for i in ipairs(entries) do
					local row = TOP + i -- 0-based row of entry i (line TOP+1+i, -1)
					local s = spans[i]
					ext(buf, picker_ns, row, 0, { end_col = s.head, hl_group = "NvMenuKey" })
					ext(buf, picker_ns, row, s.head, {
						end_col = s.name,
						hl_group = entries[i].ok and "NvMenuValue" or "NvMenuMuted",
					})
					if s.total > s.name then
						ext(buf, picker_ns, row, s.name, { end_col = s.total, hl_group = "NvMenuMuted" })
					end
					if i == sel then
						ext(buf, picker_ns, row, 0, { line_hl_group = "NvMenuSel" })
					end
				end
				ext(buf, picker_ns, #lines - 1, 0, { end_col = #lines[#lines], hl_group = "NvMenuMuted" })
				if vim.api.nvim_win_is_valid(win) then
					vim.api.nvim_win_set_cursor(win, { TOP + 1 + sel, 1 })
				end
			end

			local function cancel()
				if vim.api.nvim_win_is_valid(win) then
					pcall(vim.api.nvim_win_close, win, true)
				end
			end
			local function choose(i)
				local e = entries[i or sel]
				if not e then
					return
				end
				if not e.ok then
					vim.notify(e.name .. " is not on PATH — install it or pick another option", vim.log.levels.WARN)
					return
				end
				cancel()
				on_choice(e)
			end

			local function map(lhs, rhs)
				vim.keymap.set("n", lhs, rhs, { buffer = buf, nowait = true, silent = true })
			end
			local function move(d)
				sel = math.min(#entries, math.max(1, sel + d))
				render()
			end
			map("j", function()
				move(1)
			end)
			map("k", function()
				move(-1)
			end)
			map("<Down>", function()
				move(1)
			end)
			map("<Up>", function()
				move(-1)
			end)
			map("<CR>", choose)
			map("l", choose)
			for i = 1, #entries do
				map(tostring(i), function()
					sel = i
					render()
				end)
			end
			map("<LeftRelease>", function()
				local mp = vim.fn.getmousepos()
				if mp.winid == win then
					local i = mp.line - (TOP + 1)
					if i >= 1 and i <= #entries then
						sel = i
						choose(i)
					end
				end
			end)
			-- Hover: move the selection onto the row under the pointer (same
			-- feel as the dashboard menu and :NvSinnerMenu).
			local hover_line = -1
			map("<MouseMove>", function()
				local mp = vim.fn.getmousepos()
				if mp.winid ~= win or mp.line == hover_line then
					return
				end
				hover_line = mp.line
				local i = mp.line - (TOP + 1)
				if i >= 1 and i <= #entries and i ~= sel then
					sel = i
					render()
				end
			end)
			map("q", cancel)
			map("<Esc>", cancel)

			render()
		end

		local function toggle_ai_panel(n)
			n = n or 1
			if ai_panels[n] then
				ai_panels[n]:toggle()
				return
			end
			pick_ai_cmd(n, function(choice)
				create_ai_panel(n, choice):toggle()
			end)
		end

		-- Re-assert the column side live when it changes in :NvSinnerMenu.
		vim.api.nvim_create_autocmd("User", {
			pattern = "NvSinnerSetting",
			group = vim.api.nvim_create_augroup("nv_toggleterm_settings", { clear = true }),
			callback = function(ev)
				if ev.data and ev.data.key == "ai_side" then
					local cur = vim.api.nvim_get_current_win()
					restore_layout()
					if vim.api.nvim_win_is_valid(cur) then
						vim.api.nvim_set_current_win(cur)
					end
				end
			end,
		})

		-- Session-aware toggle for the in-terminal keys: the <leader>j* maps are
		-- normal-mode only (a t-mode <Space> map would intercept every space
		-- typed into the CLI), and the AI column sits in terminal-insert mode
		-- whenever focused — so <M-J>/<D-M-j> are the one-key way to hide the
		-- session you are typing in. Toggle THAT session, not always session 1.
		local function toggle_current_or_first()
			local buf = vim.api.nvim_get_current_buf()
			for n, term in pairs(ai_panels) do
				if term.bufnr == buf then
					return toggle_ai_panel(n)
				end
			end
			toggle_ai_panel(1)
		end

		-- iTerm2 bridge: iTerm2 cannot send Cmd to a TUI app, so we configure
		-- Cmd+Opt+J in iTerm2 as "Send Escape Sequence" with the text "J".
		-- iTerm then sends <Esc>J, which Neovim receives as <M-J>. This mapping
		-- toggles from any mode (including the terminal itself, so the session
		-- under your fingers can be hidden from within).
		vim.keymap.set(
			{ "n", "i", "t" },
			"<M-J>",
			toggle_current_or_first,
			{ desc = "Toggle AI session (current or 1)" }
		)

		-- Literal Cmd+Opt+J for GUI Neovim (Neovide, etc.) or terminals that do
		-- forward <D-...> (super/command). Harmless if your terminal doesn't.
		vim.keymap.set({ "n", "t" }, "<D-M-j>", toggle_current_or_first, { desc = "Toggle AI session (current or 1)" })

		-- Universal fallback that works in ANY terminal with no extra config:
		--   <leader>j (Space+j) in normal mode -> toggle AI session 1.
		vim.keymap.set("n", "<leader>j", function()
			toggle_ai_panel(1)
		end, { desc = "Toggle AI session 1" })

		-- <leader>j2 .. <leader>j9 -> toggle additional independent AI sessions.
		for n = 2, 9 do
			vim.keymap.set("n", "<leader>j" .. n, function()
				toggle_ai_panel(n)
			end, { desc = "Toggle AI session " .. n })
		end

		-- Let the bridge open a session when a send finds none alive (and let
		-- the <leader>ja picker reopen a hidden one).
		require("core.ai-sessions").set_opener(function(n)
			toggle_ai_panel(n or 1)
		end)
	end,
}
