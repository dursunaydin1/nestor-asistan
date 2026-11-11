import react from '@vitejs/plugin-react';
import { defineProject } from 'vitest/config';

// Separate from vite.config.ts so unit tests do not run the PWA and Tailwind plugins
export default defineProject({
  plugins: [react()],
  test: {
    name: 'web',
    // happy-dom: jsdom 31 took minutes to load on the 8 GB dev machine
    environment: 'happy-dom',
    pool: 'threads',
    setupFiles: ['./src/test/setup.ts'],
    include: ['src/**/*.test.{ts,tsx}'],
  },
});
