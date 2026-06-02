/**
 * Composition root for the chain public client.
 *
 * `packages/chain` must not import the api env, so the ranked RPC URLs (ADR-023:
 * primary → dRPC → thirdweb) are resolved here from the validated env and injected
 * into getPublicClient. This is the ONLY place that wires the env RPC config; the
 * route handler and the startup bootstrap both go through it so the (url-keyed)
 * client cache holds the env-configured fallback transport, not the bare default.
 */
import { getPublicClient } from '@tokenization/chain';
import type { PublicClient } from 'viem';
import { env } from '../../../../config/env.js';

function rankedRpcUrls(): string[] {
  return [
    env.PLUME_RPC_URL,
    env.PLUME_RPC_URL_FALLBACK_DRPC,
    env.PLUME_RPC_URL_FALLBACK_THIRDWEB,
  ].filter((url): url is string => typeof url === 'string' && url.length > 0);
}

/** Public client for `chainId` built with the env-configured ranked RPC URLs (ADR-023). */
export function apiPublicClient(chainId: number): PublicClient {
  return getPublicClient(chainId, rankedRpcUrls());
}
