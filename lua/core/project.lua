-- Project identity — the "which project is this window?" answer, in the two
-- places the user actually looks: the terminal tab (via 'titlestring') and the
-- statusline (via a lualine component).
--
-- Resolution is deliberately CWD-ANCHORED, not buffer-anchored: NvSinner is
-- launched as `cd myproject && nvsinner`, so the cwd's repo root is the "main
-- folder" the name should report. A buffer-anchored vim.fs.root(0, …) would
-- re-resolve per file and make the name jump around inside a monorepo (every
-- package with its own marker would rename the window).
--
-- The lookup is filesystem-only (vim.fs.root walks parent dirs) — no `git`
-- subprocess, unlike core/git-blame.lua — and the result is cached until the
-- cwd actually changes, because M.name() is read from a lualine component and
-- lua/plugins/ui/CLAUDE.md records that statusline components re-evaluate on
-- every redraw (an AI badge was removed from lualine for exactly that cost).
local M = {}

-- Root markers, in PRIORITY order — the order is load-bearing. vim.fs.root
-- loops the marker list and returns on the first marker that matches anywhere
-- in the upward walk (verified in runtime/lua/vim/fs.lua: `for _, mark in
-- ipairs(markers)` … `if #paths ~= 0 then return`), so it is NOT "innermost
-- directory containing any marker". Keeping ".git" first is what makes
-- `cd packages/foo && nvsinner` inside a monorepo still report the REPO name
-- instead of the package name; the manifests only apply when there is no repo
-- at all. Reordering this list silently changes what the title says.
M.MARKERS = { ".git", "package.json", "Cargo.toml", "go.mod", "pyproject.toml" }

local cached_root = nil
local cached_cwd = nil

--- Absolute path of the project root for the current working directory.
--- Falls back to the cwd itself when no marker is found (a plain folder is
--- still a "project" as far as the window title is concerned).
function M.root()
	local cwd = vim.fn.getcwd()
	if cached_cwd == cwd and cached_root then
		return cached_root
	end
	local root = vim.fs.root(cwd, M.MARKERS) or cwd
	cached_cwd, cached_root = cwd, root
	return root
end

--- Project name: the basename of M.root(). This is what the terminal tab and
--- the statusline show.
function M.name()
	return vim.fn.fnamemodify(M.root(), ":t")
end

--- Payload behind 'titlestring': "<project> · <file> [+]".
--- The project name comes FIRST so a narrow terminal tab truncates the file
--- path rather than the identity — telling two nvsinner tabs apart is the
--- whole point. Non-file buffers (dashboard, terminals) show the name alone.
---
--- Returns RAW text — do not escape "%" here. See M.EXPR.
function M.title()
	local out = M.name()
	if vim.bo.buftype == "" then
		local file = vim.fn.expand("%:~:.")
		if file ~= "" then
			out = out .. " · " .. file
			if vim.bo.modified then
				out = out .. " [+]"
			end
		end
	end
	return out
end

-- Expression for 'titlestring' (set in core/options.lua).
--
-- Plain %{…}, NOT the %{%…%} form core/filebadge.lua uses — and the difference
-- decides whether M.title() must escape "%". Measured on 0.12.3:
--   %{expr}   → the result is inserted LITERALLY; a file named "100%done"
--               renders as "100%done", and escaping it would render "100%%done".
--   %{%expr%} → the result is re-parsed as statusline items, so filebadge's
--               fragment() must (and does) escape "%".
-- This module emits text, not markup, so it takes the plain form and escapes
-- nothing. Switching to %{%…%} here would require adding the escape back.
M.EXPR = "%{v:lua.require'core.project'.title()}"

--- Statusline component body for lualine (lua/plugins/ui/lualine.lua).
function M.statusline()
	return M.name()
end

--- Test seam: drop the cache (mirrors the _reset() seam in the other core
--- modules). The DirChanged autocmd below is the production path.
function M._reset()
	cached_root, cached_cwd = nil, nil
end

vim.api.nvim_create_autocmd("DirChanged", {
	group = vim.api.nvim_create_augroup("NvProject", { clear = true }),
	pattern = "*",
	callback = M._reset,
})

return M
