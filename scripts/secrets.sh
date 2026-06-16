#!/usr/bin/env bash
#
# scripts/secrets.sh [status | set NAME | inject | run -- CMD...]
#
# launchpad secrets — optional 1Password (op) wiring with a .env.local fallback.
# Signed in to op: store/read secrets in a 1Password vault + a committed,
# secret-free .env.tpl of op:// references. Not signed in (the default): degrade
# to a plain .env.local file with a one-line note. Never blocks, never errors loud.

LP_CFG="${LP_CFG:-$HOME/.config/launchpad}"

# Add or replace a KEY=RHS line in a dotenv-style file (idempotent, order-preserving).
_kv_upsert() { # _kv_upsert <file> <key> <rhs>
  local file="$1" key="$2" rhs="$3" tmp
  [ -d "$(dirname "$file")" ] || mkdir -p "$(dirname "$file")"
  tmp="$(mktemp)"
  if [ -f "$file" ] && grep -qE "^${key}=" "$file"; then
    # Pass key/value via the environment (ENVIRON[]) rather than -v, which would
    # process C-style escapes and corrupt secret values containing backslashes.
    K="$key" V="$rhs" awk 'BEGIN{FS="="} $1==ENVIRON["K"]{print ENVIRON["K"]"="ENVIRON["V"]; next} {print}' "$file" >"$tmp"
  else
    [ -f "$file" ] && cat "$file" >"$tmp"
    printf '%s=%s\n' "$key" "$rhs" >>"$tmp"
  fi
  mv "$tmp" "$file"
}

# Brace-wrap op:// refs so `op inject` (wants {{ op://… }}) can read a file written
# in the `op run` env-file format (KEY=op://…). stdin -> stdout. Non-op lines pass through.
_bracewrap() { sed -E 's#^([A-Za-z_][A-Za-z0-9_]*)=(op://[^[:space:]]+)[[:space:]]*$#\1={{ \2 }}#'; }

# op is usable when installed AND signed in (op whoami exits 0 only when authed).
_op_ready() { command -v op >/dev/null 2>&1 && op whoami >/dev/null 2>&1; }

_vault() { # configured vault name (default Launchpad)
  local f="$LP_CFG/secrets.conf"
  if [ -f "$f" ]; then
    # shellcheck disable=SC1090
    ( . "$f" 2>/dev/null; printf '%s' "${SECRETS_VAULT:-Launchpad}" )
  else
    printf 'Launchpad'
  fi
}

_project() { basename "$(pwd)"; }   # 1Password item title = project dir name

secrets_status() {
  if _op_ready; then
    printf '1Password mode (vault: %s)\n' "$(_vault)"
    if [ -f .env.tpl ]; then
      printf '  .env.tpl: %s reference(s)\n' "$(grep -cE '=op://' .env.tpl 2>/dev/null)"
    fi
  else
    printf '.env.local mode (1Password not set up — that is fine)\n'
    printf '  to turn on 1Password later: run `op signin`, then `launchpad secrets`.\n'
  fi
}

# Read a secret value: hidden prompt when interactive, else one line from stdin (tests/agents).
_read_value() { # _read_value <name> -> echoes value
  local name="$1" val
  if [ -t 0 ]; then printf 'Value for %s (hidden): ' "$name" >&2; read -rs val; printf '\n' >&2
  else read -r val; fi
  printf '%s' "$val"
}

secrets_set() {
  local name="${1:-}" val
  case "$name" in
    ''|*[!A-Za-z0-9_]*) echo "usage: launchpad secrets set NAME   (NAME = letters/digits/underscore)"; return 1 ;;
  esac
  val="$(_read_value "$name")"
  [ -n "$val" ] || { echo "no value given; nothing stored."; return 1; }
  if _op_ready; then
    local vault proj; vault="$(_vault)"; proj="$(_project)"
    op vault get "$vault" >/dev/null 2>&1 || op vault create "$vault" >/dev/null 2>&1 || true
    # Accepted trade-off (spec): the value is passed as a CLI arg to `op item`, so
    # it's briefly visible in the local process table. Fine for a single-user Mac on
    # the sign-in-gated path; switch to a JSON template via stdin if ever hardened.
    if op item get "$proj" --vault "$vault" >/dev/null 2>&1; then
      op item edit "$proj" --vault "$vault" "${name}[password]=${val}" >/dev/null 2>&1
    else
      op item create --category=login --title="$proj" --vault "$vault" "${name}[password]=${val}" >/dev/null 2>&1
    fi
    _kv_upsert .env.tpl "$name" "op://${vault}/${proj}/${name}"
    echo "stored ${name} in 1Password (vault: ${vault}); referenced in .env.tpl"
  else
    _kv_upsert .env.local "$name" "$val"
    echo "saved ${name} to .env.local (1Password not set up). Sign in + re-run to move it into 1Password."
  fi
}

secrets_inject() {
  if ! _op_ready; then
    echo "1Password not set up — your values are already in .env.local (nothing to inject)."
    return 0
  fi
  [ -f .env.tpl ] || { echo "no .env.tpl here — add references with 'launchpad secrets set NAME'."; return 0; }
  local tmp; tmp="$(mktemp)"
  if _bracewrap < .env.tpl | op inject >"$tmp" 2>/dev/null; then
    mv "$tmp" .env.local
    echo "wrote .env.local from .env.tpl via 1Password (kept out of git)."
  else
    rm -f "$tmp"; echo "could not inject from 1Password — is op signed in? (.env.local unchanged)"; return 1
  fi
}

secrets_run() {
  [ "${1:-}" = "--" ] && shift
  [ "$#" -gt 0 ] || { echo "usage: launchpad secrets run -- <command> [args...]"; return 1; }
  if _op_ready && [ -f .env.tpl ]; then
    exec op run --env-file=.env.tpl -- "$@"
  else
    exec "$@"
  fi
}

main() {
  local sub="${1:-status}"; [ "$#" -gt 0 ] && shift || true
  case "$sub" in
    status) secrets_status ;;
    set)    secrets_set "$@" ;;
    inject) secrets_inject ;;
    run)    secrets_run "$@" ;;
    -h|--help|help) echo "launchpad secrets — status | set NAME | inject | run -- CMD" ;;
    *) echo "launchpad secrets — status | set NAME | inject | run -- CMD"; return 1 ;;
  esac
}

if [ "${BASH_SOURCE[0]:-}" = "${0}" ]; then
  set -uo pipefail
  main "$@"
fi
