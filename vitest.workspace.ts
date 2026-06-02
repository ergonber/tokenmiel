/**
 * Vitest workspace config.
 *
 * Covers apps/api and all packages/* that opt into Vitest.
 * Each project gets its own config so test globals, environment, and
 * includes can be scoped without polluting other packages.
 */

import { defineWorkspace } from 'vitest/config';

export default defineWorkspace([
  // ---------------------------------------------------------------------------
  // apps/api — Bun runtime, Node environment (Vitest runs on Node by default)
  // ---------------------------------------------------------------------------
  {
    test: {
      name: 'api',
      root: './apps/api',
      include: ['src/**/*.test.ts'],
      environment: 'node',
      globals: false,
    },
  },

  // ---------------------------------------------------------------------------
  // packages/shared
  // ---------------------------------------------------------------------------
  {
    test: {
      name: 'shared',
      root: './packages/shared',
      include: ['src/**/*.test.ts'],
      environment: 'node',
      globals: false,
    },
  },

  // ---------------------------------------------------------------------------
  // packages/chain
  // ---------------------------------------------------------------------------
  {
    test: {
      name: 'chain',
      root: './packages/chain',
      include: ['src/**/*.test.ts'],
      environment: 'node',
      globals: false,
    },
  },

  // ---------------------------------------------------------------------------
  // packages/abis  (ABI integrity + no-drift pins, CIS §2)
  // ---------------------------------------------------------------------------
  {
    test: {
      name: 'abis',
      root: './packages/abis',
      include: ['src/**/*.test.ts'],
      environment: 'node',
      globals: false,
    },
  },
  // packages/db has no unit tests yet (M1 adds the Drizzle schema + its tests);
  // it is intentionally omitted so a root `vitest run` doesn't fail on it. Its
  // turbo `test` script no-ops in CI until then.
]);
