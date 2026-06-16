# Add-on 09 — Loops & onboarding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add three `launchpad` commands — `status` (a ~/Developer backup-state dashboard), `signin` (a guided sign-in checklist), and `sentry-setup` (write a Sentry DSN into a project) — each a self-contained, source-guarded bash script with unit-tested pure logic.

**Architecture:** Three new `scripts/*.sh`, each self-contained (no `lib/common.sh`), source-guarded so tests can source them without running `main` (the `scripts/secrets.sh` pattern). Pure classifier/formatter/validator functions are unit-tested; the I/O (git scans, tool detection, file writes) is exercised by a VM probe. The Sentry MCP "automatic" path is an `AGENTS.md` agent recipe (a shell can't call MCP tools); the shell does the deterministic DSN write + a wizard fallback.

**Tech Stack:** POSIX/bash 3.2, git, awk/sed, optional `lsof`/`gh`/`claude`/`op`, `npx @sentry/wizard`, the repo's `tests/lib.sh` harness.

**Spec:** `dogfood/specs/2026-06-16-addon-09-loops-onboarding-design.md`.

**Conventions for the implementer:**
- Each script ends with the source-guard `if [ "${BASH_SOURCE[0]:-}" = "${0}" ]; then set -uo pipefail; main "$@"; fi` so sourcing it in tests does NOT run `main`.
- Tests use `tests/lib.sh` (`assert_eq <actual> <expected> <msg>`, `t_done`); `tests/test-spend.sh` / `tests/test-secrets.sh` are working examples.
- The pure functions echo to stdout (capture with `$(...)`); detection wrappers return exit codes.
- Keep shellcheck `-S warning` clean (info-level SC1090/SC2016 acceptable as elsewhere).
- `chmod +x` each new script before committing (commit them as `100755`, like the sibling scripts).
- Output uses `✓`, `•`, and `—` (em dash) — copy these literals exactly; tests assert them byte-for-byte.

**Build-time verifications (do these as you reach the relevant task):**
- `npx @sentry/wizard@latest -i nextjs` is the current wizard invocation for Next.js (fallback path; not VM-tested) — confirm the `-i nextjs` flag still selects the Next.js integration.
- `lsof -nP -iTCP -sTCP:LISTEN` + per-pid `lsof -a -p <pid> -d cwd -Fn` works on the VM/host for best-effort port→repo mapping (degrade to `—` if not).
- The `sentry_dsn_valid` glob accepts current real DSNs (region subdomains like `…ingest.us.sentry.io`, `…ingest.de.sentry.io`, legacy `@sentry.io`).

---

### Task 1: `scripts/status.sh` — backup-state dashboard

**Files:**
- Create: `scripts/status.sh`
- Create: `tests/test-status.sh`

- [ ] **Step 1: Write the failing unit tests**

Create `tests/test-status.sh`:

```bash
#!/usr/bin/env bash
# tests/test-status.sh
cd "$(dirname "$0")/.." || exit 1
. tests/lib.sh
. scripts/status.sh   # sourcing must NOT run main

# status_classify <dirty> <ahead> <has_remote> -> "ok|phrase" / "warn|phrase"
assert_eq "$(status_classify 0 0 1)" "ok|backed up"                 "clean+remote = backed up"
assert_eq "$(status_classify 3 0 1)" "warn|3 unsaved"               "dirty = unsaved"
assert_eq "$(status_classify 0 2 1)" "warn|2 unpushed"              "ahead = unpushed"
assert_eq "$(status_classify 3 2 1)" "warn|3 unsaved, 2 unpushed"   "dirty+ahead"
assert_eq "$(status_classify 0 0 0)" "warn|no remote yet"           "no remote"
assert_eq "$(status_classify 5 1 0)" "warn|no remote yet"           "no remote dominates"

# _age <seconds> -> now / Nm / Nh / Nd
assert_eq "$(_age 30)"     "now" "age < 1m"
assert_eq "$(_age 120)"    "2m"  "age minutes"
assert_eq "$(_age 7200)"   "2h"  "age hours"
assert_eq "$(_age 259200)" "3d"  "age days"

t_done
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash tests/test-status.sh`
Expected: FAIL (functions not defined / file missing).

- [ ] **Step 3: Write `scripts/status.sh`**

```bash
#!/usr/bin/env bash
#
# scripts/status.sh — `launchpad status`
#
# A fast dashboard of every git project directly under ~/Developer. Headline:
# is your work backed up? (clean / unsaved / unpushed / no-remote-yet). Plus a
# best-effort running dev-server port and the last-commit age. Local git only —
# no network — so it stays fast across many repos.

DEV_DIR="${DEVELOPER_DIR:-$HOME/Developer}"

# --- pure helpers (unit-tested) ---------------------------------------------
# status_classify <dirty_count> <ahead_count> <has_remote 0|1> -> "ok|phrase" or "warn|phrase"
status_classify() {
  local dirty="$1" ahead="$2" remote="$3" parts=""
  if [ "$remote" = 0 ]; then printf 'warn|no remote yet'; return 0; fi
  [ "${dirty:-0}" -gt 0 ] 2>/dev/null && parts="${dirty} unsaved"
  [ "${ahead:-0}" -gt 0 ] 2>/dev/null && parts="${parts:+$parts, }${ahead} unpushed"
  if [ -n "$parts" ]; then printf 'warn|%s' "$parts"; else printf 'ok|backed up'; fi
}

# _age <seconds> -> "now" / "5m" / "2h" / "3d"
_age() {
  local s="${1:-0}"
  if   [ "$s" -lt 60 ]    2>/dev/null; then printf 'now'
  elif [ "$s" -lt 3600 ]  2>/dev/null; then printf '%dm' "$((s/60))"
  elif [ "$s" -lt 86400 ] 2>/dev/null; then printf '%dh' "$((s/3600))"
  else printf '%dd' "$((s/86400))"; fi
}

# --- best-effort running dev-server port (not unit-tested; fully defended) ---
_running_port() { # _running_port <repo-abspath> -> echoes a port or nothing
  command -v lsof >/dev/null 2>&1 || return 0
  local repo="$1" pid port cwd
  lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null | awk 'NR>1{n=split($9,a,":"); if(n>1) print $2, a[n]}' | sort -u | while read -r pid port; do
    cwd="$(lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -1)"
    case "$cwd" in "$repo"|"$repo"/*) printf '%s' "$port"; break ;; esac
  done
}

# --- render ------------------------------------------------------------------
main() {
  local G='' Y='' D='' R='' B=''
  if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    G=$'\033[32m'; Y=$'\033[33m'; D=$'\033[2m'; R=$'\033[0m'; B=$'\033[1m'
  fi
  [ -d "$DEV_DIR" ] || { echo "no ~/Developer yet — 'mkproj <name>' to start."; return 0; }

  local found=0 repo name dirty ahead remote out sev phrase port ct now age col
  now="$(date +%s)"
  printf '%s%-20s %-26s %-7s %5s%s\n' "$B" "project" "backup" "running" "age" "$R"
  for repo in "$DEV_DIR"/*/; do
    [ -d "${repo}.git" ] || continue
    repo="${repo%/}"; name="$(basename "$repo")"; found=$((found+1))
    dirty="$(git -C "$repo" status --porcelain 2>/dev/null | grep -c .)"
    if git -C "$repo" rev-parse '@{u}' >/dev/null 2>&1; then
      ahead="$(git -C "$repo" rev-list '@{u}..HEAD' --count 2>/dev/null || echo 0)"
    else ahead=0; fi
    if git -C "$repo" remote 2>/dev/null | grep -q .; then remote=1; else remote=0; fi
    out="$(status_classify "$dirty" "$ahead" "$remote")"; sev="${out%%|*}"; phrase="${out#*|}"
    ct="$(git -C "$repo" log -1 --format=%ct 2>/dev/null || echo "$now")"
    age="$(_age "$((now-ct))")"
    port="$(_running_port "$repo")"
    col="$G"; [ "$sev" = warn ] && col="$Y"
    printf '%-20.20s %s%-26s%s %-7s %5s\n' "$name" "$col" "$phrase" "$R" "${port:+:$port}" "$age"
  done
  [ "$found" = 0 ] && { printf '%sno projects yet — '"'"'mkproj <name>'"'"' to start.%s\n' "$D" "$R"; }
}

if [ "${BASH_SOURCE[0]:-}" = "${0}" ]; then
  set -uo pipefail
  main "$@"
fi
```

- [ ] **Step 4: Run to verify it passes**

Run: `bash tests/test-status.sh`
Expected: 10 `ok`, `PASS`.

- [ ] **Step 5: Shellcheck + commit**

Run: `shellcheck -S warning scripts/status.sh` (expect clean).
```bash
chmod +x scripts/status.sh
git add scripts/status.sh tests/test-status.sh
git commit -m "feat(status): launchpad status — backup-state dashboard (status_classify, _age) + tests"
```

---

### Task 2: `scripts/signin.sh` — guided sign-in checklist

**Files:**
- Create: `scripts/signin.sh`
- Create: `tests/test-signin.sh`

- [ ] **Step 1: Write the failing unit tests**

Create `tests/test-signin.sh`:

```bash
#!/usr/bin/env bash
# tests/test-signin.sh
cd "$(dirname "$0")/.." || exit 1
. tests/lib.sh
. scripts/signin.sh   # sourcing must NOT run main

# signin_line <ok 0|1> <service> <action> <unlocks>
assert_eq "$(signin_line 1 GitHub 'run gh auth login' 'private backups')" \
          "  ✓ GitHub — ready" "ok line"
assert_eq "$(signin_line 0 GitHub 'run gh auth login' 'private backups')" \
          "  • GitHub — run gh auth login   (unlocks: private backups)" "todo line"

# detection wrapper with a mock `gh` on PATH
MB="$(mktemp -d)"
printf '#!/bin/sh\nexit 0\n' > "$MB/gh"; chmod +x "$MB/gh"
assert_eq "$(PATH="$MB:$PATH" _yn _gh_ok)" "1" "_gh_ok true when gh auth status exits 0"
printf '#!/bin/sh\nexit 1\n' > "$MB/gh"
assert_eq "$(PATH="$MB:$PATH" _yn _gh_ok)" "0" "_gh_ok false when gh auth status exits 1"

t_done
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash tests/test-signin.sh`
Expected: FAIL (functions not defined / file missing).

- [ ] **Step 3: Write `scripts/signin.sh`**

```bash
#!/usr/bin/env bash
#
# scripts/signin.sh — `launchpad signin`
#
# A guided checklist of the setup's external sign-ins. For each service: ✓ if
# you're set, or the exact action + what it unlocks. It GUIDES — it never signs
# you in for you. Idempotent, read-only, safe to run anytime.

# --- pure formatter (unit-tested) -------------------------------------------
# signin_line <ok 0|1> <service> <action> <unlocks>
signin_line() {
  if [ "$1" = 1 ]; then
    printf '  ✓ %s — ready\n' "$2"
  else
    printf '  • %s — %s   (unlocks: %s)\n' "$2" "$3" "$4"
  fi
}

# --- thin detection wrappers ------------------------------------------------
_gh_ok()      { command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; }
_sentry_ok()  { command -v claude >/dev/null 2>&1 && claude mcp get sentry >/dev/null 2>&1; }
_herenow_ok() { [ -f "$HOME/.herenow/credentials" ] || [ -n "${HERENOW_API_KEY:-}" ]; }
_agent_ok()   { command -v "$1" >/dev/null 2>&1; }

# _yn <cmd...> -> echoes 1 if the command succeeds, else 0
_yn() { if "$@" >/dev/null 2>&1; then echo 1; else echo 0; fi; }

main() {
  local ready=0 total=0 ok
  echo "Sign-in checklist:"

  ok="$(_yn _gh_ok)";            total=$((total+1)); [ "$ok" = 1 ] && ready=$((ready+1))
  signin_line "$ok" "GitHub"   "run gh auth login" "private project backups + the GitHub MCP"

  ok="$(_yn _sentry_ok)";        total=$((total+1)); [ "$ok" = 1 ] && ready=$((ready+1))
  signin_line "$ok" "Sentry"   "type /mcp in claude (then codex/agy) and sign in" "agents read your app's runtime errors"

  ok="$(_yn _herenow_ok)";       total=$((total+1)); [ "$ok" = 1 ] && ready=$((ready+1))
  signin_line "$ok" "here.now" "sign up at here.now and add your key" "permanent published links (anonymous works without)"

  ok="$(_yn _agent_ok claude)";  total=$((total+1)); [ "$ok" = 1 ] && ready=$((ready+1))
  signin_line "$ok" "Claude Code" "run claude and sign in with your Claude account" "the main assistant"

  printf '\n%d of %d ready.\n' "$ready" "$total"
}

if [ "${BASH_SOURCE[0]:-}" = "${0}" ]; then
  set -uo pipefail
  main "$@"
fi
```

- [ ] **Step 4: Run to verify it passes**

Run: `bash tests/test-signin.sh`
Expected: 4 `ok`, `PASS`.

- [ ] **Step 5: Shellcheck + commit**

Run: `shellcheck -S warning scripts/signin.sh` (expect clean).
```bash
chmod +x scripts/signin.sh
git add scripts/signin.sh tests/test-signin.sh
git commit -m "feat(signin): launchpad signin — guided sign-in checklist (signin_line + detection) + tests"
```

---

### Task 3: `scripts/sentry-setup.sh` — write a Sentry DSN into a project

**Files:**
- Create: `scripts/sentry-setup.sh`
- Create: `tests/test-sentry.sh`

- [ ] **Step 1: Write the failing unit tests**

Create `tests/test-sentry.sh`:

```bash
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash tests/test-sentry.sh`
Expected: FAIL (functions not defined / file missing).

- [ ] **Step 3: Write `scripts/sentry-setup.sh`**

```bash
#!/usr/bin/env bash
#
# scripts/sentry-setup.sh — `launchpad sentry-setup [--dsn <dsn>] [--wizard]`
#
# Write a Sentry DSN into the current project's .env.local so the pre-wired
# @sentry/nextjs starts reporting errors. The DSN comes from --dsn, the
# SENTRY_DSN env var, or an interactive paste. `--wizard` runs the vendor
# wizard. The "automatic" path is an AGENTS.md agent recipe (the agent fetches
# the DSN via its Sentry MCP, then calls this with --dsn) — a shell can't call MCP.

# --- pure helpers (unit-tested) ---------------------------------------------
# sentry_dsn_valid <string> -> 0 if it looks like a Sentry DSN (https://<key>@<host>sentry.io/<id>)
sentry_dsn_valid() {
  case "$1" in
    https://*@*sentry.io/[0-9]*) return 0 ;;
    *) return 1 ;;
  esac
}

# _env_upsert <file> <key> <val> — add or replace KEY=val (ENVIRON[] => backslash-safe)
_env_upsert() {
  local file="$1" key="$2" val="$3" tmp
  [ -d "$(dirname "$file")" ] || mkdir -p "$(dirname "$file")"
  tmp="$(mktemp)"
  if [ -f "$file" ] && grep -qE "^${key}=" "$file"; then
    K="$key" V="$val" awk 'BEGIN{FS="="} $1==ENVIRON["K"]{print ENVIRON["K"]"="ENVIRON["V"]; next} {print}' "$file" >"$tmp"
  else
    [ -f "$file" ] && cat "$file" >"$tmp"
    printf '%s=%s\n' "$key" "$val" >>"$tmp"
  fi
  mv "$tmp" "$file"
}

# sentry_env_upsert <file> <dsn> — write both keys the template reads
sentry_env_upsert() {
  _env_upsert "$1" NEXT_PUBLIC_SENTRY_DSN "$2"
  _env_upsert "$1" SENTRY_DSN "$2"
}

main() {
  local dsn="" wizard=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --dsn)     dsn="${2:-}"; shift 2 ;;
      --dsn=*)   dsn="${1#*=}"; shift ;;
      --wizard)  wizard=1; shift ;;
      -h|--help) echo "usage: launchpad sentry-setup [--dsn <dsn>] [--wizard]"; return 0 ;;
      *)         shift ;;
    esac
  done

  if [ "$wizard" = 1 ]; then exec npx @sentry/wizard@latest -i nextjs; fi

  [ -n "$dsn" ] || dsn="${SENTRY_DSN:-}"
  if [ -z "$dsn" ]; then
    [ -t 0 ] && printf 'Paste your Sentry DSN (from sentry.io): ' >&2
    read -r dsn
  fi
  if ! sentry_dsn_valid "$dsn"; then
    echo "that doesn't look like a Sentry DSN (expected https://…@…sentry.io/<id>). Nothing written." >&2
    return 1
  fi
  sentry_env_upsert .env.local "$dsn"
  echo "wrote NEXT_PUBLIC_SENTRY_DSN + SENTRY_DSN to .env.local — error reporting is on."
  if command -v op >/dev/null 2>&1 && op whoami >/dev/null 2>&1; then
    echo "tip: 'launchpad secrets set SENTRY_DSN' to keep it in 1Password instead."
  fi
}

if [ "${BASH_SOURCE[0]:-}" = "${0}" ]; then
  set -uo pipefail
  main "$@"
fi
```

- [ ] **Step 4: Run to verify it passes**

Run: `bash tests/test-sentry.sh`
Expected: 11 `ok`, `PASS`.

- [ ] **Step 5: Shellcheck + commit**

Run: `shellcheck -S warning scripts/sentry-setup.sh` (expect clean — info SC1090/SC2016 ok).
```bash
chmod +x scripts/sentry-setup.sh
git add scripts/sentry-setup.sh tests/test-sentry.sh
git commit -m "feat(sentry): launchpad sentry-setup — DSN validate + .env.local upsert + wizard fallback"
```

---

### Task 4: Wire the dispatcher

**Files:**
- Modify: `scripts/launchpad`

- [ ] **Step 1: Add the three cases**

In `scripts/launchpad`, in the `case "$cmd"` block, add after the `secrets)` line:

```bash
  status)       exec bash "$ROOT/scripts/status.sh" "$@" ;;
  signin)       exec bash "$ROOT/scripts/signin.sh" "$@" ;;
  sentry-setup) exec bash "$ROOT/scripts/sentry-setup.sh" "$@" ;;
```

- [ ] **Step 2: Add usage lines**

In the `usage()` heredoc, after the `launchpad secrets` line, add:

```
  launchpad status    See all your projects + which need a backup
  launchpad signin    Guided checklist of the sign-ins (GitHub, Sentry, here.now)
  launchpad sentry-setup  Turn on error tracking for this project (writes the DSN)
```

- [ ] **Step 3: Verify dispatch**

Run: `bash scripts/launchpad status` (prints a table or the "no ~/Developer" line), `bash scripts/launchpad signin` (prints the checklist), `bash scripts/launchpad help` (shows the three new lines).
Expected: each runs without error.

- [ ] **Step 4: Commit**

```bash
git add scripts/launchpad
git commit -m "feat: launchpad status / signin / sentry-setup dispatch + usage"
```

---

### Task 5: Doctor check + module chmod

**Files:**
- Modify: `lib/doctor.sh` (Developer experience section, ~line 182)
- Modify: `modules/09-dx.sh`

- [ ] **Step 1: Add the doctor check**

In `lib/doctor.sh`, in the "Developer experience" section, after the `check "spend-check script" …` line, add:

```bash
check  "loops & onboarding scripts"  'test -x "$LP_ROOT/scripts/status.sh" && test -x "$LP_ROOT/scripts/signin.sh" && test -x "$LP_ROOT/scripts/sentry-setup.sh"'
```

- [ ] **Step 2: Make the scripts executable at install time**

In `modules/09-dx.sh`, find the existing `chmod +x "$LP_ROOT/scripts/spend-check.sh"` (the spend-guardrail section). Immediately after it, add:

```bash
chmod +x "$LP_ROOT/scripts/status.sh" "$LP_ROOT/scripts/signin.sh" "$LP_ROOT/scripts/sentry-setup.sh" 2>/dev/null || true
```

- [ ] **Step 3: Verify**

Run: `bash lib/doctor.sh 2>&1 | grep -i 'loops & onboarding'` (the line appears, green ✔ — the scripts are committed executable).
Run: `shellcheck -S warning lib/doctor.sh modules/09-dx.sh` (clean).

- [ ] **Step 4: Commit**

```bash
git add lib/doctor.sh modules/09-dx.sh
git commit -m "feat(doctor): check status/signin/sentry-setup scripts; 09-dx makes them executable"
```

---

### Task 6: Agent recipe — "turn on error tracking"

**Files:**
- Modify: `config/agents/AGENTS.md`

- [ ] **Step 1: Add the recipe**

In `config/agents/AGENTS.md`, find the error-tracking section (the bullet that begins "**Check Sentry first when something breaks.**"). Immediately after that bullet, add a new bullet:

```markdown
- **Turning on error tracking is automatic.** When the user wants Sentry on for a
  project, use your **Sentry MCP** to find or create their project and read its
  client key (DSN), then run `launchpad sentry-setup --dsn <dsn>` in the project
  to write `NEXT_PUBLIC_SENTRY_DSN` + `SENTRY_DSN` into `.env.local`. If the Sentry
  MCP isn't signed in, fall back to `launchpad sentry-setup --wizard` (the vendor
  flow) or have them paste a DSN from sentry.io into `launchpad sentry-setup`.
  You can also run `launchpad status` (project backup overview) and `launchpad
  signin` (sign-in checklist) to help the user.
```

- [ ] **Step 2: Verify**

Run: `grep -n 'launchpad sentry-setup' config/agents/AGENTS.md` (the recipe is present).

- [ ] **Step 3: Commit**

```bash
git add config/agents/AGENTS.md
git commit -m "docs(agents): 'turn on error tracking' recipe (Sentry MCP -> launchpad sentry-setup)"
```

---

### Task 7: Docs

**Files:**
- Modify: `docs/cheatsheet.html`
- Modify: `docs/recipes.html`
- Modify: `README.md`

> ⚠️ **Straight quotes only.** Use ONLY straight ASCII quotes (`'` `"`) in all HTML attributes and code. After editing, run `git diff | grep -nP '[\x{2018}\x{2019}\x{201C}\x{201D}]'` and fix any curly quotes your editor introduced in attributes/code (a recurring bug). Em-dashes `—` in prose are fine.

- [ ] **Step 1: Cheatsheet lines**

In `docs/cheatsheet.html`, in the "Safety, data &amp; backups" `<dl class="kv">`, after the `launchpad secrets run -- cmd` entry, add:

```html
      <dt>launchpad status</dt><dd>See all your <code>~/Developer</code> projects at a glance — and which still need a backup.</dd>
      <dt>launchpad signin</dt><dd>A guided checklist of the sign-ins (GitHub, Sentry, here.now) with the exact command for each.</dd>
      <dt>launchpad sentry-setup</dt><dd>Turn on error tracking for the current project (writes the Sentry DSN to <code>.env.local</code>).</dd>
```

- [ ] **Step 2: Recipe**

In `docs/recipes.html`, in the "Save, undo &amp; get help" section (or after the "Keep my keys safe" section), add a new `<section>`:

```html
  <section>
    <h2>Turn on error tracking</h2>
    <p>When your app misbehaves, <strong>Sentry</strong> can capture the exact error, file, and line. Your app is already wired for it — you just need to turn it on for the project:</p>
    <div class="codeblock"><pre><code>Turn on Sentry error tracking for this app: create (or find) the
project, get the DSN, and set it up. Then throw a test error and show
me it appears in Sentry.</code></pre></div>
    <p class="muted">The assistant fetches the key for you and runs <code>launchpad sentry-setup</code>. No account yet? It'll walk you through the free signup, or you can paste a DSN from sentry.io into <code>launchpad sentry-setup</code>.</p>
  </section>
```

- [ ] **Step 3: README audit row + check the core list**

In `README.md`, add an **Add-on 09** audit row after the Add-on 08 row:

```
| **Add-on 09** | loops & onboarding: `launchpad status` (~/Developer backup-state dashboard, local-git-only), `launchpad signin` (guided GitHub/Sentry/here.now/agent checklist), `launchpad sentry-setup` (DSN validate + `.env.local` upsert; agent-MCP path via AGENTS.md recipe, `@sentry/wizard` fallback) |
```

- [ ] **Step 4: Verify + commit**

Run: `git diff | grep -nP '[\x{2018}\x{2019}\x{201C}\x{201D}]'` (must find nothing in attributes/code).
```bash
git add docs/cheatsheet.html docs/recipes.html README.md
git commit -m "docs(addon-09): cheatsheet + 'turn on error tracking' recipe + README audit"
```

---

### Task 8: VM integration probe

**Files:**
- Create: `dogfood/remote-addon09.sh`

- [ ] **Step 1: Write the probe**

Create `dogfood/remote-addon09.sh`:

```bash
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
DEVELOPER_DIR="$DEV" bash "$ROOT/scripts/launchpad" status >/tmp/lp.out 2>&1 && grep -q 'backup' /tmp/lp.out && echo "PROBE:dispatch=PASS" || echo "PROBE:dispatch=FAIL"

# doctor check line present
( cd "$ROOT" && bash lib/doctor.sh >/tmp/doc.out 2>&1; grep -q 'loops & onboarding scripts' /tmp/doc.out ) && echo "PROBE:doctor=PASS" || echo "PROBE:doctor=FAIL"

echo "##### ADDON09 PROBE DONE #####"
```

- [ ] **Step 2: Static checks (do NOT execute — VM only)**

Run: `bash -n dogfood/remote-addon09.sh` (parses) and `shellcheck dogfood/remote-addon09.sh` (info-level only, like `dogfood/remote-addon08.sh`). Do NOT run the probe on the host (it runs `bootstrap.sh` + modules).

- [ ] **Step 3: Commit**

```bash
chmod +x dogfood/remote-addon09.sh
git add dogfood/remote-addon09.sh
git commit -m "test(addon-09): VM probe — status/signin/sentry-setup units + integration"
```

---

### Task 9: Final validation (controller)

**Files:** none (validation only)

- [ ] **Step 1: Full host unit suite**

Run: `bash tests/test-status.sh && bash tests/test-signin.sh && bash tests/test-sentry.sh && bash tests/test-secrets.sh && bash tests/test-doctorfix.sh && bash tests/test-spend.sh`
Expected: six `PASS` lines.

- [ ] **Step 2: Shellcheck everything new/changed**

Run: `shellcheck -S warning scripts/status.sh scripts/signin.sh scripts/sentry-setup.sh scripts/launchpad lib/doctor.sh modules/09-dx.sh && shellcheck dogfood/remote-addon09.sh`
Expected: clean (info-level on the probe acceptable).

- [ ] **Step 3: VM probe**

Run: `TART_VM=launchpad-addon09 bash dogfood/vm-probes.sh dogfood/remote-addon09.sh`
Expected: every `PROBE:*=PASS`, exit 0.

- [ ] **Step 4: Final review + finish the branch**

Dispatch a final code reviewer over `main..HEAD`; on READY TO MERGE, use superpowers:finishing-a-development-branch (squash-merge to `main`, push, verify Pages).

---

## Self-Review

**1. Spec coverage:**
- `launchpad status` (backup-state dashboard, local-git-only, best-effort port, age) → Task 1. ✓
- `launchpad signin` (guided checklist, detection wrappers, summary) → Task 2. ✓
- `launchpad sentry-setup` (DSN validate + `.env.local` upsert, `--dsn`/env/paste, `--wizard`, 1Password tip) → Task 3. ✓
- Dispatcher wiring → Task 4. ✓
- Doctor check + `09-dx` chmod → Task 5. ✓
- AGENTS.md "turn on error tracking" recipe → Task 6. ✓
- Docs (cheatsheet, recipe, README audit) → Task 7. ✓
- Unit tests (status/signin/sentry, with mock gh) → Tasks 1–3. ✓
- VM probe → Task 8. ✓
- Build-time verifications (wizard flag, lsof, DSN shape) → plan header + Tasks 3/1. ✓

**2. Placeholder scan:** No TBD/TODO; every code step has complete code; every test has real assertions + expected output.

**3. Type/name consistency:** `status_classify`, `_age`, `_running_port` (Task 1); `signin_line`, `_gh_ok`/`_sentry_ok`/`_herenow_ok`/`_agent_ok`, `_yn` (Task 2); `sentry_dsn_valid`, `_env_upsert`, `sentry_env_upsert` (Task 3) — defined once, used consistently by the dispatcher (Task 4), doctor (Task 5), and probe (Task 8). `.env.local` keys `NEXT_PUBLIC_SENTRY_DSN` + `SENTRY_DSN` consistent with the web template. The `out%%|*` / `out#*|` split matches `status_classify`'s `ok|…`/`warn|…` output.

**Residual risk (documented):** the Sentry MCP live path can't be VM-tested (agent capability, sign-in-gated) — covered by the AGENTS.md recipe + the deterministic `--dsn` write path which IS tested; the `@sentry/wizard` invocation and `lsof` port-mapping are best-effort, build-time-verified, and degrade gracefully.
