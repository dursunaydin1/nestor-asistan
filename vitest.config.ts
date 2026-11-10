import { defineConfig } from 'vitest/config';

// Each project keeps its own config; packages without tests yet do not fail the run
export default defineConfig({
  test: {
    projects: ['apps/web', 'packages/*'],
    passWithNoTests: true,
  },
});
