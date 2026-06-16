#!/usr/bin/env bash
#
# scripts/signin.sh — `launchpad signin`
#
# A guided checklist of the setup's external sign-ins. For each service: ✓ if
# you're set, or the exact action + what it unlocks. It GUIDES — it never signs
# you in for you. Idempotent, read-only, safe to run anytime.

# --- pure formatter (unit-tested) -------------------------------------------
# signin_line <ok 0|1> <service> <action> <unlocks>
signin_line() {
  if [ "$1" = 1 ]; then
    printf '  ✓ %s — ready\n' "$2"
  else
    printf '  • %s — %s   (unlocks: %s)\n' "$2" "$3" "$4"
  fi
}

# --- thin detection wrappers ------------------------------------------------
_gh_ok()      { command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; }
_sentry_ok()  { command -v claude >/dev/null 2>&1 && claude mcp get sentry >/dev/null 2>&1; }
_herenow_ok() { [ -f "$HOME/.herenow/credentials" ] || [ -n "${HERENOW_API_KEY:-}" ]; }
_agent_ok()   { command -v "$1" >/dev/null 2>&1; }

# _yn <cmd...> -> echoes 1 if the command succeeds, else 0
_yn() { if "$@" >/dev/null 2>&1; then echo 1; else echo 0; fi; }

main() {
  local ready=0 total=0 ok
  echo "Sign-in checklist:"

  ok="$(_yn _gh_ok)";            total=$((total+1)); [ "$ok" = 1 ] && ready=$((ready+1))
  signin_line "$ok" "GitHub"   "run gh auth login" "private project backups + the GitHub MCP"

  ok="$(_yn _sentry_ok)";        total=$((total+1)); [ "$ok" = 1 ] && ready=$((ready+1))
  signin_line "$ok" "Sentry"   "type /mcp in claude (then codex/agy) and sign in" "agents read your app's runtime errors"

  ok="$(_yn _herenow_ok)";       total=$((total+1)); [ "$ok" = 1 ] && ready=$((ready+1))
  signin_line "$ok" "here.now" "sign up at here.now and add your key" "permanent published links (anonymous works without)"

  ok="$(_yn _agent_ok claude)";  total=$((total+1)); [ "$ok" = 1 ] && ready=$((ready+1))
  signin_line "$ok" "Claude Code" "run claude and sign in with your Claude account" "the main assistant"

  printf '\n%d of %d ready.\n' "$ready" "$total"
}

if [ "${BASH_SOURCE[0]:-}" = "${0}" ]; then
  set -uo pipefail
  main "$@"
fi
