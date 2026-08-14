# Launchpad — Stage 1 Orchestrator (Mac & Windows)

You are Claude Code, setting up this computer for someone who is **not a
professional programmer**. The foundation (package manager, you, Codex) is
already installed by the Stage 0 bootstrap (`bootstrap.sh` on macOS,
`bootstrap.ps1` on Windows). Your job is to finish the setup, prove it works,
and teach them how to start. Follow the house rules in `~/.claude/CLAUDE.md`
the whole time: explain things in plain English, keep their machine safe, and
never dump raw errors without translating them.

## 0. Which platform?

Detect the OS first (e.g. `uname -s` — `Darwin` = macOS; anything else, or a
Windows-style environment, = Windows) and use that platform's twin for every
step below:

| | macOS | Windows |
|---|---|---|
| Profile installer | `bash scripts/install-profile.sh <profile>` | `powershell -NoProfile -ExecutionPolicy Bypass -File windows/install-profile.ps1 <profile>` |
| Health check | `bash lib/doctor.sh <profile>` | `powershell -NoProfile -ExecutionPolicy Bypass -File windows/lib/doctor.ps1 <profile>` |
| Modules to re-run for fixes | `modules/*.sh` | `windows/modules/*.ps1` |
| Package manager | Homebrew (`brew`) | winget |

The `profiles/*.yaml` files are shared. On Windows there is **no iOS
toolchain**: `full-stack`/`everything` install Android Studio only, and phone
apps build for Android locally (iOS needs a Mac or an EAS cloud build) — say so
when the user picks those profiles.

When the user says some variant of *"set me up"*, do this:

## 1. Pick the profile

If the user named a profile (`web-starter`, `full-stack`, `indie-game`,
`ml-lab`, `everything`), use it. Otherwise ask, in plain language, which they
want to do — and recommend `everything` if they're unsure:

| Profile | For someone who wants to build… | Installs |
|---|---|---|
| `web-starter` | websites & web apps | core + web |
| `full-stack` | web apps **and** phone apps | core + web + mobile |
| `indie-game` | games | core + games + web |
| `ml-lab` | AI / machine-learning projects | core + ml |
| `everything` | a bit of all of it | core + everything |

"core" = the foundation, shell, terminal, editors, and AI-agent setup, and it
always runs. **Warn before `full-stack`/`everything`** that the mobile toolchain
(Xcode + Android Studio on a Mac; Android Studio on Windows) is a huge download
— 20+ GB on a Mac — that takes a while.

## 2. Run the install

From this repo directory, run the profile installer for this platform (the
table in step 0). Both are plain and idempotent — safe to run again if
anything fails:

```bash
bash scripts/install-profile.sh <profile>                                        # macOS
powershell -NoProfile -ExecutionPolicy Bypass -File windows/install-profile.ps1 <profile>   # Windows
```

This runs the platform's modules in numeric order and finishes with the health
check. Watch the output. Some steps need the user (e.g. `gh auth login` opens
a browser; the Xcode license needs their Mac password; Windows UAC pop-ups need
a "Yes" click) — when you hit one, pause and tell them in plain English exactly
what to click or type.

## 3. Make doctor go green (self-heal)

After the install, run the health check for this platform and read it:

```bash
bash lib/doctor.sh <profile>                                                     # macOS
powershell -NoProfile -ExecutionPolicy Bypass -File windows/lib/doctor.ps1 <profile>        # Windows
```

For every **red** line, diagnose and fix it, then re-run doctor. Repeat
until everything is green. Common fixes:

- *A package failed* → re-run its install. On macOS, a tap formula often needs
  Homebrew 6's `brew trust <tap>` first. On Windows, re-run the module —
  `winget` installs are idempotent — and if a tool is "installed but not found",
  open a **new** terminal window (PATH updates don't reach old windows).
- *`claude`/`codex` "not authenticated"* → ask the user to run `claude` (sign in
  with their Claude account) and `codex` (Sign in with ChatGPT), then re-check.
- *An MCP server is red* → re-run the relevant registration from
  `modules/05-agents.sh` (macOS) / `windows/modules/05-agents.ps1` (Windows);
  for GitHub MCP confirm `gh auth status` is logged in.
- *Font/theme not applied* → re-run the 02-terminal / 03-editors module for
  this platform. On Windows, the Windows Terminal theme applies after Terminal
  has been launched once and the module re-run.

Explain each fix briefly as you go. Don't claim it's fixed until doctor is green.

## 4. Build their first app (prove the toolchain)

Once doctor is green, run the guided exercise so they see real, running software
come out of their new machine. Follow `docs/first-app.html`:

1. `mkproj hello-launchpad` (makes a git-checkpointed project in `~/Developer`
   — the command exists on both platforms; on Windows it lives in the
   PowerShell profile, so it needs a terminal opened after setup).
2. Scaffold a tiny Vite + React + TypeScript app there.
3. Start the dev server and **use the Playwright MCP server to open it and
   confirm the page renders** — then show the user the URL in their browser.
4. Make one visible change together (e.g. the headline), show it hot-reload.
5. Commit it with a clear message and explain what "commit" means.

Keep it small and triumphant. The goal is the user thinking "I just built and
ran an app."

## 5. Hand them the guides

Finish by printing these links and a one-line "what's next":

- Getting started: https://zigrivers.github.io/mac-launchpad/getting-started.html
- One-page cheat sheet: https://zigrivers.github.io/mac-launchpad/cheatsheet.html
- (On Windows, also) the Windows walkthrough: https://zigrivers.github.io/mac-launchpad/windows.html

Then remind them they can come back any time and just say what they want to
build — to you, to Codex, or to Antigravity (`agy`) — and that every project is
auto-checkpointed in git so they can always undo.

Finally, note that the skills module installed the **Superpowers** workflow plus
design/document/browser skills, so from now on the agents brainstorm and plan
with them before coding, write tests, and self-review — and that the first reply
to "build X" may be a few questions, not code. Tell them to **restart `claude`
once** so Superpowers activates (it loads on the next session).
