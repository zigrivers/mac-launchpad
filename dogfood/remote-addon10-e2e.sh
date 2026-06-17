#!/usr/bin/env bash
# dogfood/remote-addon10-e2e.sh — REAL end-to-end dogfood for Add-on 10.
#
# Beyond the mock-CLI + `tsc --noEmit` probe (remote-addon10.sh), this scaffolds
# all three wizards into a real Next.js app and runs a REAL production build:
#   Phase A — scaffold BEFORE keys are set, then `next build`. A non-programmer
#             may scaffold and build before finishing the third-party login, so
#             the generated code must build even with no keys yet.
#   Phase B — add keys (the documented happy path), rebuild.
#   Phase C — `next start` the built app and curl every route (real HTTP).
#   Phase D — the Vercel link→env→deploy orchestration against a mock CLI.
# Runs entirely inside a throwaway VM. The account-gated login/deploy steps are
# mocked (they need real accounts / browser OAuth); the npm SDKs are installed
# for real and the app is really built and served.
set -o pipefail
HERE="$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)"
ROOT="$(cd "$HERE/.." >/dev/null 2>&1 && pwd)"
export LAUNCHPAD_NONINTERACTIVE=1 LAUNCHPAD_SKIP_CLONE=1
export PATH="$HOME/.local/bin:/opt/homebrew/bin:$PATH"

echo "##### BOOTSTRAP #####"; /bin/bash "$ROOT/bootstrap.sh"
echo "##### LEAN INSTALL (00,01,10-web) #####"
for m in 00-foundation 01-shell 10-web; do echo "-- $m --"; /bin/bash "$ROOT/modules/$m.sh"; done
command -v fnm >/dev/null 2>&1 && eval "$(fnm env 2>/dev/null)" && fnm use default >/dev/null 2>&1

# Mock the account-gated CLIs (login/deploy need real accounts).
MOCKBIN="$(mktemp -d)"
for c in supabase stripe vercel; do printf '#!/bin/sh\necho "mock %s $*"\nexit 0\n' "$c" > "$MOCKBIN/$c"; chmod +x "$MOCKBIN/$c"; done
export PATH="$MOCKBIN:$PATH"

echo "##### UNIT PROBE #####"
( cd "$ROOT" && bash tests/test-provision.sh >/tmp/tp.out 2>&1 ) && echo "PROBE:provision_unit=PASS" || { echo "PROBE:provision_unit=FAIL"; tail -5 /tmp/tp.out; }

echo "##### CREATE NEXT APP #####"
APP="$(mktemp -d)/app1"
npx --yes create-next-app@latest "$APP" --ts --app --tailwind --no-linter --no-src-dir --no-agents-md --import-alias "@/*" --use-npm --yes >/tmp/cna.out 2>&1 \
  && echo "PROBE:next_app=PASS" || { echo "PROBE:next_app=FAIL"; tail -20 /tmp/cna.out; echo "##### ADDON10 E2E DONE #####"; exit 0; }
cd "$APP" || { echo "PROBE:cd_app=FAIL"; echo "##### ADDON10 E2E DONE #####"; exit 0; }

# ---- Phase A: scaffold WITHOUT keys, then a REAL production build ----------
echo "##### PHASE A: scaffold (no keys) + next build #####"
bash "$ROOT/scripts/add-supabase.sh" >/tmp/sb.out 2>&1
bash "$ROOT/scripts/add-stripe.sh"   >/tmp/st.out 2>&1
npm run build >/tmp/build-nokeys.out 2>&1 \
  && echo "PROBE:build_no_keys=PASS" || { echo "PROBE:build_no_keys=FAIL"; tail -40 /tmp/build-nokeys.out; }

# ---- Phase B: add keys (the documented happy path), rebuild ----------------
echo "##### PHASE B: add keys + next build #####"
bash "$ROOT/scripts/add-supabase.sh" --url 'https://abcd.supabase.co' --anon-key 'anon123' >/dev/null 2>&1
bash "$ROOT/scripts/add-stripe.sh" --secret 'sk_test_abc' --pub 'pk_test_abc' >/dev/null 2>&1
npm run build >/tmp/build-keys.out 2>&1 \
  && echo "PROBE:build_with_keys=PASS" || { echo "PROBE:build_with_keys=FAIL"; tail -40 /tmp/build-keys.out; }

# ---- Phase C: run the built app and curl every route -----------------------
echo "##### PHASE C: next start + HTTP smoke #####"
if [ -d .next ]; then
  PORT=3000
  npm run start -- -p "$PORT" >/tmp/start.out 2>&1 &
  SRV=$!
  up=0; for _ in $(seq 1 60); do curl -fsS "http://localhost:$PORT/" >/dev/null 2>&1 && { up=1; break; }; sleep 1; done
  if [ "$up" = 1 ]; then
    echo "PROBE:serve_boot=PASS"
    code() { curl -s -o /dev/null -w '%{http_code}' "$@"; }
    rc=$(code "http://localhost:$PORT/pricing"); [ "$rc" = 200 ] && echo "PROBE:route_pricing=PASS" || echo "PROBE:route_pricing=FAIL ($rc)"
    rc=$(code "http://localhost:$PORT/login");   [ "$rc" = 200 ] && echo "PROBE:route_login=PASS"   || echo "PROBE:route_login=FAIL ($rc)"
    rc=$(code "http://localhost:$PORT/premium"); [ "$rc" = 200 ] && echo "PROBE:route_premium=PASS" || echo "PROBE:route_premium=FAIL ($rc)"
    # webhook with no/invalid signature must be rejected with 400 (constructEvent throws -> catch -> 400)
    rc=$(code -X POST "http://localhost:$PORT/api/webhook"); [ "$rc" = 400 ] && echo "PROBE:route_webhook_400=PASS" || echo "PROBE:route_webhook_400=FAIL ($rc)"
    # informational: these hit the FAKE supabase/stripe, so the exact code varies — just record that the route is live (not 000).
    echo "INFO:route_dashboard=$(code "http://localhost:$PORT/dashboard")"
    echo "INFO:route_checkout=$(code -X POST "http://localhost:$PORT/api/checkout")"
  else
    echo "PROBE:serve_boot=FAIL"; tail -30 /tmp/start.out
  fi
  kill "$SRV" >/dev/null 2>&1 || true
  pkill -f next-server >/dev/null 2>&1 || true
else
  echo "PROBE:serve_boot=SKIP_NO_BUILD"
fi

# ---- Phase D: vercel orchestration (mock) ----------------------------------
echo "##### PHASE D: vercel wizard (mock) #####"
bash "$ROOT/scripts/add-vercel.sh" >/tmp/vc.out 2>&1 && grep -qi 'deploy' /tmp/vc.out \
  && echo "PROBE:vercel_run=PASS" || { echo "PROBE:vercel_run=FAIL"; tail -10 /tmp/vc.out; }

# ---- dispatcher sanity -----------------------------------------------------
bash "$ROOT/scripts/launchpad" add 2>&1 | grep -qi 'supabase' && echo "PROBE:dispatch=PASS" || echo "PROBE:dispatch=FAIL"

echo "##### ADDON10 E2E DONE #####"
