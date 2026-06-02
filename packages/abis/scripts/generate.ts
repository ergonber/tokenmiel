#!/usr/bin/env bun
/**
 * Genera bindings de ABI tipados (`as const satisfies Abi`) a partir de los
 * artefactos congelados `*.abi.json`. Los bindings dan inferencia de tipos
 * completa a viem/abitype (nombres de función/evento como literales).
 *
 * Correr: `pnpm --filter @tokenization/abis generate` (o `bun scripts/generate.ts`).
 * Los archivos generados llevan sufijo `.gen.ts` y biome los ignora (root biome.json).
 */
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const pkgRoot = join(dirname(fileURLToPath(import.meta.url)), '..');
const outDir = join(pkgRoot, 'src', 'generated');
mkdirSync(outDir, { recursive: true });

const CONTRACTS = [
  { json: 'AssetVault.abi.json', constName: 'assetVaultAbi', file: 'assetVault.gen.ts' },
  { json: 'IdentityRegistry.abi.json', constName: 'identityRegistryAbi', file: 'identityRegistry.gen.ts' },
  { json: 'RedemptionManager.abi.json', constName: 'redemptionManagerAbi', file: 'redemptionManager.gen.ts' },
] as const;

for (const c of CONTRACTS) {
  const abi = readFileSync(join(pkgRoot, c.json), 'utf8').trim();
  const out = `// AUTO-GENERATED from ${c.json}. Do NOT edit by hand — run \`pnpm --filter @tokenization/abis generate\`.\nimport type { Abi } from 'abitype';\n\nexport const ${c.constName} = ${abi} as const satisfies Abi;\n`;
  writeFileSync(join(outDir, c.file), out);
  // biome-ignore lint/suspicious/noConsole: generator CLI output is intentional
  console.log(`  generated src/generated/${c.file}`);
}
// biome-ignore lint/suspicious/noConsole: generator CLI output is intentional
console.log(`Done — ${CONTRACTS.length} ABI bindings.`);
