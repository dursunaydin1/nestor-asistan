import { defineConfig, devices } from '@playwright/test';

const port = 4173;
// Explicit IPv4: `vite preview` on "localhost" may bind only ::1, which the readiness check misses
const baseURL = `http://127.0.0.1:${port}`;
const isCI = Boolean(process.env.CI);

// Every feature is also tested on WebKit because iOS Safari is a primary target (CLAUDE.md rule 10)
export default defineConfig({
  testDir: './e2e',
  fullyParallel: true,
  forbidOnly: isCI,
  retries: isCI ? 2 : 0,
  // WebKit on Windows is slow; lazy tab chunks on a cold browser can exceed the defaults
  timeout: 60_000,
  expect: { timeout: 10_000 },
  reporter: isCI ? [['github'], ['html', { open: 'never' }]] : 'list',
  use: {
    baseURL,
    locale: 'tr-TR',
    timezoneId: 'Europe/Istanbul',
    trace: 'on-first-retry',
    // Precaching competes with page loads in every fresh context; offline/PWA specs opt back in
    serviceWorkers: 'block',
  },
  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
    { name: 'webkit', use: { ...devices['Desktop Safari'] } },
    { name: 'mobile-android', use: { ...devices['Pixel 7'] } },
    { name: 'mobile-ios', use: { ...devices['iPhone 15'] } },
  ],
  // Tests run against the production build, the same output the service worker caches
  webServer: {
    command: `pnpm build && pnpm --filter @app/web preview --host 127.0.0.1 --port ${port} --strictPort`,
    url: baseURL,
    reuseExistingServer: !isCI,
    timeout: 300_000,
  },
});
