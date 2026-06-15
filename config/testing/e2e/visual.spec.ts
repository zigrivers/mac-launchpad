import { test, expect } from '@playwright/test';

// Visual regression. The first run records a baseline screenshot; later runs
// fail if the page changes. Update baselines on purpose with:
//   npx playwright test --update-snapshots
test('homepage looks right', async ({ page }) => {
  await page.goto('/');
  await expect(page).toHaveScreenshot('homepage.png', { maxDiffPixels: 100 });
});
