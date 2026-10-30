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
HERDR_CLIENT="$HOME/.local/bin/$APP-herdr"

info() { printf '\033[36m▸ %s\033[0m\n' "$1"; }
ok()   { printf '\033[32m✓ %s\033[0m\n' "$1"; }
warn() { printf '\033[33m! %s\033[0m\n' "$1"; }

ASSUME_YES=0
FORCE=0
for arg in "$@"; do
  case "$arg" in
    -y|--yes) ASSUME_YES=1 ;;
    -f|--force) FORCE=1 ;;
    -h|--help)
      printf 'Usage: uninstall.sh [--yes] [--force]\n'
      printf 'Removes the nvsinner config/data/state/cache dirs and the launcher.\n'
      printf '\n'
      printf '  -y, --yes    skip the confirmation prompt (required when piped)\n'
      printf '  -f, --force  also delete a config dir that is neither a git clone nor a\n'
      printf '               symlink (a manual copy, which install.sh leaves untouched)\n'
      printf '\n'
      printf 'Flags are separate words: use "-y -f", not "-yf" (combined short flags\n'
      printf 'are not supported).\n'
      exit 0 ;;
    *) warn "Unknown argument: $arg (try --help)"; exit 1 ;;
  esac
done

targets=("$CONFIG_DIR" "$DATA_DIR" "$STATE_DIR" "$CACHE_DIR" "$LAUNCHER" "$HERDR_CLIENT")

# Keep only paths that actually exist. `-e` follows symlinks (false for a dangling
# link), so also test `-L` to catch a broken symlink.
present=()
for t in "${targets[@]}"; do
  if [ -e "$t" ] || [ -L "$t" ]; then present+=("$t"); fi
done

# install.sh leaves a config dir that is neither a symlink nor a git clone alone
# ("manual copy": the user's own files, possibly unversioned edits). Deleting it
# here would be the one irreversible step, so skip it unless --force is given.
# "Git clone" is tested exactly as install.sh does (`-d .git`), so the two
# scripts agree: a worktree-style dir whose .git is a FILE counts as a manual copy.
kept=()
if [ "$FORCE" -ne 1 ] && [ -d "$CONFIG_DIR" ] && [ ! -L "$CONFIG_DIR" ] && [ ! -d "$CONFIG_DIR/.git" ]; then
  warn "$CONFIG_DIR is not a git clone or a symlink (a manual copy?) — leaving it in place."
  warn "Re-run with --force to delete it too."
  kept+=("$CONFIG_DIR")
  filtered=()
  for t in "${present[@]}"; do
    if [ "$t" != "$CONFIG_DIR" ]; then filtered+=("$t"); fi
  done
  # "${arr[@]}" on an empty array trips `set -u` on bash < 4.4 (macOS 3.2).
  present=()
  if [ ${#filtered[@]} -gt 0 ]; then present=("${filtered[@]}"); fi
fi

if [ ${#present[@]} -eq 0 ]; then
  if [ ${#kept[@]} -gt 0 ]; then
    ok "Nothing else to remove — the manual-copy config was left in place."
  else
    ok "Nothing to remove — no nvsinner files found."
  fi
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
if [ ${#kept[@]} -gt 0 ]; then
  ok "NvSinner uninstalled, except ${kept[0]} (kept; re-run with --force to delete it)."
else
  ok "NvSinner uninstalled. (Your ~/.config/nvim, if any, was not touched.)"
fi
info "If you added ~/.local/bin to your PATH just for NvSinner, you can drop that line now."
