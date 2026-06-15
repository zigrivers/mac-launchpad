#!/usr/bin/env bash
#
# scripts/harden-project.sh <dir> [--no-remote]
#
# Turn a project folder into a SAFE, BACKED-UP project. Idempotent — safe to run
# on a brand-new folder or an existing one. Does, in order:
#   1. git init (if needed) + a sensible project .gitignore
#   2. drop in the secret-scanning pre-commit hook + Biome config
#   3. `pre-commit install` so the hooks fire on every commit
#   4. an initial commit (if the repo has none yet)
#   5. a PRIVATE GitHub repo + initial push (real off-machine backup), unless
#      --no-remote or GitHub isn't logged in
#   6. GitHub push protection where it's free (public repos); skips quietly on
#      the HTTP 422 you get on a free private repo
#
# Both `launchpad new` and the `mkproj` shell helper call this, so every project
# — even ones an agent spins up — gets the same safety net.

set -uo pipefail
export LP_QUIET=1   # read by common.sh to suppress its load note
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
ROOT="$(cd "$HERE/.." >/dev/null 2>&1 && pwd)"
# shellcheck source=../lib/common.sh
. "$ROOT/lib/common.sh"

dir=""
want_remote=1
for arg in "$@"; do
  case "$arg" in
    --no-remote) want_remote=0 ;;
    -*) log_warn "harden-project: unknown flag '$arg'" ;;
    *) dir="$arg" ;;
  esac
done
[ -n "$dir" ] || die "usage: harden-project.sh <dir> [--no-remote]"
[ -d "$dir" ] || die "no such directory: $dir"
cd "$dir" || die "cannot enter: $dir"
proj_name="$(basename "$(pwd)")"

log_step "Securing '${proj_name}'"

# --- 1. git + a project .gitignore (the global one covers most; this is a
#        friendly, visible reminder inside the repo) ---------------------------
if [ ! -d .git ]; then
  git init -q
  log_ok "git initialised (an unlimited undo button for this project)"
fi
if [ ! -f .gitignore ]; then
  cat > .gitignore <<'IGN'
# Secrets live in .env — it is ignored here AND in your global gitignore.
.env
.env.*
!.env.example
# Dependencies & build output (regenerated, never committed)
node_modules/
dist/
build/
.next/
.expo/
coverage/
.DS_Store
*.log
IGN
  log_ok "wrote .gitignore"
fi

# --- 2. secret-scanning hook + formatter config ------------------------------
if [ ! -f .pre-commit-config.yaml ]; then
  cp -f "$ROOT/config/safety/.pre-commit-config.yaml" .pre-commit-config.yaml
  log_ok "added secret-scanning pre-commit hooks (.pre-commit-config.yaml)"
fi
if [ ! -f biome.json ]; then
  cp -f "$ROOT/config/dx/biome.json" biome.json
  log_ok "added Biome formatter config (biome.json)"
fi

# --- 3. install the hooks so they run on every commit ------------------------
if have pre-commit; then
  pre-commit install >>"$LAUNCHPAD_LOG" 2>&1 \
    && log_ok "pre-commit hooks installed (gitleaks + Biome + tests run on commit)" \
    || log_warn "could not install pre-commit hooks (see ${LAUNCHPAD_LOG})"
else
  log_warn "pre-commit not found — run 08-safety.sh, then re-harden this project"
fi

# --- 4. an initial commit, if there are none yet -----------------------------
if ! git rev-parse HEAD >/dev/null 2>&1; then
  git add -A
  # The format hook may rewrite files on this first commit; if so, re-stage and
  # retry WITH the hooks. We never use --no-verify — that would bypass the secret
  # scan, and a fresh checkpoint is exactly when you want that scan to run.
  if git commit -q -m "init: project checkpoint" >>"$LAUNCHPAD_LOG" 2>&1; then
    log_ok "made the first checkpoint (commit)"
  else
    git add -A
    if git commit -q -m "init: project checkpoint" >>"$LAUNCHPAD_LOG" 2>&1; then
      log_ok "made the first checkpoint (commit)"
    else
      log_warn "the first commit was blocked by a safety gate — likely a secret or a failing test (see ${LAUNCHPAD_LOG})"
    fi
  fi
fi

# --- 5. private GitHub repo + off-machine backup -----------------------------
if [ "$want_remote" = "1" ]; then
  if ! have gh; then
    log_note "GitHub CLI not installed — skipping the off-machine backup."
  elif ! gh auth status >/dev/null 2>&1; then
    log_warn "Not logged in to GitHub — skipping the private backup repo."
    log_note "Run 'gh auth login', then: launchpad harden \"$(pwd)\""
  elif git remote get-url origin >/dev/null 2>&1; then
    log_ok "already has a GitHub remote ('origin') — pushing latest"
    git push -u origin HEAD >>"$LAUNCHPAD_LOG" 2>&1 || log_warn "push failed (see ${LAUNCHPAD_LOG})"
  else
    log_info "Creating a PRIVATE GitHub repo '${proj_name}' and pushing (your backup)…"
    if gh repo create "$proj_name" --private --source=. --remote=origin --push >>"$LAUNCHPAD_LOG" 2>&1; then
      log_ok "backed up to a private GitHub repo (private by default — your code stays yours)"
      # Bonus: server-side push protection. Free on public repos only; a free
      # PRIVATE repo returns HTTP 422 — that's expected, not an error.
      owner="$(gh api user --jq .login 2>/dev/null || true)"
      if [ -n "$owner" ]; then
        if gh api --method PATCH "/repos/${owner}/${proj_name}" --input - >>"$LAUNCHPAD_LOG" 2>&1 <<'JSON'
{ "security_and_analysis": {
    "secret_scanning": { "status": "enabled" },
    "secret_scanning_push_protection": { "status": "enabled" } } }
JSON
        then
          log_ok "enabled GitHub push protection (server-side secret scanning)"
        else
          log_note "GitHub push protection isn't available on a free private repo — your local gitleaks hook is the real defence."
        fi
      fi
    else
      log_warn "could not create the GitHub repo (see ${LAUNCHPAD_LOG}) — your work is still saved locally"
    fi
  fi
fi

log_ok "'${proj_name}' is safe: checkpoints on, secrets scanned, backed up where possible"
