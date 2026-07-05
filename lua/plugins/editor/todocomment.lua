-- DISABLED: replaced by the native keyword-chip module in lua/core/todo.lua
-- (visible-range TODO:/FIXME:/HACK:… scan → carbon accent chips; drops a
-- plenary consumer). Kept as a one-line revert.
return {
	"folke/todo-comments.nvim",
	enabled = false,
	event = { "BufReadPost", "BufNewFile" },
	dependencies = { "nvim-lua/plenary.nvim" },
	opts = {},
}
