/**
 * Read-only typed client for AssetVault (CIS §4.1).
 *
 * Wraps the frozen ABI + the resolved address + a viem public client. Exposes
 * only the view surface; write calldata builders are added with OP-3 (write path).
 */
import { assetVaultAbi } from '@tokenization/abis';
import { getPublicClient, resolveAddress } from '@tokenization/chain';
import { type Address, type PublicClient, getContract } from 'viem';

export type AssetVaultClient = ReturnType<typeof createAssetVaultClient>;

export function createAssetVaultClient(chainId: number, client?: PublicClient) {
  const address = resolveAddress(chainId, 'AssetVault');
  const contract = getContract({
    address,
    abi: assetVaultAbi,
    client: client ?? getPublicClient(chainId),
  });

  return {
    address,
    /**
     * Emergency pause flag. Pre-tx gates (comprar/redeem) MUST read this LIVE;
     * the status-display endpoint may serve it through a short TTL cache (app.ts).
     */
    paused: () => contract.read.paused(),
    /** USDC payment-token address wired at deploy. */
    usdc: () => contract.read.usdc(),
    /** IdentityRegistry address wired at deploy. */
    identityRegistry: () => contract.read.identityRegistry(),
    /** RedemptionManager address (zero until setRedemptionManager wiring). */
    redemptionManager: () => contract.read.redemptionManager(),
    /** ERC-1155 balance of `account` for `loteId`. Read LIVE for exact pre-tx balance. */
    balanceOf: (account: Address, loteId: bigint) => contract.read.balanceOf([account, loteId]),
    /** Circulating supply of a lote. */
    totalSupply: (loteId: bigint) => contract.read.totalSupply([loteId]),
    /** Whether a lote exists. */
    exists: (loteId: bigint) => contract.read.exists([loteId]),
    /** Full LoteMiel struct — also the source of hashFotosApiario/tipoCertificadoOrigen (no event). */
    lotes: (loteId: bigint) => contract.read.lotes([loteId]),
    /** Available capacity in grams (FIX H-02). Read LIVE for capacity checks pre-comprar. */
    kgDisponibles: (loteId: bigint) => contract.read.kgDisponibles([loteId]),
    /** Technical reserve still held for a lote. */
    reservaTecnicaActual: (loteId: bigint) => contract.read.reservaTecnicaActual([loteId]),
    /** AccessControl role check. */
    hasRole: (role: `0x${string}`, account: Address) => contract.read.hasRole([role, account]),
  };
}
