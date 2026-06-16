# Add-on 09 — Loops & onboarding (design spec)

Status: approved design, 2026-06-16. Implements Phase 3 of `dogfood/roadmap.md`.
Spec lives here (not `docs/`) because `docs/` is the published GitHub Pages site;
this is an internal maintainer artifact.

## Goal

Three "loops & onboarding" features that give a non-technical user visibility and
a guided path through the setup's external accounts:

1. **`launchpad status`** — a fast dashboard of every `~/Developer` project's state (headline: is my work backed up?).
2. **`launchpad signin`** — a guided checklist of the external sign-ins (GitHub, Sentry, here.now, the agents) with the exact command + what each unlocks.
3. **`launchpad sentry-setup`** — write a Sentry DSN into a project (closing the error-tracking loop), with an agent-driven "automatic" path and a wizard fallback.

Approved scope decision (user, 2026-06-16): **all three** in one add-on. Sentry's
live path is **sign-in-gated** and validated via a mock (the Add-on 08 pattern);
the deterministic DSN-write core is fully unit-tested.

## Key architecture decision

`launchpad` is a **shell script** and cannot call MCP tools (those are AI-agent
capabilities). So Sentry DSN provisioning is split:
- **Shell (`launchpad sentry-setup`)** does the deterministic, testable part: take a DSN and write it into `.env.local` (or 1Password), or drive the wizard.
- **Agent (an `AGENTS.md` recipe)** does the MCP part: use the Sentry MCP to create/find a project + fetch its DSN, then call `launchpad sentry-setup --dsn <dsn>`.

This keeps all testable logic in shell and the sign-in-gated "magic" in a documented agent recipe.

## Shared conventions

- Idempotent; logged to `~/launchpad-setup.log` via `lib/common.sh` helpers where modules are involved (the new scripts are self-contained like `scripts/spend-check.sh`/`scripts/secrets.sh` and source-guarded so their pure functions are unit-testable).
- New commands hang off the existing `launchpad` dispatcher (`scripts/launchpad`): `status`, `signin`, `sentry-setup`.
- `lib/doctor.sh`: checks that the new scripts are present/executable (hard); the Sentry MCP soft-check already exists.
- Docs: `docs/cheatsheet.html` (+ getting-started/recipes where relevant) and the README audit table.
- New scripts live in `scripts/*.sh`; no new numbered module is required (these are commands, not install steps) — but a tiny wiring step in an existing module makes them executable + ensures the AGENTS.md recipe ships (see Rollout).

## Architecture at a glance

| Unit | Responsibility |
|---|---|
| `scripts/status.sh` (new) | `launchpad status`: scan `~/Developer` git repos, classify backup state, print an aligned table. Pure classifier + fetch separated for testing. |
| `scripts/signin.sh` (new) | `launchpad signin`: detect each service's sign-in state, print ✓ or the exact command + what it unlocks. |
| `scripts/sentry-setup.sh` (new) | `launchpad sentry-setup`: upsert a DSN into `.env.local` (or 1Password), or drive `@sentry/wizard`. |
| `scripts/launchpad` (edit) | Dispatch `status` / `signin` / `sentry-setup`. |
| `lib/doctor.sh` (edit) | Developer-experience checks: the three scripts are executable. |
| `config/agents/AGENTS.md` (edit) | "Turn on error tracking" recipe; note agents can run `launchpad status`/`signin`. |
| `modules/09-dx.sh` (edit) | `chmod +x` the three scripts (they're dispatched by `launchpad`). |

## Feature 1 — `launchpad status`

**Design:** `scripts/status.sh` scans the immediate children of `$DEVELOPER_DIR`
(`~/Developer`) that are git work trees. For each, compute and print an aligned row:

- **name** — the directory name.
- **backup state** (the headline) — classified from local git only:
  - `no remote yet` — no `origin` remote (not backed up at all) → warn color.
  - `N unsaved` — `git status --porcelain` non-empty (dirty) → warn.
  - `N unpushed` — commits ahead of `@{u}` (`git rev-list @{u}..HEAD --count`) → warn.
  - `backed up` — clean and not ahead → ok color. (Unsaved + unpushed combine, e.g. `3 unsaved, 2 unpushed`.)
- **running** — best-effort dev-server port: a listening port whose process cwd is under the repo (`lsof -nP -iTCP -sTCP:LISTEN`); `—` if none. Best-effort, never blocks.
- **last commit** — relative age of HEAD (`git log -1 --format=%cr`-style, shortened to `2h`/`3d`).

**Pure unit (testable):** `status_classify <porcelain_lines> <ahead_count> <has_remote>` → echoes the backup-state string + a severity (ok/warn). No I/O.

**Speed/robustness:** pure local git (`git -C "$repo" …`), each call defended with `2>/dev/null`; parallelize across repos with a small cap (e.g. background jobs, bounded); **no per-repo network** (`gh`/`git fetch`) — remote *presence* is read from `git remote`, not its reachability. Skip non-git dirs. If there are more than N repos (e.g. 50), print the first N and a "+M more" line.

**Error handling:** any repo that errors → its row shows `?` and the scan continues. Empty `~/Developer` → a friendly "no projects yet — `mkproj <name>` to start."

**Doctor:** hard check `scripts/status.sh` executable.

**Acceptance / probe:** create repos under `~/Developer` in varied states (clean+pushed, dirty, ahead, no-remote) → the table shows the right backup state per repo; a clean repo is ok-colored, a dirty/unpushed/no-remote one is warned.

## Feature 2 — `launchpad signin`

**Design:** `scripts/signin.sh` checks each external account's local state and prints,
for each, either `✓ <service> — done` or `• <service> — run: <command>  (unlocks: <what>)`:

- **GitHub:** `gh auth status` → `gh auth login` — unlocks *private project backups + the GitHub MCP*.
- **Sentry:** `claude mcp get sentry` (config present) → *type `/mcp` inside `claude` (and `codex`/`agy`) and pick Sentry to sign in* — unlocks *agents reading your app's runtime errors*.
- **here.now:** `~/.herenow/credentials` exists or `HERENOW_API_KEY` set → *sign up at here.now and add your key* — unlocks *permanent published links* (anonymous publishing works without it; no CLI login command is asserted — the exact key-setup step is documented, not auto-run).
- **Agents:** `claude`/`codex`/`agy` on PATH and reachable → the relevant sign-in (`claude`, `codex`, `agy`) — unlocks *using that assistant*.

**Pure unit (testable):** `signin_line <service> <ok 0|1> <command> <unlocks>` → formats one checklist line consistently (ok vs todo). Detection functions call the real tools but are thin wrappers.

**Behavior:** idempotent, read-only (never signs anyone in automatically — it *guides*). Ends with a one-line summary ("3 of 4 ready"). Safe to run anytime.

**Doctor:** hard check `scripts/signin.sh` executable.

**Acceptance / probe:** with nothing signed in (fresh VM), prints the full checklist with the right commands; the formatter unit asserts the ok vs todo line shapes.

## Feature 3 — `launchpad sentry-setup`

**Design:** `scripts/sentry-setup.sh` — the deterministic core writes a Sentry **DSN**
into the current project so the pre-wired `@sentry/nextjs` (web template) starts reporting.

**DSN source (in priority order):**
1. `--dsn <dsn>` flag (used by the agent path).
2. `SENTRY_DSN` environment variable.
3. Interactive paste prompt (read from stdin; the user copies it from sentry.io).

**DSN destination:** upsert **both** `NEXT_PUBLIC_SENTRY_DSN` and `SENTRY_DSN` (the template reads both) into the project's `.env.local` (gitignored). If the user has 1Password set up (`launchpad secrets` from Add-on 08 reports op-ready), offer to store via `launchpad secrets set` instead; default is `.env.local`. Idempotent upsert (replace existing lines, no dupes).

**DSN validation:** a DSN looks like `https://<key>@<org>.ingest.<region>.sentry.io/<projectid>` (or `…@oXXXX.ingest.sentry.io/…`). Validate the shape before writing; reject obviously-wrong input with a clear message. (Pure, unit-tested.)

**Provision paths (how you get a DSN):**
- **Agent path (the "automatic" one):** an `AGENTS.md` recipe — the agent uses its **Sentry MCP** to find/create a project and fetch the client key (DSN), then runs `launchpad sentry-setup --dsn <dsn>`. Sign-in-gated; documented; not shell-testable (MCP is an agent capability).
- **Wizard fallback:** `launchpad sentry-setup --wizard` runs `npx @sentry/wizard@latest -i nextjs` in the project (interactive vendor flow). Documented.
- **Manual:** `launchpad sentry-setup` with no DSN prompts the user to paste one.

**Pure units (testable):** `sentry_dsn_valid <string>` (shape check) and `sentry_env_upsert <file> <dsn>` (writes both keys idempotently). The `--dsn` write path is exercised with a **fake but well-formed DSN** — no real Sentry account needed.

**Error handling:** invalid/empty DSN → clear message, non-zero, nothing written. No network in the testable core.

**Doctor:** hard check `scripts/sentry-setup.sh` executable. (No new DSN check — DSN is per-project, not global; the Sentry MCP soft-check already exists in the Safety-net section.)

**Acceptance / probe:** `launchpad sentry-setup --dsn <fake-valid-dsn>` in a temp project writes both `NEXT_PUBLIC_SENTRY_DSN` and `SENTRY_DSN` to `.env.local`; an invalid DSN is rejected and writes nothing; `sentry_dsn_valid` unit covers good/bad shapes.

## Out of scope (YAGNI)

- **No** test-result or Sentry-link columns in `status` (expensive/fragile); backup state + running + age only.
- **No** network calls in `status` (no `gh repo view` / `git fetch` per repo) — local git only.
- **No** automatic sign-in in `signin` — it guides, never authenticates for you.
- **No** shell attempt to call the Sentry MCP (impossible from a shell); the MCP path is the agent recipe.
- **No** non-Next.js Sentry framework wiring in the wizard path (the web template is Next.js).

## Build-time verifications

- **`@sentry/wizard` invocation** on the current version (expected `npx @sentry/wizard@latest -i nextjs`) — the fallback path; confirm the flag.
- **`lsof` invocation** for mapping a listening port to a repo cwd (`lsof -nP -iTCP -sTCP:LISTEN` + cwd) on the VM image — keep best-effort; degrade to `—` if unavailable.
- **DSN shape** against a current real Sentry DSN format (region subdomain variants) so `sentry_dsn_valid` isn't too strict.
- (Known, accepted: the Sentry MCP's exact project-create / client-key tool names can't be verified from this environment; the agent recipe describes intent and the agent selects the tools — sign-in-gated, like the GitHub MCP.)

## Rollout & validation

Three new `scripts/*.sh` + dispatcher wiring + doctor checks + the AGENTS.md recipe
+ docs. `modules/09-dx.sh` gains a one-line `chmod +x` for the three scripts (so a
fresh install makes them runnable). Unit tests for the pure classifiers/formatters/
validators (`tests/test-status.sh`, `tests/test-signin.sh`, `tests/test-sentry.sh`,
using the `tests/lib.sh` harness, with mocks for `gh`/`op` where needed); a VM probe
(`dogfood/remote-addon09.sh`) creating varied-state repos for `status`, asserting the
`signin` checklist output, and exercising `sentry-setup --dsn` writing `.env.local`.
Ship when the VM run is green and the probes pass. The Sentry agent/MCP live path and
the wizard are documented as sign-in-gated.
