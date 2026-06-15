#!/usr/bin/env bash
#
# 01-shell — wire up ~/.zshrc (fnm, Starship, fzf, history, aliases), install
# the Starship prompt config, and apply sensible macOS keyboard/Finder tweaks.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=../lib/common.sh
. "$HERE/../lib/common.sh"
ensure_brew_env

log_step "01 · Shell"

# --- ~/.zshrc managed block -------------------------------------------------
replace_managed_block "$HOME/.zshrc" \
  "# >>> launchpad (zshrc) >>>" \
  "# <<< launchpad (zshrc) <<<" \
  < "$LP_ROOT/config/zshrc.append"
log_ok "configured ~/.zshrc (managed block)"

# --- Starship prompt config -------------------------------------------------
ensure_dir "$HOME/.config"
if [ -f "$HOME/.config/starship.toml" ]; then backup_file "$HOME/.config/starship.toml"; fi
cp -f "$LP_ROOT/config/starship.toml" "$HOME/.config/starship.toml"
log_ok "installed ~/.config/starship.toml"

# --- macOS quality-of-life defaults -----------------------------------------
# Fast key repeat (great for editing); disable press-and-hold accent popup so
# holding a key repeats it; show hidden files in Finder.
defaults write -g KeyRepeat -int 2            >/dev/null 2>&1 || true
defaults write -g InitialKeyRepeat -int 15    >/dev/null 2>&1 || true
defaults write -g ApplePressAndHoldEnabled -bool false >/dev/null 2>&1 || true
defaults write com.apple.finder AppleShowAllFiles -bool true >/dev/null 2>&1 || true
defaults write com.apple.finder AppleShowAllExtensions -bool true >/dev/null 2>&1 || true
killall Finder >/dev/null 2>&1 || true
log_ok "applied macOS keyboard + Finder tweaks (some need a logout to fully apply)"

log_ok "Shell complete"
