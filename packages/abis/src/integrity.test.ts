import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import { assetVaultAbi, identityRegistryAbi, redemptionManagerAbi } from './index';

const pkgRoot = join(dirname(fileURLToPath(import.meta.url)), '..');

// sha256 of each frozen ABI JSON (CIS §2 pin). If an artifact changes, this fails
// loudly so the generated bindings can never silently drift from the deployed contract.
const ABI_PINS: Readonly<Record<string, string>> = {
  'AssetVault.abi.json': '3513d67e575b8061c839aff52a0abb0665d5988eff20c7158b228a5477fb2394',
  'IdentityRegistry.abi.json': 'f606588dff8fc9d24158d2bc99ac60dbc02716d7eac860f5dcffac818bf21000',
  'RedemptionManager.abi.json': 'd276e9bee7834c6dd65a1a5ddd973e5d3e0431f2c97c8f10918237128b826db5',
};

describe('ABI integrity (CIS §2 pins)', () => {
  for (const [file, pin] of Object.entries(ABI_PINS)) {
    it(`${file} matches its pinned sha256`, () => {
      const sha = createHash('sha256')
        .update(readFileSync(join(pkgRoot, file)))
        .digest('hex');
      expect(sha).toBe(pin);
    });
  }

  it('exports the three typed ABIs as non-empty arrays', () => {
    expect(assetVaultAbi.length).toBeGreaterThan(0);
    expect(identityRegistryAbi.length).toBeGreaterThan(0);
    expect(redemptionManagerAbi.length).toBeGreaterThan(0);
  });
});

// Maps each frozen ABI JSON to its generated binding file.
const GEN_BINDINGS: Readonly<Record<string, string>> = {
  'AssetVault.abi.json': 'generated/assetVault.gen.ts',
  'IdentityRegistry.abi.json': 'generated/identityRegistry.gen.ts',
  'RedemptionManager.abi.json': 'generated/redemptionManager.gen.ts',
};

describe('ABI bindings have not drifted from the pinned JSON', () => {
  for (const [json, gen] of Object.entries(GEN_BINDINGS)) {
    it(`${gen} embeds the exact ${json}`, () => {
      const jsonContent = readFileSync(join(pkgRoot, json), 'utf8').trim();
      const genContent = readFileSync(join(pkgRoot, 'src', gen), 'utf8');
      // The generator inlines the trimmed JSON verbatim; a hand-edit to the .gen.ts
      // ABI would no longer contain the (sha-pinned) JSON, so this fails loudly.
      expect(genContent).toContain(jsonContent);
    });
  }
});
