/**
 * Hono application instance.
 *
 * Wires middleware and mounts routes.
 * Keeps server.ts (Bun.serve) separate from the Hono app so the app
 * is importable in tests without binding a port.
 */

import { AddressPending, UnknownDeployment } from '@tokenization/chain';
import { Hono } from 'hono';
import type { PublicClient } from 'viem';
import { env } from './config/env.js';
import {
  createAssetVaultClient,
  createIdentityRegistryClient,
  createRedemptionManagerClient,
} from './modules/shared/infrastructure/on-chain/index.js';
import { apiPublicClient } from './modules/shared/infrastructure/on-chain/publicClient.js';
import { ChainError, NotFoundError, ServiceUnavailableError } from './shared/errors.js';
import { logger } from './shared/logger.js';
import { corsMiddleware, errorHandler, rateLimit } from './shared/middleware.js';

const app = new Hono();

/** Minimal shape the status endpoint needs from any contract client. */
type StatusReader = { readonly address: string; paused: () => Promise<boolean> };
type StatusReaderFactory = (chainId: number, client?: PublicClient) => StatusReader;

// A Map (not a plain object) so unknown names like "toString"/"constructor" don't
// resolve to inherited prototype methods and slip past the 404 guard.
const CONTRACT_READERS = new Map<string, StatusReaderFactory>([
  ['AssetVault', createAssetVaultClient],
  ['IdentityRegistry', createIdentityRegistryClient],
  ['RedemptionManager', createRedemptionManagerClient],
]);

// Short TTL cache for the public status read so a request flood hits the cache,
// not the metered RPC. The read-vs-live LIVE rule (CIS §1.2) is about GATES
// (canMint/canRedeem/balance pre-tx), not this status display, so ~10s is fine.
// Bounded by construction: at most one entry per (chainId, contract).
const STATUS_TTL_MS = 10_000;
const statusCache = new Map<string, { paused: boolean; expiresAt: number }>();

// ---------------------------------------------------------------------------
// Global middleware
// ---------------------------------------------------------------------------

app.use('*', corsMiddleware);
app.use('*', rateLimit);

// ---------------------------------------------------------------------------
// Health check
// Per the plan: GET /health returns { status: 'ok', chainId: <active> }
// ---------------------------------------------------------------------------

app.get('/health', (c) => {
  return c.json({
    status: 'ok',
    chainId: env.CHAIN_ID,
    service: 'tokenization-api',
    version: '0.1.0',
  });
});

// ---------------------------------------------------------------------------
// Contract status — reads paused() from chain through a short TTL cache so a
// request flood can't amplify into the metered RPC. CIS §4.
// GET /contracts/AssetVault|IdentityRegistry|RedemptionManager/status
// ---------------------------------------------------------------------------

app.get('/contracts/:name/status', async (c) => {
  const name = c.req.param('name');
  const reader = CONTRACT_READERS.get(name);
  if (!reader) {
    return c.json(
      { ok: false, code: 'UNKNOWN_CONTRACT', message: `Unknown contract "${name}"` },
      404,
    );
  }
  try {
    // Building the client is RPC-free (resolveAddress + getContract); only paused()
    // hits the chain, so we serve that from the TTL cache when still fresh.
    const client = reader(env.CHAIN_ID, apiPublicClient(env.CHAIN_ID));
    const cacheKey = `${env.CHAIN_ID}:${name}`;
    const now = Date.now();
    const cached = statusCache.get(cacheKey);
    let paused: boolean;
    if (cached && now < cached.expiresAt) {
      paused = cached.paused;
    } else {
      paused = await client.paused();
      statusCache.set(cacheKey, { paused, expiresAt: now + STATUS_TTL_MS });
    }
    return c.json({ name, address: client.address, chainId: env.CHAIN_ID, paused });
  } catch (err) {
    // Classify so monitoring sees the real condition (not an opaque 500) and the
    // raw viem error (which carries the RPC url) never reaches the generic logger.
    if (err instanceof AddressPending) {
      throw new ServiceUnavailableError(`${name} is not deployed on chain ${env.CHAIN_ID}`);
    }
    if (err instanceof UnknownDeployment) {
      throw new NotFoundError(`No deployment for ${name} on chain ${env.CHAIN_ID}`);
    }
    // Sanitized by the logger err serializer (RPC URL stripped) — gives a diagnostic trail.
    logger.warn({ err }, `failed to read ${name} status`);
    throw new ChainError(`Failed to read ${name} status from chain`);
  }
});

// ---------------------------------------------------------------------------
// Module routes (wired in M1 as modules are implemented)
// ---------------------------------------------------------------------------
// app.route('/api/v1/identity', identityRoutes);
// app.route('/api/v1/lots', lotsRoutes);
// app.route('/api/v1/assets', assetsRoutes);
// ...

// ---------------------------------------------------------------------------
// Global error handler
// ---------------------------------------------------------------------------

app.onError(errorHandler);

// 404 handler
app.notFound((c) => {
  return c.json(
    {
      ok: false,
      code: 'NOT_FOUND',
      message: `Route ${c.req.method} ${c.req.path} not found`,
    },
    404,
  );
});

export { app };
