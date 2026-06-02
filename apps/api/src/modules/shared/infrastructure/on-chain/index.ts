/**
 * On-chain read clients for the 3 MVP contracts (CIS §4 read surface).
 * The single typed gateway from the backend into Plume.
 */
export { type AssetVaultClient, createAssetVaultClient } from './AssetVaultClient';
export {
  createIdentityRegistryClient,
  type IdentityRegistryClient,
} from './IdentityRegistryClient';
export {
  createRedemptionManagerClient,
  type RedemptionManagerClient,
} from './RedemptionManagerClient';
export {
  type BootstrapCheck,
  type BootstrapResult,
  bootstrapChain,
  BytecodeMismatch,
  MissingBytecodePin,
  NoBytecode,
} from './ChainBootstrap';
