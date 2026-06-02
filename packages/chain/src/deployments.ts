/**
 * Static deployment registry for the MVP contracts.
 *
 * Per ADR-003 the contracts are IMMUTABLE (no proxy), so a deployment address
 * pins one fixed version of the logic. The registry is therefore a static map
 * `chainId → contracts`, versioned by `deployVersion` (bumped only on re-deploy).
 *
 * Data source: CIS §1/§2 + packages/contracts/broadcast/.../98867/run-latest.json.
 * Mainnet (98866) is [PENDIENTE DEPLOY] → address/sha null until the deploy lands.
 */
import type { Address } from 'viem';

export const PLUME_TESTNET_CHAIN_ID = 98867 as const;
export const PLUME_MAINNET_CHAIN_ID = 98866 as const;

/** Supported chain IDs (source: CIS §1). */
export const SUPPORTED_CHAIN_IDS = [PLUME_TESTNET_CHAIN_ID, PLUME_MAINNET_CHAIN_ID] as const;
export type SupportedChainId = (typeof SUPPORTED_CHAIN_IDS)[number];

export type ContractName = 'AssetVault' | 'IdentityRegistry' | 'RedemptionManager' | 'USDC';

export interface ContractDeployment {
  /** Deployed address, or `null` when [PENDIENTE DEPLOY]. */
  readonly address: Address | null;
  /**
   * sha256 of the deployed runtime bytecode (CIS §2 pin), or `null` if not deployed.
   * Canonical form: `sha256(getCode())` — the lowercase `0x`-prefixed runtime
   * bytecode hex string as returned by eth_getCode, NO trailing whitespace. The
   * backend bootstrap recomputes this and aborts on mismatch (points at unaudited code).
   */
  readonly runtimeBytecodeSha256: string | null;
  /** Whether the source is verified on the block explorer. */
  readonly verified: boolean;
  /** Optional marker for non-suite contracts (e.g. the testnet payment-token mock). */
  readonly kind?: string;
}

export interface ChainDeployment {
  readonly chainId: SupportedChainId;
  readonly name: string;
  /** Bumped ONLY on a re-deploy (immutable contracts, ADR-003). `null` if not deployed. */
  readonly deployVersion: number | null;
  /** First block of the deploy — the indexer `startBlock`. `null` if not deployed. */
  readonly deployedAtBlock: number | null;
  readonly contracts: Readonly<Record<ContractName, ContractDeployment>>;
}

export const DEPLOYMENTS: Readonly<Record<SupportedChainId, ChainDeployment>> = {
  [PLUME_TESTNET_CHAIN_ID]: {
    chainId: PLUME_TESTNET_CHAIN_ID,
    name: 'Plume Testnet',
    deployVersion: 1,
    deployedAtBlock: 23_675_712,
    contracts: {
      AssetVault: {
        address: '0x1E39944BD26485F5946abae706Aa99D729886b47',
        runtimeBytecodeSha256: 'c5b6add720910144ae7c3cc4e69c184e08b719695cc22fea4f978d6a6401ca58',
        verified: false,
      },
      IdentityRegistry: {
        address: '0x8FBa3ae61B53516a32Ce443E2abb83Edcddfd6Cc',
        runtimeBytecodeSha256: '5e406ef468ebce45c221d550dbd52fac16ef422ef93b7180ecf041367e092780',
        verified: false,
      },
      RedemptionManager: {
        address: '0xd6EA5406D7579C1bc5ea935d5ED46675Edf8d062',
        runtimeBytecodeSha256: '13ae89956e466db0dc8a3e2c0275b322a4d5c76f1e109bed413877e6ab910e58',
        verified: false,
      },
      USDC: {
        address: '0xf309e1eB2E3f4Cb169d6C9986A98C3e408C72Fb5',
        runtimeBytecodeSha256: null,
        verified: false,
        kind: 'MockUSDC',
      },
    },
  },
  [PLUME_MAINNET_CHAIN_ID]: {
    chainId: PLUME_MAINNET_CHAIN_ID,
    name: 'Plume Mainnet',
    deployVersion: null,
    deployedAtBlock: null,
    contracts: {
      AssetVault: { address: null, runtimeBytecodeSha256: null, verified: false },
      IdentityRegistry: { address: null, runtimeBytecodeSha256: null, verified: false },
      RedemptionManager: { address: null, runtimeBytecodeSha256: null, verified: false },
      USDC: { address: null, runtimeBytecodeSha256: null, verified: false },
    },
  },
};
