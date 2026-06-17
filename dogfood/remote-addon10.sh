#!/usr/bin/env bash
# dogfood/remote-addon10.sh — VM integration probe for Add-on 10 (provisioning
# wizards). Scaffolds into a throwaway Next.js project with MOCK supabase/stripe/
# vercel CLIs (no real accounts), asserts files + keys are written idempotently,
# and typechecks the generated code with `tsc --noEmit`.
set -o pipefail
HERE="$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)"
ROOT="$(cd "$HERE/.." >/dev/null 2>&1 && pwd)"
export LAUNCHPAD_NONINTERACTIVE=1 LAUNCHPAD_SKIP_CLONE=1
export PATH="$HOME/.local/bin:/opt/homebrew/bin:$PATH"

echo "##### BOOTSTRAP #####"; /bin/bash "$ROOT/bootstrap.sh"
echo "##### LEAN INSTALL (00,01,10-web) #####"
for m in 00-foundation 01-shell 10-web; do echo "-- $m --"; /bin/bash "$ROOT/modules/$m.sh"; done
command -v fnm >/dev/null 2>&1 && eval "$(fnm env 2>/dev/null)" && fnm use default >/dev/null 2>&1

# Mock CLIs (login/deploy need accounts; the npm packages are installed for real).
MOCKBIN="$(mktemp -d)"
for c in supabase stripe vercel; do printf '#!/bin/sh\necho "mock %s $*"\nexit 0\n' "$c" > "$MOCKBIN/$c"; chmod +x "$MOCKBIN/$c"; done
export PATH="$MOCKBIN:$PATH"

echo "##### PROBES #####"
( cd "$ROOT" && bash tests/test-provision.sh >/tmp/tp.out 2>&1 ) && echo "PROBE:provision_unit=PASS" || { echo "PROBE:provision_unit=FAIL"; tail -5 /tmp/tp.out; }

# A throwaway Next.js project to scaffold into
APP="$(mktemp -d)/app1"
npx --yes create-next-app@latest "$APP" --ts --app --tailwind --no-linter --no-src-dir --no-agents-md --import-alias "@/*" --use-npm --yes >/tmp/cna.out 2>&1 && echo "PROBE:next_app=PASS" || { echo "PROBE:next_app=FAIL"; tail -15 /tmp/cna.out; echo "##### ADDON10 PROBE DONE #####"; exit 0; }

# Supabase wizard: scaffolds + writes keys; idempotent re-run
( cd "$APP" && bash "$ROOT/scripts/add-supabase.sh" --url 'https://abcd.supabase.co' --anon-key 'anon123' >/dev/null 2>&1
  test -f lib/supabase/client.ts && test -f lib/supabase/server.ts && test -f middleware.ts && test -f app/login/page.tsx && test -f app/dashboard/page.tsx \
  && grep -q '^NEXT_PUBLIC_SUPABASE_URL=https://abcd.supabase.co' .env.local && grep -q '^NEXT_PUBLIC_SUPABASE_ANON_KEY=anon123' .env.local ) \
  && echo "PROBE:supabase_scaffold=PASS" || echo "PROBE:supabase_scaffold=FAIL"
# Idempotency: a user's edit to a scaffolded file must survive a re-run untouched.
# Append a VALID-TypeScript sentinel comment (NOT raw 'EDITED', which would break
# the tsc compile gate below), snapshot it, re-run, then assert byte-identical —
# this both proves non-clobber and leaves client.ts compilable for the gate.
( cd "$APP" && printf '\n// LP_SENTINEL_DO_NOT_CLOBBER\n' >> lib/supabase/client.ts \
  && cp lib/supabase/client.ts /tmp/lp_client_snapshot.ts \
  && bash "$ROOT/scripts/add-supabase.sh" >/dev/null 2>&1 \
  && diff -q lib/supabase/client.ts /tmp/lp_client_snapshot.ts >/dev/null ) \
  && echo "PROBE:supabase_idempotent=PASS" || echo "PROBE:supabase_idempotent=FAIL"

# Stripe wizard: scaffolds; rejects a live secret; accepts test keys
( cd "$APP" && bash "$ROOT/scripts/add-stripe.sh" --secret 'sk_test_abc' --pub 'pk_test_abc' >/dev/null 2>&1
  test -f app/pricing/page.tsx && test -f app/api/checkout/route.ts && test -f app/api/webhook/route.ts && test -f app/premium/page.tsx \
  && grep -q '^STRIPE_SECRET_KEY=sk_test_abc' .env.local ) && echo "PROBE:stripe_scaffold=PASS" || echo "PROBE:stripe_scaffold=FAIL"
( cd "$APP" && bash "$ROOT/scripts/add-stripe.sh" --secret 'sk_live_NOPE' >/dev/null 2>&1; ! grep -q 'sk_live_' .env.local ) \
  && echo "PROBE:stripe_rejects_live=PASS" || echo "PROBE:stripe_rejects_live=FAIL"

# Vercel wizard: runs with the mock CLI, pushes keys, "deploys"
( cd "$APP" && bash "$ROOT/scripts/add-vercel.sh" >/tmp/vc.out 2>&1 && grep -qi 'deploy' /tmp/vc.out ) \
  && echo "PROBE:vercel_run=PASS" || echo "PROBE:vercel_run=FAIL"

# The generated TypeScript must typecheck (proves the scaffolds compile against the real SDKs)
( cd "$APP" && npx --yes tsc --noEmit >/tmp/tsc.out 2>&1 ) && echo "PROBE:tsc_compiles=PASS" || { echo "PROBE:tsc_compiles=FAIL"; tail -20 /tmp/tsc.out; }

# Stripe CLI really installed by 10-web — check brew, NOT `command -v stripe`
# (the MOCKBIN mock shadows `stripe` on PATH, so command -v would false-pass).
brew list stripe >/dev/null 2>&1 && echo "PROBE:stripe_cli=PASS" || echo "PROBE:stripe_cli=FAIL"
bash "$ROOT/scripts/launchpad" add 2>&1 | grep -qi 'supabase' && echo "PROBE:dispatch=PASS" || echo "PROBE:dispatch=FAIL"

echo "##### ADDON10 PROBE DONE #####"
