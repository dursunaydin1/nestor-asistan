import { expect, test } from '@playwright/test';
import tr from '../apps/web/src/i18n/tr.json' with { type: 'json' };

const tabs = [
  { label: tr.nav.today, path: '/bugun', title: tr.pages.today.title },
  { label: tr.nav.query, path: '/sorgula', title: tr.pages.query.title },
  { label: tr.nav.portfolio, path: '/portfoy', title: tr.pages.portfolio.title },
  { label: tr.nav.customers, path: '/musteriler', title: tr.pages.customers.title },
  { label: tr.nav.more, path: '/daha-fazla', title: tr.pages.more.title },
];

test('opens on the Today tab with the product name', async ({ page }) => {
  await page.goto('/');
  await expect(page).toHaveURL(/\/bugun$/);
  await expect(page).toHaveTitle(tr.app.name);
  await expect(page.getByRole('banner')).toContainText(tr.app.name);
  await expect(page.getByRole('heading', { level: 1 })).toHaveText(tr.pages.today.title);
});

test('switches between the five tabs from the bottom nav', async ({ page }) => {
  await page.goto('/bugun');
  const nav = page.getByRole('navigation', { name: tr.nav.label });

  for (const tab of tabs) {
    await nav.getByRole('link', { name: tab.label }).click();
    await expect(page).toHaveURL(new RegExp(`${tab.path}$`));
    await expect(page.getByRole('heading', { level: 1 })).toHaveText(tab.title);
    await expect(nav.getByRole('link', { name: tab.label })).toHaveAttribute(
      'aria-current',
      'page',
    );
  }
});

test('create menu opens with four options and closes with Escape', async ({ page }) => {
  await page.goto('/bugun');
  const openButton = page.getByRole('button', { name: tr.create.open });
  const dialog = page.getByRole('dialog', { name: tr.create.title });

  await openButton.click();
  await expect(dialog).toBeVisible();
  for (const label of [tr.create.property, tr.create.person, tr.create.request, tr.create.note]) {
    await expect(dialog.getByRole('button', { name: label })).toBeVisible();
  }

  await page.keyboard.press('Escape');
  await expect(dialog).toBeHidden();
});

// Safari does not focus buttons on mouse or touch, so focus return is a keyboard-user contract
test('create menu returns focus to its button for keyboard users', async ({ page }) => {
  await page.goto('/bugun');
  const openButton = page.getByRole('button', { name: tr.create.open });
  const dialog = page.getByRole('dialog', { name: tr.create.title });

  await openButton.focus();
  await page.keyboard.press('Enter');
  await expect(dialog).toBeVisible();

  await page.keyboard.press('Escape');
  await expect(dialog).toBeHidden();
  await expect(openButton).toBeFocused();
});

test('create menu closes from its close button', async ({ page }) => {
  await page.goto('/bugun');
  await page.getByRole('button', { name: tr.create.open }).click();
  const dialog = page.getByRole('dialog', { name: tr.create.title });
  await dialog.getByRole('button', { name: tr.create.close }).click();
  await expect(dialog).toBeHidden();
});

test('unknown address shows the not-found screen with a way back', async ({ page }) => {
  await page.goto('/boyle-bir-sayfa-yok');
  await expect(page.getByRole('heading', { name: tr.errors.notFound })).toBeVisible();
  await page.getByRole('link', { name: tr.errors.goHome }).click();
  await expect(page).toHaveURL(/\/bugun$/);
});

test('serves an installable Turkish web app manifest', async ({ request }) => {
  const response = await request.get('/manifest.webmanifest');
  expect(response.ok()).toBe(true);
  const manifest = (await response.json()) as {
    name: string;
    lang: string;
    display: string;
    icons: { sizes: string; purpose?: string }[];
  };
  expect(manifest.name).toBe(tr.app.name);
  expect(manifest.lang).toBe('tr');
  expect(manifest.display).toBe('standalone');
  expect(manifest.icons.some((icon) => icon.sizes === '512x512' && !icon.purpose)).toBe(true);
  expect(manifest.icons.some((icon) => icon.purpose === 'maskable')).toBe(true);
});
