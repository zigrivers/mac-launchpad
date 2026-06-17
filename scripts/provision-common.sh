#!/usr/bin/env bash
# scripts/provision-common.sh — shared, pure-ish helpers for the launchpad add
# wizards (supabase/stripe/vercel). A LIBRARY: defines functions only, no main.
# Sourced by scripts/add-*.sh and by tests/test-provision.sh.

# is_next_project -> 0 if the CWD is a Next.js project (package.json with a next dep)
is_next_project() {
  [ -f package.json ] || return 1
  grep -qE '"next"[[:space:]]*:' package.json
}

# supabase_url_valid <s> -> 0 if it looks like https://<ref>.supabase.co
supabase_url_valid() {
  case "$1" in *[![:graph:]]*) return 1 ;; esac
  case "$1" in
    https://*.supabase.co|https://*.supabase.co/) return 0 ;;
    *) return 1 ;;
  esac
}

# stripe_test_secret_valid <s> -> 0 only for a TEST-mode secret key
stripe_test_secret_valid() {
  case "$1" in *[![:graph:]]*) return 1 ;; esac
  case "$1" in sk_test_*) return 0 ;; *) return 1 ;; esac
}

# stripe_pub_valid <s> -> 0 only for a TEST-mode publishable key
stripe_pub_valid() {
  case "$1" in *[![:graph:]]*) return 1 ;; esac
  case "$1" in pk_test_*) return 0 ;; *) return 1 ;; esac
}

# env_upsert <file> <key> <val> — add/replace KEY=val (ENVIRON-safe, no escape processing)
env_upsert() {
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

# env_keys <file> -> list KEY names (skip comments/blanks)
env_keys() {
  [ -f "$1" ] || return 0
  awk -F= '/^[[:space:]]*#/ || /^[[:space:]]*$/ {next} /=/ {print $1}' "$1"
}

# scaffold_if_absent <path>  (content on stdin) — write only if the file is absent
scaffold_if_absent() {
  local path="$1"
  if [ -e "$path" ]; then
    cat >/dev/null   # drain stdin
    printf '  exists, skipped: %s\n' "$path"
    return 0
  fi
  [ -d "$(dirname "$path")" ] || mkdir -p "$(dirname "$path")"
  cat > "$path"
  printf '  wrote: %s\n' "$path"
}

# _op_tip — if 1Password is signed in, suggest storing keys there (Add-on 08)
_op_tip() {
  if command -v op >/dev/null 2>&1 && op whoami >/dev/null 2>&1; then
    printf 'tip: with 1Password set up, `launchpad secrets set <NAME>` keeps keys out of .env.local.\n'
  fi
}
