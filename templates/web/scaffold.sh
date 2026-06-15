#!/usr/bin/env bash
#
# templates/web/scaffold.sh <target-dir>
#
# A known-good WEB starter that RUNS IMMEDIATELY (no accounts or keys needed):
#   Next.js (App Router, TypeScript) + Tailwind
#   + Vitest/Testing Library + Playwright + axe (the repo's shared test stack)
#   + Sentry pre-wired to read its DSN from an env var (a no-op until you set it)
#   + Biome formatting + a GitHub Actions CI workflow
#
# Login (Supabase) and payments (Stripe) are deliberately NOT bundled — they'd
# stop the app from running until you pasted keys. Add them later with an
# assistant (see docs/recipes.html) on top of this working base.
#
# Verified 2026-06-15: create-next-app (Next 16), @sentry/nextjs v10 (env DSN is
# a documented no-op when unset).

set -uo pipefail
target="${1:?usage: scaffold.sh <target-dir>}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
REPO="$(cd "$HERE/../.." >/dev/null 2>&1 && pwd)"

echo "→ Creating a Next.js app (this takes a couple of minutes)…"
npx --yes create-next-app@latest "$target" \
  --ts --app --tailwind --no-eslint --no-src-dir \
  --import-alias "@/*" --use-npm --yes || { echo "create-next-app failed"; exit 1; }

cd "$target" || exit 1

echo "→ Adding the test stack (Vitest + Playwright + accessibility)…"
# --legacy-peer-deps avoids the @vitejs/plugin-react ↔ Vite peer churn on a fresh app.
npm i -D --legacy-peer-deps \
  vitest @vitejs/plugin-react jsdom \
  @testing-library/react @testing-library/dom @testing-library/jest-dom @testing-library/user-event \
  @playwright/test @axe-core/playwright >/dev/null 2>&1 || echo "  (some test deps didn't install — you can add them later)"

# Drop in the repo's shared testing overlays.
cp -f "$REPO/config/testing/vitest.config.ts" . 2>/dev/null || true
cp -f "$REPO/config/testing/vitest.setup.ts" . 2>/dev/null || true
cp -f "$REPO/config/testing/example.test.tsx" . 2>/dev/null || true
cp -f "$REPO/config/testing/playwright.config.ts" . 2>/dev/null || true
mkdir -p e2e && cp -f "$REPO/config/testing/e2e/"*.spec.ts e2e/ 2>/dev/null || true
mkdir -p .github/workflows && cp -f "$REPO/config/testing/ci/test.yml" .github/workflows/ 2>/dev/null || true
# Next.js dev server is :3000 (the shared config defaults to Vite's :5173).
sed -i '' 's/localhost:5173/localhost:3000/g' playwright.config.ts 2>/dev/null || true

echo "→ Pre-wiring Sentry error reporting (off until you add a DSN)…"
if npm i @sentry/nextjs >/dev/null 2>&1; then
  cat > instrumentation-client.ts <<'TS'
import * as Sentry from "@sentry/nextjs";

// Reads the DSN from an env var. Unset => the SDK sends nothing (a safe no-op).
// Add NEXT_PUBLIC_SENTRY_DSN to .env.local to turn on error reporting.
Sentry.init({
  dsn: process.env.NEXT_PUBLIC_SENTRY_DSN,
  tracesSampleRate: 1.0,
});
TS
  cat > sentry.server.config.ts <<'TS'
import * as Sentry from "@sentry/nextjs";

Sentry.init({
  dsn: process.env.SENTRY_DSN, // unset => no-op
  tracesSampleRate: 1.0,
});
TS
  cat > sentry.edge.config.ts <<'TS'
import * as Sentry from "@sentry/nextjs";

Sentry.init({
  dsn: process.env.SENTRY_DSN, // unset => no-op
  tracesSampleRate: 1.0,
});
TS
  cat > instrumentation.ts <<'TS'
export async function register() {
  if (process.env.NEXT_RUNTIME === "nodejs") await import("./sentry.server.config");
  if (process.env.NEXT_RUNTIME === "edge") await import("./sentry.edge.config");
}
export { captureRequestError as onRequestError } from "@sentry/nextjs";
TS
else
  echo "  (Sentry didn't install — add it later with: npx @sentry/wizard@latest -i nextjs)"
fi

# Biome config + scripts. Only wire a `test` script if Vitest actually installed,
# so the pre-commit test gate never fails on a fresh project.
cp -f "$REPO/config/dx/biome.json" . 2>/dev/null || true
npm pkg set scripts.format="biome format --write ." >/dev/null 2>&1 || true
npm pkg set scripts.check="biome check --write ." >/dev/null 2>&1 || true
npm pkg set scripts.e2e="playwright test" >/dev/null 2>&1 || true
if [ -d node_modules/vitest ]; then
  npm pkg set scripts.test="vitest run" >/dev/null 2>&1 || true
fi

# A .env you can fill in later (real .env.local stays gitignored).
cat > .env.example <<'ENV'
# Copy to .env.local and fill in as you add features. Never commit .env.local.

# Turn on error reporting (free Sentry account → Settings → Client Keys/DSN):
# NEXT_PUBLIC_SENTRY_DSN=
# SENTRY_DSN=

# Added when you wire up login (Supabase) — ask an assistant, see docs/recipes.html:
# NEXT_PUBLIC_SUPABASE_URL=
# NEXT_PUBLIC_SUPABASE_ANON_KEY=

# Added when you wire up payments (Stripe):
# STRIPE_SECRET_KEY=
# NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY=
ENV

echo "✓ Next.js app ready (runs key-free with: npm run dev)"
