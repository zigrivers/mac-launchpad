#!/usr/bin/env bash
#
# 08-safety — the safety net. Installs local secret-scanning (gitleaks) and the
# pre-commit framework, and wires a comprehensive GLOBAL gitignore so secrets
# are never even staged. Runs for every profile.
#
# Why this matters: the people using this Mac run three full-autonomy agents and
# can't read a leaked key. The defence is layered and LOCAL-FIRST:
#   1. global gitignore (here)         — secrets never get staged
#   2. gitleaks pre-commit hook         — a commit with a secret is refused
#   3. private GitHub repo per project  — off-machine backup (harden-project.sh)
#   4. GitHub push protection (bonus)   — only free on PUBLIC repos
# The per-project hook + private repo are installed by scripts/harden-project.sh,
# which `launchpad new` and `mkproj` call on every new project.
#
# Verified 2026-06-15: gitleaks 8.30.x (formula `gitleaks`), pre-commit 4.x
# (formula `pre-commit`). GitHub secret-scanning push protection is FREE on
# public repos and NOT available on free private repos (returns HTTP 422).

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=../lib/common.sh
. "$HERE/../lib/common.sh"
ensure_brew_env

log_step "08 · Safety net (secret scanning + backups)"

# --- 1. local secret scanning + the pre-commit framework --------------------
brew_install gitleaks pre-commit

# --- 2. global gitignore (git's core.excludesfile) --------------------------
# Applies to EVERY repo on this Mac, so .env / *.key / SSH keys etc. can never be
# staged by accident. Per-project .gitignore files add to this.
gitignore_global="$HOME/.config/git/ignore.global"
ensure_dir "$HOME/.config/git"
if [ -f "$gitignore_global" ]; then backup_file "$gitignore_global"; fi
cp -f "$LP_ROOT/config/safety/gitignore.global" "$gitignore_global"
current_excludes="$(git config --global --get core.excludesfile 2>/dev/null || true)"
if [ "$current_excludes" != "$gitignore_global" ]; then
  git config --global core.excludesfile "$gitignore_global"
  log_ok "wired global gitignore → ~/.config/git/ignore.global (core.excludesfile)"
else
  log_ok "global gitignore already wired (core.excludesfile)"
fi

# --- 3. make the project-hardener available -----------------------------------
# scripts/harden-project.sh is what turns a bare folder into a safe, backed-up
# project (git + secret-scanning hook + private GitHub repo). It's invoked by
# `launchpad new` and `mkproj`; just make sure it's executable here.
chmod +x "$LP_ROOT/scripts/harden-project.sh" 2>/dev/null || true

log_note "Secret defence is LOCAL-FIRST: the gitleaks pre-commit hook is the real"
log_note "safeguard. GitHub's server-side push protection is a bonus and is only"
log_note "free on PUBLIC repos (free private repos can't use it)."
log_ok "Safety net ready: gitleaks + pre-commit + global gitignore"
