import { PLUME_TESTNET_CHAIN_ID } from '@tokenization/chain';
import { describe, expect, it } from 'vitest';
import { createAssetVaultClient } from './AssetVaultClient';
import { createIdentityRegistryClient } from './IdentityRegistryClient';
import { createRedemptionManagerClient } from './RedemptionManagerClient';

// Construction-only unit tests (no network). Live reads against testnet 98867 are
// covered by the ChainBootstrap integration test (M1 step 5).
describe('on-chain read clients', () => {
  it('AssetVaultClient resolves the testnet address and exposes reads', () => {
    const c = createAssetVaultClient(PLUME_TESTNET_CHAIN_ID);
    expect(c.address).toBe('0x1E39944BD26485F5946abae706Aa99D729886b47');
    expect(typeof c.paused).toBe('function');
    expect(typeof c.balanceOf).toBe('function');
    expect(typeof c.kgDisponibles).toBe('function');
  });

  it('IdentityRegistryClient resolves the testnet address and exposes the gates', () => {
    const c = createIdentityRegistryClient(PLUME_TESTNET_CHAIN_ID);
    expect(c.address).toBe('0x8FBa3ae61B53516a32Ce443E2abb83Edcddfd6Cc');
    expect(typeof c.canMint).toBe('function');
    expect(typeof c.canRedeem).toBe('function');
  });

  it('RedemptionManagerClient resolves the testnet address and exposes reads', () => {
    const c = createRedemptionManagerClient(PLUME_TESTNET_CHAIN_ID);
    expect(c.address).toBe('0xd6EA5406D7579C1bc5ea935d5ED46675Edf8d062');
    expect(typeof c.getNextRedencionId).toBe('function');
    expect(typeof c.tokensLockedFor).toBe('function');
  });
});
