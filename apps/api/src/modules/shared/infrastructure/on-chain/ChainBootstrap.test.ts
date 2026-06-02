import {
  AddressPending,
  PLUME_MAINNET_CHAIN_ID,
  PLUME_TESTNET_CHAIN_ID,
} from '@tokenization/chain';
import type { PublicClient } from 'viem';
import { describe, expect, it } from 'vitest';
import { createAssetVaultClient } from './AssetVaultClient';
import { BytecodeMismatch, NoBytecode, bootstrapChain } from './ChainBootstrap';

// Fake client: returns a fixed bytecode whose sha256 will never match a real pin.
const fakeClient = (code: string) => ({ getCode: async () => code }) as unknown as PublicClient;

describe('bootstrapChain (deterministic, mocked)', () => {
  it('throws BytecodeMismatch when the runtime bytecode differs from the pin', async () => {
    await expect(bootstrapChain(PLUME_TESTNET_CHAIN_ID, fakeClient('0xdeadbeef'))).rejects.toThrow(
      BytecodeMismatch,
    );
  });

  it('throws NoBytecode when there is no code at the address', async () => {
    await expect(bootstrapChain(PLUME_TESTNET_CHAIN_ID, fakeClient('0x'))).rejects.toThrow(
      NoBytecode,
    );
  });

  it('throws AddressPending on mainnet (not deployed yet)', async () => {
    await expect(bootstrapChain(PLUME_MAINNET_CHAIN_ID, fakeClient('0x00'))).rejects.toThrow(
      AddressPending,
    );
  });
});

// Live integration test against the real Plume testnet. Opt-in: run with
// `LIVE_PLUME=1 pnpm --filter @tokenization/api test`. CI skips it (no flag) so
// the pipeline never depends on testnet uptime.
describe.skipIf(!process.env.LIVE_PLUME)('bootstrapChain (LIVE Plume testnet 98867)', () => {
  it('matches the pinned bytecode for the 3 suite contracts', async () => {
    const result = await bootstrapChain(PLUME_TESTNET_CHAIN_ID);
    expect(result.checks).toHaveLength(3);
    expect(result.deployVersion).toBe(1);
  }, 30_000);

  it('reads paused() and usdc() live from AssetVault', async () => {
    const av = createAssetVaultClient(PLUME_TESTNET_CHAIN_ID);
    expect(typeof (await av.paused())).toBe('boolean');
    expect((await av.usdc()).toLowerCase()).toBe('0xf309e1eb2e3f4cb169d6c9986a98c3e408c72fb5');
  }, 30_000);
});
