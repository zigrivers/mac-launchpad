# Mac Launchpad — Stage 1 Orchestrator

You are Claude Code, setting up this Mac for someone who is **not a professional
programmer**. The foundation (Homebrew, you, Codex) is already installed by
`bootstrap.sh`. Your job is to finish the setup, prove it works, and teach them
how to start. Follow the house rules in `~/.claude/CLAUDE.md` the whole time:
explain things in plain English, keep their machine safe, and never dump raw
errors without translating them.

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
(Xcode, Android Studio) is a 20+ GB download that takes a while.

## 2. Run the install

From this repo directory, run the profile installer. It is plain, idempotent
bash — safe to run again if anything fails:

```bash
bash scripts/install-profile.sh <profile>
```

This runs the modules in `modules/` in numeric order and finishes by running
`lib/doctor.sh`. Watch the output. Some steps need the user (e.g. `gh auth
login` opens a browser, the Xcode license needs their Mac password) — when you
hit one, pause and tell them in plain English exactly what to click or type.

## 3. Make doctor go green (self-heal)

After the install, run the health check and read it:

```bash
bash lib/doctor.sh <profile>
```

For every **red** line, diagnose and fix it, then re-run `doctor.sh`. Repeat
until everything is green. Common fixes:

- *A formula/cask failed* → re-run its install; if it's from a tap, the cause is
  often Homebrew 6's tap-trust — run `brew trust <tap>` then retry.
- *`claude`/`codex` "not authenticated"* → ask the user to run `claude` (sign in
  with their Claude account) and `codex` (Sign in with ChatGPT), then re-check.
- *An MCP server is red* → re-run the relevant `claude mcp add …` from
  `modules/05-agents.sh`; for GitHub MCP confirm `gh auth status` is logged in.
- *Font/theme not applied* → re-run `modules/02-terminal.sh` /
  `modules/03-editors.sh`.

Explain each fix briefly as you go. Don't claim it's fixed until doctor is green.

## 4. Build their first app (prove the toolchain)

Once doctor is green, run the guided exercise so they see real, running software
come out of their new machine. Follow `docs/first-app.html`:

1. `mkproj hello-launchpad` (makes a git-checkpointed project in `~/Developer`).
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

Then remind them they can come back any time and just say what they want to
build — to you or to Codex — and that every project is auto-checkpointed in git
so they can always undo.
