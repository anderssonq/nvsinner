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
if [ -e "$CONFIG_DIR" ]; then
  ok "Config already present at $CONFIG_DIR (leaving it untouched)"
else
  info "Cloning NvSinner into $CONFIG_DIR"
  git clone --depth=1 "$REPO_URL" "$CONFIG_DIR"
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

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) warn "$BIN_DIR is not on your PATH — add it to your shell rc:  export PATH=\"$BIN_DIR:\$PATH\"" ;;
esac

# 3. Bootstrap plugins --------------------------------------------------------
info "Bootstrapping plugins (the first run downloads everything)…"
NVIM_APPNAME="$APP" nvim --headless "+Lazy! sync" +qa
ok "Plugins installed"

printf '\n'
ok "NvSinner is ready — launch it with:  nvsinner"
info "First launch also auto-installs LSP servers (lua_ls, ts_ls, html) via Mason."
