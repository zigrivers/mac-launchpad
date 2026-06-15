# Starter templates

`launchpad new` (or `scripts/new-project.sh`) scaffolds one of these, then runs
the safety flow (git + secret-scanning pre-commit hook + a **private** GitHub
backup) and opens your editor. Agents modify working code far better than they
write from a blank folder, so every project starts from something that **already
runs**.

| Template | What it is | Runs without keys? | Run it with |
|---|---|---|---|
| `web` | Next.js (App Router, TS) + Tailwind + Vitest/Playwright/axe + Sentry (env-DSN) + Biome + CI | **Yes** | `npm run dev` → http://localhost:3000 |
| `mobile` | Expo (React Native) + Expo Router + TypeScript + jest-expo | **Yes** (on your phone) | `npx expo start` → scan QR with Expo Go |
| `game` | Phaser 4 + Vite + TypeScript (official `template-vite-ts`, MIT) | **Yes** | `npm run dev` → http://localhost:8080 |
| `blank` | An empty, safe, backed-up project | — | tell an assistant what to build |

## How these are built (design note)

Each template is a small `scaffold.sh` that drives the **official** `create-*`
CLI (`create-next-app`, `create-expo-app`, Phaser's `template-vite-ts`) and then
layers on the repo's shared test stack (`config/testing/`), Biome
(`config/dx/biome.json`), and — for web — a no-op-until-configured Sentry wiring.

We scaffold via the official CLIs (rather than committing a frozen copy of each
app) so the starters never go stale and the repo stays lean. All facts were
verified against live sources on 2026-06-15.

## About login & payments (Supabase + Stripe)

The `web` starter deliberately **does not** bundle Supabase auth or Stripe
payments. The maintained third-party "Next + Supabase + Stripe" starters won't
even start `npm run dev` until you've created Supabase/Stripe accounts and pasted
keys — a terrible first experience for someone new. (The long-canonical
`vercel/nextjs-subscription-payments` is also archived as of 2025.)

So instead: start from the working `web` app, then add login and payments **on
top** when you're ready — just ask an assistant ("add user login", "add a payment
flow"); see `docs/recipes.html`. For a full pre-built SaaS, the agents can pull
in a maintained starter like `nextjs/saas-starter` and wire your keys.
