# Flow 08: Nightly Sanctions Screening — OFAC/UN/EU/UIF → markSanctioned

## Executive Summary

Every night at 02:00 UTC, the backend runs an automated job that downloads the latest versions of the OFAC SDN, UN Consolidated, EU Consolidated, and UIF Bolivia sanctions lists, then checks every registered wallet address against those lists. Matching is done by blockchain address (Chainalysis API) and by fuzzy name match against the off-chain identity data stored in PostgreSQL (never PII on-chain). If a high-confidence match is found, the backend calls `IdentityRegistry.markSanctioned()` automatically, which immediately disables the wallet's ability to mint or redeem. The Compliance Officer receives a Slack and email alert to review each match.

---

## Actors Involved

- 🤖 Backend — automated cron job (BullMQ worker, `COMPLIANCE_OFFICER_ROLE` on-chain for this job)
- 🔐 OFAC / UN / EU / UIF — external sanctions list providers (public download URLs)
- 🔐 Chainalysis — optional real-time blockchain address screening API
- ⚖️ Compliance Officer — reviews matches, confirms or reverses decisions
- 📜 IdentityRegistry — on-chain compliance registry
- 🚨 Goldsky — indexes `Sanctioned` and `Unsanctioned` events

> **Important architecture note:** In the current codebase, `markSanctioned()` requires `COMPLIANCE_OFFICER_ROLE` (line 97 of `IdentityRegistry.sol`). The automated job wallet must hold this role. This is a deliberate design decision: automatic sanctioning is treated as a compliance action, not a backend signer action, because it has irreversible consequences. This means the job wallet is a privileged operational wallet that must be secured at the same level as a hardware wallet (KMS-backed minimum).

---

## Pre-conditions

- Backend cron scheduler (BullMQ) is running and the `sanctions-screening` job is registered
- `identity` table in PostgreSQL contains the list of registered wallets with their `applicantId` and hashed PII (name hash, DOB hash)
- Sumsub holds the full PII — the backend retrieves it on demand only for matching purposes, never stores raw PII in its own DB
- Backend sanctions job wallet holds `COMPLIANCE_OFFICER_ROLE` on `IdentityRegistry`
- OFAC/UN/EU/UIF download URLs are accessible (public endpoints)

---

## Sanctions List Sources and Formats

| List | Source URL | Format | Update frequency |
|---|---|---|---|
| OFAC SDN | `https://ofac.treasury.gov/downloads/sdn.xml` | XML | Business days |
| UN Consolidated | `https://scsanctions.un.org/resources/xml/en/consolidated.xml` | XML | Several times per week |
| EU Consolidated | `https://webgate.ec.europa.eu/fsd/fsf/public/files/xmlFullSanctionsList_1_1/content?token=dG9rZW4t` | XML | As-updated |
| UIF Bolivia | PDF download from UIF Bolivia website (manual upload for now) | PDF parsed → structured | Monthly |

The backend downloads these lists, parses them into a structured in-memory format (arrays of `{ name, aliases[], dob, countries[], entityType }`), and compares against registered identities.

---

## Matching Algorithm

The backend does NOT store full PII. The matching pipeline is:

1. **Blockchain address match (Chainalysis):** For each wallet in `kyc_users` table, query Chainalysis OFAC screening API. This is the most precise match — if a wallet has been directly associated with a sanctioned entity, the score is definitive. Cost: API call per address (~$0.01 per call). Chainalysis is optional; fall back to name match if unavailable.

2. **Name fuzzy match (if Chainalysis unavailable or score inconclusive):**
   - Backend calls Sumsub API to retrieve the applicant's full name and DOB for the wallet being checked (one-time per screening cycle, cached in Redis for 24h with TTL matching the screening job frequency)
   - Applies a normalized Levenshtein distance + token-set ratio comparison against each sanctioned entity's name and all aliases
   - A match is "high confidence" if score > 0.95 AND DOB matches (if DOB is available in the sanctions list)
   - A match is "medium confidence" if score is 0.85-0.95 and DOB is absent from the list

3. **High confidence matches** (score > 0.95 OR Chainalysis confirmed) → automatic `markSanctioned()` call
4. **Medium confidence matches** (0.85-0.95) → flagged in `compliance_review_queue` table, Compliance Officer must manually confirm before any on-chain action

---

## Sequence Diagram

```
⏰ BullMQ     --> 🤖 Backend   : fire "sanctions-screening" job at 02:00 UTC

🤖 Backend   --> 🔐 OFAC      : GET https://ofac.treasury.gov/downloads/sdn.xml
🔐 OFAC      --> 🤖 Backend   : sdn.xml (~40MB XML)

🤖 Backend   --> 🔐 UN        : GET https://scsanctions.un.org/resources/xml/en/consolidated.xml
🔐 UN        --> 🤖 Backend   : consolidated.xml

🤖 Backend   --> 🔐 EU        : GET EU consolidated list URL
🔐 EU        --> 🤖 Backend   : xmlFullSanctionsList.xml

🤖 Backend   --> 🤖 Backend   : parse all lists into in-memory structured format
                                 (name, aliases, dob, countries, entityType per entry)

🤖 Backend   --> 📜 DB        : SELECT wallet_address, applicant_id FROM kyc_users
                                 WHERE tier >= 1 AND status = 'approved'
                                 LIMIT 5000 (paginated)

📜 DB        --> 🤖 Backend   : [ { wallet: "0xAaaa...", applicantId: "1a2b3c4d" }, ... ]

-- Loop over each wallet --

🤖 Backend   --> 🔐 Chainalysis : POST /v2/addresses/0xAaaa.../sanctions
🔐 Chainalysis --> 🤖 Backend   : { score: 0.02, matches: [] }  (no match)
                                  [OR if match:]
                                  { score: 0.98, matches: [{ entity: "ACME Corp", listType: "SDN" }] }

-- If Chainalysis score > 0.95 OR name match score > 0.95 --

🤖 Backend   --> 🔐 Sumsub    : GET /applicants/1a2b3c4d  [PII for match evidence]
🔐 Sumsub    --> 🤖 Backend   : { fullName: "...", dob: "1975-03-12", country: "DE" }

🤖 Backend   --> 🤖 Backend   : build evidenceHash:
                                  keccak256(abi.encode(
                                    "OFAC-SDN",
                                    sanctionedEntityId,
                                    applicantId,
                                    block.timestamp
                                  ))

🤖 Backend   --> 📜 IR        : markSanctioned(
                                  user: "0xBbbb...",
                                  reason: "OFAC SDN match: score=0.97, entity=Petrov Viktor",
                                  evidenceHash: 0x1234...
                                )
                                [COMPLIANCE_OFFICER_ROLE wallet, KMS-signed]

📜 IR        --> 📜 IR        : validate user != address(0)        ✓
📜 IR        --> 📜 IR        : validate reason not empty           ✓
📜 IR        --> 📜 IR        : validate !_kyc[user].sanctioned     ✓  (not already sanctioned)
📜 IR        --> 📜 IR        : _kyc[user].sanctioned = true        [EFFECT]
📜 IR        --> 📜 IR        : _kyc[user].updatedAt = block.timestamp [EFFECT]

📜 IR        ~~> 🚨 Event     : Sanctioned(
                                  user: "0xBbbb...",
                                  reason: "OFAC SDN match: score=0.97, entity=Petrov Viktor",
                                  evidenceHash: 0x1234...,
                                  timestamp: <block.timestamp>
                                )

🤖 Backend   <-- 📜 IR        : tx confirmed (txHash: "0x...")

🤖 Backend   --> 📜 DB        : INSERT compliance_sanctions_log {
                                  wallet: "0xBbbb...",
                                  list: "OFAC-SDN",
                                  matchScore: 0.97,
                                  evidenceHash: "0x1234...",
                                  txHash: "0x...",
                                  reviewStatus: "pending_review"
                                }

🤖 Backend   --> 📢 Slack     : POST #compliance-alerts
                                "SANCTIONS HIT: 0xBbbb... matched OFAC SDN (score: 0.97).
                                 Entity: Petrov Viktor. Tx: 0x...
                                 Review required: https://admin.platform.io/compliance/review/123"

🤖 Backend   --> 📧 Email     : send to compliance@platform.io
                                Subject: "[ACTION REQUIRED] Sanctions match detected — 0xBbbb..."

-- End loop --

🤖 Backend   --> 📜 DB        : INSERT screening_runs { run_at, total_checked: 5000,
                                  hits: 2, auto_sanctioned: 2, pending_review: 1 }

🤖 Backend   --> 📢 Slack     : POST #ops-monitoring
                                "Nightly screening complete: 5000 checked, 2 hits (1 confirmed, 1 pending review)"
```

---

## Detailed Steps with Gas Estimates

### Step 1 — List Download and Parse (off-chain)

- Downloads 3-4 XML files totaling ~60-80MB
- Parses into structured in-memory arrays
- Estimated time: 20-40 seconds
- OFAC SDN contains ~9,000 individuals and entities with aliases

Gas cost: zero.

### Step 2 — Wallet Address Screening (off-chain)

- One Chainalysis API call per wallet: ~$0.01 each
- For 5,000 wallets: ~$50/night max (declining as % of users approach saturation)
- Redis cache for Chainalysis responses: 24h TTL to avoid re-checking within the same day
- Sumsub PII fetch is only done for wallets that pass the threshold; usually <1% of the list

Gas cost: zero.

### Step 3 — `markSanctioned()` on-chain

**Contract:** `IdentityRegistry.sol`, lines 95–107

**Caller:** backend job wallet holding `COMPLIANCE_OFFICER_ROLE`

**Validations (fail-fast):**
1. `user != address(0)` → reverts `ZeroAddressUser()`
2. `bytes(reason).length > 0` → reverts `EmptyReason()`
3. `!_kyc[user].sanctioned` → reverts `AlreadySanctioned()` (idempotent: if already sanctioned, skip)

**State changes:**
- `_kyc[user].sanctioned = true`
- `_kyc[user].updatedAt = block.timestamp`

**Event:** `Sanctioned(address indexed user, string reason, bytes32 evidenceHash, uint64 timestamp)`

Note: `evidenceHash` is stored in the event log (not in contract storage). It is a keccak256 hash linking to the match evidence document, which will also be uploaded to Arweave by the backend and stored in PostgreSQL.

**Gas estimate:**
- ~45,000 gas per `markSanctioned()` call (warm storage update + event)
- For 2 hits per night: ~90,000 gas total, negligible cost

### Step 4 — False Positive Review

The Compliance Officer reviews the flagged address in the admin panel:

- Views the match evidence: list name, entity name, score, and Chainalysis report
- Views the user's Sumsub summary (redacted PII visible only to authorized admin role)
- Decision options: "Confirm — true positive" (no action needed, already sanctioned on-chain) or "Reverse — false positive"

For false positives, Compliance Officer calls `unmarkSanctioned()`:

```
⚖️ CO        --> 📜 IR        : unmarkSanctioned(
                                  user: "0xCccc...",
                                  reason: "False positive — name collision, different DOB and nationality"
                                )
                                [COMPLIANCE_OFFICER_ROLE hardware wallet, Ledger-signed]

📜 IR        ~~> 🚨 Event     : Unsanctioned(user: "0xCccc...", reason: "False positive...")
```

Gas estimate for `unmarkSanctioned()`: ~30,000 gas.

---

## Post-conditions (after marking one wallet as sanctioned)

- `IdentityRegistry.isSanctioned(0xBbbb...)` returns `true`
- `IdentityRegistry.canMint(0xBbbb...)` returns `false` (because `!sanctioned` check in line 173 fails)
- `IdentityRegistry.canRedeem(0xBbbb...)` returns `false`
- Any subsequent `AssetVault.comprar()` for `0xBbbb...` will revert via `_update()` → `NotKYCVerified()`
- Any subsequent `RedemptionManager.iniciarRedencion()` will revert with `CannotRedeem()`
- PostgreSQL `compliance_sanctions_log` has a new row with evidence hash and tx hash
- Slack and email alerts sent to compliance team

---

## Error Cases

| Scenario | Result |
|---|---|
| OFAC server down | Retry up to 3 times with 60s backoff. If all fail, skip OFAC for this run and alert Slack. Log as `partial_run`. |
| Chainalysis API unavailable | Fall back to name-only matching. Log fallback mode. Alert Slack. |
| `markSanctioned()` called on already-sanctioned address | Reverts `AlreadySanctioned()`. Backend catches and logs as "already sanctioned, skip" — not an error. |
| Job wallet out of gas | Transaction fails. Alert PagerDuty. Ops tops up wallet. Screening run marked as `partial_failed`. |
| Match score borderline (0.85-0.95) | Queued for manual review only, no automatic on-chain action. |
| User has no KYC record in IR yet (tier=0) | `markSanctioned()` still succeeds — the contract stores sanctioned=true regardless of tier. If the user later tries to complete KYC (via `setKYC`), they get tier set but `canMint` will still return `false`. |

---

## Concrete Numeric Example

```
Screening run at 02:00 UTC on 2026-05-25.
Total wallets checked: 5,000

Results:
  - 4,997 wallets: no match
  - 2 wallets: high-confidence OFAC SDN match (score > 0.95)
  - 1 wallet: medium-confidence UN list match (score 0.88) → queued for manual review

For the 2 high-confidence matches:

Match #1:
  Wallet:      0xBbbb0001...
  applicantId: 5e6f7g8h
  Matched list: OFAC SDN
  Entity:      Viktor Petrov (alias "V. Petrov", DOB 1965-11-20, RU)
  Chainalysis score: 0.97
  evidenceHash: keccak256(abi.encode("OFAC-SDN", "SDN-45621", "5e6f7g8h", 1748131200))
               = 0xabc123...
  markSanctioned tx: 0xdef456...
  Gas used: ~45,000

Match #2:
  Wallet:      0xBbbb0002...
  applicantId: 9h0i1j2k
  Matched list: OFAC SDN
  Entity:      Agroexport SA (Panama, SDGT-listed)
  Chainalysis score: 0.99 (direct address association)
  evidenceHash: 0x789abc...
  markSanctioned tx: 0x012def...
  Gas used: ~45,000

After Compliance Officer review (next business morning):
  Match #1: Confirmed true positive. Sanctioned status maintained.
  Match #2: Confirmed true positive. Sanctioned status maintained.

The medium-confidence UN match:
  Wallet:       0xCccc0003...
  Match score:  0.88 (name match, no DOB in UN list to cross-check)
  Action:       Queued in compliance_review_queue. No on-chain action.
  CO decision:  False positive after reviewing Sumsub full name and nationality.
  On-chain:     No markSanctioned() called. No on-chain footprint.
```

---

## Race Conditions and Edge Cases

### Race: user is mid-purchase when sanctioned during the nightly run

Timeline:
1. Backend receives MoonPay webhook at 02:01 UTC, builds `comprar()` tx
2. Screening job runs at 02:00 UTC, `markSanctioned()` tx confirmed at 02:00:45
3. `comprar()` tx submitted and mined at 02:01:30

Result: `comprar()` calls `_update()` in `AssetVault.sol` (line 511), which calls `identityRegistry.canMint(buyer)`. At this point `sanctioned=true`, so `canMint` returns `false`, and `_update` reverts with `NotKYCVerified()`. The purchase fails.

The user's USDC was already transferred to the AssetVault before `comprar()` was called (per the purchase flow in `02-purchase-b2c.md`). This creates a USDC recovery scenario: the USDC is stuck in the AssetVault. The backend must detect the reverted `comprar()` and initiate a manual off-chain USDC return via the `TREASURY_SRL_ROLE` or a dedicated recovery mechanism.

> CONFLICT: The current architecture does not document a formal recovery path for USDC that was pre-transferred but whose `comprar()` reverted. This edge case requires an operational runbook. Flagged for documentation in a future ADR.

### Race: sanctioned address has tokens from a previous purchase (lot not FALLIDO)

The `markSanctioned()` call does not burn any tokens. The user retains their existing tokens but cannot:
- Mint new tokens (canMint returns false)
- Initiate a redemption (canRedeem returns false)
- Receive a refund if the lot becomes FALLIDO

The last point is documented in `AssetVault.sol` lines 368-369: `reembolsarLoteFallido` explicitly checks `isSanctioned(buyer)` and reverts with `CannotRefundBlockedAddress()` if true.

> ⚠️ This means a sanctioned buyer who legitimately purchased tokens before being sanctioned will have their refund blocked on a FALLIDO lot. The tokens are effectively frozen in place. Resolution requires off-chain legal coordination and potentially a regulatory unfreeze + unsanction pair.

### Idempotency of the nightly run

If the same wallet triggers a hit on consecutive nights (because the sanctioned flag was not cleared between runs), `markSanctioned()` will revert with `AlreadySanctioned()` on the second night. The backend catches this error and treats it as a no-op. No duplicate Slack alerts are sent (the backend checks `compliance_sanctions_log` before sending alerts for the same wallet if a recent sanctioning is already logged).

---

## Cross-references

- This flow can block: `02-purchase-b2c.md` (canMint), `05-redemption-export.md` (canRedeem), `06-failed-lot-refund.md` (CannotRefundBlockedAddress — ⚠️ finding M-06)
- Triggered independently from: `07-identity-kyc-sync.md` (does not modify tier, only sanctioned flag)
- Can be manually reversed by: `09-identity-freeze-regulatory.md`-style manual review using `unmarkSanctioned()`
