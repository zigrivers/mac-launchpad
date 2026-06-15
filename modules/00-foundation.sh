#!/usr/bin/env bash
#
# 00-foundation — git, GitHub CLI, Node (via fnm), the modern CLI toolkit, the
# coding font, and the ~/Developer workspace. Runs for every profile.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=../lib/common.sh
. "$HERE/../lib/common.sh"
ensure_brew_env

log_step "00 · Foundation"

# --- git + the CLI toolkit --------------------------------------------------
brew_install git gh ripgrep fd bat eza fzf jq tree wget htop starship mas 1password-cli fnm

# --- shared git config (non-destructively included from ~/.gitconfig) --------
gitcfg_dir="$HOME/.config/git"
ensure_dir "$gitcfg_dir"
cp -f "$LP_ROOT/config/git/gitconfig" "$gitcfg_dir/launchpad.gitconfig"
if [ ! -f "$gitcfg_dir/ignore" ]; then
  cat > "$gitcfg_dir/ignore" <<'IGN'
.DS_Store
.env
.env.local
node_modules/
dist/
build/
.venv/
__pycache__/
*.log
IGN
fi
if ! git config --global --get-all include.path 2>/dev/null | grep -qx "$gitcfg_dir/launchpad.gitconfig"; then
  git config --global --add include.path "$gitcfg_dir/launchpad.gitconfig"
  log_ok "linked shared git config via ~/.gitconfig include"
else
  log_ok "shared git config already included"
fi
# Set an identity only if none exists yet (derive from GitHub; never overwrite).
if ! git config --global user.name >/dev/null 2>&1; then
  ghname="$(gh api user --jq .login 2>/dev/null || true)"
  if [ -n "$ghname" ]; then
    git config --global user.name "$ghname"
    git config --global user.email "${ghname}@users.noreply.github.com"
    log_ok "set git identity to '${ghname}' (change with: git config --global user.email you@example.com)"
  else
    log_note "git identity not set yet — will be set once GitHub is authenticated"
  fi
fi

# --- GitHub authentication --------------------------------------------------
if gh auth status >/dev/null 2>&1; then
  log_ok "GitHub CLI already authenticated"
elif is_interactive; then
  log_info "Opening GitHub login — choose HTTPS and log in via the browser."
  gh auth login || log_warn "gh auth login did not complete; re-run later with 'gh auth login'"
else
  log_warn "GitHub not authenticated and running non-interactively — skipping (run 'gh auth login' later)"
fi

# --- Node via fnm (LTS, set as default) -------------------------------------
if have fnm; then
  eval "$(fnm env)" 2>/dev/null || true
  if fnm install --lts >>"$LAUNCHPAD_LOG" 2>&1; then
    lts_ver="$(fnm ls 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | sort -V | tail -1)"
    if [ -n "$lts_ver" ]; then
      fnm default "$lts_ver" >>"$LAUNCHPAD_LOG" 2>&1 || true
      fnm use "$lts_ver" >>"$LAUNCHPAD_LOG" 2>&1 || true
      log_ok "Node ${lts_ver} (LTS) installed and set as default"
    fi
    # corepack ships with Node — enables pnpm/yarn shims.
    have corepack && corepack enable >>"$LAUNCHPAD_LOG" 2>&1 || true
  else
    log_warn "fnm could not install Node LTS (see ${LAUNCHPAD_LOG})"
  fi
fi

# --- coding font ------------------------------------------------------------
brew_cask font-jetbrains-mono-nerd-font

# --- Antigravity CLI (agy) — third core agent, installed for every profile --
export PATH="$HOME/.local/bin:$PATH"
if command -v agy >/dev/null 2>&1; then
  log_ok "Antigravity CLI present ($(command -v agy))"
else
  log_info "installing Antigravity CLI (agy)…"
  curl -fsSL https://antigravity.google/cli/install.sh | bash >>"$LAUNCHPAD_LOG" 2>&1 \
    && log_ok "agy installed (~/.local/bin/agy)" \
    || log_warn "agy install failed (see ${LAUNCHPAD_LOG})"
fi
# Google Chrome — Antigravity uses it for Google sign-in + its browser tools.
brew_cask google-chrome

# --- workspace --------------------------------------------------------------
ensure_dir "$DEVELOPER_DIR"
if [ ! -f "$DEVELOPER_DIR/.env.template" ]; then
  cat > "$DEVELOPER_DIR/.env.template" <<'ENV'
# Copy this to ".env" inside a project and fill in real values.
# NEVER commit a real .env file — it's git-ignored for you.
#
# ANTHROPIC_API_KEY=
# OPENAI_API_KEY=
# DATABASE_URL=
# SUPABASE_URL=
# SUPABASE_ANON_KEY=
ENV
  log_ok "created ${DEVELOPER_DIR}/.env.template"
fi

log_ok "Foundation complete"
