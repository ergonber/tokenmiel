/**
 * @tokenization/chain — typed chain config + deployment registry for the MVP.
 *
 * Per ADR-001 Plume Network (98866 mainnet, 98867 testnet) is the primary chain.
 * Per ADR-003 the contracts are immutable (no proxy) → a static address registry
 * versioned by re-deploy (no proxy indirection to tolerate).
 * Per ADR-023 the viem transport will use fallback() with ranked RPC providers.
 * Per ADR-022 the backend signer uses GCP Cloud KMS (wired in a later M1 step).
 */
export * from './clients';
export * from './deployments';
export * from './resolve';
