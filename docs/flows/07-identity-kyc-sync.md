# Flow 07: KYC Initial Sync — Sumsub → Backend → IdentityRegistry

## Executive Summary

A new user completes the KYC identity verification process through Sumsub, triggering a webhook to the backend. The backend validates the webhook signature, maps the verification result to a KYC tier, and writes the identity record on-chain via `IdentityRegistry.setKYC()`. This flow runs once per user at registration and again whenever Sumsub re-verifies or updates the applicant status (e.g., tier upgrade, expiry renewal). It is the prerequisite for any user to participate in token purchases (see `02-purchase-b2c.md`).

---

## Actors Involved

- 👤 User — end user filling in KYC form via the platform's embedded Sumsub widget
- 🤖 Backend — HSM-signed wallet, holds `BACKEND_SIGNER_ROLE` on `IdentityRegistry`
- 🔐 Sumsub — external KYC provider that manages the applicant lifecycle and emits signed webhooks
- 📜 IdentityRegistry — on-chain identity store (`IdentityRegistry.sol`)
- 🚨 Goldsky indexer — picks up `KYCUpdated` events and updates off-chain read models

---

## Pre-conditions

- User has created an account on the platform and has a wallet address (EOA or Plume Smart Wallet)
- Backend has a valid Sumsub `applicantId` associated with the user's wallet address (stored in `identity` table in PostgreSQL)
- `IdentityRegistry` is deployed with `BACKEND_SIGNER_ROLE` granted to the backend signer wallet
- Backend signer wallet holds enough native gas tokens (PLM on Plume Network) to pay for the `setKYC` transaction
- `IdentityRegistry` is **not paused** — `setKYC` is a mutator and requires `whenNotPaused` (FIX H-02)

---

## Sumsub Applicant Lifecycle

Before reaching the webhook, the applicant passes through these internal Sumsub states:

```
created          -- backend calls POST /applicants via Sumsub API
    |
    v
sdk_open         -- user opens Sumsub widget in frontend
    |
    v
submitted        -- user submits documents
    |
    v
(pending)        -- Sumsub runs automated checks
    |
    v
reviewed         -- manual review triggered (if needed)
    |
   / \
  v   v
approved        rejected
```

Sumsub emits webhooks on state transitions. The backend acts only on `applicantReviewed` with `reviewResult.reviewAnswer == GREEN` (approved) or `reviewAnswer == RED` (rejected).

---

## Sequence Diagram

```
👤 User      --> 🌐 Frontend  : opens /kyc route, clicks "Verify Identity"

🌐 Frontend  --> 🤖 Backend   : POST /identity/kyc/session
                                { walletAddress: "0xAaaa...", locale: "de" }

🤖 Backend   --> 🔐 Sumsub    : POST /applicants  { externalUserId: "0xAaaa..." }
🔐 Sumsub    --> 🤖 Backend   : { applicantId: "1a2b3c4d", token: "..." }

🤖 Backend   --> 📜 DB        : INSERT identity { wallet: "0xAaaa...", applicantId: "1a2b3c4d",
                                  sumsubHash: keccak256("1a2b3c4d"), tier: 0, status: "pending" }

🤖 Backend   --> 🌐 Frontend  : { sdkToken: "...", applicantId: "1a2b3c4d" }

👤 User      --> 🔐 Sumsub    : fills form (document scan, selfie, liveness check)
                                [inside Sumsub WebSDK widget in the frontend]

🔐 Sumsub    --> 🔐 Sumsub    : runs automated NFC + face-match + database checks
                                [async, 30s to 5min typically]

🔐 Sumsub    --> 🤖 Backend   : POST /webhooks/sumsub
                                {
                                  type: "applicantReviewed",
                                  applicantId: "1a2b3c4d",
                                  reviewResult: {
                                    reviewAnswer: "GREEN",
                                    reviewRejectType: null
                                  },
                                  applicantType: "individual",
                                  levelName: "basic-kyc-level"
                                }
                                Header: X-App-Token: <sumsub-secret-key>

🤖 Backend   --> 🤖 Backend   : validate HMAC-SHA256 signature
                                (header X-App-Token vs HMAC-SHA256 of raw body with SUMSUB_WEBHOOK_SECRET)
                                [reject with HTTP 401 if invalid — no DB changes, no on-chain]

🤖 Backend   --> 🔐 Sumsub    : GET /applicants/1a2b3c4d/one   [idempotency: re-fetch applicant]
🔐 Sumsub    --> 🤖 Backend   : { ...applicant data, country: "DE", levelName: "basic-kyc-level" }

🤖 Backend   --> 🤖 Backend   : map levelName → tier
                                "basic-kyc-level"    → tier = 1
                                "standard-kyc-level" → tier = 2
                                "enhanced-edd-level"  → tier = 3

🤖 Backend   --> 🤖 Backend   : calculate expiresAt = now() + 365 days
                                jurisdiction = "DE" (from applicant.country)
                                sumsubApplicantHash = keccak256(abi.encode("1a2b3c4d"))

🤖 Backend   --> 📜 IR        : setKYC(
                                  user: "0xAaaa...",
                                  tier: 1,
                                  expiresAt: 1780000000,
                                  jurisdiction: 0x4445,            (bytes2 for "DE")
                                  sumsubApplicantHash: 0xabc123...
                                )
                                [signed by BACKEND_SIGNER_ROLE wallet via KMS]

📜 IR        --> 📜 IR        : whenNotPaused check                          ✓ (FIX H-02)
📜 IR        --> 📜 IR        : validate user != address(0)                   ✓ → ZeroAddressUser
📜 IR        --> 📜 IR        : validate tier != 0                            ✓ → TierZeroNotAllowed (FIX M-04)
📜 IR        --> 📜 IR        : validate tier <= MAX_KYC_TIER (3)             ✓ → InvalidTier
📜 IR        --> 📜 IR        : validate expiresAt > block.timestamp          ✓ → ExpiryInPast
📜 IR        --> 📜 IR        : _kyc[user].tier = 1                           [EFFECT]
📜 IR        --> 📜 IR        : _kyc[user].expiresAt = 1780000000             [EFFECT]
📜 IR        --> 📜 IR        : _kyc[user].updatedAt = block.timestamp        [EFFECT]
📜 IR        --> 📜 IR        : _kyc[user].jurisdiction = 0x4445              [EFFECT]
📜 IR        --> 📜 IR        : _kyc[user].sumsubApplicantHash = 0xabc123...  [EFFECT]

📜 IR        ~~> 🚨 Event     : KYCUpdated(user: "0xAaaa...", actor: <BACKEND_SIGNER>,
                                           tier: 1, expiresAt: 1780000000,
                                           jurisdiction: 0x4445)             (FIX M-03)

🤖 Backend   <-- 📜 IR        : tx confirmed (txHash: "0x...")

🤖 Backend   --> 📜 DB        : UPDATE identity SET tier=1, status="approved",
                                  expiresAt=1780000000, onChainTxHash="0x..."

🚨 Goldsky   --> 🚨 Goldsky   : indexes KYCUpdated event → updates Identity entity in subgraph

🤖 Backend   --> 👤 User      : email "KYC approved — you can now purchase tokens"
```

---

## Detailed Steps with Gas Estimates

### Step 1 — Sumsub Widget Initialization (off-chain)

The backend calls Sumsub's REST API to create an applicant and obtain an SDK token. The `externalUserId` is the user's wallet address, creating the 1:1 binding between the Sumsub identity and the on-chain address. This call does not touch the blockchain.

Gas cost: zero.

### Step 2 — User Completes KYC (off-chain, Sumsub)

The user completes the document upload and liveness check flow entirely inside Sumsub's WebSDK. The platform does not see the raw documents — only the outcome. Documents are stored in Sumsub's infrastructure.

Gas cost: zero.

### Step 3 — Webhook Receipt and HMAC Validation

The backend receives a POST to `/webhooks/sumsub`. Before processing:

1. Extract `X-App-Token` header
2. Compute `HMAC-SHA256(rawBody, SUMSUB_WEBHOOK_SECRET)`
3. Compare constant-time with the header value

If the comparison fails, return HTTP 401 immediately. No database changes, no on-chain action. This prevents replay attacks and spoofed events from triggering fraudulent KYC approvals.

Gas cost: zero.

### Step 4 — Applicant Re-fetch (idempotency guard)

The backend re-fetches the applicant from Sumsub after receiving the webhook. This guards against:

- Stale webhook data (Sumsub may queue webhooks; the actual current state may differ)
- Replay of old webhooks with outdated status

If the re-fetched applicant's `reviewAnswer` differs from the webhook payload, the backend uses the re-fetched value as authoritative.

Gas cost: zero.

### Step 5 — Tier Mapping

| Sumsub levelName | Tier | Permissions |
|---|---|---|
| `basic-kyc-level` | 1 | Can purchase tokens (MIN_KYC_TIER_PARA_COMPRAR = 1) |
| `standard-kyc-level` | 2 | Can purchase + initiate redemption (MIN_KYC_TIER_PARA_REDIMIR = 2) |
| `enhanced-edd-level` | 3 | Same as tier 2, plus EDD-cleared for large transactions |

Expiry is set to `block.timestamp + 365 days` at the time the backend builds the transaction. The `sumsubApplicantHash` is `keccak256(abi.encode(applicantId))` — it stores a one-way reference to the Sumsub applicant without exposing PII on-chain.

### Step 6 — `setKYC()` on-chain

**Contract:** `IdentityRegistry.sol`, function `setKYC`

**Caller:** backend signer wallet (AWS/GCP KMS) holding `BACKEND_SIGNER_ROLE`

**Signature:**
```solidity
function setKYC(
    address user,
    uint8 tier,
    uint64 expiresAt,
    bytes2 jurisdiction,
    bytes32 sumsubApplicantHash
) external onlyRole(BACKEND_SIGNER_ROLE) whenNotPaused
```

**Validations (fail-fast order):**
1. `whenNotPaused` — reverts if contract is paused (FIX H-02; only mutators are paused, views stay live)
2. `user != address(0)` → reverts `ZeroAddressUser()`
3. `tier == 0` → reverts `TierZeroNotAllowed()` (FIX M-04 — tier-0 downgrade uses `revokeKYC`, not `setKYC`)
4. `tier > ComplianceConstants.MAX_KYC_TIER` (3) → reverts `InvalidTier()`
5. `expiresAt <= block.timestamp` → reverts `ExpiryInPast()`

> **Important:** to revoke a user's KYC (downgrade to tier 0), the backend must call `revokeKYC(address user, string reason)` instead. Calling `setKYC` with `tier=0` always reverts. This separates "never verified" (storage default) from "was verified and explicitly revoked".

**State changes (all in one slot update — storage packed):**
- `_kyc[user].tier` = new tier
- `_kyc[user].expiresAt` = expiry timestamp
- `_kyc[user].updatedAt` = `block.timestamp`
- `_kyc[user].jurisdiction` = ISO 3166-1 alpha-2 country code as `bytes2`
- `_kyc[user].sumsubApplicantHash` = keccak256 of applicantId

**Event emitted:** `KYCUpdated(address indexed user, address indexed actor, uint8 tier, uint64 expiresAt, bytes2 jurisdiction)` — `actor` is `msg.sender` (FIX M-03: indexed for forensics post-incident)

**Gas estimate:**
- First-time write (cold storage slots): ~58,000 gas
- Update of existing record (warm slots): ~35,000 gas

At 0.01 gwei on Plume, this costs approximately $0.03 per first-time setKYC.

---

### Pause asymmetry (FIX H-02)

`IdentityRegistry` inherits `Pausable` and `AccessControlDefaultAdminRules` (3-day delay for `DEFAULT_ADMIN_ROLE` transfers, FIX M-08).

| Function | Pausable? | Who can call |
|---|---|---|
| `setKYC` | Yes (`whenNotPaused`) | `BACKEND_SIGNER_ROLE` |
| `revokeKYC` | Yes (`whenNotPaused`) | `BACKEND_SIGNER_ROLE` |
| `pause()` | — | `COMPLIANCE_OFFICER_ROLE` **or** `DEFAULT_ADMIN_ROLE` |
| `unpause()` | — | `DEFAULT_ADMIN_ROLE` only |
| All view functions (`canMint`, `getTier`, etc.) | No — views always work | anyone |

The asymmetric unpause (admin-only) prevents a compromised Compliance Officer from undoing an emergency pause.

---

## Post-conditions

- `IdentityRegistry.canMint(0xAaaa...)` returns `true` (tier 1 >= MIN_KYC_TIER_PARA_COMPRAR, not sanctioned, not frozen, not expired)
- `IdentityRegistry.getTier(0xAaaa...)` returns `1`
- `IdentityRegistry.getJurisdiction(0xAaaa...)` returns `0x4445` ("DE")
- `IdentityRegistry.isExpired(0xAaaa...)` returns `false` (expiresAt is one year from now)
- PostgreSQL `identity` table updated with `tier=1`, `status=approved`, `onChainTxHash`
- Goldsky subgraph `Identity` entity has `tier: 1`
- User receives email notification
- Any subsequent call to `AssetVault.comprar()` for this wallet will pass the `_update()` KYC check (lines 510–514 of `AssetVault.sol`)

---

## Error Cases

| Scenario | Backend behavior | On-chain revert |
|---|---|---|
| HMAC validation fails | HTTP 401, drop webhook | No tx sent |
| Sumsub `reviewAnswer == RED` | Insert `status=rejected` in DB, no on-chain tx, email user | No tx sent |
| Sumsub down (re-fetch fails) | Retry with exponential backoff (max 5 attempts over 30 min), alert Slack | No tx sent until retry succeeds |
| Backend signer wallet out of gas | Transaction fails, alert PagerDuty. Ops team tops up wallet | `setKYC` reverts at RPC level |
| Plume RPC down | Backend queues the transaction locally, retries every 2 min | No tx confirmed until RPC recovers |
| `expiresAt <= block.timestamp` | Backend must use a future timestamp; this only happens if backend clock drifts badly | Reverts `ExpiryInPast()` |
| `tier > 3` | Should never happen with correct mapping, but protected by `InvalidTier()` | Reverts `InvalidTier()` |
| `tier == 0` sent to `setKYC` | This is a logic error — use `revokeKYC(user, reason)` instead | Reverts `TierZeroNotAllowed()` (FIX M-04) |
| Contract is paused | Backend must detect paused state before sending tx, queue until unpaused | Reverts `EnforcedPause()` (Pausable, FIX H-02) |
| Duplicate webhook (Sumsub retries) | Step 4 re-fetch shows same status. `setKYC` can be called again safely — it overwrites with same values. Idempotent. | No revert — `setKYC` is a pure upsert |

---

## Concrete Numeric Example

```
User:           alice@example.de
Wallet:         0xAaaa00000000000000000000000000000000000A
applicantId:    1a2b3c4d
Level name:     basic-kyc-level  →  tier = 1
Country:        DE  →  jurisdiction = 0x4445 (bytes2)
Expiry:         block.timestamp + 365 * 86400 = ~1780000000

sumsubApplicantHash:
  keccak256(abi.encode("1a2b3c4d"))
  = 0x3e7a5b8f9c2d1e4a6b0f3c7d2e9a5b8f9c2d1e4a6b0f3c7d2e9a5b8f9c2d1e4a

setKYC(
  user: 0xAaaa...,
  tier: 1,
  expiresAt: 1780000000,
  jurisdiction: 0x4445,
  sumsubApplicantHash: 0x3e7a...
)

Gas used:         ~58,000 (first-time, cold storage)
Gas price:        0.01 gwei
Cost:             ~$0.03

Events emitted:
  KYCUpdated(
    user:        0xAaaa...,
    actor:       <BACKEND_SIGNER wallet>,   // msg.sender, indexed (FIX M-03)
    tier:        1,
    expiresAt:   1780000000,
    jurisdiction: 0x4445
  )

Post-state:
  canMint(0xAaaa...)  = true
  canRedeem(0xAaaa...) = false  (requires tier >= 2)
  getTier(0xAaaa...)   = 1
  isExpired(0xAaaa...) = false
```

---

## Race Conditions and Edge Cases

### Race: webhook arrives AFTER Compliance Officer has already sanctioned the wallet

Timeline:
1. Compliance Officer calls `markSanctioned(0xAaaa..., "OFAC-SDN-match", 0xevidence...)` at block T
2. Sumsub webhook for the same wallet's KYC approval arrives and `setKYC()` is included in block T+1

Result: `setKYC()` succeeds and sets `tier=1`, but `_kyc[user].sanctioned = true` is NOT touched by `setKYC()`. The sanctioned flag is independent of tier. After both transactions:

- `canMint(0xAaaa...)` = `tier >= 1 && !sanctioned && !frozen && !expired`
  = `1 >= 1 && !true && ...` = `false`

The sanctioned flag wins. No mint is possible. No code change needed — this is the correct behavior by design.

Backend should detect this via the `isSanctioned` check before building the `setKYC` transaction and skip the on-chain call (save gas), while logging the skip in the audit trail.

### Race: KYC expiry during an active purchase flow

If a user's KYC expires between the backend's pre-check (`canMint`) and the on-chain `_update()` call inside `comprar()`, the on-chain check in `_update()` (line 511 of `AssetVault.sol`) will catch it and revert with `NotKYCVerified()`. This is the correct behavior — the on-chain check is the authoritative gate. Backend's pre-check is an optimization only.

### Idempotency: webhook redelivery

Sumsub guarantees at-least-once delivery. If the same `applicantReviewed` webhook arrives twice, the second call to `setKYC()` will:

1. Pass all validations (same tier, same expiry built from current timestamp → slightly different expiresAt, which is fine)
2. Overwrite the record with the same values
3. Emit `KYCUpdated` again

This is harmless. The Goldsky indexer will process the duplicate event and update the same entity with the same values. The backend should use idempotency keys in the DB to skip the second on-chain call if the same `applicantId` was recently processed (within 5 minutes), but the on-chain contract itself handles duplicates safely.

### KYC downgrade: tier 2 → tier 1

If a user had tier 2 and Sumsub re-reviews them and downgrades (e.g., enhanced documents rejected), the backend will call `setKYC()` with `tier=1`. This takes immediate effect on-chain. Any in-flight `iniciarRedencion()` call (which requires tier 2) will check `canRedeem()` at the time of the call. If the downgrade tx is mined first, the redemption call will revert.

### Backend signer key rotation

When the backend HSM key is rotated, the new signer address must be granted `BACKEND_SIGNER_ROLE` before the old one is revoked. Both operations require `DEFAULT_ADMIN_ROLE` (Safe multi-sig 2-of-3). The rotation window must be coordinated so no KYC syncs are dropped during the transition.

---

## Cross-references

- This flow is required before: `02-purchase-b2c.md` (canMint check), `05-redemption-export.md` (canRedeem check)
- Complements: `08-identity-sanction-screening.md` (nightly batch that can override KYC status)
- Overridden by: `09-identity-freeze-regulatory.md` (regulatory freeze takes precedence over valid KYC)
