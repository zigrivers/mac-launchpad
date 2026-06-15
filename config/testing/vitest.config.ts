import { defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  test: {
    environment: 'jsdom',
    globals: true,
    setupFiles: './vitest.setup.ts',
    // Keep Vitest away from Playwright's e2e specs.
    exclude: ['**/node_modules/**', '**/e2e/**'],
  },
});
