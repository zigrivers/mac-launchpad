# Mac Launchpad — Gaps & Innovations Roadmap

Operationalizes the gaps/innovations list from `dogfood/2026-06-15-report.md` into a
sequenced, buildable plan. Nine items, grouped into **four shippable add-ons**,
ordered **quick-wins-first → flagship → loops → big bet**.

This is a roadmap, not a design. Each item, when greenlit, goes through the
repo's normal flow (Superpowers brainstorm → spec → plan → TDD → review → VM-green
→ docs) before any code lands.

## Sequencing at a glance

| Phase | Add-on | Items | Impact | Effort | Depends on |
|---|---|---|---|---|---|
| 1 | **07 · Polish & resilience** | pre-warm hook envs · spend guardrail · backup nudge · `doctor --fix` | ★–★★ | ● each | — |
| 2 | **08 · Secret management** | 1Password injection (`op`) | ★★★ | ●● | — |
| 3 | **09 · Loops & onboarding** | `launchpad status` · `launchpad signin` · Sentry DSN auto-provision | ★★–★★★ | ●● each | 08 (optional, key storage) |
| 4 | **10 · Guided provisioning** | Supabase / Stripe / Vercel wizards | ★★★ | ●●● | 08 (keys) + 09 (Sentry pattern) |

**Why this order:** Phase 1 is low-risk, high-felt polish that builds momentum and needs nothing else. Phase 2 (1Password) is the highest-leverage safety win *and* unblocks the wizards' key handling, so it comes before them. Phase 3 closes the error/visibility loops and reuses 1Password for storing any keys it provisions. Phase 4 is the largest and depends on both.

## Cross-cutting conventions (every item follows these)

- **Surface:** extend the existing `launchpad` dispatcher (`scripts/launchpad`) — it already does `new/harden/report/doctor/update/notify`; we add `status/signin/secrets/sentry-setup` and a `doctor --fix` path. New logic lives in `scripts/*.sh` or a numbered `modules/NN-*.sh`, sourcing `lib/common.sh`, idempotent, logged to `~/launchpad-setup.log`.
- **Health:** every new capability gets `lib/doctor.sh` checks (hard where deterministic, soft where it needs a sign-in).
- **Agents:** add `config/agents/AGENTS.md` house-rules so all three agents use the new capability.
- **Docs:** update `docs/cheatsheet.html` + `docs/recipes.html` (+ getting-started/troubleshooting where relevant) and the README audit table.
- **Validation:** a `dogfood/`-style VM probe for each, plus `scripts/test-in-vm.sh` staying green.
- **Optional-by-default:** anything that needs a third-party account (1Password, Stripe…) must degrade gracefully when not signed in — never block the core flow.

---

## Phase 1 — Add-on 07 · Polish & resilience (quick wins)

Four small, independent improvements. Ships as one add-on.

### 1.1 Pre-warm pre-commit hook environments  (★★, ●)
- **Goal:** kill the silent 1–2 min pause on a project's *first* commit (pre-commit lazily downloads the gitleaks + Biome hook envs).
- **Approach:** in `modules/08-safety.sh`, after installing `pre-commit`, run it once against the base config in a throwaway temp repo to populate `~/.cache/pre-commit` (e.g. `pre-commit install-hooks` with `config/safety/.pre-commit-config.yaml`). Also have `harden-project.sh` print a one-line "setting up safety checks…" only when the cache is cold.
- **Depends on:** —. **Risk:** none (cache is shared across projects).
- **Acceptance:** first commit in a fresh `launchpad new` project does not pause to download hook envs. **Verify:** VM probe times a first commit.

### 1.2 Spend guardrail  (★★, ●)
- **Goal:** notify when Claude Code (and Codex) token spend crosses a threshold — three full-autonomy agents can run up cost unseen.
- **Approach:** `scripts/spend-check.sh` reads `npx ccusage --json` (daily/monthly cost), compares to a threshold in `~/.config/launchpad/limits` (configurable; sensible default), and fires `launchpad-notify` when exceeded. Install a **launchd** plist (`~/Library/LaunchAgents/com.launchpad.spendcheck.plist`) for a daily run. Expose `launchpad spend` for an on-demand check.
- **Depends on:** `launchpad-notify` (exists), ccusage (exists). **Risk:** ccusage JSON shape — verify at build time.
- **Acceptance:** spend over threshold → desktop notification; `launchpad spend` prints today/this-month. **Verify:** stub a high usage value → notification fires.

### 1.3 Backup nudge  (★★, ●)
- **Goal:** "private backup" is only as good as the last push — nudge on uncommitted / unpushed work.
- **Approach:** a zsh `chpwd`/`precmd` hook in the `zshrc.append` managed block: when entering a `~/Developer/*` project that's dirty or has commits ahead of `origin`, print a gentle one-liner ("3 unsaved changes — ask an assistant to save a checkpoint"). Throttle (once per project per session). Also fold a "backup state" column into `launchpad status` (1.7).
- **Depends on:** —. **Risk:** noise — keep it quiet and throttled; make it opt-out via a config flag.
- **Acceptance:** cd into a dirty/unpushed project → single nudge; clean project → silence. **Verify:** VM probe creates dirty/ahead repos and checks output.

### 1.4 `launchpad doctor --fix`  (★, ●●)
- **Goal:** non-agent self-heal — re-run the module that owns a failing check, without needing an agent in the loop.
- **Approach:** map each `doctor.sh` check to its owning module (a small table), add a `--fix` flag that, for each red, re-runs that module then re-checks. `launchpad doctor --fix`. Keep it conservative (only re-runs idempotent modules; never destructive).
- **Depends on:** —. **Risk:** a module that legitimately can't self-heal (needs a sign-in) — those stay yellow with guidance, not looped.
- **Acceptance:** deliberately remove an installed tool → `doctor --fix` reinstalls it → green. **Verify:** VM probe breaks a check and fixes it.

---

## Phase 2 — Add-on 08 · Secret management (1Password)  ★ flagship

### 2.1 Wire up the installed-but-unused 1Password CLI  (★★★, ●●)
- **Goal:** let agents store and read secrets via `op` instead of plaintext `.env` — directly serving the "never hardcode secrets" mission with a tool the foundation **already installs** (`1password-cli`, today completely unwired).
- **Approach:**
  - New `modules/11-secrets.sh` (core): confirm `op` present; set up the shell plugin/agent integration; install a `launchpad secrets` subcommand.
  - `launchpad secrets set <NAME>` → stores a value in a launchpad 1Password vault (`op item create/edit`); `launchpad secrets inject` → materializes `.env` from a committed `.env.tpl` of `op://` references via `op inject` (gitignored output); `launchpad secrets run -- <cmd>` → `op run --env-file=.env.tpl -- <cmd>` injects secrets into a process **without writing plaintext at all**.
  - `AGENTS.md` house-rule: for any new secret, prefer `op run`/`op inject`; store it in 1Password; fall back to `.env.local` only when `op` isn't available.
  - `doctor.sh`: soft-check `op` is signed in (needs `op signin` / a 1Password account — a documented human step like the other sign-ins).
- **Depends on:** —. **Key decision (needs your call):** **optional vs required.** Default plan = **optional**: when `op` isn't signed in, everything falls back to the current `.env.local` flow, so non-technical users without a 1Password account are unaffected; users who have one get plaintext-free secrets.
- **Acceptance:** `launchpad secrets set/inject/run` work; `op run` starts a dev server with a key injected and no plaintext on disk; doctor reports op state; agents follow the house-rule. **Verify:** VM probe (with a mock `op`) exercises inject/run + the `.env` fallback path.
- **Docs:** new recipe "keep my keys safe with 1Password"; getting-started callout.

---

## Phase 3 — Add-on 09 · Loops & onboarding

### 3.1 `launchpad status` dashboard  (★★, ●●)
- **Goal:** one command showing every `~/Developer` project's state — there's no overview today.
- **Approach:** `scripts/status.sh` + `launchpad status`. For each project: git clean/dirty + commits ahead of `origin` (backup state), private-remote present (`gh repo view`), running dev server + port (`lsof`), last-commit age, and (if present) last test result / Sentry link. Pretty, aligned, Catppuccin-tinted table.
- **Depends on:** —. (Richer once 3.3 Sentry + 2.1 secrets exist.) **Risk:** speed across many repos — cap/parallelize git/gh calls.
- **Acceptance:** lists each project with backup/dirty/running columns and flags unbacked-up work. **Verify:** VM probe creates a few projects in varied states.

### 3.2 `launchpad signin` checklist  (★★, ●●)
- **Goal:** per-agent OAuth across GitHub + Sentry + here.now (×3 agents) is confusing — give one guided checklist.
- **Approach:** `scripts/signin.sh` + `launchpad signin`. Checks each service's state (`gh auth status`; Sentry MCP reachability per agent; `~/.herenow/credentials`; claude/codex/agy logged in) and prints, for each missing one, the exact command + what it unlocks. Idempotent; safe to run anytime.
- **Depends on:** —. **Acceptance:** with nothing signed in, prints the full ordered checklist; after signing in, shows green. **Verify:** VM probe asserts it reports each service state.

### 3.3 Sentry DSN auto-provision  (★★★, ●●)
- **Goal:** close the error loop end-to-end — today the DSN is a manual paste; new apps are pre-wired but inert until then.
- **Approach:** a `launchpad sentry-setup` flow (+ an `AGENTS.md` recipe "turn on error tracking") that uses the **already-wired Sentry MCP** to find/create a project and fetch its client key (DSN), then writes `NEXT_PUBLIC_SENTRY_DSN` / `SENTRY_DSN` to `.env.local` (or to 1Password via 2.1 when available). Fallback: drive `npx @sentry/wizard`.
- **Depends on:** Sentry MCP sign-in; optionally 2.1 for key storage. **Risk:** **verify the Sentry MCP actually exposes project-create / client-key tools at build time** — if not, fall back to the wizard path. **Acceptance:** from a fresh web app, "turn on error tracking" results in a thrown error appearing in Sentry with the DSN auto-written. **Verify:** documented as sign-in-gated (like the GitHub MCP); mechanism verified by config/code.

---

## Phase 4 — Add-on 10 · Guided provisioning wizards  (★★★, ●●●)

### 4.1 Supabase / Stripe / Vercel "from prompt to working"  
- **Goal:** turn the recipes from *prompts* into *guided flows* that handle account creation + key injection + a working integration — login and payments are the most-wanted features and the hardest first step.
- **Approach:** primarily **agent-guided recipes + CLI wrappers** (these involve interactive account/OAuth steps that can't be fully automated), each storing keys via 2.1 (1Password) or `.env.local`:
  - **Supabase** (`supabase` CLI already installed): `launchpad add supabase` / recipe → `supabase login`, create/link a project, pull anon+service keys, wire the Next.js client, add an auth example + a test.
  - **Stripe** (CLI **not** installed — add `stripe` via the module): `stripe login`, fetch **test-mode** keys, scaffold Checkout + a webhook via `stripe listen`, gate a premium page.
  - **Vercel** (`vercel` CLI already installed): `vercel link` + `vercel env` to push the collected keys and deploy.
- **Depends on:** 2.1 (key storage) + the 3.3 provision pattern. **Risk:** highest-effort, mostly guided not automated; sequence each as its own sub-deliverable. **Acceptance:** "add user login" / "add a payment flow" walk a non-technical user through account → keys → a working, tested integration on the existing web template. **Verify:** the runnable parts (CLI wiring, scaffolds, tests) in a VM; the account/OAuth steps documented as guided.

---

## Dependency graph

```
Phase 1 (07): pre-warm · spend · backup-nudge · doctor --fix   [all independent]
Phase 2 (08): 1Password  ─────────────┐
Phase 3 (09): status · signin          │ (independent)
              sentry-provision ◄────────┤ (optional: store DSN in 1Password)
Phase 4 (10): Supabase/Stripe/Vercel ◄──┴──◄ 3.3 pattern   [needs keys + provision pattern]
```

## Open decisions (your input shapes the plan)

1. **1Password: optional (default) or required?** Optional keeps non-technical users without an account unaffected; required maximizes safety. *Recommend optional.*
2. **Ship as 4 add-ons (above) or fewer/more?** *Recommend the 4 as scoped.*
3. **Scheduling mechanism** for 1.2/1.3 — launchd jobs (durable, recommended) vs. shell hooks (lighter, session-only). *Recommend launchd for spend, a throttled shell hook for the nudge.*
4. **Stripe CLI** — add it in Add-on 10 (only the wizards need it), or to the foundation now? *Recommend add-on 10.*
5. Anything to **drop or reprioritize** before we start.

## Suggested greenlight order

**07 → 08 → 09 → 10.** Phase 1 (07) can start immediately and ships fast for an early UX win; 08 (1Password) is the highest-leverage single change and unblocks 10. Each phase is independently shippable and VM-validated before the next.
