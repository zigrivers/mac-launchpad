# Add-on 08 — Secret management (1Password) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire the installed-but-unused 1Password CLI (`op`) into an optional `launchpad secrets` toolset that degrades gracefully to a plain `.env.local` file when 1Password isn't signed in.

**Architecture:** A new `scripts/secrets.sh` holds all logic as small source-guarded functions (unit-testable with a mock `op`); a new core module `modules/07-secrets.sh` installs it; `scripts/launchpad` dispatches `secrets`; `lib/doctor.sh` adds a soft check; static edits add the agent house-rule and the `!.env.tpl` gitignore allow-list. Everything is optional and never blocks the core flow.

**Tech Stack:** POSIX/bash 3.2, `op` 2.34.1, awk/sed, the repo's `lib/common.sh` helpers and `tests/lib.sh` assertion harness.

**Spec:** `dogfood/specs/2026-06-15-addon-08-secret-management-design.md`.

**Verified at plan time (op 2.34.1):**
- `op whoami` → exit 0 only when signed in (account / `op signin` / `OP_SERVICE_ACCOUNT_TOKEN`); exit 1 + stderr otherwise.
- `op inject` resolves `{{ op://vault/item/field }}` (braces) from stdin → stdout.
- `op run --env-file=FILE -- CMD` reads dotenv lines `KEY=op://…` (no braces) and runs CMD with resolved secrets as env vars (nothing written to disk).
- `op item create --category=login --title=T --vault=V 'NAME[password]=VALUE'`; `op item edit T --vault=V 'NAME[password]=VALUE'`; `op item get T --vault=V` (exit 0 if exists); `op vault get V` / `op vault create V`; `op read op://V/T/NAME`.

**Convention notes for the implementer:**
- `.env.tpl` is the canonical template in **`op run` format** (`KEY=op://…`); `inject` bridges to `op inject` by brace-wrapping. `.env.tpl` holds only references (no secrets) and is committable; `.env.local` holds real values and stays gitignored.
- `config/agents/AGENTS.md` is **symlinked** to all three agents by `05-agents.sh` (`~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`, `~/.gemini/{AGENTS,GEMINI}.md`). The house-rule is therefore a **static edit to the source file** — `07-secrets.sh` does NOT modify it at runtime.
- The global gitignore is installed by `08-safety.sh` via `cp -f` from `config/safety/gitignore.global` (runs after `07`), so the `!.env.tpl` line lives in that source file — `07` does not touch the installed gitignore.
- All `secrets` subcommands operate on `.env.tpl` / `.env.local` in the **current working directory** (the project).

---

### Task 1: Test fixture (mock `op`) + `scripts/secrets.sh` skeleton + pure helpers

**Files:**
- Create: `tests/mock-op`
- Create: `scripts/secrets.sh`
- Create: `tests/test-secrets.sh`

- [ ] **Step 1: Write the mock `op` fixture**

Create `tests/mock-op` (a deterministic fake `op`; tests symlink it onto PATH as `op`):

```bash
#!/usr/bin/env bash
# tests/mock-op — a deterministic fake `op` for secrets tests. Put on PATH as `op`.
# Switches (env): MOCK_OP_SIGNED_IN=1 (whoami ok), MOCK_OP_HAS_ITEM=1 (item exists),
# MOCK_OP_HAS_VAULT=1 (default 1), MOCK_OP_VALUE (resolved value; default MOCKVALUE).
val="${MOCK_OP_VALUE:-MOCKVALUE}"
case "${1:-}" in
  whoami)
    if [ "${MOCK_OP_SIGNED_IN:-0}" = 1 ]; then echo "mock-account"; exit 0
    else echo "[ERROR] no account found" >&2; exit 1; fi ;;
  vault)
    case "${2:-}" in
      get)    [ "${MOCK_OP_HAS_VAULT:-1}" = 1 ] && exit 0 || exit 1 ;;
      create) echo "created vault"; exit 0 ;;
      *)      exit 0 ;;
    esac ;;
  item)
    case "${2:-}" in
      get)    [ "${MOCK_OP_HAS_ITEM:-0}" = 1 ] && exit 0 || exit 1 ;;
      create) echo "created item"; exit 0 ;;
      edit)   echo "edited item"; exit 0 ;;
      *)      exit 0 ;;
    esac ;;
  read) echo "$val"; exit 0 ;;
  inject) # stdin has KEY={{ op://… }} → replace each {{ op://… }} with the value
    sed -E 's#\{\{[[:space:]]*op://[^}]+[[:space:]]*\}\}#'"$val"'#g'; exit 0 ;;
  run) # op run --env-file=F -- CMD… : export each KEY=op://… as KEY=value, then run CMD
    shift; envfile=""
    while [ "$#" -gt 0 ]; do
      case "$1" in --env-file=*) envfile="${1#*=}" ;; --) shift; break ;; esac
      shift
    done
    if [ -n "$envfile" ] && [ -f "$envfile" ]; then
      while IFS= read -r line; do
        case "$line" in [A-Za-z_]*=op://*) export "${line%%=*}=$val" ;; esac
      done < "$envfile"
    fi
    exec "$@" ;;
  *) exit 0 ;;
esac
```

- [ ] **Step 2: Write the `secrets.sh` skeleton with the two pure helpers**

Create `scripts/secrets.sh` with the header, config, and the two pure (no-I/O-on-`op`) helpers. Nothing else yet:

```bash
#!/usr/bin/env bash
#
# scripts/secrets.sh [status | set NAME | inject | run -- CMD...]
#
# launchpad secrets — optional 1Password (op) wiring with a .env.local fallback.
# Signed in to op: store/read secrets in a 1Password vault + a committed,
# secret-free .env.tpl of op:// references. Not signed in (the default): degrade
# to a plain .env.local file with a one-line note. Never blocks, never errors loud.

LP_CFG="${LP_CFG:-$HOME/.config/launchpad}"

# Add or replace a KEY=RHS line in a dotenv-style file (idempotent, order-preserving).
_kv_upsert() { # _kv_upsert <file> <key> <rhs>
  local file="$1" key="$2" rhs="$3" tmp
  [ -d "$(dirname "$file")" ] || mkdir -p "$(dirname "$file")"
  tmp="$(mktemp)"
  if [ -f "$file" ] && grep -qE "^${key}=" "$file"; then
    awk -v k="$key" -v v="$rhs" 'BEGIN{FS="="} $1==k{print k"="v; next} {print}' "$file" >"$tmp"
  else
    [ -f "$file" ] && cat "$file" >"$tmp"
    printf '%s=%s\n' "$key" "$rhs" >>"$tmp"
  fi
  mv "$tmp" "$file"
}

# Brace-wrap op:// refs so `op inject` (wants {{ op://… }}) can read a file written
# in the `op run` env-file format (KEY=op://…). stdin -> stdout. Non-op lines pass through.
_bracewrap() { sed -E 's#^([A-Za-z_][A-Za-z0-9_]*)=(op://[^[:space:]]+)[[:space:]]*$#\1={{ \2 }}#'; }

if [ "${BASH_SOURCE[0]:-}" = "${0}" ]; then
  set -uo pipefail
  main "$@"
fi
```

Note: `main` is referenced by the source-guard but defined in Task 5. Until then, running the script directly errors — that's fine; tests **source** it (the guard prevents `main` from running on source).

- [ ] **Step 3: Write failing unit tests for the pure helpers**

Create `tests/test-secrets.sh`:

```bash
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

t_done
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `chmod +x tests/mock-op && bash tests/test-secrets.sh`
Expected: all `ok`, final `PASS`. (Helpers are pure; no `op` needed yet.)

- [ ] **Step 5: Commit**

```bash
chmod +x tests/mock-op
git add tests/mock-op scripts/secrets.sh tests/test-secrets.sh
git commit -m "feat(secrets): pure helpers (_kv_upsert, _bracewrap) + mock-op fixture"
```

---

### Task 2: Readiness + `status`

**Files:**
- Modify: `scripts/secrets.sh`
- Test: `tests/test-secrets.sh`

- [ ] **Step 1: Add the readiness/config helpers + `secrets_status`**

Insert after `_bracewrap` (before the source-guard) in `scripts/secrets.sh`:

```bash
# op is usable when installed AND signed in (op whoami exits 0 only when authed).
_op_ready() { command -v op >/dev/null 2>&1 && op whoami >/dev/null 2>&1; }

_vault() { # configured vault name (default Launchpad)
  local f="$LP_CFG/secrets.conf"
  if [ -f "$f" ]; then
    # shellcheck disable=SC1090
    ( . "$f" 2>/dev/null; printf '%s' "${SECRETS_VAULT:-Launchpad}" )
  else
    printf 'Launchpad'
  fi
}

_project() { basename "$(pwd)"; }   # 1Password item title = project dir name

secrets_status() {
  if _op_ready; then
    printf '1Password mode (vault: %s)\n' "$(_vault)"
    if [ -f .env.tpl ]; then
      printf '  .env.tpl: %s reference(s)\n' "$(grep -cE '=op://' .env.tpl 2>/dev/null || echo 0)"
    fi
  else
    printf '.env.local mode (1Password not set up — that is fine)\n'
    printf '  to turn on 1Password later: run `op signin`, then `launchpad secrets`.\n'
  fi
}
```

- [ ] **Step 2: Add failing tests for readiness + status**

Append before `t_done` in `tests/test-secrets.sh`:

```bash
# --- _op_ready + secrets_status (mock op on PATH as `op`) ---
MOCKBIN="$(mktemp -d)"; ln -sf "$PWD/tests/mock-op" "$MOCKBIN/op"
OLDPATH="$PATH"; export PATH="$MOCKBIN:$PATH"

MOCK_OP_SIGNED_IN=0 _op_ready; assert_eq "$?" "1" "_op_ready false when not signed in"
MOCK_OP_SIGNED_IN=1 _op_ready; assert_eq "$?" "0" "_op_ready true when signed in"

proj="$(mktemp -d)"; ( cd "$proj"
  assert_eq "$(MOCK_OP_SIGNED_IN=0 secrets_status | head -1)" ".env.local mode (1Password not set up — that is fine)" "status: fallback mode line"
  assert_eq "$(MOCK_OP_SIGNED_IN=1 secrets_status | head -1)" "1Password mode (vault: Launchpad)" "status: op mode line"
)
export PATH="$OLDPATH"
```

- [ ] **Step 3: Run to verify pass**

Run: `bash tests/test-secrets.sh`
Expected: all `ok`, `PASS`.

- [ ] **Step 4: Commit**

```bash
git add scripts/secrets.sh tests/test-secrets.sh
git commit -m "feat(secrets): _op_ready + secrets status (op mode vs .env.local fallback)"
```

---

### Task 3: `secrets set` (both branches)

**Files:**
- Modify: `scripts/secrets.sh`
- Test: `tests/test-secrets.sh`

- [ ] **Step 1: Add `secrets_set`**

Insert after `secrets_status`:

```bash
# Read a secret value: hidden prompt when interactive, else one line from stdin (tests/agents).
_read_value() { # _read_value <name> -> echoes value
  local name="$1" val
  if [ -t 0 ]; then printf 'Value for %s (hidden): ' "$name" >&2; read -rs val; printf '\n' >&2
  else read -r val; fi
  printf '%s' "$val"
}

secrets_set() {
  local name="${1:-}" val
  case "$name" in
    ''|*[!A-Za-z0-9_]*) echo "usage: launchpad secrets set NAME   (NAME = letters/digits/underscore)"; return 1 ;;
  esac
  val="$(_read_value "$name")"
  [ -n "$val" ] || { echo "no value given; nothing stored."; return 1; }
  if _op_ready; then
    local vault proj; vault="$(_vault)"; proj="$(_project)"
    op vault get "$vault" >/dev/null 2>&1 || op vault create "$vault" >/dev/null 2>&1 || true
    if op item get "$proj" --vault "$vault" >/dev/null 2>&1; then
      op item edit "$proj" --vault "$vault" "${name}[password]=${val}" >/dev/null 2>&1
    else
      op item create --category=login --title="$proj" --vault "$vault" "${name}[password]=${val}" >/dev/null 2>&1
    fi
    _kv_upsert .env.tpl "$name" "op://${vault}/${proj}/${name}"
    echo "stored ${name} in 1Password (vault: ${vault}); referenced in .env.tpl"
  else
    _kv_upsert .env.local "$name" "$val"
    echo "saved ${name} to .env.local (1Password not set up). Sign in + re-run to move it into 1Password."
  fi
}
```

- [ ] **Step 2: Add failing tests for both branches**

Append before `t_done`:

```bash
# --- secrets_set: fallback writes .env.local; op-mode writes .env.tpl ---
MOCKBIN2="$(mktemp -d)"; ln -sf "$PWD/tests/mock-op" "$MOCKBIN2/op"; export PATH="$MOCKBIN2:$PATH"

p1="$(mktemp -d)"; ( cd "$p1"
  printf 'sk-secret-123\n' | MOCK_OP_SIGNED_IN=0 secrets_set API_KEY >/dev/null
  assert_eq "$(cat .env.local 2>/dev/null)" "API_KEY=sk-secret-123" "set (fallback) writes value to .env.local"
  assert_eq "$([ -f .env.tpl ] && echo yes || echo no)" "no" "set (fallback) does NOT create .env.tpl"
)
p2="$(mktemp -d)"; ( cd "$p2"
  printf 'sk-secret-123\n' | MOCK_OP_SIGNED_IN=1 secrets_set API_KEY >/dev/null
  assert_eq "$(cat .env.tpl 2>/dev/null)" "API_KEY=op://Launchpad/$(basename "$p2")/API_KEY" "set (op mode) writes an op:// ref to .env.tpl"
  assert_eq "$([ -f .env.local ] && echo yes || echo no)" "no" "set (op mode) keeps the secret out of .env.local"
)
assert_eq "$(printf 'x\n' | secrets_set 'BAD NAME' 2>&1 | head -1)" "usage: launchpad secrets set NAME   (NAME = letters/digits/underscore)" "set rejects invalid NAME"
export PATH="$OLDPATH"
```

- [ ] **Step 3: Run to verify pass**

Run: `bash tests/test-secrets.sh`
Expected: all `ok`, `PASS`.

- [ ] **Step 4: Commit**

```bash
git add scripts/secrets.sh tests/test-secrets.sh
git commit -m "feat(secrets): set — 1Password item + .env.tpl ref, or .env.local fallback"
```

---

### Task 4: `secrets inject`

**Files:**
- Modify: `scripts/secrets.sh`
- Test: `tests/test-secrets.sh`

- [ ] **Step 1: Add `secrets_inject`**

Insert after `secrets_set`:

```bash
secrets_inject() {
  if ! _op_ready; then
    echo "1Password not set up — your values are already in .env.local (nothing to inject)."
    return 0
  fi
  [ -f .env.tpl ] || { echo "no .env.tpl here — add references with 'launchpad secrets set NAME'."; return 0; }
  local tmp; tmp="$(mktemp)"
  if _bracewrap < .env.tpl | op inject >"$tmp" 2>/dev/null; then
    mv "$tmp" .env.local
    echo "wrote .env.local from .env.tpl via 1Password (kept out of git)."
  else
    rm -f "$tmp"; echo "could not inject from 1Password — is op signed in? (.env.local unchanged)"; return 1
  fi
}
```

- [ ] **Step 2: Add failing tests**

Append before `t_done`:

```bash
# --- secrets_inject: op mode resolves .env.tpl -> .env.local; fallback is a no-op ---
export PATH="$MOCKBIN2:$PATH"
p3="$(mktemp -d)"; ( cd "$p3"
  printf 'API_KEY=op://Launchpad/p3/API_KEY\n' > .env.tpl
  MOCK_OP_SIGNED_IN=1 MOCK_OP_VALUE=resolved-secret secrets_inject >/dev/null
  assert_eq "$(cat .env.local 2>/dev/null)" "API_KEY=resolved-secret" "inject (op mode) materializes .env.local from .env.tpl"
)
p4="$(mktemp -d)"; ( cd "$p4"
  out="$(MOCK_OP_SIGNED_IN=0 secrets_inject)"
  assert_eq "$(printf '%s' "$out" | head -1)" "1Password not set up — your values are already in .env.local (nothing to inject)." "inject (fallback) is a friendly no-op"
  assert_eq "$([ -f .env.local ] && echo yes || echo no)" "no" "inject (fallback) writes nothing"
)
export PATH="$OLDPATH"
```

- [ ] **Step 3: Run to verify pass**

Run: `bash tests/test-secrets.sh`
Expected: all `ok`, `PASS`.

- [ ] **Step 4: Commit**

```bash
git add scripts/secrets.sh tests/test-secrets.sh
git commit -m "feat(secrets): inject — bridge .env.tpl through op inject to .env.local"
```

---

### Task 5: `secrets run` + `main` dispatch

**Files:**
- Modify: `scripts/secrets.sh`
- Test: `tests/test-secrets.sh`

- [ ] **Step 1: Add `secrets_run` and `main`**

Insert after `secrets_inject` (still before the source-guard):

```bash
secrets_run() {
  [ "${1:-}" = "--" ] && shift
  [ "$#" -gt 0 ] || { echo "usage: launchpad secrets run -- <command> [args...]"; return 1; }
  if _op_ready && [ -f .env.tpl ]; then
    exec op run --env-file=.env.tpl -- "$@"
  else
    exec "$@"
  fi
}

main() {
  local sub="${1:-status}"; [ "$#" -gt 0 ] && shift || true
  case "$sub" in
    status) secrets_status ;;
    set)    secrets_set "$@" ;;
    inject) secrets_inject ;;
    run)    secrets_run "$@" ;;
    -h|--help|help) echo "launchpad secrets — status | set NAME | inject | run -- CMD" ;;
    *) echo "launchpad secrets — status | set NAME | inject | run -- CMD"; return 1 ;;
  esac
}
```

- [ ] **Step 2: Add failing tests (run in a subshell so `exec` is contained)**

Append before `t_done`:

```bash
# --- secrets_run: op mode injects via op run; fallback execs directly ---
export PATH="$MOCKBIN2:$PATH"
p5="$(mktemp -d)"; ( cd "$p5"; printf 'INJECTED=op://Launchpad/p5/INJECTED\n' > .env.tpl
  out="$( MOCK_OP_SIGNED_IN=1 MOCK_OP_VALUE=via-op secrets_run -- sh -c 'printf "%s" "$INJECTED"' )"
  assert_eq "$out" "via-op" "run (op mode) injects the secret into the child process"
)
p6="$(mktemp -d)"; ( cd "$p6"
  out="$( MOCK_OP_SIGNED_IN=0 secrets_run -- sh -c 'printf ok' )"
  assert_eq "$out" "ok" "run (fallback) execs the command directly"
)
assert_eq "$(secrets_run 2>&1 | head -1)" "usage: launchpad secrets run -- <command> [args...]" "run with no command shows usage"
# --- main dispatch ---
( cd "$(mktemp -d)"; assert_eq "$(MOCK_OP_SIGNED_IN=0 main status | head -1)" ".env.local mode (1Password not set up — that is fine)" "main dispatches status" )
assert_eq "$(main bogus 2>&1 | head -1)" "launchpad secrets — status | set NAME | inject | run -- CMD" "main rejects unknown subcommand"
export PATH="$OLDPATH"
```

- [ ] **Step 3: Run to verify pass**

Run: `bash tests/test-secrets.sh`
Expected: all `ok`, `PASS`.

- [ ] **Step 4: Verify shellcheck is clean**

Run: `shellcheck -S warning scripts/secrets.sh`
Expected: no warnings/errors (info-level SC1090/SC2016 acceptable, as elsewhere in the repo).

- [ ] **Step 5: Commit**

```bash
git add scripts/secrets.sh tests/test-secrets.sh
git commit -m "feat(secrets): run (op run / direct exec) + main dispatch"
```

---

### Task 6: Wire `launchpad secrets` into the dispatcher

**Files:**
- Modify: `scripts/launchpad`

- [ ] **Step 1: Add the `secrets)` case**

In `scripts/launchpad`, in the `case "$cmd"` block, add after the `spend)` line (line ~55):

```bash
  secrets) exec bash "$ROOT/scripts/secrets.sh" "$@" ;;
```

- [ ] **Step 2: Add the usage line**

In the `usage()` heredoc, add after the `launchpad spend` line:

```
  launchpad secrets   Store/use API keys safely (1Password, or a local file)
```

- [ ] **Step 3: Verify dispatch works**

Run: `bash scripts/launchpad secrets status`
Expected: prints either "1Password mode (vault: Launchpad)" (if you happen to be signed in) or ".env.local mode (1Password not set up — that is fine)". Either is correct.

- [ ] **Step 4: Commit**

```bash
git add scripts/launchpad
git commit -m "feat: launchpad secrets dispatch + usage line"
```

---

### Task 7: New core module `modules/07-secrets.sh` + install-profile wiring

**Files:**
- Create: `modules/07-secrets.sh`
- Modify: `scripts/install-profile.sh:45`

- [ ] **Step 1: Write the module**

Create `modules/07-secrets.sh`:

```bash
#!/usr/bin/env bash
# modules/07-secrets.sh — wire the (already-installed) 1Password CLI into the
# optional `launchpad secrets` toolset. Core module: runs for every profile.
# Optional by design: no sign-in, no desktop app, never blocks. The .env.local
# fallback works with zero 1Password setup; signing in later "just works".
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=../lib/common.sh
. "$HERE/../lib/common.sh"
ensure_brew_env

log_step "Secret management (1Password CLI)"

# 1Password CLI is installed by 00-foundation; self-heal if somehow absent.
if have op; then
  log_ok "1Password CLI (op) present ($(op --version 2>/dev/null || echo '?'))"
else
  brew_install 1password-cli
fi

# Make the helper executable (it's dispatched by `launchpad secrets`).
if [ -f "$LP_ROOT/scripts/secrets.sh" ]; then
  chmod +x "$LP_ROOT/scripts/secrets.sh" 2>/dev/null || true
  log_ok "launchpad secrets ready (scripts/secrets.sh)"
else
  log_warn "scripts/secrets.sh missing — launchpad secrets unavailable"
fi

# Do NOT sign in / create accounts / install the desktop app — that's a human,
# optional step. Just say it's ready.
if have op && ! op whoami >/dev/null 2>&1; then
  log_note "1Password is optional and not signed in — run 'launchpad secrets' when you want it; until then secrets use .env.local."
fi

log_ok "Secret management ready (optional; .env.local fallback always works)"
```

- [ ] **Step 2: Add it to the core module loop**

In `scripts/install-profile.sh`, change the core loop (line ~45) from:

```bash
for m in 00-foundation.sh 01-shell.sh 02-terminal.sh 03-editors.sh 05-agents.sh 06-skills.sh 08-safety.sh 09-dx.sh; do
```

to (insert `07-secrets.sh` before `08-safety.sh`):

```bash
for m in 00-foundation.sh 01-shell.sh 02-terminal.sh 03-editors.sh 05-agents.sh 06-skills.sh 07-secrets.sh 08-safety.sh 09-dx.sh; do
```

- [ ] **Step 3: Run the module to verify it's idempotent and clean**

Run: `chmod +x modules/07-secrets.sh && bash modules/07-secrets.sh && bash modules/07-secrets.sh`
Expected: both runs succeed; second run shows "present"/"ready" lines (idempotent), exit 0.

- [ ] **Step 4: Commit**

```bash
git add modules/07-secrets.sh scripts/install-profile.sh
git commit -m "feat(secrets): core module 07-secrets.sh + add to install-profile core loop"
```

---

### Task 8: Static config — gitignore allow-list + agent house-rule

**Files:**
- Modify: `config/safety/gitignore.global`
- Modify: `config/agents/AGENTS.md:31-32`

- [ ] **Step 1: Allow-list `.env.tpl` in the global gitignore**

In `config/safety/gitignore.global`, in the secrets allow-list block, add `!.env.tpl` after the existing `!.env.sample` line:

```
!.env.example
!.env.template
!.env.sample
!.env.tpl
```

(`.env.tpl` holds only `op://` references — no secrets — so it is meant to be committed and shared; real `.env.local` stays ignored by `.env.*`.)

- [ ] **Step 2: Extend the agent house-rule**

In `config/agents/AGENTS.md`, replace the "Never hardcode secrets" bullet (lines 31–32):

```markdown
- **Never hardcode secrets** (API keys, passwords, tokens). Put them in a
  `.env` / `.env.local` file (git-ignored for you) and read from the environment.
```

with:

```markdown
- **Never hardcode secrets** (API keys, passwords, tokens). Prefer 1Password:
  store a new secret with `launchpad secrets set NAME`, run dev with
  `launchpad secrets run -- <cmd>` (injected in memory, no plaintext on disk), or
  materialise a local file with `launchpad secrets inject`. When 1Password isn't
  set up, fall back to a `.env` / `.env.local` file (git-ignored) and read from the
  environment. Never hardcode, and never commit `.env.local`.
```

- [ ] **Step 3: Verify the gitignore allow-list actually un-ignores `.env.tpl`**

Run:
```bash
tmp="$(mktemp -d)" && cd "$tmp" && git init -q \
  && git config core.excludesfile "$OLDPWD/config/safety/gitignore.global" \
  && touch .env.tpl .env.local \
  && echo "tpl: $(git check-ignore .env.tpl || echo NOT-IGNORED)" \
  && echo "local: $(git check-ignore .env.local || echo NOT-IGNORED)"; cd "$OLDPWD"
```
Expected: `tpl: NOT-IGNORED` and `local: .env.local` (i.e. `.env.tpl` is committable, `.env.local` is ignored).

- [ ] **Step 4: Commit**

```bash
git add config/safety/gitignore.global config/agents/AGENTS.md
git commit -m "feat(secrets): allow-list .env.tpl + agent house-rule prefers 1Password"
```

---

### Task 9: Doctor checks + section→module map

**Files:**
- Modify: `lib/doctor.sh:51` (the `_section_modules` map) and `:171` (after the pre-warm check)
- Modify: `tests/test-doctorfix.sh`

- [ ] **Step 1: Add the secrets checks in the "Safety net" section**

In `lib/doctor.sh`, after the `softck "pre-commit hooks pre-warmed" …` line (~171), add:

```bash
check  "1Password CLI (op)"               'command -v op'
softck "1Password signed in (optional)"   'op whoami'
```

(`op` presence is hard — foundation installs it; sign-in is soft — it needs a human, like the GitHub/Sentry sign-ins.)

- [ ] **Step 2: Map the "Safety net" section to include 07-secrets**

In `_section_modules`, change:

```bash
    "Safety net") echo "08-safety.sh" ;;
```

to:

```bash
    "Safety net") echo "07-secrets.sh 08-safety.sh" ;;
```

(So `doctor --fix` on a red `op` check re-runs the secrets module too — both are idempotent.)

- [ ] **Step 3: Add a failing assertion to the map unit test**

In `tests/test-doctorfix.sh`, add (the file extracts `_section_modules` via the existing harness — match its `assert_eq` style):

```bash
assert_eq "$(_section_modules 'Safety net')" "07-secrets.sh 08-safety.sh" "safety net -> 07 + 08"
```

(Update the existing `safety net -> 08` assertion if present, or replace it with this one.)

- [ ] **Step 4: Run the map test + doctor**

Run: `bash tests/test-doctorfix.sh && bash lib/doctor.sh >/dev/null 2>&1; echo "doctor rc=$?"`
Expected: `test-doctorfix.sh` → `PASS`. doctor exits 0 if `op` is installed (it is, from foundation); the sign-in line is yellow when not signed in (not a failure).

- [ ] **Step 5: Commit**

```bash
git add lib/doctor.sh tests/test-doctorfix.sh
git commit -m "feat(doctor): op presence (hard) + sign-in (soft) checks; map Safety net -> 07+08"
```

---

### Task 10: VM integration probe

**Files:**
- Create: `dogfood/remote-addon08.sh`

- [ ] **Step 1: Write the probe**

Create `dogfood/remote-addon08.sh` (runs inside a throwaway VM; reads the repo from the read-only share; uses the mock `op` so no real account is needed):

```bash
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
  grep -q '^API_KEY=v1$' .env.local ) && echo "PROBE:set_fallback=PASS" || echo "PROBE:set_fallback=FAIL"
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
bash "$ROOT/scripts/launchpad" secrets status >/tmp/lps8.out 2>&1 && grep -qiE 'mode' /tmp/lps8.out && echo "PROBE:dispatch=PASS" || echo "PROBE:dispatch=FAIL"

# gitignore: .env.tpl committable, .env.local ignored (08-safety wired the global gitignore)
pg="$(mktemp -d)"; ( cd "$pg"; git init -q; touch .env.tpl .env.local
  ! git check-ignore -q .env.tpl && git check-ignore -q .env.local ) && echo "PROBE:gitignore=PASS" || echo "PROBE:gitignore=FAIL"

# doctor: op present (hard) passes; running doctor doesn't error on the secrets checks
( cd "$ROOT" && bash lib/doctor.sh >/tmp/doc8.out 2>&1; grep -q '1Password CLI (op)' /tmp/doc8.out ) && echo "PROBE:doctor=PASS" || echo "PROBE:doctor=FAIL"

echo "##### ADDON08 PROBE DONE #####"
```

- [ ] **Step 2: Shellcheck the probe**

Run: `shellcheck dogfood/remote-addon08.sh`
Expected: only info-level notes (SC2015 etc.), consistent with `dogfood/remote-addon07.sh`.

- [ ] **Step 3: Commit**

```bash
chmod +x dogfood/remote-addon08.sh
git add dogfood/remote-addon08.sh
git commit -m "test(addon-08): VM probe — secrets set/inject/run/status + gitignore + doctor (mock op)"
```

> The VM run itself is the final validation step (Task 12), executed by the controller.

---

### Task 11: Docs

**Files:**
- Modify: `docs/recipes.html` (new section)
- Modify: `docs/getting-started.html` (callout in the secrets section)
- Modify: `docs/cheatsheet.html` (Safety section)
- Modify: `README.md` (audit row + core-module list)

- [ ] **Step 1: Add a recipe to `docs/recipes.html`**

Insert a new `<section>` after the "See your data" section (before "Put it online"), matching the existing structure:

```html
  <section>
    <h2>Keep my keys safe (1Password)</h2>
    <p>If you use <strong>1Password</strong>, your API keys can live there instead of a plain file — and an assistant can run your app with them injected in memory, never written to disk. Optional: if you skip it, keys just live in a git-ignored <code>.env.local</code> as usual.</p>
    <div class="codeblock"><pre><code>launchpad secrets set STRIPE_SECRET_KEY   # store a key (in 1Password if signed in)
launchpad secrets run -- npm run dev      # run with secrets injected, nothing on disk
launchpad secrets status                  # which mode am I in?</code></pre></div>
    <p class="muted">Not signed in to 1Password? Every command falls back to <code>.env.local</code> and tells you so — turn 1Password on anytime with <code>op signin</code>.</p>
  </section>
```

- [ ] **Step 2: Add a callout to `docs/getting-started.html`**

In the secrets warning area of section 6 (after the 🔒 "Never paste passwords" callout), add:

```html
    <div class="callout note"><div class="ico" aria-hidden="true">🔑</div><p><strong>Using 1Password?</strong> You can keep API keys there instead of a file: <code>launchpad secrets set NAME</code> to store one, and <code>launchpad secrets run -- npm run dev</code> to run your app with keys injected in memory. It's optional — without it, keys live safely in a git-ignored <code>.env.local</code>.</p></div>
```

- [ ] **Step 3: Add cheatsheet lines to `docs/cheatsheet.html`**

In the "Safety, data &amp; backups" `<dl class="kv">`, after the `launchpad nudge off` entry, add:

```html
      <dt>launchpad secrets set NAME</dt><dd>Store an API key (in 1Password if you're signed in, otherwise a git-ignored <code>.env.local</code>).</dd>
      <dt>launchpad secrets run -- <em>cmd</em></dt><dd>Run a command with your secrets injected in memory — nothing written to disk.</dd>
```

- [ ] **Step 4: Update `README.md`**

(a) Add an audit row after the **Add-on 07** row (~line 106):

```
| **Add-on 08** | secret management: optional 1Password (`op`) wiring — `launchpad secrets set/inject/run` over a committed secret-free `.env.tpl` (`op://` refs), `.env.local` fallback that never blocks; `07-secrets.sh` (core); op `inject {{ }}` vs `run KEY=op://` formats verified on op 2.34.1 |
```

(b) Update the core-module list (~line 31) to include `07`:

```
modules/00,01,02,03,05,06,07,08,09  core (every profile): foundation, shell, terminal, editors, agents, skills, secrets, safety, dx
```

- [ ] **Step 5: Commit**

```bash
git add docs/recipes.html docs/getting-started.html docs/cheatsheet.html README.md
git commit -m "docs(addon-08): launchpad secrets — recipe, getting-started callout, cheatsheet, README audit"
```

---

### Task 12: Final validation (controller)

**Files:** none (validation only)

- [ ] **Step 1: Run the full host unit suite**

Run: `bash tests/test-secrets.sh && bash tests/test-doctorfix.sh && bash tests/test-spend.sh`
Expected: three `PASS` lines.

- [ ] **Step 2: Shellcheck all new/changed scripts**

Run: `shellcheck -S warning scripts/secrets.sh modules/07-secrets.sh lib/doctor.sh scripts/launchpad && shellcheck dogfood/remote-addon08.sh`
Expected: no warnings/errors (info-level acceptable).

- [ ] **Step 3: Run the VM probe**

Run: `TART_VM=launchpad-addon08 bash dogfood/vm-probes.sh dogfood/remote-addon08.sh`
Expected: every `PROBE:*=PASS`, exit 0.

- [ ] **Step 4: Final review + finish the branch**

Dispatch a final code reviewer over `main..HEAD`; on READY TO MERGE, use superpowers:finishing-a-development-branch (squash-merge to `main`, push, verify Pages — matching the Add-on 07 release).

---

## Self-Review

**1. Spec coverage:**
- Module `07-secrets.sh` core + install-profile loop → Task 7. ✓
- `scripts/secrets.sh` status/set/inject/run, op-optional, `.env.local` fallback → Tasks 1–5. ✓
- `.env.tpl` op-run format + brace-wrap bridge for inject → Tasks 1, 4 (`_bracewrap`, `secrets_inject`). ✓
- Dispatch in `scripts/launchpad` → Task 6. ✓
- Doctor soft-check in Safety net + map → Task 9. ✓
- AGENTS.md house-rule (static edit, symlinked) → Task 8. ✓
- `!.env.tpl` in `config/safety/gitignore.global` → Task 8. ✓
- Unit tests with mock op (both branches) → Tasks 1–5 + fixture in Task 1. ✓
- VM probe `dogfood/remote-addon08.sh` → Task 10. ✓
- Docs (recipes, getting-started, cheatsheet, README audit) → Task 11. ✓
- Build-time verifications (op item syntax, whoami contract, inject/run formats) → resolved in plan header. ✓
- Vault default `Launchpad` configurable via `secrets.conf` → Task 2 (`_vault`). ✓

**2. Placeholder scan:** No TBD/TODO; every code step has complete code; every test has real assertions and expected output. ✓

**3. Type/name consistency:** `_op_ready`, `_vault`, `_project`, `_kv_upsert`, `_bracewrap`, `_read_value`, `secrets_status/set/inject/run`, `main` — defined in Tasks 1–5 and used consistently in Tasks 6, 9, 10. `.env.tpl` (op-run format) and `.env.local` used consistently. Mock-op env switches (`MOCK_OP_SIGNED_IN`, `MOCK_OP_HAS_ITEM`, `MOCK_OP_VALUE`, `MOCK_OP_HAS_VAULT`) consistent between fixture (Task 1) and tests/probe (Tasks 2–5, 10). ✓

**Residual risk (documented, accepted per spec):** the live signed-in `op item create/edit` path can't be exercised without a real 1Password account (the user opted out); its **syntax** is verified against op 2.34.1 and its **call path** is covered by the mock. Full live validation is sign-in-gated.
