# Flow 06: Failed Lot + Pro-rata Refund

## Executive Summary

If a lot fails — bad weather destroying the harvest, contamination, quality rejection, force majeure — the Oracle Safe marks it `FALLIDO` (terminal state). Token holders receive a pro-rata refund from the escrow pool held in the contract.

**Escrow-total model (ADR-009):** the refund pool equals `montoNetoPendiente + (reservaTecnicaUSDC - reservaTecnicaLiberada)`. If the lot fails in `PREVENTA` (the only state where `montoNetoPendiente > 0`), the full 100% of buyer payments is on-chain and reimbursable without any off-chain prefunding. If the lot fails in `COSECHADO` (after `confirmarCosecha` already released `montoNetoPendiente` to the producer), only the unreleased technical reserve remains in the contract; the rest requires off-chain recovery.

**FIX M-05:** `marcarFallido` is only callable from `PREVENTA` or `COSECHADO`. Post-`ALMACENADO` failures are out of scope for this flow (reserved for a future `marcarFallidoPostAlmacenamiento` with a higher governance role).

This flow documents the on-chain execution. Where a known gap remains it is labelled explicitly.

---

## Actors Involved

- **SRL Operator** — Detects the failure, documents it, triggers the flow.
- **Backend** — Prepares Safe transaction, queries buyer list from Goldsky.
- **Oracle Safe** — Signs `marcarFallido()`, `reembolsarLoteFallido()`, and `finalizarReembolso()`.
- **AssetVault** — Executes state change + burn + USDC refund via private helper `_refundBuyer`.
- **Buyers** — Receive pro-rata USDC refund.

---

## Pre-conditions

- Lot exists in `AssetVault` with `estado == PREVENTA` or `estado == COSECHADO`. Any other state causes `CannotFailLoteInThisState` (FIX M-05).
- Evidence of failure is documented and uploaded to Arweave.
- Buyer list is compiled by the backend via Goldsky (all addresses that received mints for this `loteId`).
- Buyers are processed in batches. Each batch is capped at `MAX_REFUND_BATCH = 100`. For lots with more than 100 buyers, `reembolsarLoteFallido` is called multiple times; after all batches, `finalizarReembolso` is called once to seal the refund.

---

## Sequence Diagram

```
--- Failure detection and documentation ---

SRL      --> AdminPanel : SELECT lot #7 → "Mark as Failed"
SRL      --> AdminPanel : Fill form: motivo="cosecha_perdida_granizo",
                          evidencia: [campo-report.pdf, perito-report.pdf]

Backend  --> Backend    : hashEvidencia = SHA-256(evidence-bundle.zip) = 0xEVID...
Backend  --> Arweave    : Upload evidence → permanent record (off-chain)

--- Safe transaction: marcarFallido ---

Backend  --> OracleSafe : createTransaction({
                            to: AV_ADDR,
                            data: AV.marcarFallido.encode(
                              loteId=7,
                              motivo="cosecha_perdida_granizo") })

NOTE: marcarFallido(uint256 loteId, string calldata motivo) — only ORACLE_ROLE.
      hashEvidencia is NOT stored on-chain (evidence lives in Arweave, Goldsky audit trail).

Signer1 + Signer2 --> OracleSafe : sign + execute

OracleSafe --> AV      : marcarFallido(loteId=7, motivo="cosecha_perdida_granizo")
                        [ORACLE_ROLE]

AV       --> AV        : validate lote exists ✓
AV       --> AV        : validate estado == PREVENTA || estado == COSECHADO ✓
                        (reverts CannotFailLoteInThisState otherwise — FIX M-05)
AV       --> AV        : validate motivo.length > 0 ✓
AV       --> AV        : lote.estado = FALLIDO  [EFFECT]
AV       --> AV        : lote.motivoFallo = "cosecha_perdida_granizo"  [EFFECT]

AV       ~~> Event     : LoteFallido(loteId=7, "cosecha_perdida_granizo")

Backend  <-- AV        : LoteFallido event detected by Goldsky

--- Backend computes refund pool ---

Backend  --> AV        : lotes(7)  [view]
AV       --> Backend   : LoteMiel { montoNetoPendiente=1360_000000,
                                    reservaTecnicaUSDC=240_000000,
                                    reservaTecnicaLiberada=0, ... }

NOTE: Pool = montoNetoPendiente + (reservaTecnicaUSDC - reservaTecnicaLiberada)
      = 1360 + (240 - 0) = 1600 USDC  ← 100% of buyer payments (PREVENTA case).
      If the lot had reached COSECHADO and montoNetoPendiente was already paid out,
      pool = 0 + (240 - 0) = 240 USDC; off-chain recovery needed for the rest.

Backend  --> Backend   : Query Goldsky for LoteComprado events for loteId=7
                         buyers = [BUYER_1(10 tokens), ..., BUYER_8(10 tokens)]
                         totalSupply = 80 tokens

NOTE: No prefunding needed in the PREVENTA case. Contract already holds 1600 USDC.

--- Safe transaction: reembolsarLoteFallido (batch 1 of 1 — 8 buyers, within MAX_REFUND_BATCH=100) ---

Backend  --> OracleSafe : createTransaction({
                            to: AV_ADDR,
                            data: AV.reembolsarLoteFallido.encode(
                              loteId=7,
                              compradores=[BUYER_1,...,BUYER_8]) })

NOTE: reembolsarLoteFallido(uint256 loteId, address[] calldata compradores)
      — ORACLE_ROLE + nonReentrant. compradores.length must be > 0 and <= 100.
      _reembolsado[loteId] must be false (i.e. finalizarReembolso not yet called).
      For lots with > 100 buyers, call this function in multiple batches BEFORE finalizarReembolso.

Signer1 + Signer2 --> OracleSafe : sign + execute

OracleSafe --> AV      : reembolsarLoteFallido(loteId=7, [BUYER_1,...,BUYER_8])
                        [ORACLE_ROLE, nonReentrant]

AV       --> AV        : validate lote exists ✓
AV       --> AV        : validate lote.estado == FALLIDO ✓
AV       --> AV        : validate _reembolsado[7] == false ✓
AV       --> AV        : validate compradores.length > 0 && <= MAX_REFUND_BATCH ✓
AV       --> AV        : totalSupplyLote = totalSupply(7) = 80
AV       --> AV        : totalDisponible = montoNetoPendiente + (reservaTecnicaUSDC - reservaTecnicaLiberada)
                                         = 1360_000000 + (240_000000 - 0) = 1600_000000

--- Loop per buyer — delegated to private _refundBuyer(loteId, buyer, totalDisponible, totalSupplyLote) ---

--- Buyer BUYER_1 (10 tokens) ---
AV       --> AV        : _refundBuyer(7, BUYER_1, 1600_000000, 80)
AV       --> AV        : balance = balanceOf(BUYER_1, 7) = 10
AV       --> IR        : identityRegistry.isSanctioned(BUYER_1) → false ✓
                        (reverts CannotRefundBlockedAddress if sanctioned — FIX M-06)
AV       --> IR        : identityRegistry.isFrozen(BUYER_1) → false ✓
                        (reverts CannotRefundBlockedAddress if frozen — FIX M-06)
AV       --> IR        : identityRegistry.getTier(BUYER_1) → 1 (>0) ✓
                        (reverts CannotRefundRevokedAddress if tier==0 — FIX H-01 / ADR-014)

AV       --> AV        : reembolsoUSDC = (1600_000000 * 10) / 80 = 200_000000  [pro-rata]
AV       --> AV        : _burn(BUYER_1, 7, 10)  [EFFECT]
Token    ~~> Event     : TransferSingle(AV_ADDR, BUYER_1, 0x0, 7, 10)  (burn)

AV       --> USDC      : safeTransfer(BUYER_1, 200_000000)  [INTERACTION]
USDC     ~~> Event     : Transfer(AV_ADDR, BUYER_1, 200_000000)

AV       ~~> Event     : ReembolsoEjecutado(loteId=7, BUYER_1, 10, 200_000000)

--- (repeat for BUYER_2 through BUYER_8) ---

--- Buyer with balance=0 (skipped early) ---
AV       --> AV        : _refundBuyer(7, BUYER_X, ...) → balance == 0 → return (skip)
NOTE: No event emitted for skipped buyers. Audit trail via absence of ReembolsoEjecutado (L-06 — open).

NOTE: _reembolsado[7] is NOT set here. The batch is complete but more batches can follow.

--- Safe transaction: finalizarReembolso (after all batches are done) ---

Backend  --> OracleSafe : createTransaction({
                            to: AV_ADDR,
                            data: AV.finalizarReembolso.encode(loteId=7) })

NOTE: finalizarReembolso(uint256 loteId) — ORACLE_ROLE only. Call ONCE after all reembolsarLoteFallido
      batches are processed. Subsequent calls revert with ReembolsoYaEjecutado.

Signer1 + Signer2 --> OracleSafe : sign + execute

OracleSafe --> AV      : finalizarReembolso(loteId=7)  [ORACLE_ROLE]

AV       --> AV        : validate lote exists ✓
AV       --> AV        : validate lote.estado == FALLIDO ✓
AV       --> AV        : validate _reembolsado[7] == false ✓
AV       --> AV        : _reembolsado[7] = true  [EFFECT]

Backend  <-- AV        : tx confirmed

Backend  --> DB        : UPDATE lot { status: "failed_refunded", txHash: "0x..." }
Backend  --> Buyers    : email "Your refund of X USDC for Lot #7 has been processed"
```

---

## Detailed Steps

### Step 1 — Failure Detection and Documentation

- **Actor:** SRL Operator
- **Trigger:** Discovery of lot failure (weather, theft, contamination, lab rejection).
- **Process:** Collect all evidence, upload to Arweave, compute evidence bundle hash.
- **Output:** `hashEvidencia` (SHA-256 of evidence bundle, off-chain), `motivo` string.

### Step 2 — `marcarFallido(uint256 loteId, string calldata motivo)`

- **Actor:** Oracle Safe (ORACLE_ROLE)
- **Validations:**
  - Lot exists
  - `estado == PREVENTA || estado == COSECHADO` — reverts `CannotFailLoteInThisState` otherwise (FIX M-05)
  - `motivo.length > 0` — reverts `EmptyMotivo` otherwise
- **State changes:** `lote.estado = FALLIDO`, `lote.motivoFallo = motivo`
- **Events emitted:** `LoteFallido(loteId, motivo)`
- **Gas estimated:** ~55k

### Step 3 — Compute Refund Pool (off-chain)

Backend reads `lotes(loteId)` and computes:

```
totalDisponible = lote.montoNetoPendiente + (lote.reservaTecnicaUSDC - lote.reservaTecnicaLiberada)
```

- **PREVENTA failure:** `montoNetoPendiente > 0` (net amount still in escrow) + full reserve → 100% refundable on-chain.
- **COSECHADO failure (post-confirmarCosecha):** `montoNetoPendiente == 0` (released to producer) + remaining reserve only. Off-chain recovery from the producer is needed for the rest.

Backend also queries Goldsky for all buyer addresses and splits into batches of ≤ 100.

### Step 4 — `reembolsarLoteFallido(uint256 loteId, address[] calldata compradores)`

- **Actor:** Oracle Safe (ORACLE_ROLE)
- **Modifiers:** `nonReentrant`
- **Validations:**
  - Lot exists and `estado == FALLIDO`
  - `_reembolsado[loteId] == false` (finalizarReembolso not yet called)
  - `compradores.length > 0` — reverts `EmptyBuyers`
  - `compradores.length <= MAX_REFUND_BATCH (100)` — reverts `BatchTooLarge`
- **Per buyer (via private `_refundBuyer`):**
  1. Gets `balance = balanceOf(buyer, loteId)`; returns early if `balance == 0` (skipped silently)
  2. Checks `identityRegistry.isSanctioned(buyer)` → reverts `CannotRefundBlockedAddress` if true
  3. Checks `identityRegistry.isFrozen(buyer)` → reverts `CannotRefundBlockedAddress` if true
  4. Checks `identityRegistry.getTier(buyer) == 0` → reverts `CannotRefundRevokedAddress` if true (ADR-014)
  5. Computes `reembolsoUSDC = (totalDisponible * balance) / totalSupplyLote`
  6. Burns buyer's tokens: `_burn(buyer, loteId, balance)` [EFFECT]
  7. Transfers USDC: `usdc.safeTransfer(buyer, reembolsoUSDC)` [INTERACTION] (skipped if reembolsoUSDC == 0)
  8. Emits `ReembolsoEjecutado(loteId, buyer, balance, reembolsoUSDC)`
- **After loop:** nothing — `_reembolsado` is NOT set here; call `finalizarReembolso` when done.
- **Gas estimated:** ~80k per buyer in batch (includes 3 external calls to IdentityRegistry)

### Step 5 — `finalizarReembolso(uint256 loteId)`

- **Actor:** Oracle Safe (ORACLE_ROLE)
- **Purpose:** Seals the refund. Called once after all `reembolsarLoteFallido` batches are done.
- **Validations:**
  - Lot exists
  - `estado == FALLIDO`
  - `_reembolsado[loteId] == false`
- **State changes:** `_reembolsado[loteId] = true`
- **Events emitted:** none (state change only)
- **Gas estimated:** ~30k

---

## Post-conditions

- `lote.estado == FALLIDO` (terminal, no further transitions).
- `_reembolsado[loteId] == true` (set by `finalizarReembolso`).
- All listed buyers have received pro-rata USDC and their tokens burned.
- `totalSupply(loteId) == 0` (if all buyers were included across all batches).
- Audit log entries in DB with on-chain tx hashes.

---

## Error Cases

| Cause | Result | Reverts with |
|-------|--------|-------------|
| `estado` is not PREVENTA or COSECHADO | can't fail | `CannotFailLoteInThisState` |
| Lot in AGOTADO or FALLIDO (marcarFallido) | already finalized | `LoteAlreadyFinalized` |
| Empty motivo | blocked | `EmptyMotivo` |
| `_reembolsado` already true | double refund blocked | `ReembolsoYaEjecutado` |
| Empty compradores array | blocked | `EmptyBuyers` |
| compradores.length > 100 | oversized batch | `BatchTooLarge` |
| Buyer is sanctioned | blocked per FIX M-06 | `CannotRefundBlockedAddress` |
| Buyer is frozen | blocked per FIX M-06 | `CannotRefundBlockedAddress` |
| Buyer has KYC tier == 0 (revoked) | blocked per ADR-014 | `CannotRefundRevokedAddress` |
| Insufficient USDC in contract | per-buyer transfer fails | SafeERC20 revert |
| Buyer in compradores with balance 0 | silently skipped | no revert, no event (L-06 — open) |

---

## Known Gaps (Open — Not Yet Fixed)

**L-06 — No event for skipped buyers (balance == 0)**

When a buyer address in the `compradores` array has `balanceOf == 0`, `_refundBuyer` returns early without emitting an event. The audit trail for that address is incomplete (no on-chain signal that they were visited and skipped).

Fix: emit a `ReembolsoOmitido(loteId, buyer)` event for balance-zero entries.

---

**Post-COSECHADO failure — partial on-chain refund**

If `confirmarCosecha` was already called, `montoNetoPendiente == 0` (released to the producer). The refund pool covers only `reservaTecnicaUSDC - reservaTecnicaLiberada`. The remaining 80-85% requires off-chain producer recovery before the backend can prefund the contract and call a second-phase `reembolsarLoteFallido` with the remaining amount. This is an operational risk, not a code bug — it is the documented consequence of the escrow-total model when a lot fails after harvest confirmation.

---

## Concrete Numeric Example

```
Lot #7 — Hail damage scenario (lot still in PREVENTA)
  8 buyers, 10 tokens each, 20 USDC/token, reservaBps=1500

  Total minted:              80 tokens
  Total collected:           80 × 20 = 1600 USDC (all in contract — escrow total)
  reservaTecnicaUSDC:        1600 × 0.15 = 240 USDC
  montoNetoPendiente:        1600 × 0.85 = 1360 USDC
  reservaTecnicaLiberada:    0 (cosecha not confirmed → reserve not releasable)
  USDC in contract at FALLIDO: 1600 USDC

At reembolsarLoteFallido time:
  totalDisponible = 1360 + (240 - 0) = 1600 USDC  ← 100% refundable

Per-buyer refund:
  BUYER_1: 10 tokens → (1600 × 10) / 80 = 200 USDC  (full purchase price, 100%)
  BUYER_2: 10 tokens → 200 USDC
  ...
  BUYER_8: 10 tokens → 200 USDC
  Total distributed: 8 × 200 = 1600 USDC = 100% of escrow pool

Lot falls post-COSECHADO (alternative scenario):
  confirmarCosecha() already called:
    → montoNetoPendiente = 0 (transferred to producer)
    → reservaTecnicaUSDC = 240, reservaTecnicaLiberada = 0
    totalDisponible = 0 + (240 - 0) = 240 USDC
  Per-buyer refund: (240 × 10) / 80 = 30 USDC (15% — rest requires off-chain recovery)
```

---

## Operational Runbook

### Pre-conditions before executing `reembolsarLoteFallido`

1. Confirm `lote.estado == FALLIDO` on-chain.
2. Read `lotes(loteId)` to get `montoNetoPendiente`, `reservaTecnicaUSDC`, `reservaTecnicaLiberada`.
3. Compute `totalDisponible = montoNetoPendiente + (reservaTecnicaUSDC - reservaTecnicaLiberada)`.
4. If partial refund is expected (post-COSECHADO case) and full refund is required: coordinate off-chain recovery from the producer, then prefund `AssetVault` with the gap USDC before calling `reembolsarLoteFallido`.
5. Query Goldsky for all `LoteComprado` events for this `loteId` to build the full buyer list.
6. Split buyer list into batches of ≤ 100.
7. For each batch: execute `reembolsarLoteFallido(loteId, batchArray)` via Oracle Safe.
8. After all batches: execute `finalizarReembolso(loteId)` via Oracle Safe to seal the refund.

### Buyers blocked during refund

If a buyer address reverts with `CannotRefundBlockedAddress` (sanctioned or frozen) or `CannotRefundRevokedAddress` (tier == 0), remove that address from the batch and retry. Their funds remain in the contract. Compliance decides the off-chain recovery path for blocked buyers.

Cross-reference: `02-purchase-b2c.md` for how escrow accumulates, `04-quality-attestation.md` (if applicable) for when reserves are released.
