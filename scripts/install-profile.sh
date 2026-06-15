#!/usr/bin/env bash
#
# scripts/install-profile.sh <profile>
#
# Pure-bash profile runner: maps a profile (profiles/<name>.yaml) to module
# scripts and runs them in numeric order, then runs doctor. The core modules
# (00,01,02,03,05) always run; 10/20/30/40 run per the profile's area list.
#
# This is the single source of truth for "install a profile". Both the
# CLAUDE.md orchestrator (an agent) and scripts/test-in-vm.sh (no agent) drive
# the install through here, so the headless VM test exercises the real path.
#
# Set LAUNCHPAD_NONINTERACTIVE=1 to skip steps that need a human (gh login,
# Xcode license) — used by the VM test.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
ROOT="$(cd "$HERE/.." >/dev/null 2>&1 && pwd)"
# shellcheck source=../lib/common.sh
. "$ROOT/lib/common.sh"

profile="${1:-}"
if [ -z "$profile" ]; then
  die "usage: install-profile.sh <web-starter|full-stack|indie-game|ml-lab|everything>"
fi
pf="$ROOT/profiles/${profile}.yaml"
[ -f "$pf" ] || die "Unknown profile '$profile' (no such file: $pf)"

ensure_brew_env
log_step "Mac Launchpad — installing profile: ${profile}"

run_module() {
  local name="$1" path="$ROOT/modules/$1"
  if [ ! -f "$path" ]; then log_warn "missing module: ${name}"; return 0; fi
  log_step "Module: ${name}"
  if bash "$path"; then
    log_ok "module ${name} complete"
  else
    log_warn "module ${name} reported errors (continuing — doctor will catch it)"
  fi
}

# --- core modules: every profile ---
for m in 00-foundation.sh 01-shell.sh 02-terminal.sh 03-editors.sh 05-agents.sh 06-skills.sh; do
  run_module "$m"
done

# --- profile-selected area modules ---
declare -a selected=()
areas_seen=""
while IFS= read -r area; do
  areas_seen="${areas_seen} ${area}"
  case "$area" in
    web)    selected+=("10-web.sh" "15-testing.sh") ;;  # testing layer rides with web
    mobile) selected+=("20-mobile.sh") ;;
    games)  selected+=("30-games.sh") ;;
    ml)     selected+=("40-ml.sh") ;;
    "")     ;;
    *)      log_warn "unknown area '${area}' in ${pf}" ;;
  esac
done < <(grep -E '^[[:space:]]*-[[:space:]]+[A-Za-z]' "$pf" \
         | sed -E 's/^[[:space:]]*-[[:space:]]*//; s/[[:space:]]*#.*$//; s/[[:space:]]*$//')
# Exported so 15-testing.sh knows whether mobile e2e (Maestro) is in scope.
export LAUNCHPAD_AREAS="${areas_seen}"

if [ "${#selected[@]}" -gt 0 ]; then
  # NB: stock macOS ships bash 3.2 (no `mapfile`), so build the array by hand.
  ordered=()
  while IFS= read -r m; do
    [ -n "$m" ] && ordered+=("$m")
  done < <(printf '%s\n' "${selected[@]}" | sort -u)
  for m in "${ordered[@]}"; do
    run_module "$m"
  done
fi

# --- health check ---
log_step "Verifying the install (doctor)"
if bash "$ROOT/lib/doctor.sh" "$profile"; then
  log_ok "doctor: all green for profile '${profile}'"
else
  log_warn "doctor found issues — review the red lines above and re-run."
fi
