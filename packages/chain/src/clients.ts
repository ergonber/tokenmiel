/**
 * viem chain definitions + cached public clients for Plume.
 *
 * Per ADR-023 the transport uses `fallback()` over ranked RPC providers
 * (official → dRPC → thirdweb) so a single RPC outage does not stall live reads.
 * RPC URLs are injected by the caller (apps/api env loader); the chain defaults
 * point at the official endpoints.
 */
import { http, type Chain, type PublicClient, createPublicClient, fallback } from 'viem';
import { PLUME_MAINNET_CHAIN_ID, PLUME_TESTNET_CHAIN_ID } from './deployments';
import { UnknownDeployment } from './resolve';

const PLUME_NATIVE = { name: 'Plume', symbol: 'PLUME', decimals: 18 } as const;

export const plumeTestnet: Chain = {
  id: PLUME_TESTNET_CHAIN_ID,
  name: 'Plume Testnet',
  nativeCurrency: PLUME_NATIVE,
  rpcUrls: { default: { http: ['https://testnet-rpc.plume.org'] } },
  blockExplorers: {
    default: { name: 'Plume Testnet Explorer', url: 'https://testnet-explorer.plume.org' },
  },
  testnet: true,
};

export const plumeMainnet: Chain = {
  id: PLUME_MAINNET_CHAIN_ID,
  name: 'Plume',
  nativeCurrency: PLUME_NATIVE,
  rpcUrls: { default: { http: ['https://rpc.plume.org'] } },
  blockExplorers: { default: { name: 'Plume Explorer', url: 'https://explorer.plume.org' } },
};

function chainFor(chainId: number): Chain | undefined {
  if (chainId === PLUME_TESTNET_CHAIN_ID) return plumeTestnet;
  if (chainId === PLUME_MAINNET_CHAIN_ID) return plumeMainnet;
  return undefined;
}

// Cache keyed by chainId + the resolved URL set, so distinct URL rankings yield
// distinct clients (a chainId-only cache would let the first caller's transport
// poison every later one — e.g. bootstrap with defaults vs the env-ranked URLs).
const clientCache = new Map<string, PublicClient>();

/**
 * Returns a cached read-only public client for `chainId`.
 *
 * @param rpcUrls optional ranked RPC URLs (primary first); empty strings are
 *   dropped. With >1 usable URL a viem `fallback()` transport is built with
 *   latency ranking + retries (ADR-023). Defaults to the chain's official endpoint.
 * @throws {UnknownDeployment} when the chain is not Plume testnet/mainnet
 */
export function getPublicClient(chainId: number, rpcUrls?: readonly string[]): PublicClient {
  const chain = chainFor(chainId);
  if (!chain) throw new UnknownDeployment(chainId);

  const provided = (rpcUrls ?? []).filter(
    (u): u is string => typeof u === 'string' && u.length > 0,
  );
  const urls = provided.length > 0 ? provided : [...chain.rpcUrls.default.http];

  const cacheKey = `${chainId}:${urls.join(',')}`;
  const cached = clientCache.get(cacheKey);
  if (cached) return cached;

  const [primary, ...rest] = urls;
  if (primary === undefined) {
    // `urls` is non-empty by construction; this proves it to the type system and
    // guards a future refactor from silently falling back to the chain default.
    throw new UnknownDeployment(chainId);
  }
  const transport =
    rest.length > 0
      ? fallback(
          [primary, ...rest].map((url) => http(url, { retryCount: 3 })),
          { rank: true, retryCount: 3 },
        )
      : http(primary, { retryCount: 3 });

  const client = createPublicClient({ chain, transport });
  clientCache.set(cacheKey, client);
  return client;
}
