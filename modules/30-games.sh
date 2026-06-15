#!/usr/bin/env bash
#
# 30-games — game engines. Godot is the lightweight default; Unity Hub is the
# heavier option. Web-game stacks (Phaser, Three.js, Babylon.js) need no system
# install — they're scaffolded per-project on Node (see first-app guide).

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=../lib/common.sh
. "$HERE/../lib/common.sh"
ensure_brew_env

log_step "30 · Games"

brew_cask godot unity-hub

log_note "Godot is ready to open now — no account needed."
log_note "Unity: open 'Unity Hub', sign in with a (free) Unity account, and install an"
log_note "       Editor version from there. Web games need nothing extra — Node has it."

log_ok "Games complete"
