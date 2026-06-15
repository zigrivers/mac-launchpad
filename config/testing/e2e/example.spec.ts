import { test, expect } from '@playwright/test';

test('homepage loads', async ({ page }) => {
  await page.goto('/');
  await expect(page).toHaveTitle(/.+/); // replace with your real title, e.g. /My App/
  await expect(page.locator('body')).toBeVisible();
});
