# Mac Launchpad

Turn a brand-new Mac into a complete software-development machine for a
**non-technical person**, driven by **Claude Code**, **OpenAI Codex**, and
**Google Antigravity** (`agy`).

> **This README is for whoever maintains the repo.** Everything for the end user
> lives on the GitHub Pages site: **https://zigrivers.github.io/mac-launchpad/**

The end state: someone runs one command in the stock Terminal, signs into the
two agents, then tells Claude Code *"set me up"* and walks away — ending with a
configured environment for web apps, games, mobile apps, and AI/ML work, plus
the guides to start building.

## How it works (two stages)

| Stage | File | Run by | Does |
|---|---|---|---|
| **0** | `bootstrap.sh` | the human, in Terminal.app | Xcode CLT → Homebrew → all three agents (native installers) + Chrome → seed full-autonomy configs → clone this repo. Self-contained; no agent yet. |
| **1** | `CLAUDE.md` | Claude Code (or Codex via `AGENTS.md` symlink) | Picks a profile, runs the modules, self-heals against `doctor.sh`, builds a first app. |

The actual install is plain idempotent bash, so it's testable **without an
agent**: `scripts/install-profile.sh <profile>` is the single source of truth
that both the orchestrator and the VM test drive.

```
bootstrap.sh            Stage 0 (curl | bash)
CLAUDE.md               Stage 1 orchestrator   (AGENTS.md → symlink for Codex)
profiles/*.yaml         web-starter | full-stack | indie-game | ml-lab | everything
scripts/install-profile.sh   profile → modules, in numeric order, then doctor
modules/00,01,02,03,05,06,07,08,09  core (every profile): foundation, shell, terminal, editors, agents, skills, secrets, safety, dx
modules/10,12,15,20,30,40        web, containers, testing, mobile, games, ml (per profile)
templates/              known-good starters (web/mobile/game) that `launchpad new` scaffolds
lib/common.sh           logging, idempotency, backup, brew + MCP helpers
lib/doctor.sh           green/red health check (exit non-zero on red)
config/                 alacritty, starship, zshrc, git, agent + safety + dx configs + house-rules
docs/                   GitHub Pages site (Catppuccin Mocha, no build step)
scripts/new-project.sh  `launchpad new`: scaffold a template, then git + private backup + hooks
scripts/harden-project.sh  make any folder safe: secret-scan hook + private GitHub backup
scripts/report.sh       `launchpad report`: secret-free diagnostic bundle to send for help
scripts/update.sh       refresh brew/npm/uv + re-wire MCP + doctor
scripts/test-in-vm.sh   Tart harness: clean macOS VM → bootstrap → install → doctor
```

## Design principles

- **Idempotent** — every install checks "already present?" first; re-running is safe.
- **Full autonomy** — both agents are pre-configured to run without approval prompts.
- **Back up before touching** — any dotfile is copied to `<file>.backup.<timestamp>`.
- **Log everything** — all scripts tee to `~/launchpad-setup.log`.
- **Self-healing** — `doctor.sh` is red/green; the orchestrator fixes reds and re-runs.
- **Safety-first for non-coders** — secrets are blocked locally (global gitignore + a gitleaks pre-commit hook), every project gets a **private** GitHub backup, and apps report runtime errors to Sentry that the agents can read and fix.
- **Apple Silicon + macOS ≥ 14 only** — hardcoded `/opt/homebrew`, asserts and bails otherwise.

## Verified-facts audit (2026-06-14)

Tool names and config keys drift; these were checked against live docs at build
time. The corrections baked in (vs. older guidance):

| Area | Current truth |
|---|---|
| Claude autonomy | `~/.claude/settings.json` → `{"permissions":{"defaultMode":"bypassPermissions"}}` |
| Codex autonomy | `~/.codex/config.toml` → `approval_policy="never"`, `sandbox_mode="danger-full-access"` |
| Codex `approval_policy` | valid values are `untrusted` / `on-request` / `never` — **`on-failure` is deprecated** |
| Claude MCP | `claude mcp add --scope user <name> -- npx …` (stdio) / `--transport http <url> --header …` |
| Codex MCP | `[mcp_servers.<name>]` tables in `config.toml`; remote uses `url` + `bearer_token_env_var` |
| **GitHub MCP** | old `@modelcontextprotocol/server-github` is **deprecated** → use remote `https://api.githubcopilot.com/mcp/` with `gh auth token` |
| Context7 MCP | `@upstash/context7-mcp`; optional free key via `--api-key` (local) or `CONTEXT7_API_KEY` header (remote) |
| Playwright MCP | `@playwright/mcp@latest --headless --isolated` (Microsoft official) |
| Filesystem MCP | `@modelcontextprotocol/server-filesystem <dir>` (still canonical) |
| Codex editor ext | **`openai.chatgpt`** (not `openai.codex`) |
| Claude editor ext | `anthropic.claude-code` (installs into Cursor via OpenVSX) |
| **Homebrew 6.0** | third-party taps now require **`brew trust <tap>`** before their formulae load (handled in `brew_tap`) |
| ollama | CLI/server = formula `brew install ollama`; the GUI app is `--cask ollama-app` |
| ngrok | `brew install --cask ngrok` (no tap) |
| Codex brew | `--cask codex` is now the **CLI** (desktop app is `codex-app`); the native installer stays canonical |
| PyTorch MPS | the default macOS `pip install torch` wheel already includes MPS — no CUDA index |
| **Antigravity install** | `curl -fsSL https://antigravity.google/cli/install.sh \| bash` → `~/.local/bin/agy`; self-de-quarantines; `agy update` to upgrade (verified against binary v1.0.8) |
| **Antigravity autonomy** | launch flag `--dangerously-skip-permissions` (no settings-key equivalent) → a `~/.zshrc` shell function makes it the interactive default |
| **Antigravity rules** | `~/.gemini/AGENTS.md` (the binary instructs *"append to AGENTS.md in the global customizations root"*) — we symlink both `AGENTS.md` and legacy `GEMINI.md` |
| **Antigravity MCP** | `~/.gemini/antigravity-cli/mcp_config.json` (JSON `mcpServers`; stdio = `command`/`args`/`env`, remote = `serverUrl`/`headers`) — **no `agy mcp add` subcommand exists** |
| Antigravity config | reuses the `~/.gemini/` tree; `colorScheme:"dark"` in `settings.json`; requires a Google/Gmail account + Chrome |
| **here.now** | an Agent **Skill**, not MCP. Vendor `install.sh` populates `~/.claude/skills/here-now` (+ a SHA-verified bundled jq); we mirror it into `~/.agents/skills` (Codex's real read path, *not* `~/.codex/skills` where `skills -g` wrongly puts it) and `~/.gemini/antigravity-cli/skills` (agy) |
| here.now auth | anonymous (24h **public** sites) or `HERENOW_API_KEY` / `~/.herenow/credentials`. Sites are public by default — house-rules warn agents not to publish secrets |
| **Superpowers (Claude Code)** | full plugin via the **scriptable** `claude plugin install superpowers@claude-plugins-official` CLI (slash `/plugin` is user-only and can't be scripted) + `enabledPlugins` in `settings.json` |
| **Superpowers (Codex + agy)** | **degraded mode**: `npx skills add obra/superpowers -a codex -a antigravity-cli` + workflow wired into the shared `AGENTS.md` (neither has a scriptable native path; agy has no native path at all) |
| Skills CLI | Vercel `npx skills add … -g -y -a claude-code -a codex -a antigravity-cli`. **agy target is `antigravity-cli`**, not `antigravity` (different dir) |
| Curated skills | `agent-browser` (vercel-labs/agent-browser); `web-design-guidelines` (vercel-labs/agent-skills); `frontend-design`, `skill-creator`, `pdf`, `docx`, `pptx`, `xlsx` (**anthropics/skills** — the Vercel README example misattributes the first two) |
| Superpowers `debugging` | actual skill name is **`systematic-debugging`** |
| **agent-browser** | Homebrew core formula `brew install agent-browser` + `agent-browser install` (Chrome for Testing). Update verb is **`upgrade`** (not `update`); **no `--version`** — use `agent-browser doctor` |
| **Maestro (mobile e2e)** | `curl -fsSL https://get.maestro.mobile.dev \| bash` → `~/.maestro/bin` (needs JDK 17+). **NOT `brew install maestro`** — that cask is the unrelated runmaestro.ai tool |
| Playwright pre-cache | macOS = plain `npx playwright install` (`--with-deps` is Linux-only); cache `~/Library/Caches/ms-playwright`. CI uses `--with-deps` + `~/.cache/ms-playwright` |
| Test scaffold | `config/testing/`: Vitest 4 + Testing Library, Playwright + `@axe-core/playwright` (**default** import) + `toHaveScreenshot`, GH Actions CI. 15-testing runs with the `web` area; Maestro only with `mobile` |
| **Containers** | **OrbStack only** (no Docker Desktop): `brew install --cask orbstack` gives `docker` + Compose v2 + buildx + GUI + `.orb.local`. Moved out of 10-web into `12-containers.sh` (runs with `web` or `ml`). Engine needs the app launched → doctor checks it **soft** |
| Container tools | `hadolint` (Dockerfile lint), `dive` (image slim), `flyctl`→**`fly`** (deploy). buildx ships with the engine. Templates in `config/docker/` (multi-stage Node, Compose app+pg+redis, `.dockerignore`) |
| Container skill | **none installed** — no well-maintained docker skill exists on skills.sh; rely on templates + the `AGENTS.md` Containers house-rule |
| **Safety (secrets)** | local-first: a global gitignore wired via `core.excludesfile` blocks `.env`/keys, and a **gitleaks** pre-commit hook (`v8.30.1`) refuses commits containing a secret. `08-safety.sh`. The local hook is the **primary** defence |
| **Backups** | every project gets a **private** GitHub repo + initial push (`gh repo create --private`, in `harden-project.sh`); `mkproj` and `launchpad new` install the hook + backup. Local git on one Mac is not a backup |
| **GitHub push protection** | enabled via `gh api --method PATCH` with **bracket-notation** `security_and_analysis[…][status]=enabled` — **free on public repos only**; free private repos return **HTTP 422** (detected and skipped gracefully) |
| **pre-commit** | framework `brew install pre-commit`; base `config/safety/.pre-commit-config.yaml` runs gitleaks + Biome (`biome-check` `v2.5.0`) + `npm test --if-present`; `pre-commit install` is per-repo |
| **Biome** | `brew install biome` (v2.x; binary `biome`, `biome check --write` — **not** `--apply`); shared `config/dx/biome.json` (`$schema` 2.5.0) copied into every project |
| **Sentry MCP** | all three agents → hosted `https://mcp.sentry.dev/mcp` (OAuth, one-time `/mcp` sign-in, exactly like the GitHub MCP). Headless alt: `npx @sentry/mcp-server@latest` + `SENTRY_ACCESS_TOKEN`. SDK `@sentry/nextjs` **v10** in the web template (env DSN ⇒ no-op when unset) |
| **DX tools** | `09-dx.sh`: `beekeeper-studio` cask (DB GUI), `terminal-notifier` (+ a `launchpad-notify` wrapper), the `launchpad` command. Media tools `ffmpeg` + `imagemagick` (binary `magick`) added to `00-foundation.sh` |
| **Starter templates** | `templates/` scaffold via official CLIs: web = `create-next-app` (+ tests + Sentry, **runs key-free**), mobile = `create-expo-app`, game = Phaser `template-vite-ts`. Supabase/Stripe are **not** bundled (they can't run without keys); added via recipes. `vercel/nextjs-subscription-payments` is **archived** |
| **ccusage** | `npx ccusage@latest` (shell alias) — Claude Code token usage + estimated cost from local logs, no key/network |
| **Add-on 07** | polish & resilience: pre-warmed pre-commit hooks; `launchpad spend` (spike detector + optional monthly budget, launchd-scheduled, ccusage `daily --json` → `.period`/`.totalCost`); `chpwd` backup nudge (throttled, opt-out); `launchpad doctor --fix` (section→module re-run) |
| **Add-on 08** | secret management: optional 1Password (`op`) wiring — `launchpad secrets set/inject/run` over a committed secret-free `.env.tpl` (`op://` refs), `.env.local` fallback that never blocks; `07-secrets.sh` (core); op `inject {{ }}` vs `run KEY=op://` formats verified on op 2.34.1 |
| **Add-on 09** | loops & onboarding: `launchpad status` (~/Developer backup-state dashboard, local-git-only), `launchpad signin` (guided GitHub/Sentry/here.now/agent checklist), `launchpad sentry-setup` (DSN validate + `.env.local` upsert; agent-MCP path via AGENTS.md recipe, `@sentry/wizard` fallback) |
| **Add-on 10** | guided provisioning wizards: `launchpad add supabase` (email/password auth via @supabase/ssr), `launchpad add stripe` (test-mode Checkout + webhook), `launchpad add vercel` (link + push env + deploy) — testable shell wrappers scaffold-if-absent + write keys; the interactive logins are AGENTS.md recipes (sign-in-gated). APIs verified vs live docs 2026-06-17 |

## Test it

On an Apple-Silicon Mac with [Tart](https://tart.run):

```bash
scripts/test-in-vm.sh web-starter      # clean VM → bootstrap → install → doctor
```

It clones a fresh `macos-sequoia-base` VM, shares this repo in, runs the real
install path headlessly, and exits non-zero if `doctor.sh` finds any red.

Static checks: `shellcheck **/*.sh` and the config parsers (TOML/JSON/YAML).

## Publish / fork

Publish (from the repo root, `gh` authenticated):

```bash
gh repo create <user>/mac-launchpad --public --source=. --remote=origin --push
gh api --method POST -H "Accept: application/vnd.github+json" \
  /repos/<user>/mac-launchpad/pages --input - <<<'{"source":{"branch":"main","path":"/docs"}}'
```

To **fork/rebrand**: change the `zigrivers/mac-launchpad` URLs in `bootstrap.sh`
(or set `LAUNCHPAD_REPO`), `CLAUDE.md`, and `docs/*.html`. `bootstrap.sh` honors
`LAUNCHPAD_REPO`, `LAUNCHPAD_DIR`, and `LAUNCHPAD_SKIP_CLONE`.

## License

MIT — see `LICENSE`.
