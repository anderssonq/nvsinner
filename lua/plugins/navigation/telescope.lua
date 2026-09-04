return {
	"nvim-telescope/telescope.nvim",
	-- Pinned to 0.1.8 (2024-05-23). NOTE: this is genuinely BEHIND — upstream has
	-- shipped v0.2.2. (An earlier version of this comment claimed "upstream ships
	-- tags rarely"; checked against `git ls-remote --tags`, that was wrong.)
	-- Held deliberately rather than bumped: 0.1.x -> 0.2.x is a minor jump on the
	-- most-used UI in the editor, it drags telescope-ui-select with it, and
	-- telescope is a Wave 3 native-replacement target (NvSinnerFind, see
	-- docs/native-roadmap.md). Bump it as its own change with its own testing, or
	-- replace it — not as a drive-by.
	tag = "0.1.8",
	-- Lazy: loads on the :Telescope command or any of the keymaps below.
	cmd = "Telescope",
	-- vim.ui.select is only skinned by telescope-ui-select once telescope has
	-- loaded — without this shim, the first <leader>ja/jc of a session fell
	-- back to Neovim's builtin numbered prompt (rendered inconsistently by
	-- noice). First call loads telescope and re-dispatches, so every select
	-- picker is the same dropdown (LazyVim's load-on-first-use pattern).
	init = function()
		local builtin = vim.ui.select
		vim.ui.select = function(...)
			vim.ui.select = builtin -- a failed load must not re-enter the shim
			require("lazy").load({ plugins = { "telescope.nvim" } })
			return vim.ui.select(...)
		end
	end,
	dependencies = {
		"nvim-lua/plenary.nvim",
		"nvim-telescope/telescope-ui-select.nvim",
	},
	keys = {
		{ "<leader>f", "<cmd>Telescope find_files<cr>", desc = "Find files" },
		{ "<leader>sf", "<cmd>Telescope live_grep<cr>", desc = "Live grep" },
		{ "<leader>sd", "<cmd>Telescope diagnostics<cr>", desc = "Search diagnostics" },
		{ "<leader>sk", "<cmd>Telescope keymaps<cr>", desc = "Search keymaps" },
		{ "<leader>sc", "<cmd>Telescope commands<cr>", desc = "Search commands" },
		{ "<leader>sr", "<cmd>Telescope resume<cr>", desc = "Resume last search" },
		{ "<leader>sh", "<cmd>Telescope help_tags<cr>", desc = "Search help" },
		{ "<leader>ss", "<cmd>Telescope lsp_document_symbols<cr>", desc = "Document symbols" },
		{ "<leader>sR", "<cmd>Telescope lsp_references<cr>", desc = "LSP references" },
		-- gd/grt jump straight to the file; these show the same targets as a
		-- modal with a code preview, so you can read the definition and press
		-- q/Esc without leaving where you were. jump_type = "never" matters:
		-- telescope's LSP pickers jump DIRECTLY to a single result instead of
		-- opening the picker (builtin/__lsp.lua), which would make the peek
		-- indistinguishable from gd whenever there is exactly one definition.
		{
			"<leader>ld",
			function()
				require("telescope.builtin").lsp_definitions({ jump_type = "never" })
			end,
			desc = "Preview definition",
		},
		{
			"<leader>lt",
			function()
				require("telescope.builtin").lsp_type_definitions({ jump_type = "never" })
			end,
			desc = "Preview type definition",
		},
		-- <leader>fb (buffers) is mapped in lua/core/keymaps.lua and also triggers
		-- this lazy load via the :Telescope command stub.
	},
	config = function()
		-- Telescope is three floats, not one modal window. Once its windows exist,
		-- find the preview by its public highlight mapping and put NvSinner's
		-- shared backdrop below it. Pickers without a preview (notably ui-select's
		-- dropdown) never match, so nested selectors are not dimmed twice.
		local function attach_preview_backdrop()
			for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
				if vim.api.nvim_win_is_valid(win) then
					local winhl = vim.wo[win].winhighlight
					if winhl:find("TelescopePreviewNormal", 1, true) then
						local existing = vim.w[win].nvsinner_telescope_backdrop
						if type(existing) == "number" and vim.api.nvim_win_is_valid(existing) then
							return
						end
						local backdrop = require("core.backdrop").attach(win)
						if backdrop then
							vim.w[win].nvsinner_telescope_backdrop = backdrop
						end
						return
					end
				end
			end
		end

		vim.api.nvim_create_autocmd("User", {
			group = vim.api.nvim_create_augroup("nv_telescope_backdrop", { clear = true }),
			pattern = { "TelescopeFindPre", "TelescopePreviewerLoaded" },
			callback = function(ev)
				-- FindPre fires before Telescope creates its floats; defer that path.
				-- PreviewerLoaded also covers a preview recreated after a resize.
				if ev.match == "TelescopeFindPre" then
					vim.schedule(attach_preview_backdrop)
				else
					attach_preview_backdrop()
				end
			end,
		})

		require("telescope").setup({
			defaults = {
				-- Never surface git internals even when searching hidden files below.
				file_ignore_patterns = { "^%.git/" },
				-- One search surface, two shapes: wide screens keep results beside a
				-- larger preview; narrow screens stack them. Best matches stay near
				-- the prompt at the top in both arrangements.
				sorting_strategy = "ascending",
				layout_strategy = "flex",
				layout_config = {
					horizontal = {
						width = 0.92,
						height = 0.86,
						prompt_position = "top",
						preview_width = 0.58,
						preview_cutoff = 1,
					},
					vertical = {
						width = 0.92,
						height = 0.90,
						mirror = true,
						prompt_position = "top",
						preview_height = 0.58,
						preview_cutoff = 20,
					},
				},
			},
			pickers = {
				-- <leader>f finds hidden dotfiles too (rg --hidden). .git/ is still
				-- excluded via file_ignore_patterns above so it doesn't flood results.
				find_files = {
					hidden = true,
				},
			},
			extensions = {
				["ui-select"] = {
					require("telescope.themes").get_dropdown({}),
				},
			},
		})
		require("telescope").load_extension("ui-select")
	end,
}
