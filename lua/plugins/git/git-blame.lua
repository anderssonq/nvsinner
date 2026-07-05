return {
	"f-person/git-blame.nvim",
	-- DISABLED: replaced by the native inline blame in lua/core/git-blame.lua
	-- (same " <summary> • <date> • <author> • <sha>" annotation, rendered from
	-- an async `git blame --porcelain` of the buffer contents). Kept as a
	-- one-line revert.
	enabled = false,
	event = "VeryLazy",
	opts = {
		enabled = true,
		message_template = " <summary> • <date> • <author> • <<sha>>",
		date_format = "%m-%d-%Y %H:%M:%S",
		virtual_text_column = 1,
	},
}
