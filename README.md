# Mac Launchpad

Turn a brand-new Mac into a complete software-development machine for a
**non-technical person**, driven by **Claude Code** and **OpenAI Codex**.

> **This README is for whoever maintains the repo.** Everything for the end user
> lives on the GitHub Pages site: **https://zigrivers.github.io/mac-launchpad/**

The end state: someone runs one command in the stock Terminal, signs into the
two agents, then tells Claude Code *"set me up"* and walks away — ending with a
configured environment for web apps, games, mobile apps, and AI/ML work, plus
the guides to start building.

## How it works (two stages)

| Stage | File | Run by | Does |
|---|---|---|---|
| **0** | `bootstrap.sh` | the human, in Terminal.app | Xcode CLT → Homebrew → both agents (native installers) → seed full-autonomy configs → clone this repo. Self-contained; no agent yet. |
| **1** | `CLAUDE.md` | Claude Code (or Codex via `AGENTS.md` symlink) | Picks a profile, runs the modules, self-heals against `doctor.sh`, builds a first app. |

The actual install is plain idempotent bash, so it's testable **without an
agent**: `scripts/install-profile.sh <profile>` is the single source of truth
that both the orchestrator and the VM test drive.

```
bootstrap.sh            Stage 0 (curl | bash)
CLAUDE.md               Stage 1 orchestrator   (AGENTS.md → symlink for Codex)
profiles/*.yaml         web-starter | full-stack | indie-game | ml-lab | everything
scripts/install-profile.sh   profile → modules, in numeric order, then doctor
modules/00,01,02,03,05  core (every profile): foundation, shell, terminal, editors, agents
modules/10,20,30,40     web, mobile, games, ml (per profile)
lib/common.sh           logging, idempotency, backup, brew + MCP helpers
lib/doctor.sh           green/red health check (exit non-zero on red)
config/                 alacritty, starship, zshrc, git, agent configs + house-rules
docs/                   GitHub Pages site (Catppuccin Mocha, no build step)
scripts/update.sh       refresh brew/npm/uv + re-wire MCP + doctor
scripts/test-in-vm.sh   Tart harness: clean macOS VM → bootstrap → install → doctor
```

## Design principles

- **Idempotent** — every install checks "already present?" first; re-running is safe.
- **Full autonomy** — both agents are pre-configured to run without approval prompts.
- **Back up before touching** — any dotfile is copied to `<file>.backup.<timestamp>`.
- **Log everything** — all scripts tee to `~/launchpad-setup.log`.
- **Self-healing** — `doctor.sh` is red/green; the orchestrator fixes reds and re-runs.
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
