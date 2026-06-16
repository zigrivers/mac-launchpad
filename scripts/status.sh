#!/usr/bin/env bash
#
# scripts/status.sh — `launchpad status`
#
# A fast dashboard of every git project directly under ~/Developer. Headline:
# is your work backed up? (clean / unsaved / unpushed / no-remote-yet). Plus a
# best-effort running dev-server port and the last-commit age. Local git only —
# no network — so it stays fast across many repos.

DEV_DIR="${DEVELOPER_DIR:-$HOME/Developer}"

# --- pure helpers (unit-tested) ---------------------------------------------
# status_classify <dirty_count> <ahead_count> <has_remote 0|1> -> "ok|phrase" or "warn|phrase"
status_classify() {
  local dirty="$1" ahead="$2" remote="$3" parts=""
  if [ "$remote" = 0 ]; then printf 'warn|no remote yet'; return 0; fi
  [ "${dirty:-0}" -gt 0 ] 2>/dev/null && parts="${dirty} unsaved"
  [ "${ahead:-0}" -gt 0 ] 2>/dev/null && parts="${parts:+$parts, }${ahead} unpushed"
  if [ -n "$parts" ]; then printf 'warn|%s' "$parts"; else printf 'ok|backed up'; fi
}

# _age <seconds> -> "now" / "5m" / "2h" / "3d"
_age() {
  local s="${1:-0}"
  if   [ "$s" -lt 60 ]    2>/dev/null; then printf 'now'
  elif [ "$s" -lt 3600 ]  2>/dev/null; then printf '%dm' "$((s/60))"
  elif [ "$s" -lt 86400 ] 2>/dev/null; then printf '%dh' "$((s/3600))"
  else printf '%dd' "$((s/86400))"; fi
}

# --- best-effort running dev-server ports (computed ONCE, not per repo) -------
# Echo "cwd<TAB>port" for every listening TCP server. Resolves lsof at most twice
# TOTAL (one listen scan + one cwd scan for all listening pids), so `status` stays
# fast no matter how many repos you have. Empty when lsof is unavailable.
# _join_ports <listen "pid<TAB>port" lines> — reads `lsof -Fpn` cwd records on
# stdin and echoes "cwd<TAB>port" for the listening pids. Passes the (multi-line)
# listen list via ENVIRON, not -v: stock macOS awk rejects a newline in a -v value.
_join_ports() {
  L="$1" awk '
    BEGIN { n=split(ENVIRON["L"], rows, "\n"); for (i=1;i<=n;i++){ split(rows[i], kv, "\t"); if (kv[1]!="") port[kv[1]]=kv[2] } }
    /^p/ { pid=substr($0,2) }
    /^n/ { if (pid in port) print substr($0,2)"\t"port[pid] }'
}

_port_map() {
  command -v lsof >/dev/null 2>&1 || return 0
  local listen pids
  listen="$(lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null \
    | awk 'NR>1{n=split($9,a,":"); if(n>1 && a[n] ~ /^[0-9]+$/) print $2"\t"a[n]}' | sort -u)"
  [ -n "$listen" ] || return 0
  pids="$(printf '%s\n' "$listen" | awk -F'\t' '{print $1}' | sort -u | paste -sd, -)"
  [ -n "$pids" ] || return 0
  lsof -a -p "$pids" -d cwd -Fpn 2>/dev/null | _join_ports "$listen"
}

# _lookup_port <portmap> <repo-abspath> -> the port whose cwd is the repo (or under it)
_lookup_port() {
  printf '%s\n' "$1" | awk -F'\t' -v r="$2" '$1==r || index($1, r"/")==1 {print $2; exit}'
}

# --- render ------------------------------------------------------------------
main() {
  local G='' Y='' D='' R='' B=''
  if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    G=$'\033[32m'; Y=$'\033[33m'; D=$'\033[2m'; R=$'\033[0m'; B=$'\033[1m'
  fi
  [ -d "$DEV_DIR" ] || { echo "no ~/Developer yet — 'mkproj <name>' to start."; return 0; }

  local found=0 repo name dirty ahead remote out sev phrase port ct now age col portmap
  now="$(date +%s)"; portmap="$(_port_map)"
  printf '%s%-20s %-26s %-7s %5s%s\n' "$B" "project" "backup" "running" "age" "$R"
  for repo in "$DEV_DIR"/*/; do
    [ -d "${repo}.git" ] || continue
    repo="${repo%/}"; name="$(basename "$repo")"; found=$((found+1))
    dirty="$(git -C "$repo" status --porcelain 2>/dev/null | grep -c .)"
    if git -C "$repo" rev-parse '@{u}' >/dev/null 2>&1; then
      ahead="$(git -C "$repo" rev-list '@{u}..HEAD' --count 2>/dev/null || echo 0)"
    else ahead=0; fi
    if git -C "$repo" remote 2>/dev/null | grep -q .; then remote=1; else remote=0; fi
    out="$(status_classify "$dirty" "$ahead" "$remote")"; sev="${out%%|*}"; phrase="${out#*|}"
    ct="$(git -C "$repo" log -1 --format=%ct 2>/dev/null || echo "$now")"
    age="$(_age "$((now-ct))")"
    port="$(_lookup_port "$portmap" "$repo")"
    col="$G"; [ "$sev" = warn ] && col="$Y"
    printf '%-20.20s %s%-26s%s %-7s %5s\n' "$name" "$col" "$phrase" "$R" "${port:+:$port}" "$age"
  done
  if [ "$found" = 0 ]; then printf '%sno projects yet — '"'"'mkproj <name>'"'"' to start.%s\n' "$D" "$R"; fi
  return 0
}

if [ "${BASH_SOURCE[0]:-}" = "${0}" ]; then
  set -uo pipefail
  main "$@"
fi
