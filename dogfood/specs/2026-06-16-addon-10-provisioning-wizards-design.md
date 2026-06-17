# Add-on 10 — Guided provisioning wizards (design spec)

Status: approved design, 2026-06-16. Implements Phase 4 of `dogfood/roadmap.md`.
Spec lives here (not `docs/`) because `docs/` is the published GitHub Pages site;
this is an internal maintainer artifact.

## Goal

Turn three "prompt" recipes (login, payments, deploy) into **guided flows** that
take a non-technical user from intent → a working, tested integration on the
existing Next.js web template: **Supabase** (login/auth), **Stripe** (payments),
**Vercel** (deploy). Each stores keys via Add-on 08 (1Password) or `.env.local`.

Approved scope decision (user, 2026-06-16): **all three** in one add-on. Internally
decomposed into three independent units (each its own wrapper script + agent
recipe + tests) so they build, test, and review in isolation.

## Key architecture decision (the sign-in-gated pattern, from Add-ons 08–09)

The account/login/key steps (`supabase login`, `stripe login`, `vercel login`)
are **interactive browser/OAuth flows** that cannot be automated or VM-tested. So
each wizard splits in two:

- **Shell wrapper (`launchpad add <svc>`):** the deterministic, unit-tested part —
  confirm we're in a Next.js project, install the CLI/SDK if needed, scaffold the
  code files (idempotently), validate + write the keys the user provides into
  `.env.local` (or 1Password), add a test.
- **Agent recipe (`AGENTS.md`):** the "automatic" path — the assistant walks the
  user through the browser login + copying keys, then calls the wrapper with those
  keys. Sign-in-gated; documented; not shell-testable.

The scaffolds + key-writing + install paths are validated in a VM with **mock**
`supabase`/`stripe`/`vercel`/`brew` CLIs; the live login is documented as a human step.

## Shared conventions

- Self-contained, source-guarded scripts (the `scripts/secrets.sh` pattern): pure helpers (key validation, `.env` upsert, "in a Next.js project?", scaffold-if-absent) are unit-tested; CLI calls are mocked in tests.
- New commands hang off a new `launchpad add` dispatcher (`scripts/launchpad` → `add` → `scripts/add-<svc>.sh`).
- Keys default to `.env.local` (gitignored); when `op` is signed in (Add-on 08), the wrapper offers `launchpad secrets`. Reuse the ENVIRON-safe `.env` upsert from `scripts/sentry-setup.sh` (extract to avoid duplication, or copy the small helper).
- **Idempotent + non-destructive:** scaffold a file only if it does not already exist (never clobber the user's edited code); log a note when skipping. Re-running a wizard is safe.
- `lib/doctor.sh`: hard checks that the three CLIs are present (`supabase`, `vercel`, and `stripe` once this add-on installs it) + the three wrapper scripts executable.
- Docs: upgrade the existing `docs/recipes.html` login/payments/deploy prompts to mention `launchpad add`; getting-started callout; README audit.

## Architecture at a glance

| Unit | Responsibility |
|---|---|
| `scripts/add-supabase.sh` (new) | `launchpad add supabase`: install `@supabase/...`, scaffold the auth client + login/guard pages + test, write URL/anon-key. |
| `scripts/add-stripe.sh` (new) | `launchpad add stripe`: install the Stripe CLI + `stripe`/`@stripe/stripe-js`, scaffold pricing/checkout/webhook/premium + test, write secret/publishable keys. |
| `scripts/add-vercel.sh` (new) | `launchpad add vercel`: orchestrate `vercel link` → push `.env.local` keys via `vercel env` → `vercel deploy`. |
| `scripts/launchpad` (edit) | `add)` dispatcher → the three scripts. |
| `modules/10-web.sh` (edit) | Install the **Stripe CLI** (`brew install stripe`); `chmod +x` the three wrappers. |
| `lib/doctor.sh` (edit) | Web-stack checks: `stripe` CLI present; the three wrappers executable. |
| `config/agents/AGENTS.md` (edit) | Three recipes: "add login", "add payments", "deploy". |
| `templates/web/*` (maybe) | The scaffolded files live in the user's project (written by the wrappers), not the template; the template's `.env.example` already lists the keys. |

## Wizard 1 — Supabase (`launchpad add supabase [--url <u>] [--anon-key <k>]`)

**Deterministic core (tested):**
- Guard: must be run inside a Next.js project (a `package.json` with a `next` dependency); else a clear message, non-zero.
- Install `@supabase/supabase-js` (+ `@supabase/ssr` if the verified App-Router auth pattern needs it — see build-time verification).
- Scaffold (only if absent): a Supabase client module, an **email + password** login/sign-up/sign-out page, a server-side "must be logged in" guard on a dashboard page, and a test (the client module builds; the pages render). Exact file paths + code finalized against the **current** Supabase Next.js App-Router pattern at build time.
- Keys: validate + upsert `NEXT_PUBLIC_SUPABASE_URL` (an `https://<ref>.supabase.co` URL) and `NEXT_PUBLIC_SUPABASE_ANON_KEY` (a non-empty JWT-ish string) into `.env.local`.

**Pure units (tested):** `supabase_url_valid <s>`, `env_upsert`, `is_next_project`, `scaffold_if_absent <file>`.

**Agent recipe:** walk `supabase login` → create/link a project → copy the Project URL + anon (public) key → `launchpad add supabase --url … --anon-key …`.

## Wizard 2 — Stripe (`launchpad add stripe [--secret <sk>] [--pub <pk>]`)

**Deterministic core (tested):**
- Install the **Stripe CLI** (`brew install stripe`, via `modules/10-web.sh` and/or self-heal in the wrapper) + `stripe` (server) and `@stripe/stripe-js` (client) npm packages.
- Scaffold (only if absent): a pricing page with a Subscribe button, a Checkout API route (creates a Checkout Session), a webhook route (verifies the signature, marks paid), and a gated premium page; a test. Code finalized against the **current** `stripe` Node + Checkout + webhook API at build time.
- Keys: validate + upsert `STRIPE_SECRET_KEY` (must be **test mode** — `sk_test_…`) and `NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY` (`pk_test_…`) into `.env.local`. Reject live keys (`sk_live_`) with a clear "use test mode" message.

**Pure units (tested):** `stripe_test_secret_valid <s>` (accepts `sk_test_…`, rejects `sk_live_…`/junk), `stripe_pub_valid <s>` (`pk_test_…`), reuse `env_upsert`/`is_next_project`/`scaffold_if_absent`.

**Agent recipe:** walk `stripe login` → copy test-mode keys → `stripe listen --forward-to localhost:3000/api/webhook` for the webhook secret → `launchpad add stripe --secret … --pub …`.

## Wizard 3 — Vercel (`launchpad add vercel`)

**Deterministic core (tested where possible):**
- Guard: in a Next.js project; `vercel` CLI present.
- Orchestrate: `vercel link` (link/create the project — interactive), then for each `KEY=value` in `.env.local`, `vercel env add <KEY> production` (push the key), then `vercel deploy --prod`. Hand back the deployment URL.
- The **env-push logic** (read `.env.local`, push each non-comment `KEY` to Vercel) is the testable pure part (`env_keys <file>` lists the keys); the `vercel` calls are mocked in tests.

**Pure units (tested):** `env_keys <file>` (lists `KEY` names from a `.env.local`, skipping comments/blanks), reuse `is_next_project`.

**Agent recipe:** walk `vercel login` → `launchpad add vercel` (link + push env + deploy) → share the live URL.

## Shared infrastructure

- **`launchpad add` dispatcher:** `scripts/launchpad` gains `add)` → `case "$1" in supabase|stripe|vercel) exec bash "$ROOT/scripts/add-$1.sh" "${@:2}" ;; *) usage ;;`. Usage lines.
- **Stripe CLI install:** `modules/10-web.sh` adds `brew_install stripe` (the only new tool; supabase + vercel already install there) and `chmod +x` for the three wrappers.
- **Doctor:** in the "Web stack" section — `stripe` CLI present (hard, once installed); the three wrappers executable (hard).
- **Agent recipes (`AGENTS.md`):** "add login (Supabase)", "add payments (Stripe)", "deploy (Vercel)" — each: do the interactive login with the user, then run the wrapper.
- **Docs:** `docs/recipes.html` login/payments/deploy entries mention `launchpad add`; README audit row.

## Out of scope (YAGNI)

- **Supabase:** email/password only (no OAuth providers, magic links, RLS policies, or app data tables beyond auth).
- **Stripe:** **test mode only** (reject live keys); one Checkout flow + one webhook + one gated page (no customer portal, multiple plans, or tax/invoicing).
- **Vercel:** link + env + deploy (no custom domains, monorepos, or preview/prod env separation beyond Vercel's default).
- **No** non-Next.js framework support (the web template is Next.js App Router).
- **No** automation of the interactive `*-login` steps (guided via the agent recipe + docs).
- **Non-destructive:** never overwrite a file the user already has; scaffold-if-absent only.

## Build-time verifications (this add-on's biggest risk — version-sensitive app code)

- **Supabase Next.js App-Router auth pattern** on the current SDK: `@supabase/supabase-js` vs `@supabase/ssr` (`createBrowserClient`/`createServerClient` + cookie handling), `auth.signInWithPassword`/`signUp`/`signOut`, and the server-side session guard. Use the live docs (Context7) + the current package.
- **Stripe** current Node API: `stripe.checkout.sessions.create`, `stripe.webhooks.constructEvent`, `@stripe/stripe-js` `loadStripe`, and the Next 16 route-handler shapes for the checkout + webhook routes. Confirm the test-key prefixes (`sk_test_`/`pk_test_`).
- **Vercel** CLI: `vercel link`, `vercel env add <name> <environment>` (stdin value), `vercel deploy --prod` flags on the current CLI.
- **Next 16 App-Router** conventions (`app/` routes, route handlers, server vs client components) for every scaffold.
- The scaffolded TypeScript must **typecheck + the project must build** (`next build` or `tsc --noEmit`) with placeholder/test keys — the scaffolds are real app code, so a build smoke test is part of validation.

## Rollout & validation

Three new `scripts/add-*.sh` + the `launchpad add` dispatcher + the Stripe-CLI
install + doctor checks + three AGENTS.md recipes + docs. Unit tests for the pure
helpers (key validators, `.env` upsert, `is_next_project`, `scaffold_if_absent`,
`env_keys`) with **mock** `supabase`/`stripe`/`vercel`/`brew` CLIs. A VM probe
(`dogfood/remote-addon10.sh`) that scaffolds into a throwaway Next.js project with
the mock CLIs, asserts each wizard writes its files + keys idempotently, exercises
the Stripe-CLI install path, and (resources permitting) runs `next build` on a
scaffolded project to prove the generated code compiles. Ship when the VM run is
green and the probes pass; the live `*-login` + deploy paths are documented as
sign-in-gated. Because each wizard is independent, the implementation builds and
reviews them as separate work units.
