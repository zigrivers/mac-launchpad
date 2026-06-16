#!/usr/bin/env bash
# modules/07-secrets.sh — wire the (already-installed) 1Password CLI into the
# optional `launchpad secrets` toolset. Core module: runs for every profile.
# Optional by design: no sign-in, no desktop app, never blocks. The .env.local
# fallback works with zero 1Password setup; signing in later "just works".
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=../lib/common.sh
. "$HERE/../lib/common.sh"
ensure_brew_env

log_step "Secret management (1Password CLI)"

# 1Password CLI is installed by 00-foundation; self-heal if somehow absent.
if have op; then
  log_ok "1Password CLI (op) present ($(op --version 2>/dev/null || echo '?'))"
else
  brew_install 1password-cli
fi

# Make the helper executable (it's dispatched by `launchpad secrets`).
if [ -f "$LP_ROOT/scripts/secrets.sh" ]; then
  chmod +x "$LP_ROOT/scripts/secrets.sh" 2>/dev/null || true
  log_ok "launchpad secrets ready (scripts/secrets.sh)"
else
  log_warn "scripts/secrets.sh missing — launchpad secrets unavailable"
fi

# Do NOT sign in / create accounts / install the desktop app — that's a human,
# optional step. Just say it's ready.
if have op && ! op whoami >/dev/null 2>&1; then
  log_note "1Password is optional and not signed in — run 'launchpad secrets' when you want it; until then secrets use .env.local."
fi

log_ok "Secret management ready (optional; .env.local fallback always works)"
