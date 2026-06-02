/**
 * Environment schema — pure, side-effect free.
 *
 * Lives apart from env.ts so tests can import the REAL schema without triggering
 * the fail-fast `loadEnv()` singleton (which calls process.exit on invalid env).
 *
 * Per ADR-022: BACKEND_SIGNER_KMS_KEY_ID must be a GCP Cloud KMS resource name.
 * Per ADR-023: RPC failover URLs are optional (empty → undefined).
 * Per CIS §1: CHAIN_ID must be 98867 (testnet) or 98866 (mainnet).
 */
import { z } from 'zod';

const SUPPORTED_CHAIN_IDS = [98867, 98866] as const;

const chainIdSchema = z
  .number()
  .int()
  .refine(
    (n): n is (typeof SUPPORTED_CHAIN_IDS)[number] =>
      (SUPPORTED_CHAIN_IDS as readonly number[]).includes(n),
    {
      message: `CHAIN_ID must be one of ${SUPPORTED_CHAIN_IDS.join(', ')} (Plume testnet / mainnet). Got an unsupported chain ID.`,
    },
  );

// GCP Cloud KMS cryptoKeyVersion resource name (ADR-022).
const gcpKmsKeyVersionSchema = z
  .string()
  .regex(
    /^projects\/[^/]+\/locations\/[^/]+\/keyRings\/[^/]+\/cryptoKeys\/[^/]+\/cryptoKeyVersions\/[^/]+$/,
    'Must be a GCP Cloud KMS cryptoKeyVersion resource name: projects/.../cryptoKeyVersions/...',
  );

export const envSchema = z.object({
  // Runtime
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  LOG_LEVEL: z.enum(['trace', 'debug', 'info', 'warn', 'error', 'fatal']).default('info'),
  PORT: z.coerce.number().int().positive().default(3001),

  // Active chain (testnet = 98867, mainnet = 98866)
  CHAIN_ID: z.coerce.number().pipe(chainIdSchema),

  // Plume RPC (ADR-023): primary required; fallbacks optional ('' → undefined).
  PLUME_RPC_URL: z.string().url('PLUME_RPC_URL must be a valid URL'),
  PLUME_RPC_URL_FALLBACK_DRPC: z.preprocess(
    (v) => (v === '' ? undefined : v),
    z.string().url().optional(),
  ),
  PLUME_RPC_URL_FALLBACK_THIRDWEB: z.preprocess(
    (v) => (v === '' ? undefined : v),
    z.string().url().optional(),
  ),

  // Optional in M1 (read-only interface layer). Tightened in OP-2/OP-3.
  DATABASE_URL: z.string().min(1).optional(),
  REDIS_URL: z.string().min(1).optional(),
  BACKEND_SIGNER_KMS_KEY_ID: gcpKmsKeyVersionSchema.optional(),
  GCP_KMS_LOCATION: z.string().default('us-east1'),
});

export type Env = z.infer<typeof envSchema>;
