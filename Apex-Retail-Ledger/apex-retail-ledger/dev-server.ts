// Standalone server bootstrap for local development and self-hosted production.
// (On Vercel the Express app is served directly by api/[...path].ts and this file is unused.)
import path from 'path';
import express from 'express';
import app, { PORT } from './server';

const startServer = async () => {
  if (process.env.NODE_ENV !== 'production') {
    // Vite is a dev-only dependency; import it lazily so production/self-hosted
    // startups never require it.
    const { createServer: createViteServer } = await import('vite');
    const vite = await createViteServer({
      server: { middlewareMode: true },
      appType: 'spa',
    });
    app.use(vite.middlewares);
  } else {
    const distPath = path.join(process.cwd(), 'dist');
    app.use(express.static(distPath));
    app.get('*', (req, res) => {
      res.sendFile(path.join(distPath, 'index.html'));
    });
  }

  app.listen(PORT, '0.0.0.0', () => {
    console.log(`Server running at http://0.0.0.0:${PORT} in ${process.env.NODE_ENV || 'development'} mode`);
  });
};

startServer();
