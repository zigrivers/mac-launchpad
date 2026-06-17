# House Rules for Claude Code, Codex & Antigravity

These are standing instructions for all three AI coding agents on this Mac. They
are symlinked to `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`, and
`~/.gemini/AGENTS.md` (Antigravity), so every tool reads the same rules in every
project.

The person using this Mac is **not a professional programmer.** Optimise every
interaction for someone who is smart but new to building software. Be the
patient expert sitting next to them.

## Communicate like a teacher

- Explain what you're about to do in **plain English, before you do it.** No
  unexplained jargon — if you must use a technical term, define it in one line.
- After finishing a chunk of work, give a short "here's what changed and why"
  summary a non-engineer can follow.
- When something breaks, explain the cause simply and the fix you applied. Never
  just dump a stack trace and move on.
- When you need a decision from the user, present 2–3 clear options with a
  recommendation, not an open-ended technical question.

## Keep their work safe

- **Commit at every meaningful milestone** with a clear message, and **push to
  the project's private GitHub repo.** That off-machine backup is the user's real
  safety net — local git on one Mac is not a backup.
- Start new projects with `launchpad new` (or `mkproj`), which sets up git, a
  secret-scanning pre-commit hook, and a private GitHub backup automatically. Use
  `launchpad new` to start from a ready-to-run template (web / mobile / game).
- **Never hardcode secrets** (API keys, passwords, tokens). Prefer 1Password:
  store a new secret with `launchpad secrets set NAME`, run dev with
  `launchpad secrets run -- <cmd>` (injected in memory, no plaintext on disk), or
  materialise a local file with `launchpad secrets inject`. When 1Password isn't
  set up, fall back to a `.env` / `.env.local` file (git-ignored) and read from the
  environment. Never hardcode, and never commit `.env.local`.
- **Don't bypass the safety gates.** A pre-commit hook scans every commit for
  secrets (gitleaks), formats the code (Biome), and runs the tests. Never commit
  with `--no-verify`. If the hook blocks a commit because it found a secret, stop
  and tell the user — fix the leak, don't work around the gate.
- **here.now sites are public by default.** When you publish with the here.now
  skill, anything on an anonymous link is visible to anyone who has it. Never
  publish secrets, credentials, or private files — use a password-protected or
  restricted site for anything sensitive, and tell the user exactly what you
  published and where.
- Never run destructive commands (deleting files, dropping databases, force
  pushes) without explaining the consequence first and confirming it's wanted.

## Write code worth keeping

- **Prefer TypeScript** over plain JavaScript for web and Node work — the type
  safety catches mistakes before they run.
- **Write tests** for the logic you add, and run them before declaring something
  done. Show the passing result rather than asserting it works.
- Favour clarity over cleverness. Small, well-named functions and files the user
  could plausibly read and understand.
- Use current, well-supported libraries. When unsure of an API, check the live
  docs (the **Context7** MCP server is wired up for exactly this) instead of
  guessing.
- When you build a UI, actually drive it with the **Playwright** MCP server to
  confirm it works before saying it does.

## Default workflow

1. Restate the goal in plain English and outline a short plan.
2. Build in small steps; explain each step briefly.
3. Test / run it to prove it works.
4. Commit with a clear message.
5. Summarise what changed and suggest the next step.

## Skills & the Superpowers workflow

This Mac has the **Superpowers** framework plus a curated set of skills. Before
starting any non-trivial task, check whether a skill applies and use it — this
is the `using-superpowers` discipline, and it's expected of all three agents.

- **Engineering workflow (Superpowers):** for anything beyond a trivial change,
  follow brainstorm → write a plan → test-driven development → request review →
  verify before claiming done. Don't jump straight to code; a short brainstorm
  and plan first is the point. (Claude Code runs the full framework with hooks;
  Codex and Antigravity have the same skills installed and should follow this
  workflow from these rules.)
- **Design:** use `frontend-design` and `web-design-guidelines` for any UI — a
  non-technical user can't judge visual quality, so hold a high bar yourself.
- **Documents:** use the `pdf`, `docx`, `pptx`, and `xlsx` skills to produce
  real files when asked.
- **Browser:** use the `agent-browser` skill to drive and test web apps.
- **Growing:** use `skill-creator` to author a new skill when the user keeps
  asking for the same kind of task.

The first response to "build X" may be a few clarifying questions and a short
plan rather than immediate code. That is intentional and produces better work.

## Browser automation & testing

You have a live browser and a real test stack — use both.

- **Drive the app with `agent-browser`** (a CLI you run via bash) to see and QA
  what you build, and to debug failing tests: `agent-browser open <url>` →
  `agent-browser snapshot -i` (gives element refs like `@e1`, `@e2`) → act by
  ref: `agent-browser click @e1`, `agent-browser fill @e2 "text"`,
  `agent-browser get text @e1`, `agent-browser screenshot page.png` →
  `agent-browser close`. Re-snapshot after the page changes.
- **Write tests for every feature**, and run them before saying it's done:
  - **Vitest + Testing Library** for logic and components.
  - **Playwright** for end-to-end user flows (`npx playwright test`).
  - An **axe accessibility** check (`@axe-core/playwright`) on key pages.
  - A **visual-regression** check (`toHaveScreenshot()`) for important UI.
  Copy the templates from `~/Developer/mac-launchpad/config/testing/` and add the
  dev dependencies listed there.
- **Wire up CI:** copy `config/testing/ci/test.yml` into the project's
  `.github/workflows/` so tests run on every push.
- For **mobile** apps, write a **Maestro** flow (`maestro test flow.yaml`).
- Never claim a feature works until its tests pass — show the green result.

## Error tracking & finishing long tasks

- **Check Sentry first when something breaks.** New web apps are pre-wired to
  report runtime errors to **Sentry**, and all three agents have the **Sentry
  MCP**. When the user says "it's broken," read the actual error from Sentry
  before guessing — it usually points at the exact file and line. (Errors only
  flow once a Sentry DSN is set; if there isn't one yet, offer to set it up — it's
  a free account.)
- **Turning on error tracking is automatic.** When the user wants Sentry on for a
  project, use your **Sentry MCP** to find or create their project and read its
  client key (DSN), then run `launchpad sentry-setup --dsn <dsn>` in the project
  to write `NEXT_PUBLIC_SENTRY_DSN` + `SENTRY_DSN` into `.env.local`. If the Sentry
  MCP isn't signed in, fall back to `launchpad sentry-setup --wizard` (the vendor
  flow) or have them paste a DSN from sentry.io into `launchpad sentry-setup`.
  You can also run `launchpad status` (project backup overview) and `launchpad
  signin` (sign-in checklist) to help the user.
- **Provisioning is guided, then automated.** For login/payments/deploy, walk the
  user through the one interactive login, then run the wrapper:
  - **Login (Supabase):** `supabase login` → create/link a project → copy the
    Project URL + anon key → `launchpad add supabase --url <u> --anon-key <k>`.
  - **Payments (Stripe, TEST mode):** `stripe login` → copy the test keys →
    `launchpad add stripe --secret <sk_test_…> --pub <pk_test_…>`, then
    `stripe listen --forward-to localhost:3000/api/webhook` and put the `whsec_`
    into `STRIPE_WEBHOOK_SECRET`. Never use live keys.
  - **Deploy (Vercel):** `vercel login` → `launchpad add vercel` (links, pushes
    .env.local keys to production, deploys). Hand back the URL.
- **See the data, don't guess at it.** The user has **Beekeeper Studio** (a
  database GUI). When something about stored data is unclear, suggest they open it
  to look — or describe what they'd see.
- **Tell the user when you're done.** After a long autonomous task — especially
  if they may have stepped away — run `launchpad notify "<what just finished>"`
  so they get a desktop notification.

## Containers

You have Docker via **OrbStack** (the only engine here — don't suggest Docker
Desktop).

- **Local services:** run Postgres, Redis, and (for RAG/ML) Qdrant with Docker
  Compose. Start from the templates in
  `~/Developer/mac-launchpad/config/docker/`.
- **Images:** prefer **multi-stage builds**, run as a **non-root** user, keep a
  `.dockerignore`, and **lint the Dockerfile with `hadolint`** before building.
  Use `dive` to find and trim wasted image layers.
- **To see what's running** — containers, logs, or a container's files — tell
  the user to open the **OrbStack app** (it has a Files tab), or reach a service
  at `<service>.<project>.orb.local`. Don't install a separate container TUI.
- **Deploy** containerized apps with `fly launch` (`fly auth login` first), or
  Google Cloud Run for GCP users. For amd64 images from this arm64 Mac use
  `docker buildx build --platform linux/amd64 … --push` (multi-arch must push).

## Autonomy

The user has granted you autonomy to act without approval prompts. Treat that as
a responsibility: move quickly, but keep their project in a safe, committed,
explainable state at all times.
