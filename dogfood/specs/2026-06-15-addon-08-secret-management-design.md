# Add-on 08 — Secret management (1Password) (design spec)

Status: approved design, 2026-06-15. Implements Phase 2 of `dogfood/roadmap.md`.
Spec lives here (not `docs/`) because `docs/` is the published GitHub Pages site;
this is an internal maintainer artifact.

## Goal

Wire up the already-installed-but-unused 1Password CLI (`op`, from
`modules/00-foundation.sh`) so the user and the three AI agents can store and use
secrets in 1Password instead of plaintext `.env` files — directly serving the
"never hardcode secrets" mission with a tool the foundation already installs.

Approved UX decision (user, 2026-06-15): **"just make it ready."** Ship the full
`launchpad secrets` toolset + agent house-rules and a graceful degrade, but the
user stays on the simple `.env.local` flow by default. **Optional, never
required:** no 1Password account is provisioned, the desktop app is **not**
installed, and nothing blocks the core flow when `op` isn't signed in. A user who
later signs in (any auth method) gets plaintext-free secrets with no further setup.

## Shared conventions

- Idempotent; logged to `~/launchpad-setup.log` via `lib/common.sh` helpers.
- New user config under `~/.config/launchpad/` (created if absent).
- New commands hang off the existing `launchpad` dispatcher (`scripts/launchpad`).
- New capability gets a `lib/doctor.sh` check (hard on `op` presence, soft on sign-in state — sign-in is a human step) and a `dogfood/` VM probe.
- Docs: a new `docs/recipes.html` recipe, a getting-started callout, `docs/cheatsheet.html` lines, and the README audit table.

## Architecture at a glance

| Unit | Responsibility |
|---|---|
| `modules/07-secrets.sh` (new, **core**) | Confirm `op` present; install the `launchpad secrets` helper; add the agent house-rule + the `!.env.tpl` gitignore allow-list. No sign-in, no desktop app. |
| `scripts/secrets.sh` (new) | All `launchpad secrets` logic: `status` / `set` / `inject` / `run`. Detects op readiness; degrades to `.env.local`. Pure-ish + unit-tested with a mock `op`. |
| `scripts/launchpad` (edit) | Dispatch `secrets)` → `scripts/secrets.sh`. |
| `lib/doctor.sh` (edit) | "Safety net" section: soft check reporting `op` install + signed-in state. |
| `config/agents/AGENTS.md` (edit) | House-rule so all three agents prefer `op`, fall back to `.env.local`. |
| `config/safety/gitignore.global` (edit) | Add `!.env.tpl` so the (secret-free) template commits; real `.env.local` stays ignored. Installed by `08-safety` via `cp -f` (which runs after `07`), so the line lives in this source file — `07` does **not** touch the installed gitignore. |

`07-secrets.sh` is added to the **core module loop** in `scripts/install-profile.sh`
(currently `00,01,02,03,05,06,08,09`) — inserted before `08-safety.sh` so secret
management precedes the safety net. (`07` is the free core slot; the roadmap's
tentative "11" is in the profile-module range and would not run as core.)

## The `.env.tpl` template + `op` formats (verified, op 2.34.1)

`.env.tpl` is a committed, **secret-free** file of 1Password *secret references*
(`op://vault/item/field`). It holds no actual secrets, so it is safe to commit and
share; each machine resolves it locally. Verified formats on op 2.34.1:

- `op run --env-file=FILE -- <cmd>` reads dotenv lines `KEY=op://…` (**no braces**) and exposes resolved secrets as env vars to the subprocess — **nothing written to disk**.
- `op inject -i FILE -o OUT` substitutes `{{ op://… }}` (**braces**) tokens in arbitrary text.

**Canonical `.env.tpl` uses the `op run` format** (`KEY=op://Launchpad/<item>/<field>`):
- `secrets run` is then **native**: `op run --env-file=.env.tpl -- <cmd>`.
- `secrets inject` **bridges** to `op inject` by brace-wrapping each `KEY=op://…`
  line into `KEY={{ op://… }}` on the fly (`sed`/awk), piping that to
  `op inject`, output to gitignored `.env.local`. (Both halves verified.)

## The `launchpad secrets` command

`read -s` (hidden) for all value entry. Readiness is detected with
`op whoami >/dev/null 2>&1` (exit 0 ⇒ usable: desktop-app/biometric, `op signin`
account, **or** `OP_SERVICE_ACCOUNT_TOKEN` — the module is auth-method agnostic).

| Subcommand | op signed in | op not signed in (the user's default) |
|---|---|---|
| `secrets status` | prints "1Password mode", account, vault, and `.env.tpl` ref count | prints ".env.local mode" + the one command to turn 1Password on |
| `secrets set NAME` | hidden prompt → store in the **Launchpad** vault (per-project item, field `NAME`) → upsert `NAME=op://Launchpad/<project>/NAME` into `.env.tpl` | hidden prompt → upsert `NAME=<value>` into `.env.local`; note it's local + how to upgrade |
| `secrets inject` | `.env.tpl` → gitignored `.env.local` via the brace-wrap + `op inject` bridge | friendly "1Password not set up — your values are already in `.env.local`" (no-op) |
| `secrets run -- <cmd>` | `op run --env-file=.env.tpl -- <cmd>` (in-memory, zero plaintext) | runs `<cmd>` normally (the app reads `.env.local` itself); one-line note |

- **Vault:** default `Launchpad` (configurable via `SECRETS_VAULT` in `~/.config/launchpad/secrets.conf`). Created on first `set` when signed in (`op vault create` if absent). Only relevant once signed in.
- **Item/field layout:** one item per project (named after the project directory), each secret a field. Exact `op item create/edit` flags finalized at build time (see verifications).
- Every path is optional and **never blocks** — each degrades to today's `.env.local` flow with a single explanatory line.

## Agent house-rule (`config/agents/AGENTS.md`)

Extend the existing "Never hardcode secrets" rule: *for any new secret, prefer
`launchpad secrets run` / `inject` with 1Password and store it via `launchpad
secrets set`; fall back to `.env.local` only when 1Password isn't set up; never
hardcode and never commit `.env.local`.* So all three agents behave identically.

## Module behavior (`modules/07-secrets.sh`)

1. Confirm `op` present (installed by foundation); if somehow absent, `brew_install 1password-cli`.
2. Install/refresh `scripts/secrets.sh` perms; ensure `launchpad secrets` dispatch.
3. Apply the `AGENTS.md` house-rule via `replace_managed_block` (idempotent).
4. Do **not** sign in, create accounts, or install the desktop app. If `op` is present but `op whoami` fails, `log_info` a one-liner that 1Password is ready to turn on — never an error.

(The `!.env.tpl` gitignore allow-list lives in `config/safety/gitignore.global` and is installed by `08-safety`, not here — see the architecture table.)

**Error handling:** every external call defends with `2>/dev/null` + fallbacks; the module never fails the install over an optional, sign-in-gated capability.

## Doctor check (`lib/doctor.sh`, "Safety net" section)

- `op` on PATH → ✔ (it's foundation-installed; treat absence as a real red).
- Signed-in state via `op whoami`: signed in → ✔ "1Password ready"; not → **yellow** "optional — run `launchpad secrets` to turn on" (never red; it needs a human sign-in like the GitHub/Sentry accounts).

## Testing

- **Unit tests** (`tests/test-secrets.sh`, using `tests/lib.sh`): put a **mock `op`** on `PATH` whose behavior is switched by env (e.g. `MOCK_OP_SIGNED_IN=1`), and assert the pure logic deterministically for **both** branches:
  - readiness detection (`op whoami` exit handling),
  - `.env.tpl` upsert (add new, replace existing, no dup keys),
  - the brace-wrap transform (`KEY=op://…` → `KEY={{ op://… }}`),
  - fallback routing (`set`/`inject`/`run` pick the right path when not signed in),
  - `.env.local` upsert + gitignore safety (template committable, secrets ignored).
- **VM probe** (`dogfood/remote-addon08.sh`): lean install (00, 07, 08), drop a fake `op` returning canned output, then probe: `secrets set` (both modes), `inject` materializes `.env.local`, `run` passes an injected var to a child process, `status` reports the mode, the doctor soft-check, and that `git check-ignore` ignores `.env.local` but **not** `.env.tpl`.

## Out of scope (YAGNI)

- **No** 1Password desktop-app install, account provisioning, or sign-in automation (user opted out; it's a human/paid step).
- **No** `op plugin init` shell-plugin wiring (gh/stripe/aws) — a separate, desktop-app-dependent capability.
- **No** per-project vaults, secret rotation, sharing, or `op item` browsing UI.
- **No** change to the existing `.env.example` → `.env.local` convention; `.env.tpl` is additive and only appears once a user uses `launchpad secrets`.

## Build-time verifications

- **Exact `op item create` / `op item edit` syntax** for upserting a field in a vault item on op 2.34.1 (store/update a secret) — the one remaining external unknown.
- `op whoami` is the correct readiness probe across auth methods (desktop, account, service token) — confirm exit-code contract.
- The mock-`op` contract covers every `op` subcommand `secrets.sh` calls (`whoami`, `run`, `inject`, `item`, `vault`, `read`).
- (Resolved this session: `op inject` uses `{{ op://… }}`; `op run --env-file` uses `KEY=op://…`.)

## Rollout & validation

One add-on. New `modules/07-secrets.sh` (added to the core loop) + `scripts/secrets.sh`,
wired into `scripts/launchpad`; the doctor soft-check; the `AGENTS.md` house-rule;
the `!.env.tpl` allow-list; docs (recipe + getting-started callout + cheatsheet +
README audit). Ship when the VM run is green and the addon-08 probe passes. Because
the user is on the `.env.local` fallback, the 1Password paths are validated via the
mock-`op` unit tests + VM probe and documented; the live-account path is sign-in-gated.
