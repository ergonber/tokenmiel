/**
 * Fail-fast chain bootstrap (M1 step 5).
 *
 * For each suite contract on the active chain, resolve the address, fetch the
 * runtime bytecode and assert its sha256 matches the pinned value (CIS §2). The
 * backend aborts on AddressPending / NoBytecode / BytecodeMismatch, so it can
 * never serve against an unknown chain or code that differs from what was audited.
 */
import { createHash } from 'node:crypto';
import {
  AddressPending,
  type ChainDeployment,
  type ContractName,
  DEPLOYMENTS,
  UnknownDeployment,
  getPublicClient,
} from '@tokenization/chain';
import type { PublicClient } from 'viem';

const SUITE_CONTRACTS: readonly ContractName[] = [
  'AssetVault',
  'IdentityRegistry',
  'RedemptionManager',
];

export class BytecodeMismatch extends Error {
  readonly code = 'BYTECODE_MISMATCH' as const;
  constructor(
    readonly contract: ContractName,
    readonly address: string,
    readonly expected: string,
    readonly actual: string,
  ) {
    super(
      `Runtime bytecode for ${contract} at ${address} does not match the pinned sha256 ` +
        `(expected ${expected}, got ${actual}) — the address may point at unaudited code. Aborting.`,
    );
    this.name = 'BytecodeMismatch';
  }
}

export class NoBytecode extends Error {
  readonly code = 'NO_BYTECODE' as const;
  constructor(
    readonly contract: ContractName,
    readonly address: string,
  ) {
    super(`No contract code at ${address} for ${contract}. Aborting.`);
    this.name = 'NoBytecode';
  }
}

/** A suite contract has a deployed address but no pin — verification can't be skipped. */
export class MissingBytecodePin extends Error {
  readonly code = 'MISSING_BYTECODE_PIN' as const;
  constructor(readonly contract: ContractName) {
    super(
      `${contract} has a deployed address but no runtime bytecode pin — refusing to skip verification. Aborting.`,
    );
    this.name = 'MissingBytecodePin';
  }
}

export interface BootstrapCheck {
  readonly contract: ContractName;
  readonly address: string;
  readonly sha256: string;
}

export interface BootstrapResult {
  readonly chainId: number;
  readonly deployVersion: number | null;
  readonly checks: readonly BootstrapCheck[];
}

function sha256Hex(value: string): string {
  return createHash('sha256').update(value).digest('hex');
}

export async function bootstrapChain(
  chainId: number,
  client?: PublicClient,
): Promise<BootstrapResult> {
  const chain = (DEPLOYMENTS as Record<number, ChainDeployment | undefined>)[chainId];
  if (!chain) {
    throw new UnknownDeployment(chainId);
  }
  const publicClient = client ?? getPublicClient(chainId);
  const checks: BootstrapCheck[] = [];

  for (const contract of SUITE_CONTRACTS) {
    const deployment = chain.contracts[contract];
    if (deployment.address === null) {
      throw new AddressPending(chainId, contract);
    }
    if (deployment.runtimeBytecodeSha256 === null) {
      throw new MissingBytecodePin(contract);
    }
    const code = await publicClient.getCode({ address: deployment.address });
    if (!code || code === '0x') {
      throw new NoBytecode(contract, deployment.address);
    }
    const actual = sha256Hex(code);
    if (actual !== deployment.runtimeBytecodeSha256) {
      throw new BytecodeMismatch(
        contract,
        deployment.address,
        deployment.runtimeBytecodeSha256,
        actual,
      );
    }
    checks.push({ contract, address: deployment.address, sha256: actual });
  }

  return { chainId, deployVersion: chain.deployVersion, checks };
}
