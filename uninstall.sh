#!/usr/bin/env bash
# NvSinner uninstaller.
#
# Removes everything the installer creates: the isolated NVIM_APPNAME dirs
# (config / data / state / cache) and the `nvsinner` launcher. It NEVER touches
# your other Neovim config (~/.config/nvim) — only the `nvsinner` app name.
#
#   curl -fsSL https://raw.githubusercontent.com/anderssonq/nvsinner/main/uninstall.sh | bash -s -- --yes
#   # or, from a clone:  ./uninstall.sh          (prompts for confirmation)
#
# Pass --yes / -y to skip the confirmation prompt. It's REQUIRED when the script
# is piped (curl | bash), since a piped script has no terminal to read y/n from.
set -euo pipefail

APP="nvsinner"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/$APP"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/$APP"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/$APP"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/$APP"
LAUNCHER="$HOME/.local/bin/$APP"

info() { printf '\033[36m▸ %s\033[0m\n' "$1"; }
ok()   { printf '\033[32m✓ %s\033[0m\n' "$1"; }
warn() { printf '\033[33m! %s\033[0m\n' "$1"; }

ASSUME_YES=0
for arg in "$@"; do
  case "$arg" in
    -y|--yes) ASSUME_YES=1 ;;
    -h|--help)
      printf 'Usage: uninstall.sh [--yes]\n'
      printf 'Removes the nvsinner config/data/state/cache dirs and the launcher.\n'
      exit 0 ;;
    *) warn "Unknown argument: $arg (try --help)"; exit 1 ;;
  esac
done

targets=("$CONFIG_DIR" "$DATA_DIR" "$STATE_DIR" "$CACHE_DIR" "$LAUNCHER")

# Keep only paths that actually exist. `-e` follows symlinks (false for a dangling
# link), so also test `-L` to catch a broken symlink.
present=()
for t in "${targets[@]}"; do
  if [ -e "$t" ] || [ -L "$t" ]; then present+=("$t"); fi
done

if [ ${#present[@]} -eq 0 ]; then
  ok "Nothing to remove — no nvsinner files found."
  exit 0
fi

info "This will remove:"
for t in "${present[@]}"; do
  if [ -L "$t" ]; then
    # On the dev machine ~/.config/nvsinner is a symlink to the repo; we only
    # unlink it and leave the target (your working copy) alone.
    printf '    %s  \033[33m(symlink → %s; target left untouched)\033[0m\n' "$t" "$(readlink "$t")"
  else
    printf '    %s\n' "$t"
  fi
done
printf '\n'

if [ "$ASSUME_YES" -ne 1 ]; then
  if [ -t 0 ]; then
    printf 'Proceed? [y/N] '
    read -r reply
    case "$reply" in
      y|Y|yes|YES) ;;
      *) warn "Aborted — nothing was removed."; exit 1 ;;
    esac
  else
    warn "Refusing to delete without confirmation (no terminal to prompt on)."
    warn "Re-run with --yes, e.g.:  curl -fsSL …/uninstall.sh | bash -s -- --yes"
    exit 1
  fi
fi

for t in "${present[@]}"; do
  if [ -L "$t" ]; then
    rm -f "$t"    # remove the symlink only, never follow into its target
  else
    rm -rf "$t"
  fi
  ok "Removed $t"
done

printf '\n'
ok "NvSinner uninstalled. (Your ~/.config/nvim, if any, was not touched.)"
info "If you added ~/.local/bin to your PATH just for NvSinner, you can drop that line now."
