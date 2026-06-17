#!/usr/bin/env bash
#
# scripts/add-vercel.sh — `launchpad add vercel`
#
# Link the project to Vercel, push every key from .env.local into the project's
# Production environment, and deploy. `vercel login` is a human step (see the
# AGENTS.md "deploy" recipe). The env-push reads .env.local via env_keys; the
# vercel CLI calls are mocked in tests.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=./provision-common.sh
. "$HERE/provision-common.sh"

main() {
  case "${1:-}" in -h|--help) echo "usage: launchpad add vercel   (run inside your project; deploys to Vercel)"; return 0 ;; esac

  if ! is_next_project; then
    echo "run this inside a Next.js project." >&2; return 1
  fi
  command -v vercel >/dev/null 2>&1 || { echo "the Vercel CLI isn't installed (expected from the web stack)." >&2; return 1; }

  echo "Linking this project to Vercel…"
  vercel link --yes || { echo "vercel link failed (run 'vercel login' first?)." >&2; return 1; }

  if [ -f .env.local ]; then
    echo "Pushing .env.local keys to Vercel (production)…"
    local k v
    while IFS= read -r k; do
      [ -n "$k" ] || continue
      case "$k" in ''|*[!A-Za-z0-9_]*) echo "  skipped (not a valid env name): $k" >&2; continue ;; esac
      v="$(grep -E "^${k}=" .env.local | head -1 | cut -d= -f2-)"
      printf '%s' "$v" | vercel env add "$k" production >/dev/null 2>&1 \
        && echo "  pushed $k" || echo "  (skipped $k — may already exist)"
    done <<EOF
$(env_keys .env.local)
EOF
  fi

  echo "Deploying to production…"
  vercel deploy --prod
}

if [ "${BASH_SOURCE[0]:-}" = "${0}" ]; then
  set -uo pipefail
  main "$@"
fi
