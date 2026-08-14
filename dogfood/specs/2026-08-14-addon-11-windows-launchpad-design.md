# Add-on 11 — Windows Launchpad (design)

**Goal.** The same repo provisions a brand-new **Windows PC** the way it already
provisions a new Mac: one pasted command → sign into the agents → "set me up" →
doctor goes green → first app. The end user is non-technical; the two paths must
be equally guided, and choosing between them must be obvious.

## How the two platforms coexist

| Layer | macOS (unchanged) | Windows (new) | Shared |
|---|---|---|---|
| Stage 0 | `bootstrap.sh` (curl \| bash) | `bootstrap.ps1` (irm \| iex) | repo clone target `~/Developer/mac-launchpad` |
| Stage 1 | `scripts/install-profile.sh` → `modules/*.sh` | `windows/install-profile.ps1` → `windows/modules/*.ps1` | **`profiles/*.yaml`** (area lists are platform-neutral), `CLAUDE.md` orchestrator (routes by OS) |
| Helpers | `lib/common.sh` | `windows/lib/common.ps1` | logging/idempotency *patterns* mirrored 1:1 |
| Health | `lib/doctor.sh` | `windows/lib/doctor.ps1` | green/red contract, exit non-zero on red |
| CLI | `scripts/launchpad` (bash) | `windows/scripts/launchpad.ps1` | `new`/`harden` reuse the **same bash scripts** via Git Bash (ships with Git for Windows) |
| Docs | `docs/index.html` (Mac journey) | `docs/windows.html` (Windows journey) | one site, platform switcher in both heroes |

Principle: **parity of experience, not parity of tooling.** Windows uses its
native stack (winget, PowerShell 7, Windows Terminal) rather than emulating the
Mac's (Homebrew, zsh, Alacritty). The Mac path is not restructured — the Windows
tree is purely additive, so the existing curl one-liner, docs URLs, and VM test
keep working untouched.

## Verified facts the design rests on (live-checked 2026-08-14)

- **All three agents install natively on Windows**, no WSL:
  Claude Code `irm https://claude.ai/install.ps1 | iex` (→ `%USERPROFILE%\.local\bin\claude.exe`);
  Codex `irm https://chatgpt.com/codex/install.ps1 | iex` (config `%USERPROFILE%\.codex\config.toml`);
  Antigravity `irm https://antigravity.google/cli/install.ps1 | iex` (→ `%LOCALAPPDATA%\agy\bin`).
- Claude Code on Windows uses **Git Bash for its Bash tool** when Git for
  Windows is present — so agents can still run the repo's platform-neutral bash
  scripts (`harden-project.sh`, `new-project.sh`, template scaffolds).
- `irm <url> | iex` runs under the stock **Restricted** execution policy
  (policy blocks script *files*, not piped commands). Any on-disk `.ps1` is
  invoked as `powershell -NoProfile -ExecutionPolicy Bypass -File …`.
- **winget** ships with Windows 11 / modern 10; IDs for every tool verified
  against microsoft/winget-pkgs (Git.Git, GitHub.cli, Microsoft.VisualStudioCode,
  Microsoft.WindowsTerminal, Microsoft.PowerShell, BurntSushi.ripgrep.MSVC,
  sharkdp.fd, sharkdp.bat, eza-community.eza, junegunn.fzf, jqlang.jq,
  Starship.Starship, Gitleaks.Gitleaks, Google.Chrome, Schniz.fnm, Gyan.FFmpeg,
  ImageMagick.ImageMagick, astral-sh.uv, DEVCOM.JetBrainsMonoNerdFont,
  Docker.DockerDesktop, Google.AndroidStudio, GodotEngine.GodotEngine,
  Unity.UnityHub, Ollama.Ollama, ElementLabs.LMStudio,
  beekeeper-studio.beekeeper-studio, Stripe.StripeCli, OpenJS.NodeJS.LTS).
  Unattended pattern: `winget install --id <ID> -e --silent
  --accept-package-agreements --accept-source-agreements`.
- **Supabase CLI is not on winget** (supabase/cli#1611) — Windows path is
  scoop or per-project `npx supabase`; we document `npx`, doctor soft-checks.
- **Corepack is deprecated** (removed from Node 25+) — pnpm installs via
  `npm i -g pnpm`, not corepack, on Windows.
- pre-commit is a Python tool with no winget package — installed as
  `uv tool install pre-commit` (uv itself via winget).
- MCP stdio servers on native Windows need the `cmd /c npx …` wrapper
  (npx is `npx.cmd`, a batch file; claude-code#4158).
- Expo on Windows = **Android only**; iOS builds need a Mac or EAS cloud —
  docs say so plainly.

## Windows platform substitutions

| macOS | Windows | Why |
|---|---|---|
| Homebrew | winget | preinstalled, silent flags, no admin for user-scope |
| zsh + `~/.zshrc` managed block | PowerShell `$PROFILE` managed block | same marker-block idempotency |
| Alacritty + Catppuccin | Windows Terminal + Catppuccin scheme + Nerd Font | WT is preinstalled on 11; one less app |
| `terminal-notifier` | Windows toast via WinRT (`Windows.UI.Notifications`) | no extra install |
| OrbStack | Docker Desktop (soft-checked; needs WSL2 + first launch) | only mainstream engine on Windows |
| Xcode / CocoaPods / watchman | — (Android Studio + Temurin JDK only) | no iOS toolchain exists on Windows |
| MLX / MPS torch | plain torch (+ CUDA note when `nvidia-smi` present) | MLX is Apple-silicon-only |
| 1Password `op` + launchd spend guard + Sentry wizard + `launchpad add …` | deferred to a later add-on | keep v1 surface honest; CLI says "not on Windows yet" |
| `launchpad new` / `harden` (bash) | same bash scripts via Git Bash | one source of truth for project safety logic |

## Out of scope (v1, stated in docs and the CLI)

`launchpad` subcommands `report`, `spend`, `secrets`, `status`, `signin`,
`sentry-setup`, `add` on Windows print a friendly "not on Windows yet" line.
Cursor/Sublime, Alacritty, ngrok/cloudflared, Maestro, llama.cpp, hadolint/dive
are not installed on Windows v1. A Windows VM harness (the Tart twin) does not
exist; verification is syntax-level (`tests/test-windows-syntax.sh`) + a real
Windows PC checklist in the PR.
