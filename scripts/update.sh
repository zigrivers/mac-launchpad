#!/usr/bin/env bash
#
# scripts/update.sh [profile]
#
# Refresh everything: Homebrew formulae/casks, global npm tools, uv + uv tools,
# re-assert the agent MCP wiring, then re-run doctor. Claude Code and Codex
# update themselves (native installers), so they're not touched here.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
ROOT="$(cd "$HERE/.." >/dev/null 2>&1 && pwd)"
# shellcheck source=../lib/common.sh
. "$ROOT/lib/common.sh"
ensure_brew_env

log_step "Updating Homebrew"
brew update            >>"$LAUNCHPAD_LOG" 2>&1 || log_warn "brew update had issues"
brew upgrade           >>"$LAUNCHPAD_LOG" 2>&1 || log_warn "brew upgrade had issues"
brew upgrade --cask --greedy >>"$LAUNCHPAD_LOG" 2>&1 || log_warn "brew cask upgrade had issues"
brew cleanup           >>"$LAUNCHPAD_LOG" 2>&1 || true
log_ok "Homebrew up to date"

if have npm; then
  log_step "Updating global npm tools"
  npm update -g >>"$LAUNCHPAD_LOG" 2>&1 || log_warn "npm -g update had issues"
fi

if have uv; then
  log_step "Updating uv + tools"
  uv self update         >>"$LAUNCHPAD_LOG" 2>&1 || true
  uv tool upgrade --all  >>"$LAUNCHPAD_LOG" 2>&1 || true
  log_ok "uv tools up to date"
fi

if command -v agy >/dev/null 2>&1; then
  log_step "Updating Antigravity CLI (agy)"
  agy update >>"$LAUNCHPAD_LOG" 2>&1 || log_warn "agy update had issues"
fi

log_step "Re-asserting agent + MCP configuration"
bash "$ROOT/modules/05-agents.sh" || log_warn "05-agents reported issues"

log_step "Health check"
bash "$ROOT/lib/doctor.sh" "${1:-}" || log_warn "doctor found issues"

log_note "Claude Code and Codex keep themselves updated automatically; Antigravity is updated above."
log_ok "Update complete"
