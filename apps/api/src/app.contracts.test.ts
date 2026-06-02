import { describe, expect, it } from 'vitest';

// Minimal env so importing the app's env singleton loads without fail-fast.
// M1 only needs chain config; DB/Redis/KMS are optional at this stage.
process.env.CHAIN_ID ??= '98867';
process.env.PLUME_RPC_URL ??= 'https://testnet-rpc.plume.org';

describe('GET /contracts/:name/status', () => {
  it('returns 404 for an unknown contract name (no network)', async () => {
    const { app } = await import('./app');
    const res = await app.fetch(new Request('http://local/contracts/Nope/status'));
    expect(res.status).toBe(404);
    const body = (await res.json()) as { code: string };
    expect(body.code).toBe('UNKNOWN_CONTRACT');
  });
});

// Live read against Plume testnet 98867. Opt-in: `LIVE_PLUME=1 ... test`. CI skips it.
describe.skipIf(!process.env.LIVE_PLUME)('GET /contracts/:name/status (LIVE 98867)', () => {
  it('returns the live paused status + address for AssetVault', async () => {
    const { app } = await import('./app');
    const res = await app.fetch(new Request('http://local/contracts/AssetVault/status'));
    expect(res.status).toBe(200);
    const body = (await res.json()) as {
      name: string;
      address: string;
      paused: boolean;
      chainId: number;
    };
    expect(body.name).toBe('AssetVault');
    expect(body.chainId).toBe(98867);
    expect(typeof body.paused).toBe('boolean');
    expect(body.address.toLowerCase()).toBe('0x1e39944bd26485f5946abae706aa99d729886b47');
  }, 30_000);
});
