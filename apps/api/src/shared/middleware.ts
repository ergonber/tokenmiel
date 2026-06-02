/**
 * Hono middleware: CORS, rate-limit stub, and error handler.
 *
 * Rules (CLAUDE.md §5.7, §5.8):
 *   - Strict CORS: only own domains.
 *   - Rate limiting: Redis-backed (stub for Fase 0 — full impl in M1).
 *   - Error handler: never expose stack traces to clients.
 */

import type { Context, MiddlewareHandler } from 'hono';
import { cors } from 'hono/cors';
import { HTTPException } from 'hono/http-exception';
import { AppError, RateLimitError } from './errors.js';
import { logger } from './logger.js';

// ---------------------------------------------------------------------------
// CORS — strict (CLAUDE.md §5.8)
// ---------------------------------------------------------------------------

const PROD_ORIGINS = [
  'https://tokenization-platform.com',
  'https://www.tokenization-platform.com',
  'https://app.tokenization-platform.com',
];
const DEV_ORIGINS = ['http://localhost:3000', 'http://localhost:3001'];
// Default-strict: localhost is added ONLY when NODE_ENV is explicitly dev/test, so
// an unset/typo'd NODE_ENV in production does NOT silently open the localhost
// surface (the env schema defaults NODE_ENV to 'development', so a "!== production"
// check would fail open).
const isLocalEnv = process.env.NODE_ENV === 'development' || process.env.NODE_ENV === 'test';
const ALLOWED_ORIGINS = isLocalEnv ? [...PROD_ORIGINS, ...DEV_ORIGINS] : PROD_ORIGINS;

export const corsMiddleware = cors({
  origin: (origin) => (ALLOWED_ORIGINS.includes(origin) ? origin : null),
  allowMethods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowHeaders: ['Content-Type', 'Authorization', 'X-Request-ID'],
  credentials: true,
  maxAge: 600,
});

// ---------------------------------------------------------------------------
// Rate limit stub (Fase 0)
// Full Redis-backed rate limiting is wired in M1 (per-IP + per-user).
// ---------------------------------------------------------------------------

// Minimal in-process fixed-window limiter (per IP). The public /contracts route
// hits a metered RPC per request, so even M1 needs a throttle.
// NOTE (M1, best-effort, secondary): the real RPC-amplification guard is the TTL
// cache on the status read (app.ts); this limiter is a coarse second line. The
// platform does not yet inject a trusted peer IP, so the key falls back to
// forwarding headers and is therefore spoofable — the Redis-backed, trusted-proxy
// per-IP + per-user limiter (CLAUDE.md §5.7) replaces it in OP-2. The hard cap
// below keeps the map bounded regardless of how many distinct keys arrive.
const RATE_WINDOW_MS = 60_000;
const RATE_MAX = 60;
const RATE_MAX_KEYS = 10_000;
const rateHits = new Map<string, { count: number; resetAt: number }>();

function sweepExpired(now: number): void {
  for (const [key, entry] of rateHits) {
    if (now > entry.resetAt) rateHits.delete(key);
  }
}

export const rateLimit: MiddlewareHandler = async (c, next) => {
  // Preflight requests never reach the RPC — don't count them.
  if (c.req.method === 'OPTIONS') {
    await next();
    return;
  }
  const ip =
    c.req.header('x-forwarded-for')?.split(',')[0]?.trim() ??
    c.req.header('x-real-ip') ??
    'unknown';
  const now = Date.now();
  const entry = rateHits.get(ip);

  // Live window for this key → count it.
  if (entry && now <= entry.resetAt) {
    entry.count += 1;
    if (entry.count > RATE_MAX) {
      throw new RateLimitError(`Rate limit exceeded (${RATE_MAX}/min)`);
    }
    await next();
    return;
  }

  // New window. Enforce a hard cap so distinct keys can't grow the map without
  // bound: sweep expired entries first, and if it's still full, serve without
  // recording (best-effort degrade) rather than leak memory.
  if (!entry && rateHits.size >= RATE_MAX_KEYS) {
    sweepExpired(now);
    if (rateHits.size >= RATE_MAX_KEYS) {
      await next();
      return;
    }
  }
  rateHits.set(ip, { count: 1, resetAt: now + RATE_WINDOW_MS });
  await next();
};

// ---------------------------------------------------------------------------
// Global error handler (Hono onError)
// Never exposes stack traces to clients (CLAUDE.md §7).
// ---------------------------------------------------------------------------

export function errorHandler(err: Error, c: Context) {
  if (err instanceof AppError) {
    logger.warn(
      { code: err.code, statusCode: err.statusCode, message: err.message },
      'Application error',
    );
    return c.json(
      {
        ok: false,
        code: err.code,
        message: err.message,
        ...(err.details !== undefined ? { details: err.details } : {}),
      },
      err.statusCode,
    );
  }

  if (err instanceof HTTPException) {
    logger.warn({ statusCode: err.status, message: err.message }, 'HTTP exception');
    return c.json(
      {
        ok: false,
        code: 'HTTP_ERROR',
        message: err.message,
      },
      err.status,
    );
  }

  // Unknown error — log internally but don't expose details
  logger.error({ err }, 'Unhandled error');
  return c.json(
    {
      ok: false,
      code: 'INTERNAL_ERROR',
      message: 'An unexpected error occurred',
    },
    500,
  );
}
