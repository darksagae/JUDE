import tailwindcss from '@tailwindcss/vite';
import react from '@vitejs/plugin-react';
import path from 'path';
import {defineConfig} from 'vite';

export default defineConfig(() => {
  return {
    plugins: [react(), tailwindcss()],
    resolve: {
      alias: {
        '@': path.resolve(__dirname, '.'),
      },
    },
    server: {
      // HMR is disabled in AI Studio via DISABLE_HMR env var.
      // Do not modifyâfile watching is disabled to prevent flickering during agent edits.
      hmr: process.env.DISABLE_HMR !== 'true',
      // Disable file watching when DISABLE_HMR is true to save CPU during agent edits.
      // Also ignore the server sync DB: the /api/sync endpoint rewrites server-db.json on
      // every login/sync, which would otherwise trigger a full-page reload that bounces the
      // just-authenticated user straight back to the locked login screen.
      watch: process.env.DISABLE_HMR === 'true' ? null : { ignored: ['**/server-db.json'] },
    },
  };
});
