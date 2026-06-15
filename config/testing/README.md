# Test scaffold templates

The agents copy these into a project to give it a full testing setup. They are
**templates**, not installed globally — the agent adds the dev dependencies and
the config files when it scaffolds or adds tests to a project.

## Install the dev dependencies (in the project)

```bash
npm install -D \
  vitest @vitejs/plugin-react jsdom \
  @testing-library/react @testing-library/dom @testing-library/jest-dom @testing-library/user-event \
  @playwright/test @axe-core/playwright
```

> **Peer-version note (verified 2026-06-15):** `@vitejs/plugin-react@6` expects
> Vite 8, and Vitest 4 bundles its own Vite — if `npm install` reports a peer
> conflict, either pin `vite@^8` or use `@vitejs/plugin-react@^5` to match the
> Vite your project actually uses. `@testing-library/react@16` needs
> `@testing-library/dom@^10` and React 18 or 19.

Add scripts to `package.json`:

```json
{
  "scripts": {
    "test": "vitest run",
    "test:watch": "vitest",
    "e2e": "playwright test"
  }
}
```

## What's here

| File | Purpose |
|---|---|
| `vitest.config.ts` + `vitest.setup.ts` | Unit/component tests (jsdom + Testing Library) |
| `example.test.tsx` | Sample component test |
| `playwright.config.ts` | E2E config (starts your dev server, Chromium) |
| `e2e/example.spec.ts` | Sample end-to-end test |
| `e2e/accessibility.spec.ts` | axe accessibility check on a page |
| `e2e/visual.spec.ts` | `toHaveScreenshot()` visual regression |
| `ci/test.yml` | GitHub Actions: runs Vitest + Playwright on push (copy to `.github/workflows/`) |
| `maestro/flow.yaml` | Sample Maestro mobile e2e flow |

## Run them

```bash
npm test                 # Vitest unit/component tests
npx playwright test      # Playwright e2e + a11y + visual
maestro test maestro/flow.yaml   # mobile e2e (mobile profile)
```

The browsers Playwright needs are already cached system-wide (by `15-testing.sh`),
so the first `playwright test` won't re-download them.
