#!/usr/bin/env bash
# dogfood/remote-addon08.sh — VM integration probe for Add-on 08 (secret mgmt).
# Lean install (00, 07, 08) + a fake `op` on PATH, exercising both the 1Password
# and the .env.local fallback paths, the doctor checks, and the gitignore.
set -o pipefail
HERE="$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)"
ROOT="$(cd "$HERE/.." >/dev/null 2>&1 && pwd)"
export LAUNCHPAD_NONINTERACTIVE=1 LAUNCHPAD_SKIP_CLONE=1
export PATH="$HOME/.local/bin:/opt/homebrew/bin:$PATH"

echo "##### BOOTSTRAP #####"; /bin/bash "$ROOT/bootstrap.sh"
echo "##### LEAN INSTALL (00,07,08) #####"
for m in 00-foundation 07-secrets 08-safety; do echo "-- $m --"; /bin/bash "$ROOT/modules/$m.sh"; done

# Put the deterministic mock `op` first on PATH so no real account is needed.
MOCKBIN="$(mktemp -d)"; ln -sf "$ROOT/tests/mock-op" "$MOCKBIN/op"; export PATH="$MOCKBIN:$PATH"
SECRETS="$ROOT/scripts/secrets.sh"

echo "##### PROBES #####"

# Unit suite passes in the VM too
( cd "$ROOT" && bash tests/test-secrets.sh >/tmp/ts8.out 2>&1 ) && echo "PROBE:secrets_unit=PASS" || { echo "PROBE:secrets_unit=FAIL"; tail -5 /tmp/ts8.out; }

# set (fallback) -> .env.local ; set (op) -> .env.tpl
pf="$(mktemp -d)"; ( cd "$pf"; printf 'v1\n' | MOCK_OP_SIGNED_IN=0 bash "$SECRETS" set API_KEY >/dev/null
  grep -q '^API_KEY=v1$' .env.local && [ ! -f .env.tpl ] ) && echo "PROBE:set_fallback=PASS" || echo "PROBE:set_fallback=FAIL"
po="$(mktemp -d)"; ( cd "$po"; printf 'v1\n' | MOCK_OP_SIGNED_IN=1 bash "$SECRETS" set API_KEY >/dev/null
  grep -q '^API_KEY=op://Launchpad/' .env.tpl && [ ! -f .env.local ] ) && echo "PROBE:set_opmode=PASS" || echo "PROBE:set_opmode=FAIL"

# inject (op) materializes .env.local from .env.tpl
pi="$(mktemp -d)"; ( cd "$pi"; printf 'API_KEY=op://Launchpad/pi/API_KEY\n' > .env.tpl
  MOCK_OP_SIGNED_IN=1 MOCK_OP_VALUE=resolved bash "$SECRETS" inject >/dev/null
  grep -q '^API_KEY=resolved$' .env.local ) && echo "PROBE:inject=PASS" || echo "PROBE:inject=FAIL"

# run (op) injects into the child process
pr="$(mktemp -d)"; ( cd "$pr"; printf 'INJECTED=op://Launchpad/pr/INJECTED\n' > .env.tpl
  out="$(MOCK_OP_SIGNED_IN=1 MOCK_OP_VALUE=ran bash "$SECRETS" run -- sh -c 'printf "%s" "$INJECTED"')"
  [ "$out" = "ran" ] ) && echo "PROBE:run=PASS" || echo "PROBE:run=FAIL"

# status reports the fallback mode
ps="$(mktemp -d)"; ( cd "$ps"; MOCK_OP_SIGNED_IN=0 bash "$SECRETS" status | grep -qi '.env.local mode' ) && echo "PROBE:status=PASS" || echo "PROBE:status=FAIL"

# launchpad dispatch (call the repo script directly — 09-dx, which symlinks
# `launchpad` onto PATH, is not in this lean install)
bash "$ROOT/scripts/launchpad" secrets status >/tmp/lps8.out 2>&1 && grep -qiE '1Password mode|\.env\.local mode' /tmp/lps8.out && echo "PROBE:dispatch=PASS" || echo "PROBE:dispatch=FAIL"

# gitignore: .env.tpl committable, .env.local ignored (08-safety wired the global gitignore)
pg="$(mktemp -d)"; ( cd "$pg"; git init -q; touch .env.tpl .env.local
  ! git check-ignore -q .env.tpl && git check-ignore -q .env.local ) && echo "PROBE:gitignore=PASS" || echo "PROBE:gitignore=FAIL"

# doctor: op present (hard) passes; running doctor doesn't error on the secrets checks
( cd "$ROOT" && bash lib/doctor.sh >/tmp/doc8.out 2>&1; grep -q '1Password CLI (op)' /tmp/doc8.out ) && echo "PROBE:doctor=PASS" || echo "PROBE:doctor=FAIL"

echo "##### ADDON08 PROBE DONE #####"
