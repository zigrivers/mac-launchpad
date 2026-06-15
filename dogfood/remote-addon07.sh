#!/usr/bin/env bash
# dogfood/remote-addon07.sh — VM integration probe for Add-on 07 (polish &
# resilience). Runs inside a throwaway VM, reading the repo from the read-only
# share. Lean install (only the modules the four features need) + probes.
#
# Note on doctor --fix: on a LEAN install most sections are red (uninstalled
# editors/web/etc.), so a full `doctor --fix` would try to re-install everything.
# We instead test the --fix *mechanism* surgically (the section→module map is
# unit-tested in tests/test-doctorfix.sh; here we prove that re-running the mapped
# module heals a deliberately-broken check), which is bounded and meaningful.

set -o pipefail
HERE="$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)"
ROOT="$(cd "$HERE/.." >/dev/null 2>&1 && pwd)"
export LAUNCHPAD_NONINTERACTIVE=1 LAUNCHPAD_SKIP_CLONE=1
export PATH="$HOME/.local/bin:/opt/homebrew/bin:$PATH"

echo "##### BOOTSTRAP #####"; /bin/bash "$ROOT/bootstrap.sh"
echo "##### LEAN INSTALL (00,01,08,09) #####"
for m in 00-foundation 01-shell 08-safety 09-dx; do echo "-- $m --"; /bin/bash "$ROOT/modules/$m.sh"; done
command -v fnm >/dev/null 2>&1 && eval "$(fnm env 2>/dev/null)" && fnm use default >/dev/null 2>&1

echo "##### PROBES #####"

# F1 — 08-safety pre-warmed the pre-commit hook cache
[ -n "$(ls -A "$HOME/.cache/pre-commit" 2>/dev/null)" ] && echo "PROBE:prewarm=PASS" || echo "PROBE:prewarm=FAIL"

# F2 — spend: unit tests, --summary, launchd agent loaded
( cd "$ROOT" && bash tests/test-spend.sh >/tmp/ts.out 2>&1 ) && echo "PROBE:spend_unit=PASS" || { echo "PROBE:spend_unit=FAIL"; tail -5 /tmp/ts.out; }
bash "$ROOT/scripts/spend-check.sh" --summary >/tmp/sum.out 2>&1 && grep -qi "this month" /tmp/sum.out && echo "PROBE:spend_summary=PASS" || { echo "PROBE:spend_summary=FAIL"; tail -5 /tmp/sum.out; }
launchctl list 2>/dev/null | grep -q com.launchpad.spend && echo "PROBE:spend_agent=PASS" || echo "PROBE:spend_agent=FAIL"
# launchpad spend dispatches
bash "$HOME/.local/bin/launchpad" spend >/tmp/lps.out 2>&1 && grep -qi "this month" /tmp/lps.out && echo "PROBE:launchpad_spend=PASS" || echo "PROBE:launchpad_spend=FAIL"
# F2 (launchd PATH) — the scheduled agent runs with a minimal PATH; verify
# spend-check's bootstrap makes npx reachable under it. Pass the script path via
# the (clean) env as a quoted var so a share path with spaces still sources.
# SC2016 is intentional: $SPEND_SH must expand in the INNER bash (which has it in
# its env via `env -i`), not the outer shell — switching to "" reintroduces the bug.
# shellcheck disable=SC2016
if env -i HOME="$HOME" SPEND_SH="$ROOT/scripts/spend-check.sh" PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
     /bin/bash -c '. "$SPEND_SH"; _spend_path_bootstrap; command -v npx >/dev/null 2>&1'; then
  echo "PROBE:spend_launchd_path=PASS"
else
  echo "PROBE:spend_launchd_path=FAIL"
fi

# F3 — backup nudge fires on cd into a dirty ~/Developer repo (under zsh)
mkdir -p "$HOME/Developer/nudgetest" && ( cd "$HOME/Developer/nudgetest" && git init -q && echo x > a.txt )
NUDGE_OUT="$(zsh -ic 'source ~/.zshrc 2>/dev/null; cd ~/Developer/nudgetest' 2>&1)"
printf '%s' "$NUDGE_OUT" | grep -qi "unsaved" && echo "PROBE:nudge=PASS" || echo "PROBE:nudge=FAIL"
# opt-out silences it
mkdir -p "$HOME/.config/launchpad"; bash "$HOME/.local/bin/launchpad" nudge off >/dev/null 2>&1
NUDGE_OFF="$(zsh -ic 'source ~/.zshrc 2>/dev/null; _lp_nudged=(); cd ~/Developer/nudgetest' 2>&1)"
printf '%s' "$NUDGE_OFF" | grep -qi "unsaved" && echo "PROBE:nudge_optout=FAIL" || echo "PROBE:nudge_optout=PASS"
bash "$HOME/.local/bin/launchpad" nudge on >/dev/null 2>&1

# F4 — doctor --fix MECHANISM: the map says Developer experience→09-dx; prove
# re-running that module heals a deliberately-removed tool. (Map + arg parsing
# are unit-tested in tests/test-doctorfix.sh.)
( cd "$ROOT" && bash tests/test-doctorfix.sh >/tmp/td.out 2>&1 ) && echo "PROBE:doctorfix_unit=PASS" || { echo "PROBE:doctorfix_unit=FAIL"; tail -5 /tmp/td.out; }
if command -v biome >/dev/null 2>&1; then
  brew uninstall biome >/dev/null 2>&1 || true
  command -v biome >/dev/null 2>&1 && echo "PROBE:setup=biome-still-present" || {
    /bin/bash "$ROOT/modules/09-dx.sh" >/dev/null 2>&1 || true   # the module --fix would re-run for a Dev-exp red
    command -v biome >/dev/null 2>&1 && echo "PROBE:fix_heals=PASS" || echo "PROBE:fix_heals=FAIL"
  }
else echo "PROBE:fix_heals=SKIP (biome absent)"; fi

echo "##### ADDON07 PROBE DONE #####"
