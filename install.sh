#!/usr/bin/env bash
# NvSinner installer.
#
# Clones the distro into an isolated NVIM_APPNAME (~/.config/nvsinner), drops a
# `nvsinner` launcher on your PATH, and bootstraps every plugin. Safe to run
# alongside an existing ~/.config/nvim — it never touches it.
#
#   curl -fsSL https://raw.githubusercontent.com/anderssonq/nvsinner/main/install.sh | bash
#
# Override the source repo with NVSINNER_REPO=<url> if you forked it.
set -euo pipefail

REPO_URL="${NVSINNER_REPO:-https://github.com/anderssonq/nvsinner.git}"
APP="nvsinner"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/$APP"
BIN_DIR="$HOME/.local/bin"
LAUNCHER="$BIN_DIR/$APP"

info() { printf '\033[36m▸ %s\033[0m\n' "$1"; }
ok()   { printf '\033[32m✓ %s\033[0m\n' "$1"; }
warn() { printf '\033[33m! %s\033[0m\n' "$1"; }

command -v git  >/dev/null || { warn "git is required"; exit 1; }
command -v nvim >/dev/null || { warn "neovim (>= 0.12) is required"; exit 1; }
command -v node >/dev/null || { warn "node (>= 20) is required for the JS/TS/Vue language servers"; exit 1; }
# Real version gate, not just a presence check: NvSinner's floor is Neovim 0.12
# (bundled nvim.undotree, bundled treesitter parsers), and a 0.11 install
# must fail HERE rather than at first boot. Ask the interpreter instead of
# parsing `nvim --version` in shell.
nvim --headless -c 'if has("nvim-0.12") | qa | else | cq | endif' >/dev/null 2>&1 \
  || { warn "neovim >= 0.12 is required; found: $(nvim --version | head -1)"; exit 1; }
# Ask Node itself for the major version. The language servers are launched via
# `/usr/bin/env node`, so the PATH visible here is the one the launcher inherits.
node -e 'process.exit(Number(process.versions.node.split(".")[0]) >= 20 ? 0 : 1)' \
  || { warn "node >= 20 is required; found: $(node --version 2>&1) at $(command -v node)"; exit 1; }

# 1. Config dir ---------------------------------------------------------------
# Re-running the one-liner UPDATES an existing NvSinner clone (git pull) instead
# of skipping it, so users get new config code — not just a re-sync.
if [ -d "$CONFIG_DIR/.git" ]; then
  info "Updating existing NvSinner at $CONFIG_DIR"
  # Older installs cloned with --depth=1; unshallow so history-based updates and
  # `:NvSinnerUpdate` work cleanly from here on.
  if [ "$(git -C "$CONFIG_DIR" rev-parse --is-shallow-repository 2>/dev/null)" = "true" ]; then
    info "Unshallowing the existing clone…"
    git -C "$CONFIG_DIR" fetch --unshallow --quiet || true
  fi
  git -C "$CONFIG_DIR" pull --ff-only
  ok "Updated"
elif [ -e "$CONFIG_DIR" ]; then
  # Present but not a git working tree (e.g. a manual copy): don't touch it.
  ok "Config already present at $CONFIG_DIR (not a git clone — leaving it untouched)"
else
  info "Cloning NvSinner into $CONFIG_DIR"
  # Full clone (no --depth=1) so `git pull` / `:NvSinnerUpdate` update cleanly.
  git clone "$REPO_URL" "$CONFIG_DIR"
  ok "Cloned"
fi

# 2. Launcher -----------------------------------------------------------------
mkdir -p "$BIN_DIR"
cat > "$LAUNCHER" <<'EOF'
#!/usr/bin/env bash
exec env NVIM_APPNAME=nvsinner nvim "$@"
EOF
chmod +x "$LAUNCHER"
ok "Installed launcher: $LAUNCHER"

# The herdr control client is a symlink into the clone, not a copy, so it stays
# current with `git pull` / :NvSinnerUpdate. It is inert without herdr.
if [ -x "$CONFIG_DIR/bin/nvsinner-herdr" ]; then
  ln -sf "$CONFIG_DIR/bin/nvsinner-herdr" "$BIN_DIR/nvsinner-herdr"
  ok "Installed herdr client: $BIN_DIR/nvsinner-herdr"
fi

# 2b. Fonts --------------------------------------------------------------------
# Copies every bundled fonts/*.ttf (FiraCode Nerd Font + Maple Mono NF) into the
# user font dir, SKIPPING files that are already there (so a font you installed
# yourself is never overwritten). Only the files copied here are recorded in
# $FONT_MANIFEST, which is what uninstall.sh removes — nothing else.
# NVSINNER_FONT_DIR overrides the destination (used to dry-run this step).
case "$(uname -s)" in
  Darwin) FONT_DIR="${NVSINNER_FONT_DIR:-$HOME/Library/Fonts}" ;;
  *)      FONT_DIR="${NVSINNER_FONT_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/fonts}" ;;
esac
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/$APP"
FONT_MANIFEST="$DATA_DIR/installed-fonts.txt"

# >>> fonts (extracted by tests/scripts/font_install_spec.lua)
install_fonts() {
  local src="$CONFIG_DIR/fonts" f name copied=0
  [ -d "$src" ] || return 0
  mkdir -p "$FONT_DIR" "$DATA_DIR"
  touch "$FONT_MANIFEST"
  for f in "$src"/*.ttf; do
    [ -e "$f" ] || continue
    name="$(basename "$f")"
    if [ -e "$FONT_DIR/$name" ]; then
      continue
    fi
    cp "$f" "$FONT_DIR/$name"
    printf '%s\n' "$FONT_DIR/$name" >> "$FONT_MANIFEST"
    copied=$((copied + 1))
  done
  if [ "$copied" -gt 0 ] && [ -z "${NVSINNER_FONT_DIR:-}" ] && [ "$(uname -s)" != "Darwin" ] \
    && command -v fc-cache >/dev/null; then
    fc-cache -f "$FONT_DIR" >/dev/null 2>&1 || true
  fi
  ok "Fonts: $copied new file(s) installed in $FONT_DIR (existing ones left alone)"
}
install_fonts

# Optional Ghostty include (y/N, default N, skipped when there is no terminal to
# ask on). The :NvSinnerMenu "Font" row writes ONLY the NvSinner-owned file
# ~/.config/ghostty/nvsinner-font; this appends the one line that makes Ghostty
# read it. Never done silently: the user's config is theirs. What was added is
# recorded in $DATA_DIR/ghostty-include.txt (config path, line, blank-line flag)
# so uninstall.sh can remove exactly that. NVSINNER_INCLUDE_ANSWER (y/n) is a
# test seam that stands in for the prompt.
offer_ghostty_include() {
  local cfg_home="${XDG_CONFIG_HOME:-$HOME/.config}"
  local owned="$cfg_home/ghostty/nvsinner-font"
  local line="config-file = ?$owned" cfg="" c reply blank=0
  for c in "$cfg_home/ghostty/config.ghostty" \
           "$cfg_home/ghostty/config" \
           "$HOME/Library/Application Support/com.mitchellh.ghostty/config.ghostty" \
           "$HOME/Library/Application Support/com.mitchellh.ghostty/config"; do
    if [ -f "$c" ]; then cfg="$c"; break; fi
  done
  if [ -z "$cfg" ]; then
    info "No Ghostty config found. To let :NvSinnerMenu switch the Ghostty font, add this line to your Ghostty config:  $line"
    return 0
  fi
  # Only a live (non-comment) config-file line counts as already included.
  if grep -Eq '^[[:space:]]*config-file[[:space:]]*=.*nvsinner-font' "$cfg"; then return 0; fi
  if [ -n "${NVSINNER_INCLUDE_ANSWER+x}" ]; then
    reply="$NVSINNER_INCLUDE_ANSWER"
  elif [ -t 0 ]; then
    printf 'Add "%s" to %s so the Font row can switch Ghostty fonts? [y/N] ' "$line" "$cfg"
    read -r reply || reply=""
  else
    info "To let :NvSinnerMenu switch the Ghostty font, add this line to $cfg:  $line"
    return 0
  fi
  case "$reply" in
    y|Y|yes|YES)
      if [ ! -s "$cfg" ]; then
        printf '%s\n' "$line" >> "$cfg"
      elif [ -n "$(tail -c1 "$cfg")" ]; then
        printf '\n%s\n' "$line" >> "$cfg"      # no trailing newline: it only ends the last line
      else
        printf '\n%s\n' "$line" >> "$cfg"      # blank separator + line
        blank=1
      fi
      mkdir -p "$DATA_DIR"
      printf '%s\n%s\n%s\n' "$cfg" "$line" "$blank" > "$DATA_DIR/ghostty-include.txt"
      ok "Added the include line to $cfg" ;;
    *) info "Skipped. Add it yourself to enable the Font row:  $line" ;;
  esac
}
offer_ghostty_include
# <<< fonts

# If ~/.local/bin isn't on PATH, PRINT the exact line to add (naming the likely
# shell rc) — we never edit the user's shell files, just tell them what to paste.
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *)
    case "${SHELL:-}" in
      */fish) rc="$HOME/.config/fish/config.fish"; line='fish_add_path $HOME/.local/bin' ;;
      */zsh)  rc="${ZDOTDIR:-$HOME}/.zshrc";        line='export PATH="$HOME/.local/bin:$PATH"' ;;
      */bash)
        # macOS Terminal starts bash as a login shell (.bash_profile); Linux uses .bashrc.
        if [ "$(uname)" = "Darwin" ]; then rc="$HOME/.bash_profile"; else rc="$HOME/.bashrc"; fi
        line='export PATH="$HOME/.local/bin:$PATH"' ;;
      *)      rc="your shell startup file";          line='export PATH="$HOME/.local/bin:$PATH"' ;;
    esac
    warn "$BIN_DIR is not on your PATH."
    printf '  Add this line to %s, then restart your shell (or run: source %s):\n\n      %s\n\n' "$rc" "$rc" "$line"
    ;;
esac

# 3. Install plugins ----------------------------------------------------------
# `restore` (not `sync`) installs the exact versions pinned in the committed
# lazy-lock.json, so every install/update reproduces the tested plugin set
# instead of floating to latest. lazy.nvim clones any missing plugins first.
info "Installing plugins from the pinned lazy-lock.json (the first run downloads everything)…"
NVIM_APPNAME="$APP" nvim --headless "+Lazy! restore" +qa
ok "Plugins installed"

printf '\n'
ok "NvSinner is ready — launch it with:  nvsinner"
info "First launch also auto-installs 9 LSP servers (lua_ls, vtsls, vue_ls, html, pyright, bashls, jsonls, yamlls, cssls) and 4 formatters/linters (stylua, prettier, eslint_d, shfmt) via Mason."
info "Update later with  :NvSinnerUpdate  (or re-run this installer)."
