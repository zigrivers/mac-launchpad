# Add-on 07 — Polish & resilience (design spec)

Status: approved design, 2026-06-15. Implements Phase 1 of `dogfood/roadmap.md`.
Spec lives here (not `docs/`) because `docs/` is the published GitHub Pages site;
this is an internal maintainer artifact.

## Goal

Four small, independent quality-of-life + resilience features for a non-technical
user, shipped as one add-on. None changes the core flow; each degrades gracefully.

Approved UX decisions:
- **Spend guardrail:** zero-config spike detector **plus** an optional monthly budget.
- **Backup nudge:** a gentle one-line note on `cd`, throttled once per project per session.
- **Scheduling:** launchd for the spend check. **`doctor --fix`:** targeted (re-run only modules with a red).

## Shared conventions

- Idempotent; logged to `~/launchpad-setup.log` via `lib/common.sh` helpers.
- New user config under `~/.config/launchpad/` (created if absent).
- New commands hang off the existing `launchpad` dispatcher (`scripts/launchpad`).
- Each feature gets a `lib/doctor.sh` check (hard where deterministic, soft where it needs a human) and a `dogfood/` VM probe.
- Docs: `docs/cheatsheet.html` (+ getting-started/troubleshooting where relevant) and the README audit table.

---

## Feature 1 — Pre-warm pre-commit hook environments

**Problem:** a project's first commit silently downloads the gitleaks + Biome
hook environments into `~/.cache/pre-commit` (1–2 min of apparent hang).

**Design:** in `modules/08-safety.sh`, after `brew_install gitleaks pre-commit`,
warm the cache once:
- Create a temp git repo (`mktemp -d`), copy `config/safety/.pre-commit-config.yaml` in, run `pre-commit install-hooks` (downloads + builds every hook env into the shared `~/.cache/pre-commit`), then remove the temp dir.
- Guarded: skip if the cache already has the hook repos; non-fatal on failure (offline → first real commit downloads then, as today). Log a `log_info "warming up the commit-time safety checks (one-time)…"`.

**Error handling:** any failure → `log_warn` + continue. Never blocks the install.

**Doctor:** soft check — `~/.cache/pre-commit/repos` (or equivalent) is non-empty.

**Acceptance / probe:** in a fresh `launchpad new` project, the first commit completes without a multi-second download pause (probe times it / asserts the cache is warm before the first commit).

---

## Feature 2 — Spend guardrail

**Components:**
- `scripts/spend-check.sh` — the detector (run by launchd + reusable on demand).
- `launchpad spend` — on-demand summary (dispatch to a `--summary` mode of the same script).
- `~/Library/LaunchAgents/com.launchpad.spend.plist` — daily launchd agent.
- `~/.config/launchpad/limits` — optional, holds `MONTHLY_BUDGET_USD=<n>`.
- Installed/loaded by a step in `modules/09-dx.sh` (the DX module).

**Behavior (`spend-check.sh`):**
1. Read usage as JSON from ccusage. **Build-time verification required:** confirm the exact invocation + shape (expected `ccusage daily --json` → per-day entries with a cost field, and `ccusage monthly --json` → month-to-date cost). Extract today's cost and the prior 7 days.
2. **Spike rule:** compute the trailing-7-day daily average; if `today_cost >= 2 × avg` AND `today_cost >= $1.00` (floor, so near-zero days don't false-alarm), fire `launchpad-notify "Spend spike" "Today ~$X vs ~$Y/day average"`.
3. **Budget rule (only if `MONTHLY_BUDGET_USD` set):** if month-to-date ≥ 80% → notify once; ≥ 100% → notify. Track "already notified this month" via a stamp file in `~/.config/launchpad/` so it fires once per threshold per month.
4. `--summary` mode prints today / month-to-date / vs budget to stdout (for `launchpad spend`).

**Scheduling:** the plist runs `spend-check.sh` daily (`StartCalendarInterval`, e.g. hour 18). Module installs the plist and `launchctl` bootstraps it idempotently (unload/load or `bootout`/`bootstrap`).

**Error handling:** ccusage missing/offline/parse-fail → exit 0 silently (no false alerts). All thresholds read defensively.

**Doctor:** soft check — `spend-check.sh` executable and the launchd agent is loaded (`launchctl list | grep com.launchpad.spend`).

**Acceptance / probe:** with a stubbed ccusage returning a high "today" vs low average → spike notification path triggers; with a `MONTHLY_BUDGET_USD` set below month-to-date → budget path triggers. `launchpad spend` prints a summary.

---

## Feature 3 — Backup nudge

**Design:** a zsh `chpwd` hook added to the `config/zshrc.append` managed block.
On directory change:
- Only act when `$PWD` is under `$HOME/Developer` and is a git work tree.
- If `git status --porcelain` is non-empty (dirty) OR `git rev-list @{u}.. --count` > 0 (commits ahead of upstream), print **one** quiet line, e.g. `· N unsaved change(s) here — ask an assistant to "save a checkpoint" (and push).`
- **Throttle:** once per project per shell session via `typeset -gA _lp_nudged` keyed by the repo's top-level path; skip if already marked.
- **Opt out:** skip entirely if `~/.config/launchpad/no-nudge` exists. (A `launchpad nudge off|on` toggle is a thin wrapper that creates/removes that file — include it; it's trivial.)
- Silent for clean repos, non-git dirs, and repos with no upstream (`@{u}` unset → treat as "not ahead", still nudge if dirty).

**Error handling:** all git calls `2>/dev/null`; any error → silent. Fast (porcelain + rev-list are cheap) and scoped to `~/Developer` so it never slows unrelated `cd`s.

**Doctor:** check the `chpwd` nudge hook is present in `~/.zshrc` (the managed block).

**Acceptance / probe:** `cd` into a dirty repo and a clean repo under `~/Developer`; dirty → one nudge line, clean → silence; second `cd` into the same dirty repo in the same session → no repeat; `no-nudge` file → silence.

---

## Feature 4 — `launchpad doctor --fix`

**Design:** add a `--fix` mode to `lib/doctor.sh`, surfaced as `launchpad doctor --fix`.
- doctor already groups checks under section headers (`hdr "Safety net"`, `"Developer experience"`, etc.). Maintain a **section → module** map:
  `Foundation→00`, `Shell & terminal→01,02`, `Editors→03`, `AI agents→05`, `Skills & workflow→06`, `Safety net→08`, `Developer experience→09`, `Web stack/Testing layer→10,15`, `Containers→12`, `Mobile stack→20`, `Games stack→30`, `ML stack→40`.
- On `--fix`: run the checks; collect the **sections that had a hard red** (failures only — not soft/yellow). Re-run each mapped module once (modules are idempotent), then re-run doctor **once** (without `--fix`) and report the new tally.
- **Never** re-runs for soft/sign-in/GUI items (GitHub auth, Sentry sign-in, Xcode, OrbStack engine, etc.) — those are reported with their existing guidance.
- One fix attempt, no loop — if still red after, tell the user what remains.

**Error handling:** a module that errors during re-run → `log_warn` + continue to the re-check (doctor will still report the red honestly).

**Acceptance / probe:** uninstall a deterministic tool (e.g. `brew uninstall biome`) → `launchpad doctor --fix` re-runs `09-dx` → biome reinstalled → green; a soft item (no gh auth) is left untouched and reported.

---

## Out of scope (YAGNI)

- No hard spend **cap** / kill-switch — notify only.
- No backup nudge outside `~/Developer`, and no periodic notification (cd-time only).
- `doctor --fix` does not attempt sign-in/GUI/human-step items.
- No new third-party tools (everything uses already-installed `ccusage`, `pre-commit`, `git`, `launchctl`, `launchpad-notify`).

## Build-time verifications

- **ccusage JSON shape** for daily + monthly cost (the one external unknown).
- `pre-commit install-hooks` populates the shared cache as expected on the VM image.

## Rollout & validation

One add-on. Wire the new `launchpad` subcommands (`spend`, `nudge`, `doctor --fix`)
into `scripts/launchpad`; install/load the launchd agent + warm the cache in their
modules. Add the doctor checks, the AGENTS.md note (agents can suggest `launchpad
spend`/`status`), docs, and a `dogfood/` probe per feature. Ship when the VM run
is green and the four probes pass.
