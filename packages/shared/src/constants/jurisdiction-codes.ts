/**
 * ISO 3166-1 alpha-2 country codes used as jurisdictions in IdentityRegistry.KYCData.
 *
 * The `jurisdiction` field in the on-chain KYCData struct is `bytes2`, representing
 * a two-character ISO 3166-1 alpha-2 country code (e.g., "BO", "AR", "DE").
 *
 * Per ADR-011, jurisdiction validation is performed OFF-CHAIN by the backend before
 * calling `setKYC`. This module is the single source of truth for valid jurisdiction
 * codes within the monorepo.
 *
 * Usage:
 *   import { isValidJurisdiction } from '@tokenization/shared/constants/jurisdiction-codes';
 *   if (!isValidJurisdiction(userJurisdiction)) {
 *     throw new ValidationError(`Invalid jurisdiction: ${userJurisdiction}`);
 *   }
 *
 * NOTE ON RESTRICTED COUNTRIES:
 *   This list contains ALL valid ISO 3166-1 alpha-2 codes, including countries under
 *   international sanctions (Cuba, Iran, North Korea, Syria, Venezuela, etc.).
 *   The decision to BLOCK buyers from specific countries is the responsibility of the
 *   backend `screening/` module, which consults OFAC SDN, EU Financial Sanctions, and
 *   UN Consolidated Lists. This module does NOT enforce that policy.
 *
 * @see ADR-011: docs/architecture/ADR-011-jurisdiction-validation-off-chain.md
 */

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/**
 * ISO 3166-1 alpha-2 two-letter country code, matching the `bytes2` type in Solidity.
 * Examples: "BO", "AR", "DE", "US"
 */
export type JurisdictionCode = string;

/**
 * Geographic region grouping for jurisdictions. Used for analytics and reporting.
 */
export type JurisdictionRegion = 'LATAM' | 'EU' | 'NA' | 'APAC' | 'OTHER';

/**
 * A single jurisdiction entry mapping an ISO code to a human-readable name and region.
 */
export interface JurisdictionEntry {
  /** ISO 3166-1 alpha-2 two-letter code. Matches `bytes2` in Solidity. */
  code: JurisdictionCode;
  /** English country name (official short form). */
  name: string;
  /** Geographic region grouping. */
  region: JurisdictionRegion;
}

// ---------------------------------------------------------------------------
// Jurisdiction list
// ---------------------------------------------------------------------------

/**
 * Supported jurisdictions for KYC registration.
 *
 * Priority list for the MVP:
 *  - LATAM: Bolivia (primary market) + key regional markets
 *  - EU: target export markets (honey premium B2C/B2B)
 *  - NA: US institutional + Canada
 *  - APAC: Japan, Korea, Australia (premium honey importers)
 *  - OTHER: Switzerland (non-EU financial hub), UAE, Singapore
 *
 * To add a jurisdiction: append to this array and redeploy the backend.
 * No on-chain transaction required (per ADR-011).
 */
export const JURISDICTION_CODES: readonly JurisdictionEntry[] = [
  // -------------------------------------------------------------------------
  // LATAM — Bolivia (primary market) + core regional countries
  // -------------------------------------------------------------------------
  { code: 'BO', name: 'Bolivia', region: 'LATAM' },
  { code: 'AR', name: 'Argentina', region: 'LATAM' },
  { code: 'BR', name: 'Brazil', region: 'LATAM' },
  { code: 'CL', name: 'Chile', region: 'LATAM' },
  { code: 'PE', name: 'Peru', region: 'LATAM' },
  { code: 'CO', name: 'Colombia', region: 'LATAM' },
  { code: 'EC', name: 'Ecuador', region: 'LATAM' },
  { code: 'UY', name: 'Uruguay', region: 'LATAM' },
  { code: 'PY', name: 'Paraguay', region: 'LATAM' },
  { code: 'MX', name: 'Mexico', region: 'LATAM' },
  { code: 'CR', name: 'Costa Rica', region: 'LATAM' },
  { code: 'PA', name: 'Panama', region: 'LATAM' },
  { code: 'DO', name: 'Dominican Republic', region: 'LATAM' },

  // -------------------------------------------------------------------------
  // EU — target export markets for premium honey (MiCA + AMLD6 compliant)
  // -------------------------------------------------------------------------
  { code: 'DE', name: 'Germany', region: 'EU' },
  { code: 'ES', name: 'Spain', region: 'EU' },
  { code: 'IT', name: 'Italy', region: 'EU' },
  { code: 'FR', name: 'France', region: 'EU' },
  { code: 'NL', name: 'Netherlands', region: 'EU' },
  { code: 'BE', name: 'Belgium', region: 'EU' },
  { code: 'AT', name: 'Austria', region: 'EU' },
  { code: 'PT', name: 'Portugal', region: 'EU' },
  { code: 'SE', name: 'Sweden', region: 'EU' },
  { code: 'DK', name: 'Denmark', region: 'EU' },
  { code: 'FI', name: 'Finland', region: 'EU' },
  { code: 'PL', name: 'Poland', region: 'EU' },
  { code: 'CZ', name: 'Czech Republic', region: 'EU' },
  { code: 'HU', name: 'Hungary', region: 'EU' },
  { code: 'RO', name: 'Romania', region: 'EU' },
  { code: 'GR', name: 'Greece', region: 'EU' },
  { code: 'IE', name: 'Ireland', region: 'EU' },
  { code: 'LU', name: 'Luxembourg', region: 'EU' },

  // -------------------------------------------------------------------------
  // Non-EU Europe — financial hubs and key markets
  // -------------------------------------------------------------------------
  { code: 'GB', name: 'United Kingdom', region: 'EU' },
  { code: 'CH', name: 'Switzerland', region: 'OTHER' },
  { code: 'NO', name: 'Norway', region: 'EU' },
  { code: 'IS', name: 'Iceland', region: 'EU' },
  { code: 'LI', name: 'Liechtenstein', region: 'EU' },

  // -------------------------------------------------------------------------
  // NA — United States and Canada
  // -------------------------------------------------------------------------
  { code: 'US', name: 'United States', region: 'NA' },
  { code: 'CA', name: 'Canada', region: 'NA' },

  // -------------------------------------------------------------------------
  // APAC — premium honey importers
  // -------------------------------------------------------------------------
  { code: 'JP', name: 'Japan', region: 'APAC' },
  { code: 'KR', name: 'South Korea', region: 'APAC' },
  { code: 'AU', name: 'Australia', region: 'APAC' },
  { code: 'NZ', name: 'New Zealand', region: 'APAC' },
  { code: 'SG', name: 'Singapore', region: 'APAC' },
  { code: 'HK', name: 'Hong Kong', region: 'APAC' },

  // -------------------------------------------------------------------------
  // OTHER — Middle East and additional financial hubs
  // -------------------------------------------------------------------------
  { code: 'AE', name: 'United Arab Emirates', region: 'OTHER' },
  { code: 'IL', name: 'Israel', region: 'OTHER' },
  { code: 'ZA', name: 'South Africa', region: 'OTHER' },
] as const;

// ---------------------------------------------------------------------------
// Derived lookup set (O(1) lookup at runtime)
// ---------------------------------------------------------------------------

const _jurisdictionCodeSet: ReadonlySet<string> = new Set(JURISDICTION_CODES.map((j) => j.code));

// ---------------------------------------------------------------------------
// Validation helpers
// ---------------------------------------------------------------------------

/**
 * Returns `true` if the given string is a valid two-letter ISO 3166-1 alpha-2
 * jurisdiction code supported by the platform.
 *
 * @example
 *   isValidJurisdiction('BO')   // true
 *   isValidJurisdiction('xx')   // false
 *   isValidJurisdiction('')     // false
 *   isValidJurisdiction('USA')  // false (3 chars — not alpha-2)
 */
export function isValidJurisdiction(code: string): boolean {
  if (typeof code !== 'string' || code.length !== 2) return false;
  return _jurisdictionCodeSet.has(code.toUpperCase());
}

/**
 * Returns the `JurisdictionEntry` for the given code, or `undefined` if not found.
 *
 * @example
 *   getJurisdictionEntry('BO')
 *   // { code: 'BO', name: 'Bolivia', region: 'LATAM' }
 */
export function getJurisdictionEntry(code: string): JurisdictionEntry | undefined {
  const upper = code.toUpperCase();
  return JURISDICTION_CODES.find((j) => j.code === upper);
}

/**
 * Returns `true` if the jurisdiction is in the LATAM region.
 *
 * Useful for regional reporting and fee tier overrides.
 */
export function isLATAMJurisdiction(code: string): boolean {
  const entry = getJurisdictionEntry(code);
  return entry?.region === 'LATAM';
}

/**
 * Returns `true` if the jurisdiction is in the EU region (including non-EU
 * European countries that follow equivalent MiCA/AMLD regulation: GB, NO, IS, LI).
 *
 * Useful for MiCA compliance checks and EU consumer protection rules.
 */
export function isEUJurisdiction(code: string): boolean {
  const entry = getJurisdictionEntry(code);
  return entry?.region === 'EU';
}

/**
 * Returns all jurisdiction codes for a given region.
 *
 * @example
 *   getJurisdictionsByRegion('LATAM').map(j => j.code)
 *   // ['BO', 'AR', 'BR', 'CL', ...]
 */
export function getJurisdictionsByRegion(region: JurisdictionRegion): readonly JurisdictionEntry[] {
  return JURISDICTION_CODES.filter((j) => j.region === region);
}
