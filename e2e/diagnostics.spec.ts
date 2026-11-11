import { expect, test } from '@playwright/test';
import tr from '../apps/web/src/i18n/tr.json' with { type: 'json' };

test('diagnostics page runs the automatic device checks', async ({ page }) => {
  await page.goto('/tani');
  await expect(page.getByRole('heading', { level: 1 })).toHaveText(tr.diagnostics.title);
  await expect(page.getByTestId('status-indexedDb')).toHaveText(tr.diagnostics.status.ok);
  await expect(page.getByTestId('status-quota')).toHaveText(tr.diagnostics.status.info);
  await expect(page.getByTestId('status-device')).toBeVisible();
});
