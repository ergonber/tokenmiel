/**
 * Structured logger — pino.
 *
 * Rules (CLAUDE.md §5, ADR-028):
 *   - Structured JSON output (no console.log anywhere in the codebase).
 *   - No PII: never log name, address, document identity, or applicantHash directly.
 *   - Base fields: service, version, env.
 *   - Child loggers per module: logger.child({ module: 'identity' }).
 *   - traceId / spanId injected by OpenTelemetry mixin (wired in M1).
 */

import pino from 'pino';

const isDev = process.env.NODE_ENV === 'development' || process.env.NODE_ENV === undefined;

// RPC URLs can embed provider API keys (dRPC/thirdweb). viem transport errors put
// the URL in message, stack, details, shortMessage, metaMessages AND the cause
// chain — pino's `redact.paths` can't reach those, so recursively scrub every
// string field of the serialized error before it is written.
const RPC_URL_RE = /https?:\/\/[^\s"'),<>\]}]+/g;
function scrubUrls(value: unknown): unknown {
  if (typeof value === 'string') return value.replace(RPC_URL_RE, '[REDACTED_URL]');
  if (Array.isArray(value)) return value.map(scrubUrls);
  if (value !== null && typeof value === 'object') {
    return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, scrubUrls(v)]));
  }
  return value;
}
function sanitizeErr(error: unknown): Record<string, unknown> {
  return scrubUrls(pino.stdSerializers.err(error as Error)) as Record<string, unknown>;
}

export const logger = pino({
  level: process.env.LOG_LEVEL ?? 'info',
  // Pretty-print in dev (requires pino-pretty installed), structured JSON in prod
  ...(isDev
    ? {
        transport: {
          target: 'pino-pretty',
          options: {
            colorize: true,
            translateTime: 'SYS:standard',
          },
        },
      }
    : {}),
  base: {
    service: 'tokenization-api',
    version: '0.1.0',
    env: process.env.NODE_ENV ?? 'development',
  },
  // Strip RPC URLs from viem error messages/metaMessages before serialization.
  serializers: { err: sanitizeErr },
  // Redact PII fields at the log serialization level as an extra safety net.
  // Modules MUST sanitize before logging, but this is a belt-and-suspenders guard.
  redact: {
    // PII fields + RPC URLs (viem transport errors carry `url`, which may embed
    // provider API keys once keyed fallback RPCs are wired — ADR-023/028).
    paths: ['*.name', '*.fullName', '*.email', '*.cpf', '*.dni', '*.passport', 'err.url', '*.url'],
    censor: '[REDACTED]',
  },
});
