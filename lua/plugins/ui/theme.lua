-- Dark monochrome "glassmorphism" theme.
--
-- Base: kanagawa "dragon" variant, with the editor background pushed to a
-- near-black #0a0a0f and floating windows given a slightly lighter "glass"
-- panel colour with subtle borders.
--
-- NOTE: this is the active colorscheme, replacing the previous
-- catppuccin-macchiato setup.

-- Glass palette (kept in one place so floats + statusline stay consistent).
local BG = "#0a0a0f" -- editor background, near black
local GLASS = "#111118" -- floating / panel background, the "glass" surface
local BORDER = "#333345" -- subtle float borders
local FG = "#c5c9d5" -- primary foreground / titles

-- Re-assert the glass highlights every time the colorscheme is (re)applied.
-- This keeps floats glassy even when lazy-loaded plugins redefine their groups.
local function apply_glass_highlights()
  local set = vim.api.nvim_set_hl
  set(0, "NormalFloat", { bg = GLASS, fg = FG })
  set(0, "FloatBorder", { bg = GLASS, fg = BORDER })
  set(0, "FloatTitle", { bg = GLASS, fg = FG, bold = true })
end

return {
  {
    "rebelot/kanagawa.nvim",
    lazy = false,
    priority = 1000,
    config = function()
      require("kanagawa").setup({
        theme = "dragon",
        background = { dark = "dragon" },
        compile = false,
        dimInactive = false,
        -- Highlight overrides applied on top of the dragon palette.
        overrides = function()
          return {
            Normal = { bg = BG },
            NormalNC = { bg = BG },
            SignColumn = { bg = BG },
            EndOfBuffer = { bg = BG, fg = BG },
            NormalFloat = { bg = GLASS, fg = FG },
            FloatBorder = { bg = GLASS, fg = BORDER },
            FloatTitle = { bg = GLASS, fg = FG, bold = true },
          }
        end,
      })

      vim.o.background = "dark"
      vim.cmd.colorscheme("kanagawa-dragon")

      -- Apply once now, and re-apply on every future colorscheme load so the
      -- glass look survives lazy-loaded plugins re-registering highlights.
      apply_glass_highlights()
      vim.api.nvim_create_autocmd("ColorScheme", {
        pattern = "kanagawa*",
        callback = apply_glass_highlights,
      })
    end,
  },
}
