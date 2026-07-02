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
command -v nvim >/dev/null || { warn "neovim (>= 0.11) is required"; exit 1; }

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
info "First launch also auto-installs LSP servers (lua_ls, ts_ls, html) via Mason."
info "Update later with  :NvSinnerUpdate  (or re-run this installer)."
