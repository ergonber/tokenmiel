/**
 * Server entry point.
 *
 * Supports both Bun and Node.js runtimes for deployment flexibility.
 * - In Bun: uses Bun.serve for optimal performance
 * - In Node.js/Vercel: exports the Hono app as a serverless function
 *
 * The Hono app instance lives in app.ts so it can be imported in tests
 * without side effects (no port binding).
 */

import { app } from './app.js';
import { env } from './config/env.js';
import { bootstrapChain } from './modules/shared/infrastructure/on-chain/index.js';
import { apiPublicClient } from './modules/shared/infrastructure/on-chain/publicClient.js';
import { logger } from './shared/logger.js';

// Fail-fast: verify every suite contract's runtime bytecode against its pin
// (CIS §2) BEFORE serving, using the env-ranked RPC transport (ADR-023). A
// mismatch / unknown chain / missing code / RPC failure aborts boot.
let bootstrap: Awaited<ReturnType<typeof bootstrapChain>>;
try {
  bootstrap = await bootstrapChain(env.CHAIN_ID, apiPublicClient(env.CHAIN_ID));
} catch (err) {
  // The err serializer (logger.ts) strips any RPC URL from the message first.
  logger.fatal({ err }, 'chain bootstrap failed — aborting startup');
  process.exit(1);
}
logger.info(
  {
    chainId: bootstrap.chainId,
    deployVersion: bootstrap.deployVersion,
    verified: bootstrap.checks.length,
  },
  'chain bootstrap OK — runtime bytecode verified against pins',
);

// Detect runtime: Bun vs Node.js
const isBun = typeof (globalThis as any).Bun !== 'undefined';

if (isBun) {
  // Bun runtime: use native Bun.serve
  const server = (globalThis as any).Bun.serve({
    port: env.PORT,
    fetch: app.fetch,
  });

  logger.info(
    {
      port: server.port,
      chainId: env.CHAIN_ID,
      env: env.NODE_ENV,
      runtime: 'bun',
    },
    `tokenization-api started on port ${server.port}`,
  );
} else {
  // Node.js/Vercel runtime: export the app for serverless
  logger.info(
    {
      chainId: env.CHAIN_ID,
      env: env.NODE_ENV,
      runtime: 'nodejs',
    },
    'tokenization-api ready for serverless (Vercel Functions)',
  );
}

// Export for Vercel Functions / Node.js serverless
export default app;
