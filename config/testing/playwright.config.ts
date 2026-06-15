import { defineConfig, devices } from '@playwright/test';

// E2E config. Playwright starts your dev server, runs the specs in ./e2e against
// it, and reuses an already-running server locally. Adjust the port/command to
// match your project (Vite defaults to 5173; Next.js to 3000).
export default defineConfig({
  testDir: './e2e',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  reporter: 'html',
  use: {
    baseURL: 'http://localhost:5173',
    trace: 'on-first-retry',
  },
  webServer: {
    command: 'npm run dev',
    url: 'http://localhost:5173',
    reuseExistingServer: !process.env.CI,
  },
  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
  ],
});
