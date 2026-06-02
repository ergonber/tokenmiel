/**
 * Pure address resolution over the static {@link DEPLOYMENTS} registry.
 *
 * This is the ONLY sanctioned way to obtain a contract address — hardcoding
 * addresses elsewhere is forbidden. Fails loudly with typed errors so the
 * backend bootstrap can abort (fail-fast) on an unknown chain or a not-yet
 * deployed contract.
 */
import type { Address } from 'viem';
import { type ChainDeployment, type ContractName, DEPLOYMENTS } from './deployments';

/** Thrown when the chain is not in the registry, or the contract is unknown on it. */
export class UnknownDeployment extends Error {
  readonly code = 'UNKNOWN_DEPLOYMENT' as const;
  constructor(
    readonly chainId: number,
    readonly contract?: ContractName,
  ) {
    super(
      contract
        ? `No deployment for contract "${contract}" on chain ${chainId}.`
        : `Unsupported chain ${chainId} (supported: Plume testnet 98867 / mainnet 98866).`,
    );
    this.name = 'UnknownDeployment';
  }
}

/** Thrown when the contract exists in the registry but its address is [PENDIENTE DEPLOY]. */
export class AddressPending extends Error {
  readonly code = 'ADDRESS_PENDING' as const;
  constructor(
    readonly chainId: number,
    readonly contract: ContractName,
  ) {
    super(`Address for "${contract}" on chain ${chainId} is [PENDIENTE DEPLOY].`);
    this.name = 'AddressPending';
  }
}

/**
 * Resolves the deployed address of `contract` on `chainId`.
 * @throws {UnknownDeployment} unsupported chain or unknown contract
 * @throws {AddressPending} contract not yet deployed on that chain
 */
export function resolveAddress(chainId: number, contract: ContractName): Address {
  const chain = (DEPLOYMENTS as Record<number, ChainDeployment | undefined>)[chainId];
  if (!chain) {
    throw new UnknownDeployment(chainId);
  }
  const deployment = chain.contracts[contract];
  if (!deployment) {
    throw new UnknownDeployment(chainId, contract);
  }
  if (deployment.address === null) {
    throw new AddressPending(chainId, contract);
  }
  return deployment.address;
}
