#!/usr/bin/env bash
# dogfood/remote-addon09.sh — VM integration probe for Add-on 09 (loops &
# onboarding). Lean install (just 00-foundation for git) + probes that exercise
# status (varied-state repos), signin (checklist output), and sentry-setup
# (--dsn writes .env.local; invalid DSN rejected). Runs the scripts from $ROOT
# directly (they don't need a module to work).
set -o pipefail
HERE="$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)"
ROOT="$(cd "$HERE/.." >/dev/null 2>&1 && pwd)"
export LAUNCHPAD_NONINTERACTIVE=1 LAUNCHPAD_SKIP_CLONE=1
export PATH="$HOME/.local/bin:/opt/homebrew/bin:$PATH"

echo "##### BOOTSTRAP #####"; /bin/bash "$ROOT/bootstrap.sh"
echo "##### LEAN INSTALL (00) #####"; /bin/bash "$ROOT/modules/00-foundation.sh"

echo "##### PROBES #####"

# Unit suites
( cd "$ROOT" && bash tests/test-status.sh >/tmp/ts.out 2>&1 ) && echo "PROBE:status_unit=PASS" || { echo "PROBE:status_unit=FAIL"; tail -5 /tmp/ts.out; }
( cd "$ROOT" && bash tests/test-signin.sh >/tmp/si.out 2>&1 ) && echo "PROBE:signin_unit=PASS" || { echo "PROBE:signin_unit=FAIL"; tail -5 /tmp/si.out; }
( cd "$ROOT" && bash tests/test-sentry.sh >/tmp/se.out 2>&1 ) && echo "PROBE:sentry_unit=PASS" || { echo "PROBE:sentry_unit=FAIL"; tail -5 /tmp/se.out; }

# status: build varied-state repos under ~/Developer and check the classification
DEV="$HOME/Developer"; mkdir -p "$DEV"
git config --global user.email t@t.t >/dev/null 2>&1; git config --global user.name t >/dev/null 2>&1
git config --global init.defaultBranch main >/dev/null 2>&1
mk() { mkdir -p "$DEV/$1" && ( cd "$DEV/$1" && git init -q && echo x > f.txt && git add -A && git commit -qm init ); }
mk backedup && ( cd "$DEV/backedup" && git remote add origin https://example.com/x.git )   # remote, clean, no upstream -> backed up
mk dirtyone && ( cd "$DEV/dirtyone" && git remote add origin https://example.com/y.git && echo more >> f.txt )  # dirty
mk noremote                                                                                 # no remote
OUT="$(DEVELOPER_DIR="$DEV" bash "$ROOT/scripts/status.sh" 2>/dev/null)"
printf '%s' "$OUT" | grep -q 'backed up'    && echo "PROBE:status_backedup=PASS" || { echo "PROBE:status_backedup=FAIL"; printf '%s\n' "$OUT"; }
printf '%s' "$OUT" | grep -q 'unsaved'      && echo "PROBE:status_dirty=PASS"    || echo "PROBE:status_dirty=FAIL"
printf '%s' "$OUT" | grep -q 'no remote yet' && echo "PROBE:status_noremote=PASS" || echo "PROBE:status_noremote=FAIL"

# signin: checklist renders (gh not signed in -> todo line)
SOUT="$(bash "$ROOT/scripts/signin.sh" 2>/dev/null)"
printf '%s' "$SOUT" | grep -q 'Sign-in checklist' && printf '%s' "$SOUT" | grep -q 'GitHub' && echo "PROBE:signin=PASS" || echo "PROBE:signin=FAIL"

# sentry-setup: valid --dsn writes both keys; invalid rejected
ps="$(mktemp -d)"; ( cd "$ps" && bash "$ROOT/scripts/sentry-setup.sh" --dsn 'https://abc@o1.ingest.us.sentry.io/789' >/dev/null 2>&1
  grep -q '^NEXT_PUBLIC_SENTRY_DSN=https://abc@' .env.local && grep -q '^SENTRY_DSN=https://abc@' .env.local ) && echo "PROBE:sentry_write=PASS" || echo "PROBE:sentry_write=FAIL"
pb="$(mktemp -d)"; ( cd "$pb" && ! bash "$ROOT/scripts/sentry-setup.sh" --dsn 'nonsense' >/dev/null 2>&1 && [ ! -f .env.local ] ) && echo "PROBE:sentry_reject=PASS" || echo "PROBE:sentry_reject=FAIL"

# dispatch via the launchpad script directly (09-dx symlink not in this lean install)
DEVELOPER_DIR="$DEV" bash "$ROOT/scripts/launchpad" status >/tmp/lp.out 2>&1 && grep -q 'backed up' /tmp/lp.out && echo "PROBE:dispatch=PASS" || echo "PROBE:dispatch=FAIL"

# doctor check line present
( cd "$ROOT" && bash lib/doctor.sh >/tmp/doc.out 2>&1; grep -q 'loops & onboarding scripts' /tmp/doc.out ) && echo "PROBE:doctor=PASS" || echo "PROBE:doctor=FAIL"

echo "##### ADDON09 PROBE DONE #####"
