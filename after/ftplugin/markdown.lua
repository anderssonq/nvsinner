-- Neovim 0.12.x ships runtime/ftplugin/markdown.lua which unconditionally calls
-- `vim.treesitter.start()` for every markdown buffer. On 0.12.3 the markdown
-- parser/queries are out of sync with the treesitter core: the highlighter calls
-- `node:range()` on a nil node and crashes (runtime treesitter.lua:197,
-- "attempt to call method 'range' (a nil value)"). This `after/ftplugin` runs
-- AFTER the runtime one, so it stops the treesitter highlighter and falls back to
-- Vim's regex syntax for markdown. Remove this once the upstream 0.12.x fix lands
-- (or when running on stable 0.11.x, where the crash does not occur).
-- Mirrors the other 0.12.x markdown workarounds documented in CLAUDE.md.
pcall(vim.treesitter.stop, 0)
vim.bo.syntax = "markdown"
