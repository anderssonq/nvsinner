-- Minimal monochrome statusline to match the dark glass theme.
-- No separators, a single muted palette across every mode, one global bar.
return {
  "nvim-lualine/lualine.nvim",
  event = "VeryLazy",
  dependencies = { "nvim-tree/nvim-web-devicons" },
  config = function()
    -- Glass palette (kept in sync with lua/plugins/theme.lua).
    local GLASS = "#111118"
    local FG = "#c5c9d5"
    local MUTED = "#7a7f8d"

    -- Every mode shares the same colours -> monochrome.
    local section = { a = { fg = FG, bg = GLASS }, b = { fg = MUTED, bg = GLASS }, c = { fg = MUTED, bg = GLASS } }
    local mono = {
      normal = section,
      insert = section,
      visual = section,
      replace = section,
      command = section,
      inactive = { a = { fg = MUTED, bg = GLASS }, b = { fg = MUTED, bg = GLASS }, c = { fg = MUTED, bg = GLASS } },
    }

    require("lualine").setup({
      options = {
        theme = mono,
        component_separators = "",
        section_separators = "",
        globalstatus = true,
        refresh = { statusline = 100 },
      },
      sections = {
        lualine_a = { "mode" },
        lualine_b = { "branch" },
        lualine_c = { "filename" },
        lualine_x = { "diagnostics", "filetype" },
        lualine_y = { "progress" },
        lualine_z = { "location" },
      },
    })
  end,
}
