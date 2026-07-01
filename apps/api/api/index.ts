/**
 * Vercel API route wrapper.
 *
 * This file adapts the Hono app for Vercel Functions.
 * Vercel will automatically use this as a serverless function.
 */

import { app } from '../src/app.js';

// Vercel Functions expect a default export with the handler
export default app.fetch;