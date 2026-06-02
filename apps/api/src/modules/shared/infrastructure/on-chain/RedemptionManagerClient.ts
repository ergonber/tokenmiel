/**
 * Read-only typed client for RedemptionManager (CIS §4.3).
 *
 * Writes (confirmarExportacion/completarRedencion/cancelarRedencion) are ORACLE
 * COLD calldata builders added with OP-3; iniciarRedencion is buyer self-custody
 * (never relayed). Here we expose only the read surface.
 */
import { redemptionManagerAbi } from '@tokenization/abis';
import { getPublicClient, resolveAddress } from '@tokenization/chain';
import { type Address, type PublicClient, getContract } from 'viem';

export type RedemptionManagerClient = ReturnType<typeof createRedemptionManagerClient>;

export function createRedemptionManagerClient(chainId: number, client?: PublicClient) {
  const address = resolveAddress(chainId, 'RedemptionManager');
  const contract = getContract({
    address,
    abi: redemptionManagerAbi,
    client: client ?? getPublicClient(chainId),
  });

  return {
    address,
    paused: () => contract.read.paused(),
    assetVault: () => contract.read.assetVault(),
    identityRegistry: () => contract.read.identityRegistry(),
    /** Next redemption id; the backend iterates [1, getNextRedencionId()) to enumerate. */
    getNextRedencionId: () => contract.read.getNextRedencionId(),
    getRedencion: (redencionId: bigint) => contract.read.getRedencion([redencionId]),
    /** balanceOf − tokensLockedFor for (buyer, loteId). */
    availableBalance: (buyer: Address, loteId: bigint) =>
      contract.read.availableBalance([buyer, loteId]),
    /**
     * Locked tokens for a (buyer, loteId).
     * GOTCHA: the function signature takes (buyer, loteId) but the internal mapping
     * is indexed [loteId][buyer] (ADR-018) — always pass the args in this order.
     */
    tokensLockedFor: (buyer: Address, loteId: bigint) =>
      contract.read.tokensLockedFor([buyer, loteId]),
    hasRole: (role: `0x${string}`, account: Address) => contract.read.hasRole([role, account]),
  };
}
