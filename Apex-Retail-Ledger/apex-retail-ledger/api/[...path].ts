// Vercel serverless entry point.
// A catch-all so every /api/* request is handed to the Express app defined in server.ts.
// The Express routes are declared with their full '/api/...' paths, and Vercel forwards
// the original request URL, so app routing matches without any rewriting.
// NOTE: explicit .js extension is required — the project is an ESM package
// ("type": "module"), so Vercel runs this function under Node's ESM loader, which
// does not resolve extensionless relative imports. '../server.js' maps to server.ts.
import app from '../server.js';

export default app;
