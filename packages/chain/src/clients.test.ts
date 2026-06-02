import { describe, expect, it } from 'vitest';
import { getPublicClient } from './clients';
import { PLUME_TESTNET_CHAIN_ID } from './deployments';
import { UnknownDeployment } from './resolve';

describe('getPublicClient', () => {
  it('builds a public client bound to Plume testnet (no network call)', () => {
    const client = getPublicClient(PLUME_TESTNET_CHAIN_ID);
    expect(client.chain?.id).toBe(PLUME_TESTNET_CHAIN_ID);
  });

  it('throws UnknownDeployment for an unsupported chain', () => {
    expect(() => getPublicClient(1)).toThrow(UnknownDeployment);
  });
});
