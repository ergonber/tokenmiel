/**
 * Read-only typed client for IdentityRegistry (CIS §4.2).
 *
 * The compliance gate is ON-CHAIN: use canMint/canRedeem for gating decisions,
 * NEVER getTier raw (getTier does NOT subtract expiry). Writes (setKYC/revokeKYC)
 * are added with OP-3 via the KMS relayer.
 */
import { identityRegistryAbi } from '@tokenization/abis';
import { getPublicClient, resolveAddress } from '@tokenization/chain';
import { type Address, type PublicClient, getContract } from 'viem';

export type IdentityRegistryClient = ReturnType<typeof createIdentityRegistryClient>;

export function createIdentityRegistryClient(chainId: number, client?: PublicClient) {
  const address = resolveAddress(chainId, 'IdentityRegistry');
  const contract = getContract({
    address,
    abi: identityRegistryAbi,
    client: client ?? getPublicClient(chainId),
  });

  return {
    address,
    paused: () => contract.read.paused(),
    /** The real mint gate (KYC + tier + not sanctioned/frozen/expired). Read LIVE. */
    canMint: (account: Address) => contract.read.canMint([account]),
    /** The real redeem gate. Read LIVE. */
    canRedeem: (account: Address) => contract.read.canRedeem([account]),
    /** GOTCHA: raw tier, does NOT account for expiry — do NOT gate on this; use canMint/canRedeem. */
    getTier: (account: Address) => contract.read.getTier([account]),
    isSanctioned: (account: Address) => contract.read.isSanctioned([account]),
    isFrozen: (account: Address) => contract.read.isFrozen([account]),
    isExpired: (account: Address) => contract.read.isExpired([account]),
    /** ISO 3166-1 jurisdiction as bytes2 (metadata; validated off-chain per ADR-011). */
    getJurisdiction: (account: Address) => contract.read.getJurisdiction([account]),
    getKYCData: (account: Address) => contract.read.getKYCData([account]),
    hasRole: (role: `0x${string}`, account: Address) => contract.read.hasRole([role, account]),
  };
}
