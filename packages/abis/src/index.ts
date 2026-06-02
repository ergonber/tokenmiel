/**
 * @tokenization/abis — typed ABI bindings for the deployed MVP contracts.
 *
 * The bindings are generated from the frozen `*.abi.json` artifacts (pinned by
 * `src/integrity.test.ts`, CIS §2) via `scripts/generate.ts`. Consumers get full
 * viem/abitype type inference (function/event names as literals) from the
 * `as const` ABIs — no hand-written types.
 *
 * Regenerate after a contract re-deploy: `pnpm --filter @tokenization/abis generate`.
 */
export { assetVaultAbi } from './generated/assetVault.gen';
export { identityRegistryAbi } from './generated/identityRegistry.gen';
export { redemptionManagerAbi } from './generated/redemptionManager.gen';
