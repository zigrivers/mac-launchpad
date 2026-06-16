#!/usr/bin/env bash
# tests/test-secrets.sh
cd "$(dirname "$0")/.." || exit 1
. tests/lib.sh
. scripts/secrets.sh   # sourcing must NOT run main

# --- _bracewrap ---
assert_eq "$(printf 'API_KEY=op://V/proj/API_KEY\n' | _bracewrap)" \
          "API_KEY={{ op://V/proj/API_KEY }}" "_bracewrap wraps an op:// ref"
assert_eq "$(printf 'PLAIN=hello\n' | _bracewrap)" "PLAIN=hello" "_bracewrap leaves non-op lines alone"
assert_eq "$(printf '# a comment\n' | _bracewrap)" "# a comment" "_bracewrap leaves comments alone"

# --- _kv_upsert ---
d="$(mktemp -d)"; f="$d/.env.local"
_kv_upsert "$f" FOO bar
assert_eq "$(cat "$f")" "FOO=bar" "_kv_upsert creates file + line"
_kv_upsert "$f" BAZ qux
assert_eq "$(grep -c . "$f")" "2" "_kv_upsert appends a second key"
_kv_upsert "$f" FOO changed
assert_eq "$(grep '^FOO=' "$f")" "FOO=changed" "_kv_upsert replaces an existing key in place"
assert_eq "$(grep -c '^FOO=' "$f")" "1" "_kv_upsert does not duplicate the key"
assert_eq "$(grep '^BAZ=' "$f")" "BAZ=qux" "_kv_upsert leaves other keys intact"
# regression (review #1): the update path must not process escapes — backslashes survive.
_kv_upsert "$f" FOO 'p@ss\nw0rd'
assert_eq "$(grep '^FOO=' "$f")" 'FOO=p@ss\nw0rd' "_kv_upsert preserves backslashes on update"
assert_eq "$(grep -c '^FOO=' "$f")" "1" "_kv_upsert backslash update stays one line"

# --- _op_ready + secrets_status (mock op on PATH as `op`) ---
MOCKBIN="$(mktemp -d)"; ln -sf "$PWD/tests/mock-op" "$MOCKBIN/op"
OLDPATH="$PATH"; export PATH="$MOCKBIN:$PATH"

MOCK_OP_SIGNED_IN=0 _op_ready; assert_eq "$?" "1" "_op_ready false when not signed in"
MOCK_OP_SIGNED_IN=1 _op_ready; assert_eq "$?" "0" "_op_ready true when signed in"

proj="$(mktemp -d)"; ( cd "$proj" || exit
  assert_eq "$(MOCK_OP_SIGNED_IN=0 secrets_status | head -1)" ".env.local mode (1Password not set up — that is fine)" "status: fallback mode line"
  assert_eq "$(MOCK_OP_SIGNED_IN=1 secrets_status | head -1)" "1Password mode (vault: Launchpad)" "status: op mode line"
)
export PATH="$OLDPATH"

# --- secrets_set: fallback writes .env.local; op-mode writes .env.tpl ---
MOCKBIN2="$(mktemp -d)"; ln -sf "$PWD/tests/mock-op" "$MOCKBIN2/op"; export PATH="$MOCKBIN2:$PATH"

p1="$(mktemp -d)"; ( cd "$p1" || exit
  printf 'sk-secret-123\n' | MOCK_OP_SIGNED_IN=0 secrets_set API_KEY >/dev/null
  assert_eq "$(cat .env.local 2>/dev/null)" "API_KEY=sk-secret-123" "set (fallback) writes value to .env.local"
  assert_eq "$([ -f .env.tpl ] && echo yes || echo no)" "no" "set (fallback) does NOT create .env.tpl"
)
p2="$(mktemp -d)"; ( cd "$p2" || exit
  printf 'sk-secret-123\n' | MOCK_OP_SIGNED_IN=1 secrets_set API_KEY >/dev/null
  assert_eq "$(cat .env.tpl 2>/dev/null)" "API_KEY=op://Launchpad/$(basename "$p2")/API_KEY" "set (op mode) writes an op:// ref to .env.tpl"
  assert_eq "$([ -f .env.local ] && echo yes || echo no)" "no" "set (op mode) keeps the secret out of .env.local"
)
assert_eq "$(printf 'x\n' | secrets_set 'BAD NAME' 2>&1 | head -1)" "usage: launchpad secrets set NAME   (NAME = letters/digits/underscore)" "set rejects invalid NAME"
export PATH="$OLDPATH"

# --- secrets_inject: op mode resolves .env.tpl -> .env.local; fallback is a no-op ---
export PATH="$MOCKBIN2:$PATH"
p3="$(mktemp -d)"; ( cd "$p3" || exit
  printf 'API_KEY=op://Launchpad/p3/API_KEY\n' > .env.tpl
  MOCK_OP_SIGNED_IN=1 MOCK_OP_VALUE=resolved-secret secrets_inject >/dev/null
  assert_eq "$(cat .env.local 2>/dev/null)" "API_KEY=resolved-secret" "inject (op mode) materializes .env.local from .env.tpl"
)
p4="$(mktemp -d)"; ( cd "$p4" || exit
  out="$(MOCK_OP_SIGNED_IN=0 secrets_inject)"
  assert_eq "$(printf '%s' "$out" | head -1)" "1Password not set up — your values are already in .env.local (nothing to inject)." "inject (fallback) is a friendly no-op"
  assert_eq "$([ -f .env.local ] && echo yes || echo no)" "no" "inject (fallback) writes nothing"
)
export PATH="$OLDPATH"

# --- secrets_run: op mode injects via op run; fallback execs directly ---
export PATH="$MOCKBIN2:$PATH"
p5="$(mktemp -d)"; ( cd "$p5" || exit; printf 'INJECTED=op://Launchpad/p5/INJECTED\n' > .env.tpl
  out="$( MOCK_OP_SIGNED_IN=1 MOCK_OP_VALUE=via-op secrets_run -- sh -c 'printf "%s" "$INJECTED"' )"
  assert_eq "$out" "via-op" "run (op mode) injects the secret into the child process"
)
p6="$(mktemp -d)"; ( cd "$p6" || exit
  out="$( MOCK_OP_SIGNED_IN=0 secrets_run -- sh -c 'printf ok' )"
  assert_eq "$out" "ok" "run (fallback) execs the command directly"
)
assert_eq "$(secrets_run 2>&1 | head -1)" "usage: launchpad secrets run -- <command> [args...]" "run with no command shows usage"
# --- main dispatch ---
( cd "$(mktemp -d)" || exit; assert_eq "$(MOCK_OP_SIGNED_IN=0 main status | head -1)" ".env.local mode (1Password not set up — that is fine)" "main dispatches status" )
assert_eq "$(main bogus 2>&1 | head -1)" "launchpad secrets — status | set NAME | inject | run -- CMD" "main rejects unknown subcommand"
export PATH="$OLDPATH"

t_done
