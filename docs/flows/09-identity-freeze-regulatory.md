# Flow 09: Regulatory Freeze — Judicial / UIF Order → freezeAddress

## Executive Summary

When the platform receives a binding regulatory order directing it to block a specific wallet — such as a judicial asset freeze, a UIF Bolivia asset restraint, a FinCEN order, or a sanctioning regulation from the EU — the Compliance Officer manually verifies the document's authenticity, uploads it to Arweave for permanent on-chain proof, and then calls `freezeAddress()` on `IdentityRegistry`. The wallet is immediately blocked for all mint and redemption operations. The freeze persists until the issuing authority formally revokes or expires the order. This flow is always manual, case-by-case, and requires a hardware wallet signature from the Compliance Officer.

---

## Actors Involved

- ⚖️ Compliance Officer — the natural person holding `COMPLIANCE_OFFICER_ROLE`, operating a Ledger Nano X
- 🏢 Regulatory Authority — the external body issuing the order (court, UIF Bolivia, FinCEN, EU authority)
- 🤖 Backend — receives the order, uploads to Arweave, prepares the on-chain transaction for CO review
- 📜 IdentityRegistry — on-chain compliance registry
- 🚨 Goldsky — indexes `Frozen` and `Unfrozen` events

---

## Pre-conditions

- The wallet to be frozen is registered in the platform (has an `identity` record in PostgreSQL)
- The Compliance Officer has physical access to their hardware wallet
- The regulatory order is a legally binding document with a verifiable issuer identifier (court stamp, authority letterhead, official reference number)
- The backend Arweave uploader is operational and funded
- `IdentityRegistry` is **not paused** — `freezeAddress` and `unfreezeAddress` are mutators and require `whenNotPaused` (FIX H-02)

---

## Types of Orders That Justify freezeAddress

The following table describes the order types and their expected document formats. The Compliance Officer must verify authenticity before executing the freeze. Spurious or unverified orders must never trigger an on-chain action.

| Order type | Issuing authority | Document format | Verification method |
|---|---|---|---|
| Medida cautelar / Embargo preventivo | Juzgado Comercial, Bolivia | PDF signed by judge, notarized | Cross-reference court number with Organo Judicial Bolivia registry |
| Requerimiento UIF Bolivia | Unidad de Investigación Financiera Bolivia | Official letterhead, QR code for verification | Verify QR at uif.gob.bo |
| Asset Freeze Order | FinCEN (USA) or OFAC | PDF on Treasury letterhead | Cross-reference with official Treasury.gov case numbers |
| EU Asset Freeze Regulation | European Union, national implementation | EU Official Journal reference | Cross-reference with eur-lex.europa.eu |
| FATF mutual evaluation finding | Not direct — translated via domestic regulator | Domestic agency order document | Same as domestic authority verification |

---

## Difference Between `freezeAddress` and `markSanctioned`

These are two distinct and independent compliance mechanisms. Using them interchangeably is an operational error.

| Dimension | `markSanctioned` | `freezeAddress` |
|---|---|---|
| Trigger | Automated nightly job matching against official sanctions lists (OFAC SDN, UN, EU, UIF) | Manual, case-by-case regulatory order directed at a specific individual/entity |
| Process | Automated by the backend job, reviewed post-hoc by CO | Manual: CO must verify the order document before any action |
| Reversibility | Via `unmarkSanctioned()` (e.g., false positive, entity removed from list) | Via `unfreezeAddress()` only when the order expires or is revoked by the issuing authority |
| Evidence | `evidenceHash` = hash of the match entry in the sanctions list | `orderHash` = hash of the regulatory order document uploaded to Arweave |
| Scope | Reactive to global sanctions regime | Reactive to a specific legal proceeding targeting this specific wallet |
| Simultaneity | Both can be `true` at the same time for the same wallet | Same |

A wallet can be simultaneously `sanctioned=true` AND `frozen=true`. Both flags must be cleared before `canMint` or `canRedeem` returns `true`.

---

## Sequence Diagram

```
🏢 Auth      --> ⚖️ CO        : delivery of regulatory order
                                (physical mail, certified email, judicial notification service)

⚖️ CO        --> ⚖️ CO        : verify document authenticity off-chain
                                (court reference number, official signatures, issuer identity)
                                [CRITICAL: do NOT proceed without verified authenticity]

⚖️ CO        --> 🤖 Backend   : upload order document via admin panel
                                POST /admin/compliance/regulatory-orders
                                { walletAddress: "0xBbbb...", orderRef: "JC-2026-04567",
                                  orderPdf: <binary>, issuer: "Juzgado Comercial #3 La Paz" }

🤖 Backend   --> 🤖 Backend   : compute SHA-256 of PDF
                                orderHash = SHA256(orderPdf)
                                         = 0x1234567890abcdef...

🤖 Backend   --> ☁️ R2        : PUT regulatory-orders/JC-2026-04567.pdf
                                (fast access copy)

🤖 Backend   --> 🌊 Arweave   : POST https://node.bundlr.network/tx
                                upload PDF bytes, content-type: application/pdf
                                [permanent, pays with funded Arweave/Bundlr wallet]

🌊 Arweave   --> 🤖 Backend   : { arweaveTxId: "abc123xyz789...", arweaveUri: "ar://abc123xyz789" }

🤖 Backend   --> 🤖 Backend   : verify: download from Arweave, re-compute SHA-256
                                compare vs locally computed hash → must match

🤖 Backend   --> 📜 DB        : INSERT regulatory_orders {
                                  wallet: "0xBbbb...",
                                  orderRef: "JC-2026-04567",
                                  issuer: "Juzgado Comercial #3 La Paz",
                                  localHash: "0x1234...",
                                  arweaveUri: "ar://abc123xyz789",
                                  arweaveTxId: "abc123xyz789",
                                  uploadVerified: true,
                                  status: "pending_freeze"
                                }

🤖 Backend   --> ⚖️ CO        : admin UI shows: "Document uploaded and verified.
                                  Hash: 0x1234... | Arweave: ar://abc123xyz789
                                  Confirm freeze for wallet 0xBbbb...?"

⚖️ CO        --> ⚖️ CO        : reviews wallet info in admin panel:
                                  - identity tier, jurisdiction, KYC status
                                  - token balances across all lots
                                  - purchase and redemption history
                                  - existing sanctions/freeze flags

⚖️ CO        --> 🖥️ AdminUI   : clicks "Execute Freeze" button

🖥️ AdminUI   --> 🤖 Backend   : POST /admin/compliance/execute-freeze
                                { orderId: 42 }

🤖 Backend   --> 🤖 Backend   : builds calldata for freezeAddress:
                                  user = "0xBbbb..."
                                  regulatoryOrder = "JC-2026-04567 | Juzgado Comercial #3 La Paz | 2026-04-15"
                                  orderHash = 0x1234567890abcdef...

🤖 Backend   --> ⚖️ CO        : presents tx for Ledger signing
                                (shows decoded calldata + Arweave link in admin UI)

⚖️ CO        --> 🔐 Ledger    : physically signs transaction on Ledger Nano X
                                (verifies calldata hash on device screen)

⚖️ CO        --> 📜 IR        : freezeAddress(
                                  user: "0xBbbb...",
                                  regulatoryOrder: "JC-2026-04567 | Juzgado Comercial #3 La Paz | 2026-04-15",
                                  orderHash: 0x1234567890abcdef...
                                )
                                [COMPLIANCE_OFFICER_ROLE, Ledger-signed]

📜 IR        --> 📜 IR        : whenNotPaused check                               ✓ (FIX H-02)
📜 IR        --> 📜 IR        : validate user != address(0)                      ✓ → ZeroAddressUser
📜 IR        --> 📜 IR        : validate regulatoryOrder not empty               ✓ → EmptyReason
📜 IR        --> 📜 IR        : validate orderHash != bytes32(0)                 ✓ → InvalidOrderHash (FIX M-01b)
📜 IR        --> 📜 IR        : validate !_kyc[user].frozen                      ✓ → AlreadyFrozen
📜 IR        --> 📜 IR        : _kyc[user].frozen = true                         [EFFECT]
📜 IR        --> 📜 IR        : _kyc[user].updatedAt = block.timestamp           [EFFECT]

📜 IR        ~~> 🚨 Event     : Frozen(
                                  user:             "0xBbbb...",
                                  actor:            <COMPLIANCE_OFFICER wallet>,   // msg.sender, indexed (FIX M-03)
                                  regulatoryOrder:  "JC-2026-04567 | Juzgado Comercial ...",
                                  orderHash:        0x1234567890abcdef...
                                )

⚖️ CO        <-- 📜 IR        : tx confirmed (txHash: "0x789...")

🤖 Backend   --> 📜 DB        : UPDATE regulatory_orders SET status="frozen", onChainTxHash="0x789..."
                                INSERT audit_log_compliance {
                                  action: "FREEZE",
                                  wallet: "0xBbbb...",
                                  orderRef: "JC-2026-04567",
                                  txHash: "0x789...",
                                  performedBy: <CO_wallet_address>,
                                  arweaveUri: "ar://abc123xyz789"
                                }

🚨 Goldsky   --> 🚨 Goldsky   : indexes Frozen event → updates Identity entity in subgraph

🤖 Backend   --> 📢 Slack     : POST #compliance-alerts
                                "REGULATORY FREEZE EXECUTED: 0xBbbb...
                                 Order: JC-2026-04567 (Juzgado Comercial #3 La Paz)
                                 Arweave evidence: ar://abc123xyz789
                                 Tx: 0x789..."
```

---

## Detailed Steps with Gas Estimates

### Step 1 — Document Verification (off-chain, mandatory)

This step cannot be automated. The Compliance Officer must personally verify:

- The order is from a recognized authority in a jurisdiction the platform operates in or has legal exposure to
- The document bears appropriate authentication (court stamp, notarial seal, official letterhead, or QR code that verifies with the issuing authority's public registry)
- The wallet address in the order matches the platform's registered wallet (if the order names a person, the CO must cross-reference their Sumsub-verified identity with the platform's `identity` table to find the matching wallet)
- The order is directed at the platform specifically (some orders are directed at custodians or exchanges; the platform must have received it correctly)

Gas cost: zero.

### Step 2 — Document Upload to Arweave

The backend computes SHA-256 of the PDF before and after the Arweave upload to verify data integrity. The Arweave transaction ID is the permanent proof of upload. The `orderHash` passed to `freezeAddress()` is the `keccak256` of the PDF SHA-256 hash (converting from SHA-256 bytes32 to Solidity bytes32 representation).

Gas cost: zero (Arweave cost is paid in AR tokens, typically < $0.01 for a PDF).

### Step 3 — `freezeAddress()` on-chain

**Contract:** `IdentityRegistry.sol`, function `freezeAddress`

**Caller:** Compliance Officer hardware wallet holding `COMPLIANCE_OFFICER_ROLE`

**Signature:**
```solidity
function freezeAddress(
    address user,
    string calldata regulatoryOrder,
    bytes32 orderHash
) external onlyRole(COMPLIANCE_OFFICER_ROLE) whenNotPaused
```

**Validations (fail-fast):**
1. `whenNotPaused` — reverts if contract is paused (FIX H-02)
2. `user != address(0)` → reverts `ZeroAddressUser()`
3. `bytes(regulatoryOrder).length == 0` → reverts `EmptyReason()`
4. `orderHash == bytes32(0)` → reverts `InvalidOrderHash()` (FIX M-01b — freeze sin orden documentada no se acepta)
5. `_kyc[user].frozen` → reverts `AlreadyFrozen()`

**State changes:**
- `_kyc[user].frozen = true`
- `_kyc[user].updatedAt = block.timestamp`

Note: `regulatoryOrder` (a human-readable string) and `orderHash` (bytes32) are stored in the event log only, not in contract storage. Contract storage holds only the `frozen: bool` flag. This is consistent with the principle of on-chain minimum data — the full document evidence lives in Arweave, and the event log provides the permanent on-chain reference.

**Event:** `Frozen(address indexed user, address indexed actor, string regulatoryOrder, bytes32 orderHash)` — `actor` is `msg.sender` (FIX M-03: indexed for forensics)

**Gas estimate:** ~38,000 gas (warm write to `frozen` bool + event with string)

---

### Pause asymmetry (FIX H-02)

`IdentityRegistry` inherits `Pausable` and `AccessControlDefaultAdminRules` (3-day delay for `DEFAULT_ADMIN_ROLE` transfers, FIX M-08).

| Function | Pausable? | Who can call |
|---|---|---|
| `freezeAddress` | Yes (`whenNotPaused`) | `COMPLIANCE_OFFICER_ROLE` |
| `unfreezeAddress` | Yes (`whenNotPaused`) | `COMPLIANCE_OFFICER_ROLE` |
| `pause()` | — | `COMPLIANCE_OFFICER_ROLE` **or** `DEFAULT_ADMIN_ROLE` |
| `unpause()` | — | `DEFAULT_ADMIN_ROLE` only |
| All view functions (`isFrozen`, `canMint`, etc.) | No — views always work | anyone |

The asymmetric unpause (admin-only) prevents a compromised Compliance Officer from undoing an emergency pause. Views remain live so `AssetVault` and `RedemptionManager` are never blocked from checking compliance status.

### Step 4 — Audit Trail

The `audit_log_compliance` table in PostgreSQL captures:
- Action type (`FREEZE`)
- Wallet address
- Order reference
- On-chain tx hash
- Arweave URI
- Performing officer wallet address
- Timestamp

This table is append-only (PostgreSQL policy revokes `UPDATE` and `DELETE` for all roles except the designated backup admin). The hash chain in this table links each row to the previous row's hash, ensuring retroactive tampering is detectable.

---

## Post-conditions

- `IdentityRegistry.isFrozen(0xBbbb...)` returns `true`
- `IdentityRegistry.canMint(0xBbbb...)` returns `false` (the `!data.frozen` check at line 173 of `IdentityRegistry.sol` fails)
- `IdentityRegistry.canRedeem(0xBbbb...)` returns `false` (same check at line 180)
- Any `AssetVault.comprar()` for this wallet reverts via `_update()` with `NotKYCVerified()`
- Any `RedemptionManager.iniciarRedencion()` from this wallet reverts with `CannotRedeem()`
- Existing tokens are NOT burned. The user still owns their tokens but cannot transact with them.
- PostgreSQL audit trail updated
- Goldsky subgraph updated

---

## Effect on Tokens the User Already Holds

The freeze does NOT burn or confiscate tokens. The user's ERC-1155 balance in `AssetVault` remains intact. However:

1. **New purchases:** blocked by `canMint` check in `_update()`
2. **Redemptions:** blocked by `canRedeem` check in `iniciarRedencion()`
3. **P2P transfers:** already blocked for all users regardless of freeze status (the `_update()` override in `AssetVault.sol` line 508 blocks all non-mint, non-burn transfers unconditionally)
4. **Refunds on a FALLIDO lot:** blocked — `reembolsarLoteFallido()` in `AssetVault.sol` lines 368-369 checks `isFrozen(buyer)` and reverts with `CannotRefundBlockedAddress()` ⚠️

> ⚠️ Finding M-06 (from the AssetVault security audit): `reembolsarLoteFallido` blocks refunds to frozen addresses. This is intentional for OFAC compliance, but it creates a scenario where a frozen user who legitimately purchased tokens before the freeze cannot receive their pro-rata refund when a lot fails. The tokens remain locked in the contract permanently unless:
> (a) the freeze is lifted before the refund batch is processed, or
> (b) a separate recovery mechanism is implemented via governance (future ADR).
> This is a regulatory trade-off — blocking refunds to frozen addresses prevents the platform from executing a payment to a party under a judicial asset freeze order.

The only way for a frozen user's tokens to be released is through `unfreezeAddress()` after the regulatory order is lifted. After unfreezing, the user can:
- Initiate redemptions normally
- Receive refunds in subsequent `reembolsarLoteFallido` batch calls (if the lot has not yet been fully processed)

---

## Unfreeze Process

When the regulatory order is expired, revoked, or withdrawn by the issuing authority:

1. Compliance Officer receives the revocation document
2. Verifies authenticity via the same process as for the original order
3. Uploads the revocation document to Arweave, computes its hash
4. Calls `unfreezeAddress()` with the reason string referencing the revocation

**Signature:**
```solidity
function unfreezeAddress(
    address user,
    string calldata reason
) external onlyRole(COMPLIANCE_OFFICER_ROLE) whenNotPaused
```

Reverts `NotFrozen()` if the address is not currently frozen.

```
⚖️ CO        --> 📜 IR        : unfreezeAddress(
                                  user: "0xBbbb...",
                                  reason: "Order JC-2026-04567 lifted by Juzgado Comercial #3 La Paz
                                           on 2026-09-10. Revocation doc: ar://def456..."
                                )
                                [COMPLIANCE_OFFICER_ROLE, Ledger-signed]

📜 IR        --> 📜 IR        : whenNotPaused check              ✓ (FIX H-02)
📜 IR        --> 📜 IR        : validate user != address(0)      ✓
📜 IR        --> 📜 IR        : validate reason not empty        ✓
📜 IR        --> 📜 IR        : validate _kyc[user].frozen       ✓ → NotFrozen if false

📜 IR        ~~> 🚨 Event     : Unfrozen(
                                  user:   "0xBbbb...",
                                  actor:  <COMPLIANCE_OFFICER wallet>,   // msg.sender, indexed (FIX M-03)
                                  reason: "Order lifted..."
                                )
```

Gas estimate for `unfreezeAddress()`: ~28,000 gas.

---

## Error Cases

| Scenario | Result |
|---|---|
| CO submits order for a wallet not in the platform's records (no KYC record) | `freezeAddress()` still executes successfully — the contract stores `frozen=true` regardless of tier. If that wallet registers KYC later, `canMint` will still return `false`. |
| CO attempts to freeze an already-frozen wallet | Reverts `AlreadyFrozen()`. Admin panel should pre-check `isFrozen()` before presenting the "Execute Freeze" button. |
| `orderHash` is zero (backend bug, corrupted hash) | Reverts `InvalidOrderHash()` (FIX M-01b). Backend must verify the computed hash is non-zero before presenting the tx for signing. |
| CO attempts to unfreeze a non-frozen wallet | Reverts `NotFrozen()`. Admin panel should pre-check `isFrozen()` before presenting the "Execute Unfreeze" option. |
| Contract is paused | Reverts `EnforcedPause()` (FIX H-02). An emergency pause blocks new freeze/unfreeze mutations; CO must coordinate with DEFAULT_ADMIN_ROLE to unpause before executing. Note: `unpause()` requires `DEFAULT_ADMIN_ROLE` — CO alone cannot unblock this. |
| Arweave upload fails | Backend blocks the on-chain action. No freeze is executed without a verified Arweave receipt. Alert Slack for manual intervention. |
| Arweave verification hash mismatch | Backend aborts the flow. The upload is considered corrupted. Alert Slack, retry upload. |
| CO's Ledger is unavailable | Suplente CO can sign instead (both hold `COMPLIANCE_OFFICER_ROLE` per the constructor in `IdentityRegistry.sol` lines 52-53). |
| Regulatory order arrives at weekend | Both CO and CO suplente have hardware wallets. Platform's SLA with regulatory bodies assumes business-hours response (24-48h for routine orders). For urgent judicial orders, CO suplente is reachable via the incident response protocol. |

---

## Concrete Numeric Example

```
Scenario: Judicial asset freeze order from Bolivian commercial court.

Order details:
  Reference:    JC-2026-04567
  Issuer:       Juzgado Comercial #3 de La Paz, Bolivia
  Date:         2026-04-15
  Target:       John David Morrison (passport US-984532)
  Platform wallet: 0xBbbb11111111111111111111111111111111111B
  Type:         Medida cautelar preventiva — pending investigation PR-2026-0892

Document hash:
  PDF SHA-256: a7f3b8c9d1e2f4a5b6c7d8e9f0a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9
  orderHash = keccak256(bytes.fromhex("a7f3...")) = 0x1234567890abcdef1234567890abcdef...

Arweave upload:
  arweaveTxId: AbCdEfGh1234567890...
  arweaveUri:  ar://AbCdEfGh1234567890...
  upload verified: ✓ (re-hashed from Arweave gateway, matches)

On-chain call:
  freezeAddress(
    user:             0xBbbb11111111111111111111111111111111111B,
    regulatoryOrder:  "JC-2026-04567 | Juzgado Comercial #3 La Paz | 2026-04-15",
    orderHash:        0x1234567890abcdef1234567890abcdef...
  )

Gas used:             ~38,000
Gas price:            0.01 gwei
Cost:                 ~$0.02

Events emitted:
  Frozen(
    user:             0xBbbb...,
    actor:            <CO hardware wallet>,   // msg.sender, indexed (FIX M-03)
    regulatoryOrder:  "JC-2026-04567 | Juzgado Comercial #3 La Paz | 2026-04-15",
    orderHash:        0x1234567890abcdef...   // non-zero, required (FIX M-01b)
  )

Post-state:
  isFrozen(0xBbbb...)  = true
  canMint(0xBbbb...)   = false
  canRedeem(0xBbbb...) = false

Token balances:
  AssetVault.balanceOf(0xBbbb..., loteId=7) = 20 tokens  (user had purchased previously)
  Tokens are NOT burned. They are locked in place.

Impact on in-flight operations:
  - Any pending comprar() for 0xBbbb... will revert with NotKYCVerified()
  - Any iniciarRedencion() from 0xBbbb... will revert with CannotRedeem()
  - If lot #7 becomes FALLIDO, reembolsarLoteFallido will skip 0xBbbb... with
    CannotRefundBlockedAddress() ⚠️ (finding M-06)
```

---

## Race Conditions and Edge Cases

### Race: user calls `iniciarRedencion()` in the same block as `freezeAddress()`

Blockchain transactions within a block are ordered by position. If `freezeAddress()` is mined before `iniciarRedencion()` in the same block, the redemption reverts. If `iniciarRedencion()` is mined first, it succeeds and the tokens are logically locked in the redemption. In the next block `freezeAddress()` is mined.

At this point, the tokens are "in escrow" in the `RedemptionManager` (tracked by the `Redencion` struct, though no physical token transfer occurs due to P2P lock). The Oracle can still call `confirmarExportacion()` or `cancelarRedencion()` at their discretion. A frozen address can still be the `comprador` in an existing `Redencion` record — `confirmarExportacion()` will burn their tokens (they already initiated the process). Whether this is the desired behavior during an active judicial freeze must be verified with legal counsel. The system does not technically block `confirmarExportacion()` for a frozen user's active redemption.

> CONFLICT: The contract does not explicitly prohibit `confirmarExportacion()` for a frozen address's redemption. This means a fraudulent actor could front-run the freeze by initiating a redemption before the freeze lands. Whether the Oracle should check `isFrozen` before `confirmarExportacion` is a compliance policy question that should be resolved in a new ADR before mainnet.

### Freeze of a wallet that also acts as `productorSRL`

If a producer's wallet is frozen, `freezeAddress()` only blocks their ability to mint and redeem via `canMint`/`canRedeem`. It does NOT block USDC transfers to `productorSRL` via `confirmarCosecha()` or `liberarReservaTecnica()` — those functions do not check `identityRegistry` for the producer wallet.

> CONFLICT: If a judicial order requires freezing ALL assets including pending USDC proceeds for a producer, the current implementation does NOT enforce this. The `frozen` flag only affects the `canMint`/`canRedeem` checks. Blocking USDC releases to a frozen producer requires either (a) additional compliance logic in `AssetVault`, or (b) the Oracle Safe refusing to sign `confirmarCosecha` for that producer's lot, which is an off-chain governance action. This is flagged for ADR review.

### Simultaneous sanctions (sanctioned AND frozen)

A wallet can legitimately be both `sanctioned=true` AND `frozen=true` simultaneously. The contract handles this correctly: `canMint` and `canRedeem` both check `!data.sanctioned && !data.frozen`, so both conditions must be cleared before the wallet can operate again. Clearing only one flag is not sufficient.

---

## Cross-references

- This flow blocks: `02-purchase-b2c.md` (canMint), `05-redemption-export.md` (canRedeem), `06-failed-lot-refund.md` (CannotRefundBlockedAddress ⚠️ M-06)
- Compare with: `08-identity-sanction-screening.md` (automated vs manual; different flags, different triggers)
- Prerequisites: `07-identity-kyc-sync.md` is NOT a prerequisite — freezeAddress works on wallets regardless of KYC tier
