#!/usr/bin/env bash
#
# scripts/spend-check.sh [--summary]
#
# Spend guardrail: notify on a spending SPIKE (today >= ~2x the trailing 7-day
# daily average, above a $1 floor) and on an optional MONTHLY BUDGET
# (~/.config/launchpad/limits -> MONTHLY_BUDGET_USD). Run daily by a launchd
# agent; `--summary` prints today / month-to-date for `launchpad spend`.
# Reads usage read-only via ccusage; never errors out loud (no false alarms).

LP_CFG="${LP_CFG:-$HOME/.config/launchpad}"
SPIKE_FLOOR="${LP_SPIKE_FLOOR:-1.0}"   # don't alert on near-zero days

# spend_decide <today_cost> <avg7> <mtd> <budget>  -> echoes: [spike] [budget80|budget100]
# Pure function (only uses awk for float compares). No I/O. Unit-tested.
spend_decide() {
  local today="$1" avg7="$2" mtd="$3" budget="$4" out=""
  if awk -v t="$today" -v a="$avg7" -v f="$SPIKE_FLOOR" 'BEGIN{exit !(t>=2*a && t>=f)}'; then
    out="spike"
  fi
  if [ -n "$budget" ] && awk -v b="$budget" 'BEGIN{exit !(b>0)}'; then
    if awk -v m="$mtd" -v b="$budget" 'BEGIN{exit !(m>=b)}'; then
      out="${out:+$out }budget100"
    elif awk -v m="$mtd" -v b="$budget" 'BEGIN{exit !(m>=0.8*b)}'; then
      out="${out:+$out }budget80"
    fi
  fi
  printf '%s' "$out"
}

# launchd starts us with a minimal PATH (/usr/bin:/bin:/usr/sbin:/sbin), so
# npx/node (Homebrew + the fnm-managed Node) aren't visible. Bring them onto PATH
# the same way lib/doctor.sh does, so the scheduled run can reach ccusage.
_spend_path_bootstrap() {
  export PATH="$HOME/.local/bin:$HOME/.bun/bin:/opt/homebrew/bin:$PATH"
  if command -v fnm >/dev/null 2>&1; then
    eval "$(fnm env 2>/dev/null)" 2>/dev/null || true
    fnm use default >/dev/null 2>&1 || true
  fi
}

# Bounded ccusage call — macOS has no `timeout`; kill after 30s so a slow/absent
# network can never hang the daily launchd agent.
_ccusage_daily_json() {
  local out; out="$(mktemp)"
  ( npx -y ccusage@latest daily --json >"$out" 2>/dev/null ) &
  local pid=$!
  ( sleep 30; kill "$pid" 2>/dev/null ) >/dev/null 2>&1 &
  local killer=$!
  wait "$pid" 2>/dev/null
  kill "$killer" 2>/dev/null; wait "$killer" 2>/dev/null
  cat "$out" 2>/dev/null; rm -f "$out"
}

# spend_fetch -> sets globals TODAY_COST, AVG7, MTD (all numeric strings).
# Reads ccusage daily JSON once; derives everything from the daily array.
spend_fetch() {
  TODAY_COST=0; AVG7=0; MTD=0
  command -v jq >/dev/null 2>&1 || return 0
  local json today month
  json="$(_ccusage_daily_json)" || return 0
  [ -n "$json" ] || return 0
  today="$(date +%Y-%m-%d)"; month="$(date +%Y-%m)"
  TODAY_COST="$(printf '%s' "$json" | jq -r --arg d "$today" \
    '[.daily[]? | select(.period==$d) | .totalCost] | add // 0' 2>/dev/null || echo 0)"
  AVG7="$(printf '%s' "$json" | jq -r --arg d "$today" \
    '[.daily[]? | select(.period < $d)] | sort_by(.period) | .[-7:]
     | (map(.totalCost) | add // 0) / ([length,1] | max)' 2>/dev/null || echo 0)"
  MTD="$(printf '%s' "$json" | jq -r --arg m "$month" \
    '[.daily[]? | select(.period|startswith($m)) | .totalCost] | add // 0' 2>/dev/null || echo 0)"
  [ -n "$TODAY_COST" ] || TODAY_COST=0
  [ -n "$AVG7" ] || AVG7=0
  [ -n "$MTD" ] || MTD=0
}

_read_budget() { # echoes MONTHLY_BUDGET_USD or empty
  local f="$LP_CFG/limits"
  [ -f "$f" ] || { printf ''; return 0; }
  # shellcheck disable=SC1090
  ( . "$f" 2>/dev/null; printf '%s' "${MONTHLY_BUDGET_USD:-}" )
}

_notify() { "$HOME/.local/bin/launchpad-notify" "$1" "$2" 2>/dev/null || true; }

main() {
  _spend_path_bootstrap
  spend_fetch
  local budget; budget="$(_read_budget)"

  if [ "${1:-}" = "--summary" ]; then
    printf 'Claude/Codex spend\n  today:        $%s\n  this month:   $%s\n' \
      "$(printf '%.2f' "$TODAY_COST" 2>/dev/null || echo "$TODAY_COST")" \
      "$(printf '%.2f' "$MTD" 2>/dev/null || echo "$MTD")"
    [ -n "$budget" ] && printf '  month budget: $%s\n' "$budget"
    return 0
  fi

  local decision; decision="$(spend_decide "$TODAY_COST" "$AVG7" "$MTD" "$budget")"
  case " $decision " in
    *" spike "*) _notify "Spend spike" "Today ~\$$(printf '%.0f' "$TODAY_COST" 2>/dev/null || echo "$TODAY_COST") vs ~\$$(printf '%.0f' "$AVG7" 2>/dev/null || echo "$AVG7")/day average" ;;
  esac
  case " $decision " in
    *" budget100 "*) _budget_notify 100 "$budget" ;;
    *" budget80 "*)  _budget_notify 80  "$budget" ;;
  esac
}

_budget_notify() { # _budget_notify <pct> <budget>
  local pct="$1" budget="$2" stamp
  stamp="$LP_CFG/.budget-$(date +%Y-%m)-$pct"
  [ -f "$stamp" ] && return 0
  # Stamp first (dedupe per month+threshold). If launchpad-notify is missing this
  # silently suppresses the alert for the month — an acceptable trade (no false alarms).
  mkdir -p "$LP_CFG"; : > "$stamp"
  _notify "Monthly budget ${pct}%" "Spent ~\$$(printf '%.0f' "$MTD" 2>/dev/null || echo "$MTD") of \$${budget} this month"
}

if [ "${BASH_SOURCE[0]:-}" = "${0}" ]; then
  set -uo pipefail
  main "$@"
fi
