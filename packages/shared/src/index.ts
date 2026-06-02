/**
 * @tokenization/shared — barrel de exportaciones públicas.
 *
 * Exporta los tipos, constantes y helpers compartidos entre los packages
 * del monorepo (apps/api, apps/web, packages/chain, packages/db).
 */

export {
  JURISDICTION_CODES,
  isValidJurisdiction,
  getJurisdictionEntry,
  isLATAMJurisdiction,
  isEUJurisdiction,
  getJurisdictionsByRegion,
} from './constants/jurisdiction-codes.js';

export type {
  JurisdictionCode,
  JurisdictionRegion,
  JurisdictionEntry,
} from './constants/jurisdiction-codes.js';
