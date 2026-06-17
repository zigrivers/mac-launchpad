#!/usr/bin/env bash
#
# 10-web — the web/app stack: package managers (pnpm, bun), a local Docker
# replacement (OrbStack), Supabase + Postgres, tunnels (cloudflared, ngrok),
# and the Vercel CLI. Playwright browsers are installed per-project on demand.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=../lib/common.sh
. "$HERE/../lib/common.sh"
ensure_brew_env

log_step "10 · Web / App stack"

# Make sure Node is active for npm/corepack steps.
have fnm && eval "$(fnm env)" 2>/dev/null && fnm use default >/dev/null 2>&1 || true

# --- pnpm via corepack (ships with Node) ------------------------------------
if have corepack; then
  corepack enable >>"$LAUNCHPAD_LOG" 2>&1 || true
  corepack prepare pnpm@latest --activate >>"$LAUNCHPAD_LOG" 2>&1 || true
  have pnpm && log_ok "pnpm ready ($(pnpm --version 2>/dev/null))" || log_warn "pnpm not active yet (open a new shell)"
fi

# --- bun (official installer — avoids tap ambiguity) ------------------------
if have bun; then
  log_ok "bun present ($(bun --version 2>/dev/null))"
else
  log_info "installing bun…"
  curl -fsSL https://bun.sh/install | bash >>"$LAUNCHPAD_LOG" 2>&1 || log_warn "bun install failed (see ${LAUNCHPAD_LOG})"
  export BUN_INSTALL="$HOME/.bun"; export PATH="$BUN_INSTALL/bin:$PATH"
  have bun && log_ok "bun installed"
fi

# --- db, tunnels (the container engine lives in 12-containers) ---------------
brew_install supabase stripe postgresql@16 cloudflared
brew_cask ngrok            # NOTE: ngrok moved to a cask (no tap).

# --- Vercel CLI (npm global) ------------------------------------------------
if have npm; then
  if have vercel; then
    log_ok "vercel CLI present"
  else
    npm install -g vercel >>"$LAUNCHPAD_LOG" 2>&1 && log_ok "vercel CLI installed" || log_warn "vercel install failed"
  fi
fi

chmod +x "$LP_ROOT/scripts/add-supabase.sh" "$LP_ROOT/scripts/add-stripe.sh" "$LP_ROOT/scripts/add-vercel.sh" 2>/dev/null || true

log_note "Next, when you need them (one-time, interactive):"
log_note "  • ngrok:    ngrok config add-authtoken <token from dashboard.ngrok.com>"
log_note "  • vercel:   vercel login"
log_note "  • supabase: supabase login"
log_note "  • Postgres: brew services start postgresql@16   (or just use OrbStack)"
log_note "  • Playwright browsers are pre-cached for all projects by the testing module (15-testing)."

log_ok "Web stack complete"
