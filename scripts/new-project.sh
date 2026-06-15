#!/usr/bin/env bash
#
# scripts/new-project.sh [template] [name]   (a.k.a. `launchpad new`)
#
# One command from "I have an idea" to "a working, backed-up, tested, safe
# project." Picks a known-good starter template, scaffolds it into ~/Developer,
# runs the safety flow (git + secret-scanning hook + PRIVATE GitHub backup), and
# opens your editor. Agents modify working code far better than blank folders —
# so we always start from something that already runs.
#
# Templates live in templates/<name>/scaffold.sh:
#   web     Next.js + tests + Sentry, runs in your browser (add login/payments later)
#   mobile  Expo (React Native) — runs on your phone via Expo Go, no keys needed
#   game    Phaser + Vite — a browser game that runs instantly
#   blank   an empty, safe, backed-up project

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
ROOT="$(cd "$HERE/.." >/dev/null 2>&1 && pwd)"
export LP_QUIET=1   # read by common.sh to suppress its load note
# shellcheck source=../lib/common.sh
. "$ROOT/lib/common.sh"

template="${1:-}"
name="${2:-}"

prompt_for() { # prompt_for <varname> <question>
  local __var="$1" __q="$2" __ans=""
  printf '%s' "$__q" >&2
  IFS= read -r __ans || true
  printf -v "$__var" '%s' "$__ans"
}

# --- pick a template ---------------------------------------------------------
if [ -z "$template" ]; then
  if ! is_interactive; then
    die "usage: new-project.sh <web|mobile|game|blank> <name>"
  fi
  cat >&2 <<'MENU'

What do you want to build?

  1) web     A website or web app (runs in your browser)
  2) mobile  A phone app (runs on your phone via Expo Go)
  3) game    A browser game (runs instantly)
  4) blank   An empty project (you'll tell the assistant what to build)

MENU
  prompt_for choice "Pick 1-4 (default 1): "
  case "${choice:-1}" in
    1|web) template="web" ;;
    2|mobile) template="mobile" ;;
    3|game) template="game" ;;
    4|blank) template="blank" ;;
    *) template="web" ;;
  esac
fi

case "$template" in
  web|mobile|game|blank) ;;
  *) die "unknown template '$template' (choose: web | mobile | game | blank)" ;;
esac

# --- pick a name -------------------------------------------------------------
if [ -z "$name" ]; then
  is_interactive || die "usage: new-project.sh <template> <name>"
  prompt_for name "Project name (letters, numbers, dashes): "
fi
# sanitise to a safe folder name
name="$(printf '%s' "$name" | tr '[:upper:] ' '[:lower:]-' | tr -cd 'a-z0-9-_' )"
[ -n "$name" ] || die "please give the project a name"

ensure_dir "$DEVELOPER_DIR"
target="$DEVELOPER_DIR/$name"
if [ -e "$target" ]; then
  die "a project called '$name' already exists at $target"
fi

log_step "Creating '${name}' (${template})"

# --- scaffold from the template ---------------------------------------------
if [ "$template" = "blank" ]; then
  ensure_dir "$target"
else
  scaffold="$ROOT/templates/$template/scaffold.sh"
  [ -f "$scaffold" ] || die "missing template scaffold: $scaffold"
  if ! bash "$scaffold" "$target"; then
    log_warn "the template scaffold reported problems — continuing to secure what's there"
    ensure_dir "$target"
  fi
fi

# --- make it safe + backed up ------------------------------------------------
bash "$ROOT/scripts/harden-project.sh" "$target" || log_warn "hardening had issues (see ${LAUNCHPAD_LOG})"

# --- open the editor ---------------------------------------------------------
opened=""
for ed in cursor code subl; do
  if have "$ed"; then "$ed" "$target" >/dev/null 2>&1 && opened="$ed" && break; fi
done

# --- friendly summary --------------------------------------------------------
printf '\n%s✔ %s is ready.%s\n' "${LP_GREEN}" "$name" "${LP_RESET}"
printf '   Location : %s\n' "$target"
[ -n "$opened" ] && printf '   Editor   : opened in %s\n' "$opened"
cat <<NEXT

   Next steps:
     cd "$target"
     # then start an assistant and tell it what to build:
     claude        # or:  codex   /   agy

NEXT
case "$template" in
  web)    printf '   To run it:  npm run dev   (then open the URL it prints)\n' ;;
  mobile) printf '   To run it:  npx expo start   (scan the QR code with Expo Go)\n' ;;
  game)   printf '   To run it:  npm run dev   (opens at http://localhost:8080)\n' ;;
esac
printf '\n'
