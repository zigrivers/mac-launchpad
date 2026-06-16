#!/usr/bin/env bash
# tests/test-sentry.sh
cd "$(dirname "$0")/.." || exit 1
. tests/lib.sh
. scripts/sentry-setup.sh   # sourcing must NOT run main

# sentry_dsn_valid: good shapes
sentry_dsn_valid 'https://abc123@o456.ingest.us.sentry.io/789'; assert_eq "$?" "0" "modern region DSN valid"
sentry_dsn_valid 'https://abc@sentry.io/42';                    assert_eq "$?" "0" "legacy DSN valid"
# sentry_dsn_valid: bad shapes
sentry_dsn_valid 'http://abc@sentry.io/42';      assert_eq "$?" "1" "http (not https) rejected"
sentry_dsn_valid 'https://sentry.io/42';         assert_eq "$?" "1" "missing key@ rejected"
sentry_dsn_valid 'https://abc@example.com/42';   assert_eq "$?" "1" "non-sentry host rejected"
sentry_dsn_valid 'https://abc@o1.ingest.sentry.io/'; assert_eq "$?" "1" "missing project id rejected"
sentry_dsn_valid 'nonsense';                     assert_eq "$?" "1" "garbage rejected"
sentry_dsn_valid "$(printf 'https://abc@o1.ingest.sentry.io/789\nEVIL=1')"; assert_eq "$?" "1" "DSN with embedded newline rejected (no .env.local injection)"

# sentry_env_upsert writes BOTH keys, idempotently
d="$(mktemp -d)"; f="$d/.env.local"
sentry_env_upsert "$f" 'https://abc@o1.ingest.sentry.io/789'
assert_eq "$(grep -c '^NEXT_PUBLIC_SENTRY_DSN=' "$f")" "1" "writes NEXT_PUBLIC_SENTRY_DSN"
assert_eq "$(grep -c '^SENTRY_DSN=' "$f")"             "1" "writes SENTRY_DSN"
assert_eq "$(grep '^SENTRY_DSN=' "$f")" "SENTRY_DSN=https://abc@o1.ingest.sentry.io/789" "DSN value correct"
# re-run with a new DSN replaces in place (no dupes)
sentry_env_upsert "$f" 'https://xyz@o2.ingest.sentry.io/111'
assert_eq "$(grep -c '^NEXT_PUBLIC_SENTRY_DSN=' "$f")" "1" "no dupe NEXT_PUBLIC on re-run"
assert_eq "$(grep '^SENTRY_DSN=' "$f")" "SENTRY_DSN=https://xyz@o2.ingest.sentry.io/111" "DSN updated on re-run"

t_done
