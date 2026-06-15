#!/usr/bin/env bash
#
# 03-editors — VS Code, Cursor, and Sublime Text, each with the Claude Code and
# Codex extensions, Catppuccin Mocha, and JetBrainsMono Nerd Font.
#
# Verified extension IDs (2026-06): Claude Code = anthropic.claude-code,
# Codex = openai.chatgpt (NOT openai.codex). Cursor installs from OpenVSX; both
# extensions are published there.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=../lib/common.sh
. "$HERE/../lib/common.sh"
ensure_brew_env

log_step "03 · Editors"

brew_cask visual-studio-code cursor sublime-text

# CLI launchers are linked by the casks; report if any is missing.
for cli in code cursor subl; do
  if have "$cli"; then log_ok "CLI '${cli}' on PATH"; else log_warn "CLI '${cli}' not found on PATH yet (open the app once if needed)"; fi
done

# --- install extensions into a VS Code-like editor --------------------------
install_ext() {
  local ed="$1"; shift
  have "$ed" || { log_warn "${ed} CLI not found; skipping its extensions"; return 0; }
  local e
  for e in "$@"; do
    if "$ed" --install-extension "$e" --force >>"$LAUNCHPAD_LOG" 2>&1; then
      log_ok "${ed}: ${e}"
    else
      log_warn "${ed}: could not install ${e} (Cursor pulls from OpenVSX — may lag)"
    fi
  done
}

# --- deep-merge our theme/font settings without clobbering the user's -------
apply_settings() {
  local name="$1" dir="$2"
  ensure_dir "$dir"
  local f="$dir/settings.json" patch tmp
  patch='{"workbench.colorTheme":"Catppuccin Mocha","editor.fontFamily":"JetBrainsMono Nerd Font, Menlo, monospace","editor.fontLigatures":true,"editor.fontSize":14,"terminal.integrated.fontFamily":"JetBrainsMono Nerd Font"}'
  if [ ! -f "$f" ]; then
    if have jq; then printf '%s' "$patch" | jq '.' > "$f"; else printf '%s\n' "$patch" > "$f"; fi
    log_ok "${name}: wrote settings.json"
  elif have jq && jq -e . "$f" >/dev/null 2>&1; then
    backup_file "$f"; tmp="$(mktemp)"
    if jq -s '.[0] * .[1]' "$f" <(printf '%s' "$patch") > "$tmp"; then
      mv "$tmp" "$f"; log_ok "${name}: merged settings.json"
    else
      rm -f "$tmp"; log_warn "${name}: settings merge failed (left as-is)"
    fi
  else
    log_warn "${name}: settings.json has comments/invalid JSON — left as-is (set theme + font in the UI)"
  fi
}

for ed in code cursor; do
  install_ext "$ed" Catppuccin.catppuccin-vsc anthropic.claude-code openai.chatgpt
done
apply_settings "VS Code" "$HOME/Library/Application Support/Code/User"
apply_settings "Cursor"  "$HOME/Library/Application Support/Cursor/User"

# --- Sublime Text: font only (no Package Control dependency) -----------------
subl_user="$HOME/Library/Application Support/Sublime Text/Packages/User"
subl_prefs="$subl_user/Preferences.sublime-settings"
ensure_dir "$subl_user"
if [ ! -f "$subl_prefs" ]; then
  cat > "$subl_prefs" <<'JSON'
{
	"font_face": "JetBrainsMono Nerd Font",
	"font_size": 13
}
JSON
  log_ok "Sublime: wrote Preferences"
elif have jq && jq -e . "$subl_prefs" >/dev/null 2>&1; then
  backup_file "$subl_prefs"; tmp="$(mktemp)"
  if jq '. + {"font_face":"JetBrainsMono Nerd Font","font_size":13}' "$subl_prefs" > "$tmp"; then
    mv "$tmp" "$subl_prefs"; log_ok "Sublime: merged Preferences"
  else rm -f "$tmp"; log_warn "Sublime: could not merge Preferences"; fi
else
  log_warn "Sublime: existing Preferences not plain JSON — left as-is"
fi

log_ok "Editors complete"
