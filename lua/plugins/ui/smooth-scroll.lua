return {
  "karb94/neoscroll.nvim",
  event = "VeryLazy",
  config = function()
    local neoscroll = require("neoscroll")
    local keymap = {
      ["<PageUp>"] = function()
        neoscroll.ctrl_u({ duration = 10 })
      end,
      ["<PageDown>"] = function()
        neoscroll.ctrl_d({ duration = 10 })
      end,
    }
    local modes = { "n", "v", "x" }
    for key, func in pairs(keymap) do
      vim.keymap.set(modes, key, func)
    end
  end,
}
