#!/usr/bin/env bash
#
# scripts/sentry-setup.sh — `launchpad sentry-setup [--dsn <dsn>] [--wizard]`
#
# Write a Sentry DSN into the current project's .env.local so the pre-wired
# @sentry/nextjs starts reporting errors. The DSN comes from --dsn, the
# SENTRY_DSN env var, or an interactive paste. `--wizard` runs the vendor
# wizard. The "automatic" path is an AGENTS.md agent recipe (the agent fetches
# the DSN via its Sentry MCP, then calls this with --dsn) — a shell can't call MCP.

# --- pure helpers (unit-tested) ---------------------------------------------
# sentry_dsn_valid <string> -> 0 if it looks like a Sentry DSN (https://<key>@<host>sentry.io/<id>)
sentry_dsn_valid() {
  case "$1" in
    https://*@*sentry.io/[0-9]*) return 0 ;;
    *) return 1 ;;
  esac
}

# _env_upsert <file> <key> <val> — add or replace KEY=val (ENVIRON[] => backslash-safe)
_env_upsert() {
  local file="$1" key="$2" val="$3" tmp
  [ -d "$(dirname "$file")" ] || mkdir -p "$(dirname "$file")"
  tmp="$(mktemp)"
  if [ -f "$file" ] && grep -qE "^${key}=" "$file"; then
    K="$key" V="$val" awk 'BEGIN{FS="="} $1==ENVIRON["K"]{print ENVIRON["K"]"="ENVIRON["V"]; next} {print}' "$file" >"$tmp"
  else
    [ -f "$file" ] && cat "$file" >"$tmp"
    printf '%s=%s\n' "$key" "$val" >>"$tmp"
  fi
  mv "$tmp" "$file"
}

# sentry_env_upsert <file> <dsn> — write both keys the template reads
sentry_env_upsert() {
  _env_upsert "$1" NEXT_PUBLIC_SENTRY_DSN "$2"
  _env_upsert "$1" SENTRY_DSN "$2"
}

main() {
  local dsn="" wizard=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --dsn)     dsn="${2:-}"; shift 2 ;;
      --dsn=*)   dsn="${1#*=}"; shift ;;
      --wizard)  wizard=1; shift ;;
      -h|--help) echo "usage: launchpad sentry-setup [--dsn <dsn>] [--wizard]"; return 0 ;;
      *)         shift ;;
    esac
  done

  if [ "$wizard" = 1 ]; then exec npx @sentry/wizard@latest -i nextjs; fi

  [ -n "$dsn" ] || dsn="${SENTRY_DSN:-}"
  if [ -z "$dsn" ]; then
    [ -t 0 ] && printf 'Paste your Sentry DSN (from sentry.io): ' >&2
    read -r dsn
  fi
  if ! sentry_dsn_valid "$dsn"; then
    echo "that doesn't look like a Sentry DSN (expected https://…@…sentry.io/<id>). Nothing written." >&2
    return 1
  fi
  sentry_env_upsert .env.local "$dsn"
  echo "wrote NEXT_PUBLIC_SENTRY_DSN + SENTRY_DSN to .env.local — error reporting is on."
  if command -v op >/dev/null 2>&1 && op whoami >/dev/null 2>&1; then
    echo "tip: 'launchpad secrets set SENTRY_DSN' to keep it in 1Password instead."
  fi
}

if [ "${BASH_SOURCE[0]:-}" = "${0}" ]; then
  set -uo pipefail
  main "$@"
fi
