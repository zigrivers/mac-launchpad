# Add-on 07 — Polish & resilience Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add four small, independent resilience/QoL features to Mac Launchpad — pre-warmed commit hooks, a spend guardrail, a backup nudge, and `launchpad doctor --fix` — shipped as one add-on.

**Architecture:** Plain idempotent bash following repo conventions (`lib/common.sh` helpers, `modules/NN-*.sh`, the `launchpad` dispatcher, `doctor.sh` checks). Pure decision logic is factored into source-able functions with **host-runnable bash unit tests** (`tests/`, no new dependency); install/glue/integration behavior is verified by a **VM probe** (`dogfood/remote-addon07.sh`). Everything degrades gracefully when a tool/account is missing.

**Tech Stack:** bash (3.2-compatible), zsh (the user shell, for the `chpwd` hook), `jq`, `awk` (float math), `launchd`, `ccusage` (read-only), `pre-commit`, `git`.

**Spec:** `dogfood/specs/2026-06-15-addon-07-polish-resilience-design.md`. Plan lives in `dogfood/plans/` (not `docs/`, which is the published Pages site).

**ccusage JSON (verified 2026-06-15):** `ccusage daily --json` → `{"daily":[{"period":"YYYY-MM-DD","totalCost":<usd>,…}],"totals":{…}}`. Date = `.period`, cost = `.totalCost`. Month-to-date is derived from the daily array (`select(.period|startswith("YYYY-MM"))`), so no dependency on the monthly subcommand.

---

## File structure

**Create:**
- `tests/lib.sh` — minimal assert helpers for host-runnable unit tests.
- `tests/test-spend.sh` — unit tests for the spend decision logic.
- `tests/test-doctorfix.sh` — unit tests for the doctor section→module map.
- `scripts/spend-check.sh` — spend detector (`spend_decide` pure fn + `--summary` mode + `main`).
- `dogfood/remote-addon07.sh` — VM integration probe for all four features.

**Modify:**
- `modules/08-safety.sh` — pre-warm pre-commit hook envs (Feature 1).
- `modules/09-dx.sh` — install spend-check + load the launchd agent (Feature 2).
- `config/zshrc.append` — `chpwd` backup-nudge hook (Feature 3).
- `scripts/launchpad` — `spend`, `nudge on|off` subcommands; `doctor --fix` passes through (Features 2–4).
- `lib/doctor.sh` — `--fix` mode + section tracking + `_section_modules` map; new soft checks (Features 1,2,3,4).
- `docs/cheatsheet.html`, `docs/getting-started.html`, `docs/troubleshooting.html`, `README.md` — document the new commands.

---

## Task 1: Host test harness

**Files:** Create `tests/lib.sh`

- [ ] **Step 1: Create the assert helper**

```bash
#!/usr/bin/env bash
# tests/lib.sh — minimal assertions for host-runnable bash unit tests.
# Usage: source this, call assert_eq, end with t_done.
_T_FAIL=0
assert_eq() { # assert_eq <actual> <expected> <message>
  if [ "$1" = "$2" ]; then
    printf '  ok   %s\n' "$3"
  else
    printf '  FAIL %s\n        got: [%s]\n     wanted: [%s]\n' "$3" "$1" "$2"; _T_FAIL=1
  fi
}
t_done() { if [ "$_T_FAIL" = 0 ]; then echo "PASS"; exit 0; else echo "FAILED"; exit 1; fi; }
```

- [ ] **Step 2: Verify it parses**

Run: `bash -n tests/lib.sh && echo ok`
Expected: `ok`

- [ ] **Step 3: Commit**

```bash
git add tests/lib.sh
git commit -m "test: add minimal bash assertion helpers"
```

---

## Task 2: Spend decision logic (TDD)

**Files:**
- Create: `scripts/spend-check.sh`
- Test: `tests/test-spend.sh`

- [ ] **Step 1: Write the failing test**

```bash
#!/usr/bin/env bash
# tests/test-spend.sh
cd "$(dirname "$0")/.." || exit 1
. tests/lib.sh
. scripts/spend-check.sh   # sourcing must NOT run main

assert_eq "$(spend_decide 10 2 '' '')"        "spike"      "spike: today >= 2x avg and >= floor"
assert_eq "$(spend_decide 3 2 '' '')"         ""           "no spike: 3 < 2*2"
assert_eq "$(spend_decide 0.5 0.01 '' '')"    ""           "no spike: below \$1 floor"
assert_eq "$(spend_decide 1 0.1 '' '')"       "spike"      "spike: 1 >= 0.2 and >= 1.0 floor"
assert_eq "$(spend_decide 0.5 0.01 50 40)"    "budget100"  "budget100: mtd >= budget"
assert_eq "$(spend_decide 0.5 0.01 35 40)"    "budget80"   "budget80: mtd >= 80% < 100%"
assert_eq "$(spend_decide 0.5 0.01 10 40)"    ""           "no budget alert: mtd < 80%"
assert_eq "$(spend_decide 10 2 50 40)"        "spike budget100" "both spike and budget"
t_done
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/test-spend.sh`
Expected: FAIL — `scripts/spend-check.sh` doesn't exist yet (source error / `spend_decide: command not found`).

- [ ] **Step 3: Create scripts/spend-check.sh with the pure function + a no-op main guard**

```bash
#!/usr/bin/env bash
#
# scripts/spend-check.sh [--summary]
#
# Spend guardrail: notify on a spending SPIKE (today >= ~2x the trailing 7-day
# daily average, above a $1 floor) and on an optional MONTHLY BUDGET
# (~/.config/launchpad/limits -> MONTHLY_BUDGET_USD). Run daily by a launchd
# agent; `--summary` prints today / month-to-date for `launchpad spend`.
# Reads usage read-only via ccusage; never errors out loud (no false alarms).

set -uo pipefail

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

# (fetch + main added in later tasks)

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
fi
```

Note: `main` is referenced in the guard but defined in Task 4. Sourcing (the test) never reaches the guard's body because `BASH_SOURCE[0] != $0`, so the undefined `main` is harmless until Task 4. To keep `bash -n` happy, the guard only *calls* `main`; it doesn't define it.

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/test-spend.sh`
Expected: `PASS` (all 8 assertions ok).

- [ ] **Step 5: Static check + commit**

```bash
bash -n scripts/spend-check.sh && shellcheck -S warning scripts/spend-check.sh tests/test-spend.sh
git add scripts/spend-check.sh tests/test-spend.sh
git commit -m "feat(spend): spike+budget decision logic with unit tests"
```

---

## Task 3: Spend data fetch (ccusage → today/avg7/mtd)

**Files:** Modify `scripts/spend-check.sh` (add `spend_fetch`)

- [ ] **Step 1: Add the fetch function above the `main` guard**

Insert after the `spend_decide` function:

```bash
# spend_fetch -> sets globals TODAY_COST, AVG7, MTD (all numeric strings).
# Reads ccusage daily JSON once; derives everything from the daily array.
spend_fetch() {
  TODAY_COST=0; AVG7=0; MTD=0
  command -v jq >/dev/null 2>&1 || return 0
  local json today month
  json="$(npx -y ccusage@latest daily --json 2>/dev/null)" || return 0
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
```

- [ ] **Step 2: Verify it parses**

Run: `bash -n scripts/spend-check.sh && echo ok`
Expected: `ok`

- [ ] **Step 3: Smoke-test the fetch on this machine (read-only)**

Run: `bash -c '. scripts/spend-check.sh; spend_fetch; echo "today=$TODAY_COST avg7=$AVG7 mtd=$MTD"'`
Expected: three numeric values (e.g. `today=0 avg7=… mtd=…`); no errors. (Values depend on local ccusage data; the point is no crash and numeric output.)

- [ ] **Step 4: Commit**

```bash
git add scripts/spend-check.sh
git commit -m "feat(spend): derive today/avg7/mtd from ccusage daily JSON"
```

---

## Task 4: Spend `main` + `--summary` + notifications

**Files:** Modify `scripts/spend-check.sh` (add `main` + budget reader)

- [ ] **Step 1: Add `main` and the budget reader above the guard**

Insert before the `if [ "${BASH_SOURCE[0]}" = "${0}" ]` guard:

```bash
_read_budget() { # echoes MONTHLY_BUDGET_USD or empty
  local f="$LP_CFG/limits"
  [ -f "$f" ] || { printf ''; return 0; }
  # shellcheck disable=SC1090
  ( . "$f" 2>/dev/null; printf '%s' "${MONTHLY_BUDGET_USD:-}" )
}

_notify() { "$HOME/.local/bin/launchpad-notify" "$1" "$2" 2>/dev/null || true; }

main() {
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
  # budget alerts fire once per threshold per month (stamp file)
  case " $decision " in
    *" budget100 "*) _budget_notify 100 "$budget" ;;
    *" budget80 "*)  _budget_notify 80  "$budget" ;;
  esac
}

_budget_notify() { # _budget_notify <pct> <budget>
  local pct="$1" budget="$2" stamp="$LP_CFG/.budget-$(date +%Y-%m)-$1"
  [ -f "$stamp" ] && return 0
  mkdir -p "$LP_CFG"; : > "$stamp"
  _notify "Monthly budget ${pct}%" "Spent ~\$$(printf '%.0f' "$MTD" 2>/dev/null || echo "$MTD") of \$${budget} this month"
}
```

- [ ] **Step 2: Verify it parses + the test still passes (no regression in `spend_decide`)**

Run: `bash -n scripts/spend-check.sh && bash tests/test-spend.sh`
Expected: `ok`-free parse, then `PASS`.

- [ ] **Step 3: Smoke-test `--summary`**

Run: `bash scripts/spend-check.sh --summary`
Expected: a "Claude/Codex spend" block with today + this month (no crash).

- [ ] **Step 4: Static check + commit**

```bash
shellcheck -S warning scripts/spend-check.sh
chmod +x scripts/spend-check.sh
git add scripts/spend-check.sh
git commit -m "feat(spend): main loop, --summary, spike + monthly-budget notifications"
```

---

## Task 5: Install spend-check + launchd agent (Feature 2 integration)

**Files:** Modify `modules/09-dx.sh`

- [ ] **Step 1: Add a spend-guardrail section before the "put launchpad on PATH" step**

Insert in `modules/09-dx.sh` after the `terminal-notifier` install (and before the `launchpad` symlink step):

```bash
# --- spend guardrail: a daily launchd agent that warns on a spending spike or
#     an optional monthly budget (ccusage is read-only; nothing is uploaded) ---
chmod +x "$LP_ROOT/scripts/spend-check.sh" 2>/dev/null || true
ensure_dir "$HOME/.config/launchpad"
spend_plist="$HOME/Library/LaunchAgents/com.launchpad.spend.plist"
ensure_dir "$HOME/Library/LaunchAgents"
[ -f "$spend_plist" ] && backup_file "$spend_plist"
cat > "$spend_plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.launchpad.spend</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$LP_ROOT/scripts/spend-check.sh</string>
  </array>
  <key>StartCalendarInterval</key><dict><key>Hour</key><integer>18</integer><key>Minute</key><integer>0</integer></dict>
  <key>RunAtLoad</key><false/>
  <key>StandardErrorPath</key><string>$HOME/.config/launchpad/spend.log</string>
  <key>StandardOutPath</key><string>$HOME/.config/launchpad/spend.log</string>
</dict>
</plist>
PLIST
# (re)load idempotently
launchctl bootout "gui/$(id -u)/com.launchpad.spend" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$spend_plist" >/dev/null 2>&1 \
  || launchctl load -w "$spend_plist" >/dev/null 2>&1 || true
log_ok "spend guardrail installed (daily check; warns on a spike — set a budget in ~/.config/launchpad/limits)"
```

- [ ] **Step 2: Verify it parses**

Run: `bash -n modules/09-dx.sh && echo ok`
Expected: `ok`

- [ ] **Step 3: Commit**

```bash
git add modules/09-dx.sh
git commit -m "feat(spend): install + load the daily launchd spend agent (09-dx)"
```

---

## Task 6: Backup nudge — zsh chpwd hook (Feature 3)

**Files:** Modify `config/zshrc.append`

- [ ] **Step 1: Add the hook near the `mkproj` function**

Insert into `config/zshrc.append` (after the `mkproj` function block):

```bash
# --- backup nudge: a quiet, throttled reminder when a ~/Developer project has
#     unsaved or unpushed work. Opt out: touch ~/.config/launchpad/no-nudge ---
typeset -gA _lp_nudged
_lp_backup_nudge() {
  [ -f "$HOME/.config/launchpad/no-nudge" ] && return
  case "$PWD" in "$HOME/Developer"/*) ;; *) return ;; esac
  local root; root="$(git rev-parse --show-toplevel 2>/dev/null)" || return
  [ -n "${_lp_nudged[$root]:-}" ] && return
  local dirty ahead
  dirty="$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
  ahead="$(git rev-list '@{u}..' --count 2>/dev/null || echo 0)"
  if [ "${dirty:-0}" -gt 0 ] || [ "${ahead:-0}" -gt 0 ]; then
    _lp_nudged[$root]=1
    print -P "%F{yellow}·%f ${dirty} unsaved, ${ahead} unpushed here — ask an assistant to \"save a checkpoint and push\"."
  fi
}
chpwd_functions+=(_lp_backup_nudge)
```

- [ ] **Step 2: Verify zsh syntax**

Run: `zsh -n config/zshrc.append && echo ok`
Expected: `ok`

- [ ] **Step 3: Commit**

```bash
git add config/zshrc.append
git commit -m "feat(nudge): throttled chpwd backup nudge for ~/Developer projects"
```

---

## Task 7: `launchpad spend` + `launchpad nudge on|off` (dispatcher)

**Files:** Modify `scripts/launchpad`

- [ ] **Step 1: Add the cases**

In the `case "$cmd" in` block of `scripts/launchpad`, add (before `help|-h|--help`):

```bash
  spend)   exec bash "$ROOT/scripts/spend-check.sh" --summary "$@" ;;
  nudge)
    mkdir -p "$HOME/.config/launchpad"
    case "${1:-}" in
      off) : > "$HOME/.config/launchpad/no-nudge"; echo "backup nudges off." ;;
      on)  rm -f "$HOME/.config/launchpad/no-nudge"; echo "backup nudges on." ;;
      *)   if [ -f "$HOME/.config/launchpad/no-nudge" ]; then echo "backup nudges are OFF (launchpad nudge on)"; else echo "backup nudges are ON (launchpad nudge off)"; fi ;;
    esac ;;
```

Also add `spend` and `nudge` lines to the `usage()` heredoc:

```
  launchpad spend     Show today's + this month's AI spend
  launchpad nudge     Turn the unsaved-work nudge on/off
```

- [ ] **Step 2: Verify it parses + dispatches**

Run: `bash -n scripts/launchpad && bash scripts/launchpad nudge off && bash scripts/launchpad nudge && bash scripts/launchpad nudge on`
Expected: parses; prints "backup nudges off." / "...are OFF..." / "backup nudges on."

- [ ] **Step 3: Commit**

```bash
git add scripts/launchpad
git commit -m "feat: launchpad spend + launchpad nudge on|off"
```

---

## Task 8: doctor section→module map (TDD)

**Files:**
- Test: `tests/test-doctorfix.sh`
- Modify: `lib/doctor.sh` (add `_section_modules`)

- [ ] **Step 1: Write the failing test**

```bash
#!/usr/bin/env bash
# tests/test-doctorfix.sh
cd "$(dirname "$0")/.." || exit 1
. tests/lib.sh
# Source just the mapping function without running doctor: extract & eval it.
eval "$(sed -n '/^_section_modules() {/,/^}/p' lib/doctor.sh)"

assert_eq "$(_section_modules 'Safety net')"           "08-safety.sh"               "safety net -> 08"
assert_eq "$(_section_modules 'Developer experience')" "09-dx.sh"                    "dx -> 09"
assert_eq "$(_section_modules 'Foundation')"           "00-foundation.sh"           "foundation -> 00"
assert_eq "$(_section_modules 'AI agents')"            "05-agents.sh"               "agents -> 05"
assert_eq "$(_section_modules 'Containers (OrbStack)')" "12-containers.sh"          "containers -> 12"
assert_eq "$(_section_modules 'Nonsense')"             ""                            "unknown -> empty"
t_done
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/test-doctorfix.sh`
Expected: FAIL — `_section_modules` not found in `lib/doctor.sh` yet.

- [ ] **Step 3: Add `_section_modules` to lib/doctor.sh**

Insert near the top of `lib/doctor.sh` (after the `softck` definition):

```bash
# Map a doctor section header to the module(s) that own it (for --fix).
_section_modules() {
  case "$1" in
    "Foundation") echo "00-foundation.sh" ;;
    "Shell & terminal") echo "01-shell.sh 02-terminal.sh" ;;
    "Editors") echo "03-editors.sh" ;;
    "AI agents") echo "05-agents.sh" ;;
    "Skills & workflow") echo "06-skills.sh" ;;
    "Safety net") echo "08-safety.sh" ;;
    "Developer experience") echo "09-dx.sh" ;;
    "Web stack"|"Testing layer") echo "10-web.sh 15-testing.sh" ;;
    "Containers (OrbStack)") echo "12-containers.sh" ;;
    "Mobile stack") echo "20-mobile.sh" ;;
    "Games stack") echo "30-games.sh" ;;
    "ML stack") echo "40-ml.sh" ;;
    *) echo "" ;;
  esac
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/test-doctorfix.sh`
Expected: `PASS`.

- [ ] **Step 5: Commit**

```bash
git add tests/test-doctorfix.sh lib/doctor.sh
git commit -m "feat(doctor): section->module map with unit tests"
```

---

## Task 9: doctor `--fix` mode

**Files:** Modify `lib/doctor.sh`

- [ ] **Step 1: Track failed sections — set CURRENT_SECTION in hdr, record in _no**

In `lib/doctor.sh`, change `hdr()` and `_no()`:

```bash
hdr()  { CURRENT_SECTION="$*"; printf '\n%s%s%s\n' "$LP_BOLD" "$*" "$LP_RESET"; }
_no()  { printf '   %s✘%s %s\n' "$LP_RED" "$LP_RESET" "$*"; FAIL=$((FAIL+1));
         case " ${FAILED_SECTIONS:-} " in *" ${CURRENT_SECTION} "*) ;; *) FAILED_SECTIONS="${FAILED_SECTIONS:-} ${CURRENT_SECTION}";; esac; }
```

And initialize near the `PASS=0; FAIL=0; WARN=0` line:

```bash
PASS=0; FAIL=0; WARN=0; FAILED_SECTIONS=""; CURRENT_SECTION=""
```

- [ ] **Step 2: Parse `--fix` and run the repair after the tally**

Change the profile parsing near the top:

```bash
profile=""; FIX=0
for a in "$@"; do case "$a" in --fix) FIX=1 ;; -*) ;; *) profile="$a" ;; esac; done
```

Then, just before the final `exit` logic (after the `== N passed… ==` summary print), insert:

```bash
if [ "$FIX" = "1" ] && [ "$FAIL" -gt 0 ]; then
  printf '\n%s==> doctor --fix: repairing %d failed check(s)…%s\n' "$LP_BLUE" "$FAIL" "$LP_RESET"
  _mods=""
  # FAILED_SECTIONS holds the section headers that had a red, space-joined.
  # Iterate the known headers; collect each failed one's module(s), deduped.
  for _name in "Foundation" "Shell & terminal" "Editors" "AI agents" "Skills & workflow" "Safety net" "Developer experience" "Web stack" "Testing layer" "Containers (OrbStack)" "Mobile stack" "Games stack" "ML stack"; do
    case " $FAILED_SECTIONS " in *" $_name "*)
      for _m in $(_section_modules "$_name"); do
        case " $_mods " in *" $_m "*) ;; *) _mods="$_mods $_m" ;; esac
      done ;;
    esac
  done
  for _m in $_mods; do
    [ -f "$LP_ROOT/modules/$_m" ] && { printf '   re-running %s…\n' "$_m"; bash "$LP_ROOT/modules/$_m" >/dev/null 2>&1 || true; }
  done
  printf '%s==> re-checking…%s\n' "$LP_BLUE" "$LP_RESET"
  exec bash "$LP_ROOT/lib/doctor.sh" ${profile:+"$profile"}
fi
```

- [ ] **Step 3: Verify it parses + doctor still runs normally**

Run: `bash -n lib/doctor.sh && bash lib/doctor.sh >/dev/null 2>&1; echo "exit=$?"`
Expected: parses; runs (exit 0 or 1 depending on local state — just no syntax/runtime crash).

- [ ] **Step 4: Confirm `--fix` parses + runs with the flag**

Run: `bash lib/doctor.sh --fix >/dev/null 2>&1; echo "exit=$?"`
Expected: runs without crashing (on a fully-green machine it prints the tally and exits; the red-repair path is exercised in the VM probe, Task 11).

- [ ] **Step 5: Commit**

```bash
shellcheck -S warning lib/doctor.sh
git add lib/doctor.sh
git commit -m "feat(doctor): --fix re-runs the modules owning failed sections, then re-checks"
```

---

## Task 10: doctor checks for the four features + dispatcher passthrough

**Files:** Modify `lib/doctor.sh` (new checks); confirm `scripts/launchpad` passes `--fix`.

- [ ] **Step 1: Add soft checks in the "Safety net" section (Feature 1)**

In `lib/doctor.sh`, in the `hdr "Safety net"` block, append:

```bash
softck "pre-commit hooks pre-warmed" 'test -n "$(ls -A "$HOME/.cache/pre-commit" 2>/dev/null)"'
```

- [ ] **Step 2: Add checks in the "Developer experience" section (Features 2,3)**

In the `hdr "Developer experience"` block, append:

```bash
check  "spend-check script"          'test -x "$LP_ROOT/scripts/spend-check.sh"'
softck "spend guardrail (launchd)"   'launchctl list 2>/dev/null | grep -q com.launchpad.spend'
check  "backup nudge (zsh hook)"     'grep -q "_lp_backup_nudge" "$HOME/.zshrc"'
```

- [ ] **Step 3: Confirm the dispatcher already forwards `--fix`**

Read `scripts/launchpad`: the `doctor)` case is `exec bash "$ROOT/lib/doctor.sh" "$@"`, so `launchpad doctor --fix` already works. If not present, make it so. No code change expected.

- [ ] **Step 4: Verify + commit**

```bash
bash -n lib/doctor.sh && shellcheck -S warning lib/doctor.sh
git add lib/doctor.sh
git commit -m "feat(doctor): checks for pre-warm cache, spend agent, backup nudge"
```

---

## Task 11: VM integration probe (all four features)

**Files:** Create `dogfood/remote-addon07.sh`

- [ ] **Step 1: Write the probe (runs inside a VM, reads the repo from the share)**

```bash
#!/usr/bin/env bash
# dogfood/remote-addon07.sh — VM integration probe for Add-on 07.
set -o pipefail
HERE="$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)"
ROOT="$(cd "$HERE/.." >/dev/null 2>&1 && pwd)"
export LAUNCHPAD_NONINTERACTIVE=1 LAUNCHPAD_SKIP_CLONE=1
export PATH="$HOME/.local/bin:/opt/homebrew/bin:$PATH"

echo "##### BOOTSTRAP #####"; /bin/bash "$ROOT/bootstrap.sh"
echo "##### INSTALL (00,01,08,09) #####"
for m in 00-foundation 01-shell 08-safety 09-dx; do echo "-- $m --"; /bin/bash "$ROOT/modules/$m.sh"; done
command -v fnm >/dev/null 2>&1 && eval "$(fnm env 2>/dev/null)" && fnm use default >/dev/null 2>&1

# F1: pre-commit cache warmed by 08-safety
[ -n "$(ls -A "$HOME/.cache/pre-commit" 2>/dev/null)" ] && echo "PROBE:prewarm=PASS" || echo "PROBE:prewarm=FAIL"

# F2: spend-check runs + --summary prints; decision logic via unit test
( cd "$ROOT" && bash tests/test-spend.sh >/tmp/ts.out 2>&1 ) && echo "PROBE:spend_unit=PASS" || { echo "PROBE:spend_unit=FAIL"; tail -5 /tmp/ts.out; }
bash "$ROOT/scripts/spend-check.sh" --summary >/tmp/sum.out 2>&1 && grep -q "this month" /tmp/sum.out && echo "PROBE:spend_summary=PASS" || echo "PROBE:spend_summary=FAIL"
launchctl list 2>/dev/null | grep -q com.launchpad.spend && echo "PROBE:spend_agent=PASS" || echo "PROBE:spend_agent=FAIL"

# F3: backup nudge fires on cd into a dirty ~/Developer repo (run under zsh)
mkdir -p "$HOME/Developer/nudgetest" && ( cd "$HOME/Developer/nudgetest" && git init -q && echo x > a.txt )
NUDGE_OUT="$(zsh -ic 'source ~/.zshrc 2>/dev/null; cd ~/Developer/nudgetest' 2>&1)"
printf '%s' "$NUDGE_OUT" | grep -q "unsaved" && echo "PROBE:nudge=PASS" || echo "PROBE:nudge=FAIL"

# F4: doctor --fix repairs a deliberately-removed tool
if command -v biome >/dev/null 2>&1; then
  brew uninstall biome >/dev/null 2>&1 || true
  bash "$ROOT/lib/doctor.sh" --fix >/tmp/fix.out 2>&1 || true
  command -v biome >/dev/null 2>&1 && echo "PROBE:doctor_fix=PASS" || echo "PROBE:doctor_fix=FAIL"
else echo "PROBE:doctor_fix=SKIP (biome absent)"; fi

# F4: section map unit test
( cd "$ROOT" && bash tests/test-doctorfix.sh >/tmp/td.out 2>&1 ) && echo "PROBE:doctorfix_unit=PASS" || echo "PROBE:doctorfix_unit=FAIL"
echo "##### ADDON07 PROBE DONE #####"
```

- [ ] **Step 2: Verify it parses + make executable**

Run: `bash -n dogfood/remote-addon07.sh && chmod +x dogfood/remote-addon07.sh && echo ok`
Expected: `ok`

- [ ] **Step 3: Commit**

```bash
git add dogfood/remote-addon07.sh
git commit -m "test(addon-07): VM integration probe for all four features"
```

---

## Task 12: Run the VM probe end-to-end

**Files:** none (validation)

- [ ] **Step 1: Run the probe via the existing harness**

Run: `TART_VM=launchpad-addon07 bash dogfood/vm-probes.sh dogfood/remote-addon07.sh`
Expected (after ~15–20 min): summary shows `PROBE:prewarm=PASS`, `spend_unit=PASS`, `spend_summary=PASS`, `spend_agent=PASS`, `nudge=PASS`, `doctor_fix=PASS`, `doctorfix_unit=PASS`.

- [ ] **Step 2: If any probe FAILs, fix the owning task's code and re-run. Do not proceed until green.**

- [ ] **Step 3: Commit any fixes**

```bash
git add -A && git commit -m "fix(addon-07): address VM probe findings"
```

---

## Task 13: Documentation

**Files:** Modify `docs/cheatsheet.html`, `docs/getting-started.html`, `docs/troubleshooting.html`, `README.md`

- [ ] **Step 1: Cheat sheet — add to the "Safety, data & backups" `<dl class="kv">`**

In `docs/cheatsheet.html`, inside the "Safety, data &amp; backups" section's `<dl class="kv">`, add:

```html
      <dt>launchpad spend</dt><dd>See today's and this month's AI spend. You'll also get a notification if spending suddenly spikes.</dd>
      <dt>launchpad doctor --fix</dt><dd>Health-check <em>and</em> auto-repair anything red (re-installs what's missing).</dd>
      <dt>launchpad nudge off</dt><dd>Turn off the gentle "you have unsaved work" reminder (<code>on</code> to bring it back).</dd>
```

- [ ] **Step 2: Getting-started — add a callout in the "Saving your work" section**

In `docs/getting-started.html`, after the "backed up automatically" callout, add:

```html
    <div class="callout note"><div class="ico" aria-hidden="true">🔔</div><p>If you ever leave changes unsaved or unpushed, you'll get a one-line reminder when you open that project. And if your AI spending suddenly spikes, you'll get a heads-up — check anytime with <code>launchpad spend</code>.</p></div>
```

- [ ] **Step 3: Troubleshooting — add to "Start fresh / health check"**

In `docs/troubleshooting.html`, in the "Start fresh / health check" `<div class="codeblock">`, add a line:

```
launchpad doctor --fix      # health-check AND auto-repair what's broken
```

- [ ] **Step 4: README — add an audit row**

In `README.md`, after the `ccusage` audit row, add:

```
| **Add-on 07** | polish & resilience: pre-warmed pre-commit hooks; `launchpad spend` (spike + optional monthly budget, launchd-scheduled, ccusage `daily --json` → `.period`/`.totalCost`); `chpwd` backup nudge (throttled, opt-out); `launchpad doctor --fix` (section→module re-run) |
```

- [ ] **Step 5: Verify HTML balance + commit**

Run: `for h in docs/cheatsheet.html docs/getting-started.html docs/troubleshooting.html; do grep -c '<main' "$h"; done`
Expected: each `1`.

```bash
git add docs/cheatsheet.html docs/getting-started.html docs/troubleshooting.html README.md
git commit -m "docs(addon-07): document spend, doctor --fix, and the backup nudge"
```

---

## Self-review

**Spec coverage:** Feature 1 (pre-warm) → Task 5 (08-safety) + check Task 10 + probe Task 11. Feature 2 (spend: spike+budget, launchd, `launchpad spend`) → Tasks 2,3,4 (logic/fetch/main), 5 (launchd), 7 (dispatcher), 10 (checks), 11 (probe). Feature 3 (nudge: chpwd, throttle, opt-out) → Task 6 (hook), 7 (`nudge on|off`), 10 (check), 11 (probe). Feature 4 (`doctor --fix`: section→module, targeted, soft-safe) → Tasks 8 (map+test), 9 (--fix), 10 (passthrough), 11 (probe). Docs → Task 13. All spec sections covered.

**Placeholder scan:** Task 9 intentionally calls out and removes drafting noise (Steps 2–3); no other placeholders — every code step has complete code.

**Type/name consistency:** `spend_decide(today,avg7,mtd,budget)` is defined in Task 2 and called identically in Task 4's `main` and Task 2's tests. `_section_modules` is defined in Task 8 and consumed in Task 9 and Task 8's test (via `sed` extraction). `_lp_backup_nudge` is the hook name in Task 6 and the doctor grep in Task 10. `com.launchpad.spend` label matches across Tasks 5, 10, 11. Config path `~/.config/launchpad` consistent (limits, no-nudge, budget stamp).

**Build-time unknown:** ccusage shape was verified before writing (daily `.period`/`.totalCost`); month-to-date derived from the daily array, removing the monthly-format dependency.
