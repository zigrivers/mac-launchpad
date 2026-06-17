#!/usr/bin/env bash
# tests/test-provision.sh
cd "$(dirname "$0")/.." || exit 1
. tests/lib.sh
. scripts/provision-common.sh

# supabase_url_valid: https://<ref>.supabase.co
supabase_url_valid 'https://abcdefgh.supabase.co'; assert_eq "$?" "0" "supabase url ok"
supabase_url_valid 'https://abcdefgh.supabase.co/'; assert_eq "$?" "0" "supabase url trailing slash ok"
supabase_url_valid 'http://abcdefgh.supabase.co';  assert_eq "$?" "1" "supabase url http rejected"
supabase_url_valid 'https://evil.example.com';     assert_eq "$?" "1" "supabase url non-supabase rejected"
supabase_url_valid 'nope';                          assert_eq "$?" "1" "supabase url junk rejected"

# stripe key validators: test-mode only
stripe_test_secret_valid 'sk_test_51abcXYZ'; assert_eq "$?" "0" "sk_test ok"
stripe_test_secret_valid 'sk_live_51abcXYZ'; assert_eq "$?" "1" "sk_live rejected (use test mode)"
stripe_test_secret_valid 'pk_test_51abc';    assert_eq "$?" "1" "pk is not a secret key"
stripe_pub_valid 'pk_test_51abcXYZ';         assert_eq "$?" "0" "pk_test ok"
stripe_pub_valid 'pk_live_51abcXYZ';         assert_eq "$?" "1" "pk_live rejected"

# env_upsert: add + replace, no dupes, backslash-safe
d="$(mktemp -d)"; f="$d/.env.local"
env_upsert "$f" FOO bar; assert_eq "$(cat "$f")" "FOO=bar" "env_upsert creates"
env_upsert "$f" FOO baz; assert_eq "$(grep '^FOO=' "$f")" "FOO=baz" "env_upsert replaces"
assert_eq "$(grep -c '^FOO=' "$f")" "1" "env_upsert no dupe"

# env_keys: list KEY names, skip comments/blanks
g="$(mktemp -d)/.env.local"; printf '# a comment\nA=1\n\nB=two=parts\n' > "$g"
assert_eq "$(env_keys "$g" | paste -sd, -)" "A,B" "env_keys lists keys, skips comments/blanks"

# is_next_project: true only when package.json has a next dependency
p1="$(mktemp -d)"; printf '{ "dependencies": { "next": "16.0.0" } }' > "$p1/package.json"
( cd "$p1" && is_next_project ); assert_eq "$?" "0" "is_next_project true with next dep"
p2="$(mktemp -d)"; printf '{ "dependencies": {} }' > "$p2/package.json"
( cd "$p2" && is_next_project ); assert_eq "$?" "1" "is_next_project false without next"
p3="$(mktemp -d)"; ( cd "$p3" && is_next_project ); assert_eq "$?" "1" "is_next_project false with no package.json"

# scaffold_if_absent: writes once, never clobbers
s="$(mktemp -d)/app/x.tsx"
printf 'ORIGINAL' | scaffold_if_absent "$s" >/dev/null; assert_eq "$(cat "$s")" "ORIGINAL" "scaffold writes when absent"
printf 'SECOND'   | scaffold_if_absent "$s" >/dev/null; assert_eq "$(cat "$s")" "ORIGINAL" "scaffold never clobbers"

t_done
