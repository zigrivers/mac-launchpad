#!/usr/bin/env bash
#
# 02-terminal — Alacritty + the Catppuccin Mocha theme.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=../lib/common.sh
. "$HERE/../lib/common.sh"
ensure_brew_env

log_step "02 · Terminal (Alacritty)"

brew_cask alacritty

alacritty_dir="$HOME/.config/alacritty"
themes_dir="$alacritty_dir/themes"
ensure_dir "$themes_dir"

# Theme: try the official repo first, fall back to the vendored copy so this
# always works offline / in the test VM.
theme_dst="$themes_dir/catppuccin-mocha.toml"
theme_url="https://raw.githubusercontent.com/catppuccin/alacritty/main/catppuccin-mocha.toml"
if download "$theme_url" "$theme_dst"; then
  log_ok "fetched Catppuccin Mocha theme"
else
  cp -f "$LP_ROOT/config/alacritty/themes/catppuccin-mocha.toml" "$theme_dst"
  log_ok "installed vendored Catppuccin Mocha theme"
fi

# Main config.
if [ -f "$alacritty_dir/alacritty.toml" ]; then backup_file "$alacritty_dir/alacritty.toml"; fi
cp -f "$LP_ROOT/config/alacritty/alacritty.toml" "$alacritty_dir/alacritty.toml"
log_ok "installed ~/.config/alacritty/alacritty.toml"

log_ok "Terminal complete"
