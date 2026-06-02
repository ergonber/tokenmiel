/**
 * Tests for the REAL env schema (env-schema.ts).
 *
 * We import the same schema the loader uses (not a hand-copied duplicate), so any
 * future change to the real schema is exercised here. Importing env-schema.ts has
 * no side effects — it does NOT trigger env.ts's loadEnv() / process.exit().
 */
import { describe, expect, it } from 'vitest';
import { envSchema } from './env-schema';

const validEnv = {
  CHAIN_ID: '98867',
  PLUME_RPC_URL: 'https://testnet-rpc.plume.org',
  DATABASE_URL: 'postgresql://user:pass@localhost:5432/tokenization',
  REDIS_URL: 'redis://localhost:6379',
  BACKEND_SIGNER_KMS_KEY_ID:
    'projects/my-project/locations/us-east1/keyRings/my-ring/cryptoKeys/my-key/cryptoKeyVersions/1',
} as const;

describe('env schema — CHAIN_ID', () => {
  it('accepts Plume testnet chain ID 98867', () => {
    const result = envSchema.safeParse(validEnv);
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.CHAIN_ID).toBe(98867);
    }
  });

  it('accepts Plume mainnet chain ID 98866', () => {
    expect(envSchema.safeParse({ ...validEnv, CHAIN_ID: '98866' }).success).toBe(true);
  });

  it('rejects unsupported chain ID 98865', () => {
    const result = envSchema.safeParse({ ...validEnv, CHAIN_ID: '98865' });
    expect(result.success).toBe(false);
    if (!result.success) {
      expect(result.error.errors.map((e) => e.path.join('.'))).toContain('CHAIN_ID');
    }
  });

  it('rejects Polygon chain ID 137 (not a Plume chain)', () => {
    expect(envSchema.safeParse({ ...validEnv, CHAIN_ID: '137' }).success).toBe(false);
  });

  it('rejects missing CHAIN_ID', () => {
    expect(envSchema.safeParse({ ...validEnv, CHAIN_ID: undefined }).success).toBe(false);
  });
});

describe('env schema — BACKEND_SIGNER_KMS_KEY_ID (ADR-022)', () => {
  it('accepts a valid GCP Cloud KMS cryptoKeyVersion resource name', () => {
    expect(envSchema.safeParse(validEnv).success).toBe(true);
  });

  it('accepts absence (optional in M1, read-only)', () => {
    expect(envSchema.safeParse({ ...validEnv, BACKEND_SIGNER_KMS_KEY_ID: undefined }).success).toBe(
      true,
    );
  });

  it('rejects an AWS ARN format (wrong provider)', () => {
    expect(
      envSchema.safeParse({
        ...validEnv,
        BACKEND_SIGNER_KMS_KEY_ID: 'arn:aws:kms:us-east-1:123456789012:key/abc123',
      }).success,
    ).toBe(false);
  });

  it('rejects a bare key ID (not a GCP resource name)', () => {
    expect(
      envSchema.safeParse({ ...validEnv, BACKEND_SIGNER_KMS_KEY_ID: 'my-key-id' }).success,
    ).toBe(false);
  });

  it('rejects a GCP resource name without the cryptoKeyVersions segment', () => {
    expect(
      envSchema.safeParse({
        ...validEnv,
        BACKEND_SIGNER_KMS_KEY_ID:
          'projects/my-project/locations/us-east1/keyRings/my-ring/cryptoKeys/my-key',
      }).success,
    ).toBe(false);
  });
});

describe('env schema — PLUME_RPC_URL + fallbacks (ADR-023)', () => {
  it('rejects a non-URL primary RPC', () => {
    expect(envSchema.safeParse({ ...validEnv, PLUME_RPC_URL: 'not-a-url' }).success).toBe(false);
  });

  it('coerces an empty fallback URL to undefined (graceful degradation)', () => {
    const result = envSchema.safeParse({ ...validEnv, PLUME_RPC_URL_FALLBACK_DRPC: '' });
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.PLUME_RPC_URL_FALLBACK_DRPC).toBeUndefined();
    }
  });
});
