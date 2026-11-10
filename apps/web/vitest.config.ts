import react from '@vitejs/plugin-react';
import { defineProject } from 'vitest/config';

// Separate from vite.config.ts so unit tests do not run the PWA and Tailwind plugins
export default defineProject({
  plugins: [react()],
  test: {
    name: 'web',
    environment: 'jsdom',
    setupFiles: ['./src/test/setup.ts'],
    include: ['src/**/*.test.{ts,tsx}'],
  },
});
