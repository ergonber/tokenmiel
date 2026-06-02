/**
 * Fail-fast environment variable loader.
 *
 * Validates env at import time using the schema in env-schema.ts (side-effect
 * free, so tests import the schema directly without triggering this exit).
 * The process exits immediately if any required var is missing or invalid.
 */
import { type Env, envSchema } from './env-schema.js';

export { type Env, envSchema } from './env-schema.js';

function loadEnv(): Env {
  const result = envSchema.safeParse(process.env);

  if (!result.success) {
    const formatted = result.error.errors
      .map((e) => `  [${e.path.join('.')}] ${e.message}`)
      .join('\n');
    // Use process.stderr directly — the logger is not yet initialized.
    process.stderr.write(`\n[env] Configuration error — aborting startup:\n${formatted}\n\n`);
    process.exit(1);
  }

  return result.data;
}

// Singleton — parsed once at import time.
export const env = loadEnv();
