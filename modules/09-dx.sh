#!/usr/bin/env bash
#
# 09-dx — developer-experience niceties that make autonomous building pleasant
# for a non-technical user. Runs for every profile. Installs:
#   * Beekeeper Studio — a free GUI to SEE and edit your database (no SQL needed)
#   * terminal-notifier — lets the agents ping you when a long task finishes
#   * the `launchpad` command (new / report / harden / doctor / update / notify)
#
# Verified 2026-06-15: casks `beekeeper-studio` (free OSS) and `tableplus`
# (freemium alternative); formula `terminal-notifier` (provides the
# `terminal-notifier` command).

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=../lib/common.sh
. "$HERE/../lib/common.sh"
ensure_brew_env

log_step "09 · Developer experience"

# --- 1. a database GUI you can actually see -----------------------------------
brew_cask beekeeper-studio
log_note "Prefer a polished freemium option? 'brew install --cask tableplus'."

# --- 2. consistent formatting across every project ----------------------------
# Biome formats + lints every project identically. The shared config is in
# config/dx/biome.json (copied into projects by the hardener + templates), and
# the pre-commit hook runs `biome-check` on every commit. Verified 2026-06-15:
# formula `biome` (v2.x; binary `biome`).
brew_install biome

# --- 3. desktop notifications when long tasks finish --------------------------
brew_install terminal-notifier

# A tiny wrapper the agents call to ping you. On PATH for every shell + agent.
ensure_dir "$HOME/.local/bin"
notify_bin="$HOME/.local/bin/launchpad-notify"
[ -f "$notify_bin" ] && backup_file "$notify_bin"
cat > "$notify_bin" <<'NOTIFY'
#!/usr/bin/env bash
# launchpad-notify [title] <message> — macOS notification when a task finishes.
# Used by the agents (house-rule) so you can walk away from a long build.
title="Mac Launchpad"
if [ "$#" -ge 2 ]; then title="$1"; shift; fi
msg="$*"
if command -v terminal-notifier >/dev/null 2>&1; then
  terminal-notifier -title "$title" -message "$msg" -sound Glass >/dev/null 2>&1 || true
else
  osascript -e "display notification \"$msg\" with title \"$title\" sound name \"Glass\"" >/dev/null 2>&1 || true
fi
NOTIFY
chmod +x "$notify_bin"
log_ok "installed 'launchpad-notify' (agents ping you when a long task finishes)"

# --- spend guardrail: a daily launchd agent that warns on a spending spike or
#     an optional monthly budget (ccusage is read-only; nothing is uploaded) ---
chmod +x "$LP_ROOT/scripts/spend-check.sh" 2>/dev/null || true
chmod +x "$LP_ROOT/scripts/status.sh" "$LP_ROOT/scripts/signin.sh" "$LP_ROOT/scripts/sentry-setup.sh" 2>/dev/null || true
ensure_dir "$HOME/.config/launchpad"
spend_plist="$HOME/Library/LaunchAgents/com.launchpad.spend.plist"
ensure_dir "$HOME/Library/LaunchAgents"
[ -f "$spend_plist" ] && backup_file "$spend_plist"
cat > "$spend_plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.launchpad.spend</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$LP_ROOT/scripts/spend-check.sh</string>
  </array>
  <key>StartCalendarInterval</key><dict><key>Hour</key><integer>18</integer><key>Minute</key><integer>0</integer></dict>
  <key>RunAtLoad</key><false/>
  <key>StandardErrorPath</key><string>$HOME/.config/launchpad/spend.log</string>
  <key>StandardOutPath</key><string>$HOME/.config/launchpad/spend.log</string>
</dict>
</plist>
PLIST
# (re)load idempotently
launchctl bootout "gui/$(id -u)/com.launchpad.spend" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$spend_plist" >/dev/null 2>&1 \
  || launchctl load -w "$spend_plist" >/dev/null 2>&1 || true
log_ok "spend guardrail installed (daily check; warns on a spike — set a budget in ~/.config/launchpad/limits)"

# --- 5. put the `launchpad` command on PATH -----------------------------------
# scripts/launchpad dispatches: new | harden | report | doctor | update | notify.
chmod +x "$LP_ROOT/scripts/launchpad" "$LP_ROOT/scripts/new-project.sh" \
         "$LP_ROOT/scripts/report.sh" "$LP_ROOT/scripts/harden-project.sh" 2>/dev/null || true
symlink_force "$LP_ROOT/scripts/launchpad" "$HOME/.local/bin/launchpad"

log_ok "Developer experience ready: Beekeeper Studio, notifications, 'launchpad' command"
