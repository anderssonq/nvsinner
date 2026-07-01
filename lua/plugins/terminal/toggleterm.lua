return {
	"akinsho/toggleterm.nvim",
	version = "*",
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
		-- every AI column is forced to a full-height right column (`wincmd L`)
		-- LAST, so the columns always win the right edge and the horizontals tuck
		-- into the bottom-left. Each panel keeps its own size, so the two never
		-- collide and the margins stay put (AI columns AI_WIDTH wide, horizontals
		-- 20% of the screen tall).
		local AI_WIDTH = 50
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
					vim.cmd("wincmd L")
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
				vim.b[buf].nv_term_label = id >= 100 and ("AI · " .. (id - 99)) or ("term " .. id)
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
		-- only spawns a shell the first time it is opened.
		local function get_ai_panel(n)
			if not ai_panels[n] then
				ai_panels[n] = Terminal:new({
					-- Reserved ids (100+) so they never collide with the <leader>t
					-- horizontal terminals, which use the low ids 1–9. Session 1
					-- keeps its historical id 100; session N gets 99 + N.
					id = 99 + n,
					direction = "vertical", -- splitright is on -> opens on the right
					size = AI_WIDTH, -- fixed column width (not percentual): a compact AI column
					hidden = true, -- "custom" terminal: not part of the <leader>t list
					close_on_exit = false, -- if the shell dies, don't auto-close
					-- on_panel_open forces the column full-height on the right
					-- (wincmd L) and re-tucks any horizontal terminal bottom-left.
					on_open = on_panel_open,
				})
			end
			return ai_panels[n]
		end

		local function toggle_ai_panel(n)
			get_ai_panel(n or 1):toggle()
		end

		-- iTerm2 bridge: iTerm2 cannot send Cmd to a TUI app, so we configure
		-- Cmd+Opt+J in iTerm2 as "Send Escape Sequence" with the text "J".
		-- iTerm then sends <Esc>J, which Neovim receives as <M-J>. This mapping
		-- toggles session 1 from any mode (including the terminal itself, so it
		-- can be hidden from within).
		vim.keymap.set({ "n", "i", "t" }, "<M-J>", function()
			toggle_ai_panel(1)
		end, { desc = "Toggle AI session 1" })

		-- Literal Cmd+Opt+J for GUI Neovim (Neovide, etc.) or terminals that do
		-- forward <D-...> (super/command). Harmless if your terminal doesn't.
		vim.keymap.set({ "n", "t" }, "<D-M-j>", function()
			toggle_ai_panel(1)
		end, { desc = "Toggle AI session 1" })

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
	end,
}
