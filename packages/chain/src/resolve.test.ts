import { describe, expect, it } from 'vitest';
import { PLUME_MAINNET_CHAIN_ID, PLUME_TESTNET_CHAIN_ID } from './deployments';
import { AddressPending, UnknownDeployment, resolveAddress } from './resolve';

describe('resolveAddress', () => {
  it('returns the deployed testnet AssetVault address', () => {
    expect(resolveAddress(PLUME_TESTNET_CHAIN_ID, 'AssetVault')).toBe(
      '0x1E39944BD26485F5946abae706Aa99D729886b47',
    );
  });

  it('returns the testnet USDC (MockUSDC) address', () => {
    expect(resolveAddress(PLUME_TESTNET_CHAIN_ID, 'USDC')).toBe(
      '0xf309e1eB2E3f4Cb169d6C9986A98C3e408C72Fb5',
    );
  });

  it('throws AddressPending for mainnet (not deployed yet)', () => {
    expect(() => resolveAddress(PLUME_MAINNET_CHAIN_ID, 'RedemptionManager')).toThrow(
      AddressPending,
    );
  });

  it('throws UnknownDeployment for an unsupported chain (e.g. Anvil 31337)', () => {
    expect(() => resolveAddress(31_337, 'AssetVault')).toThrow(UnknownDeployment);
  });
});
