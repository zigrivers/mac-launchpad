import { test, expect } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright'; // default import (not { AxeBuilder })

test('homepage has no accessibility violations', async ({ page }) => {
  await page.goto('/');
  const results = await new AxeBuilder({ page }).analyze();
  expect(results.violations).toEqual([]);
});
