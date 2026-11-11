import { defineConfig } from 'vitest/config';

// Each project keeps its own config; packages without tests yet do not fail the run
export default defineConfig({
  test: {
    projects: ['apps/web', 'packages/*', 'scripts'],
    passWithNoTests: true,
    // Threads start faster than forked processes, and two workers fit an 8 GB machine
    pool: 'threads',
    maxWorkers: 2,
  },
});
