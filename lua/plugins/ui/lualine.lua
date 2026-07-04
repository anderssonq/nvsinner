-- Carbon statusline: the oxocarbon mode→accent convention.
-- The mode block is a solid accent chip with dark text; every other section is
-- muted base04 text on the editor background, so the bar stays gray-dominant
-- and the mode color is the one meaningful moment of color.
return {
	"nvim-lualine/lualine.nvim",
	event = "VeryLazy",
	dependencies = { "nvim-tree/nvim-web-devicons" },
	config = function()
		-- Build + apply with FRESH carbon roles each time (single source:
		-- lua/core/carbon.lua) and re-run on ColorScheme, so a live dark↔light /
		-- accent switch (:NvSinnerMenu) restyles the bar instead of leaving it on
		-- the boot-time palette.
		-- AI cockpit badge: "AI: 2 working · 1 needs input" from the session
		-- registry (core/ai-sessions) + per-buffer status (core/ai-activity).
		-- Empty string with no sessions keeps the bar clean; the existing 100ms
		-- statusline refresh keeps the counts live. No accent chip on purpose —
		-- the mode block stays the bar's one moment of color.
		local function ai_badge()
			local ok, sessions = pcall(function()
				return require("core.ai-sessions").sessions()
			end)
			if not ok or #sessions == 0 then
				return ""
			end
			local activity = require("core.ai-activity")
			local counts = { working = 0, awaiting = 0, idle = 0 }
			for _, s in ipairs(sessions) do
				local st = (activity.status and activity.status(s.bufnr)) or "idle"
				counts[st] = (counts[st] or 0) + 1
			end
			local parts = {}
			if counts.working > 0 then
				table.insert(parts, counts.working .. " working")
			end
			if counts.awaiting > 0 then
				table.insert(parts, counts.awaiting .. " needs input")
			end
			if counts.idle > 0 then
				table.insert(parts, counts.idle .. " idle")
			end
			return "AI: " .. table.concat(parts, " · ")
		end

		local function apply()
			local c = require("core.carbon").colors()

			-- Mode → accent (map documented in lua/core/carbon.lua); base09 for
			-- Normal (the blue-forward identity accent) per the §6.2 convention.
			local function mode(accent)
				return {
					a = { fg = c.base00, bg = accent, gui = "bold" },
					b = { fg = c.base04, bg = c.base00 },
					c = { fg = c.base04, bg = c.base00 },
				}
			end
			local carbon = {
				normal = mode(c.base09),
				insert = mode(c.base12),
				visual = mode(c.base14),
				replace = mode(c.base08),
				command = mode(c.base13),
				terminal = mode(c.base11),
				inactive = {
					a = { fg = c.base03, bg = c.base01 },
					b = { fg = c.base03, bg = c.base00 },
					c = { fg = c.base03, bg = c.base00 },
				},
			}

			require("lualine").setup({
				options = {
					theme = carbon,
					component_separators = "",
					section_separators = "",
					globalstatus = true,
					refresh = { statusline = 100 },
				},
				sections = {
					lualine_a = { "mode" },
					lualine_b = { "branch" },
					lualine_c = { "filename" },
					lualine_x = { ai_badge, "diagnostics", "filetype" },
					lualine_y = { "progress" },
					lualine_z = { "location" },
				},
			})
		end
		apply()
		vim.api.nvim_create_autocmd("ColorScheme", {
			group = vim.api.nvim_create_augroup("nv_lualine_carbon", { clear = true }),
			pattern = "*",
			callback = apply,
		})
	end,
}
