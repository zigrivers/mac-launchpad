#!/usr/bin/env bash
#
# 15-testing — the testing layer. Installs agent-browser (the agents' live
# browser, driven via the agent-browser skill from 06-skills), pre-caches the
# Playwright browsers so every project shares them, and installs Maestro (mobile
# e2e) only when the mobile profile is selected. Per-project test deps + CI come
# from config/testing/ templates the agents copy into a project.
#
# Runs for app-building profiles (any profile that includes the web area).
#
# Verified 2026-06-15: agent-browser is a Homebrew core formula (`agent-browser
# install` fetches Chrome for Testing); Maestro installs via mobile.dev's curl
# script (NOT `brew install maestro`, which is an unrelated runmaestro.ai tool);
# on macOS Playwright uses plain `npx playwright install` (--with-deps is Linux).

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=../lib/common.sh
. "$HERE/../lib/common.sh"
ensure_brew_env

log_step "15 · Testing (agent-browser, Playwright cache, Maestro)"

have fnm && eval "$(fnm env)" 2>/dev/null && fnm use default >/dev/null 2>&1 || true
export PATH="$HOME/.local/bin:$PATH"

# --- agent-browser: the agents' live browser (Chrome for Testing) -----------
brew_install agent-browser
if have agent-browser; then
  # Downloads Chrome for Testing on first run; idempotent (reuses an existing
  # Chrome/Brave/Playwright browser if it finds one).
  if agent-browser install >>"$LAUNCHPAD_LOG" 2>&1; then
    log_ok "agent-browser ready (Chrome for Testing)"
  else
    log_warn "agent-browser install had issues (see ${LAUNCHPAD_LOG})"
  fi
fi

# --- Playwright browser pre-cache (shared: ~/Library/Caches/ms-playwright) ----
if have npx; then
  log_info "pre-caching Playwright browsers (shared by every project)…"
  if npx -y playwright install >>"$LAUNCHPAD_LOG" 2>&1; then
    log_ok "Playwright browsers cached"
  else
    log_warn "Playwright browser pre-cache had issues (see ${LAUNCHPAD_LOG})"
  fi
fi

# --- Maestro (mobile e2e) — only when the mobile profile is selected ---------
case " ${LAUNCHPAD_AREAS:-} " in
  *" mobile "*)
    if have maestro || [ -x "$HOME/.maestro/bin/maestro" ]; then
      log_ok "Maestro already installed"
    else
      log_info "installing Maestro (mobile e2e; needs JDK 17+, from the mobile module)…"
      curl -fsSL "https://get.maestro.mobile.dev" | bash >>"$LAUNCHPAD_LOG" 2>&1 \
        || log_warn "Maestro install had issues (see ${LAUNCHPAD_LOG})"
    fi
    ensure_line_in_file 'export PATH="$PATH:$HOME/.maestro/bin"' "$HOME/.zshrc"
    [ -x "$HOME/.maestro/bin/maestro" ] && log_ok "Maestro ready (run: maestro test flow.yaml)"
    ;;
esac

log_note "Per-project test setup (Vitest/Playwright/axe/visual/CI) lives in config/testing/ — the agents copy it in."
log_ok "Testing layer complete"
