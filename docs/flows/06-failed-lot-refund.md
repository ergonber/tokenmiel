# Flow 06: Failed Lot + Pro-rata Refund

## Executive Summary

If a lot fails for any reason — bad weather destroying the harvest, theft, contamination, quality rejection, force majeure — the Oracle Safe marks it `FALLIDO` (terminal state). Token holders receive a pro-rata refund from the technical reserve held in the contract. The refund is partial: in the current implementation, only the 15-20% technical reserve is available on-chain. The remaining 80-85% (already paid to the producer SRL) requires an off-chain recovery mechanism (producer refund, insurance payout, guarantee fund) before the backend can fund the full refund.

This flow documents the on-chain execution and explicitly marks known bugs and their operational implications.

---

## Actors Involved

- **🏢 SRL Operator** — Detects the failure, documents it, triggers the flow.
- **🤖 Backend** — Prepares Safe transaction, queries buyer list from Goldsky, prefunds contract if needed.
- **🔐 Oracle Safe** — Signs `marcarFallido()` and `reembolsarLoteFallido()`.
- **📜 AssetVault** — Executes state change + burn + USDC refund.
- **👤 Buyers** — Receive pro-rata USDC refund.

---

## Pre-conditions

- Lot exists in `AssetVault` with `estado` not in `{AGOTADO, FALLIDO}` (any other state is valid).
- Evidence of failure is documented and uploaded.
- For refund to cover more than the reserve: Safe Treasury SRL wallet has pre-funded `AssetVault` with sufficient USDC (`safeTransfer(assetVaultAddress, totalNeeded)`).
- Buyer list is compiled by the backend via Goldsky (all addresses that received mints for this loteId).
- Buyers are processed in batches if more than ~30 to avoid block gas limit.

---

## Sequence Diagram

```
--- Failure detection and documentation ---

🏢 SRL      --> 🌐 AdminPanel : SELECT lot #7 → "Mark as Failed"
🏢 SRL      --> 🌐 AdminPanel : Fill form: motivo="contamination_post_storage",
                                evidencia: [contamination-report.pdf, lab-rejection.pdf]

🤖 Backend  --> 🤖 Backend   : hashEvidencia = SHA-256(evidence-bundle.zip) = 0xEVID...
🤖 Backend  --> 🌐 Arweave   : Upload evidence → permanent record

--- Safe transaction: marcarFallido ---

🤖 Backend  --> 🔐 OracleSafe : createTransaction({
                                  to: AV_ADDR,
                                  data: AV.marcarFallido.encode(
                                    loteId=7,
                                    motivo="contamination_post_storage") })
NOTE: Current marcarFallido() signature does NOT include hashEvidencia as a parameter.
      The evidence hash is NOT stored on-chain. This is a gap vs CONTRACT-SPECS.md §4.9
      which specifies marcarFallido(loteId, motivo, hashEvidencia).
      CONFLICT: code vs spec.

🔐 Signer1 + Signer2 --> 🔐 OracleSafe : sign + execute

🔐 OracleSafe --> 📜 AV      : marcarFallido(loteId=7, motivo="contamination_post_storage")
                              [ORACLE_ROLE]

📜 AV       --> 📜 AV        : validate lote exists ✓
📜 AV       --> 📜 AV        : validate estado != AGOTADO && != FALLIDO ✓

NOTE ⚠️ M-05: No restriction on transitioning from QUALITY_ATTESTED or ALMACENADO.
              If the reserve was already released (liberarReservaTecnica was called at
              QUALITY_ATTESTED), marking FALLIDO afterward creates a fund mismatch.
              See M-04 below for impact on refund calculation.

📜 AV       --> 📜 AV        : validate motivo.length > 0 ✓
📜 AV       --> 📜 AV        : lote.estado = FALLIDO  [EFFECT]
📜 AV       --> 📜 AV        : lote.motivoFallo = "contamination_post_storage"  [EFFECT]

📜 AV       ~~> 🚨 Event     : LoteFallido(loteId=7, "contamination_post_storage")

NOTE: Event does not include hashEvidencia — gap per audit L-03.

🤖 Backend  <-- 📜 AV        : LoteFallido event detected by Goldsky

--- Backend computes refund requirements ---

🤖 Backend  --> 📜 AV        : reservaTecnicaActual(7)  [view]
📜 AV       --> 🤖 Backend   : current reserve (e.g. 240 USDC if not released, or 0 if released)

NOTE ⚠️ M-04: If liberarReservaTecnica was already called (reserve = 0 in contract),
              but lote.reservaTecnicaUSDC still holds the original 240 USDC value,
              reembolsarLoteFallido will try to distribute 240 USDC that are NOT in the
              contract. This causes safeTransfer to revert (insufficient balance).

              reservaTecnicaActual(7) = lote.reservaTecnicaUSDC - lote.reservaTecnicaLiberada
              If both = 240: result = 0 USDC available for refund.
              The fix (not yet implemented) should use this net value in reembolsarLoteFallido.

🤖 Backend  --> 🤖 Backend   : Query Goldsky for all LoteComprado events for loteId=7
                               buyers = [BUYER_1(10 tokens), BUYER_2(20 tokens), ..., BUYER_8(10 tokens)]
                               totalSupply = 80 tokens

🤖 Backend  --> 🤖 Backend   : Compute totalRefundNeeded:
                               totalRecaudadoOriginal = 80 * 20 USDC = 1600 USDC
                               reserveInContract = 240 USDC (if not released)
                               deficitForFullRefund = 1600 - 240 = 1360 USDC

🤖 Backend  --> 🏢 SRL       : "Need to fund 1360 USDC for full refund (gap)"
                               SRL transfers 1360 USDC from producer to Treasury SRL wallet
                               Treasury SRL prefunds AssetVault

🔐 TreasurySRL --> 💰 USDC   : transfer(AV_ADDR, 1360_000000)
                               (prefund to enable full refund)

--- Safe transaction: reembolsarLoteFallido ---

🤖 Backend  --> 🔐 OracleSafe : createTransaction({
                                  to: AV_ADDR,
                                  data: AV.reembolsarLoteFallido.encode(
                                    loteId=7,
                                    compradores=[BUYER_1,...,BUYER_8]) })
NOTE: Max ~30 buyers per batch to avoid gas limit. If >30 buyers, call in multiple batches.
      _reembolsado[loteId] is set to true after first batch — subsequent batches must
      check for remaining tokens, not rely on this flag.

🔐 Signer1 + Signer2 --> 🔐 OracleSafe : sign + execute

🔐 OracleSafe --> 📜 AV      : reembolsarLoteFallido(loteId=7, [BUYER_1,...,BUYER_8])
                              [ORACLE_ROLE, nonReentrant]

📜 AV       --> 📜 AV        : validate lote exists ✓
📜 AV       --> 📜 AV        : validate lote.estado == FALLIDO ✓
📜 AV       --> 📜 AV        : validate _reembolsado[7] == false ✓
📜 AV       --> 📜 AV        : validate compradores.length > 0 ✓

📜 AV       --> 📜 AV        : totalSupplyLote = totalSupply(7) = 80
📜 AV       --> 📜 AV        : totalRecaudado = lote.reservaTecnicaUSDC = 240

NOTE ⚠️ M-04: Bug — does NOT subtract reservaTecnicaLiberada.
              If reserve was released before FALLIDO, this value is wrong.
              totalRecaudado should be: 240 - lote.reservaTecnicaLiberada
              With prefunding from SRL (step above), the contract NOW has enough USDC.
              But the calculation still reflects only the reserve portion.
              For full refund, contract needs: 80 * 20 = 1600 USDC total.
              With prefunding: contract has 240 + 1360 = 1600 USDC.
              But formula uses only 240 USDC → buyers get 15% back, not 100%.
              This is H-01: the fundamental architectural limitation.

--- Loop per buyer ---

--- Buyer BUYER_1 (10 tokens) ---
📜 AV       --> 📜 AV        : balance = balanceOf(BUYER_1, 7) = 10

NOTE ⚠️ M-06: No sanctioned/frozen check before transfer.
              If BUYER_1 was sanctioned after purchase, transfer proceeds anyway.
              Fix: check isSanctioned(BUYER_1) || isFrozen(BUYER_1) before transferring.

📜 AV       --> 📜 AV        : reembolsoUSDC = (240 * 10) / 80 = 30 USDC  [pro-rata]
📜 AV       --> 📜 AV        : _burn(BUYER_1, 7, 10)  [EFFECT]
🎫 Token    ~~> 🚨 Event     : TransferSingle(AV_ADDR, BUYER_1, 0x0, 7, 10)  (burn)

📜 AV       --> 💰 USDC      : safeTransfer(BUYER_1, 30_000000)  [INTERACTION]
💰 USDC     ~~> 🚨 Event     : Transfer(AV_ADDR, BUYER_1, 30_000000)

📜 AV       ~~> 🚨 Event     : ReembolsoEjecutado(loteId=7, BUYER_1, 10, 30_000000)

--- (repeat for BUYER_2 through BUYER_8) ---
--- BUYER with balance=0 ---
📜 AV       --> 📜 AV        : balance = balanceOf(BUYER_X, 7) = 0
📜 AV       --> 📜 AV        : continue (skip silently)

NOTE ⚠️ L-06: No event emitted for skipped buyers. Audit trail incomplete.

--- After all buyers processed ---
📜 AV       --> 📜 AV        : _reembolsado[7] = true  [EFFECT]

🤖 Backend  <-- 📜 AV        : tx confirmed

🤖 Backend  --> 📜 DB        : UPDATE lot { status: "failed_refunded", txHash: "0x..." }
🤖 Backend  --> 👤 Buyers    : email "Your refund of X USDC for Lot #7 has been processed"
```

---

## Detailed Steps

### Step 1 — Failure Detection and Documentation

- **Actor:** SRL Operator
- **Trigger:** Discovery of lot failure (weather, theft, contamination, lab rejection).
- **Process:** Collect all evidence, upload to Arweave, compute evidence bundle hash.
- **Output:** `hashEvidencia` (SHA-256 of evidence bundle), `motivo` string.

### Step 2 — `marcarFallido()`

- **Actor:** Oracle Safe (ORACLE_ROLE)
- **Function called:** `AssetVault.marcarFallido(loteId, motivo)`
- **Note (CONFLICT):** `CONTRACT-SPECS.md §4.11.2` specifies `marcarFallido(loteId, motivo, hashEvidencia)`. Current code does NOT include `hashEvidencia`. The evidence hash is NOT stored on-chain.
- **Validations:**
  - Lot exists
  - `estado != AGOTADO && estado != FALLIDO`
  - `motivo.length > 0`
- **State changes:** `lote.estado = FALLIDO`, `lote.motivoFallo = motivo`
- **Events emitted:** `LoteFallido(loteId, motivo)`
- **Gas estimated:** ~55k

### Step 3 — Compute Refund Requirements (off-chain)

Backend queries Goldsky for all buyer addresses and amounts, computes the gap between what the contract holds and what full refund would require.

### Step 4 — Pre-fund Contract (if needed)

Treasury SRL transfers additional USDC to `AssetVault` to cover the gap. This is the off-chain mechanism described in `CONTRACT-SPECS.md §10 CONFLICT 4`.

### Step 5 — `reembolsarLoteFallido()`

- **Actor:** Oracle Safe (ORACLE_ROLE)
- **Function called:** `AssetVault.reembolsarLoteFallido(loteId, compradores[])`
- **Validations:**
  - Lot exists and in `FALLIDO`
  - `_reembolsado[loteId] == false`
  - `compradores.length > 0`
- **Per buyer loop:**
  - Gets `balance = balanceOf(buyer, loteId)`
  - Skips if `balance == 0`
  - Computes `reembolsoUSDC = totalRecaudado * balance / totalSupply`
  - Burns buyer's tokens
  - Transfers USDC
  - Emits `ReembolsoEjecutado`
- **After loop:** `_reembolsado[loteId] = true`
- **Gas estimated:** ~80k per buyer in batch

---

## Post-conditions

- `lote.estado == FALLIDO` (terminal, no further transitions).
- `_reembolsado[loteId] == true`.
- All listed buyers have received pro-rata USDC and their tokens burned.
- `totalSupply(loteId) == 0` (if all buyers were included in the compradores array).
- Audit log entries in DB with on-chain tx hashes.

---

## Error Cases

| Cause | Result | Reverts with |
|-------|--------|-------------|
| Lot in AGOTADO or FALLIDO | can't fail again | `LoteAlreadyFinalized()` |
| Empty motivo | blocked | `EmptyMotivo()` |
| `_reembolsado` already set | double refund blocked | `ReembolsoYaEjecutado()` |
| Empty compradores array | blocked | `EmptyBuyers()` |
| Insufficient USDC in contract | per-buyer transfer fails | SafeERC20 revert |
| Buyer in compradores with balance 0 | silently skipped | no revert, no event (L-06) |

---

## Known Bugs (Critical for This Flow)

**⚠️ H-01 — Refund covers only 15-20% of purchase price**

File: `AssetVault.sol:397-409`

The refund formula uses `lote.reservaTecnicaUSDC` as the total pot. Since 80-85% of buyer payments were already transferred to the producer SRL at mint time, a failed lot results in buyers receiving at most 20% of their capital back.

**Full operational impact:**
```
Example: 10 buyers, 10 tokens each at 20 USDC, reservaBps=1500 (15%)
Total paid by buyers: 10 × 10 × 20 = 2000 USDC
Reserve in contract: 2000 × 0.15 = 300 USDC
Already transferred to producer: 1700 USDC

Without prefunding:
  Each buyer gets: 300 / 100 tokens × 10 tokens = 30 USDC
  Each buyer loses: 200 - 30 = 170 USDC (85% capital loss)

With prefunding (producer returns 1700 USDC):
  Contract has 1700 + 300 = 2000 USDC
  But formula: totalRecaudado = lote.reservaTecnicaUSDC = 300
  Each buyer still gets: 30 USDC (formula only reads reserve field)
```

**The fundamental fix requires** either:
- (A) Retaining 100% of USDC in the contract until `confirmarCosecha`, only then releasing to producer.
- (B) A guarantee fund that pre-funds the full amount on `marcarFallido`.
- (C) Fixing `reembolsarLoteFallido` to include pre-funded USDC beyond the reserve:
  `totalRefund = USDC.balanceOf(address(this))` or a dedicated per-lot accounting.

**Decision required from product + legal before auditing this contract externally.**

---

**⚠️ M-04 — Reserve net calculation missing**

If `liberarReservaTecnica` was called (reserve released to producer), `lote.reservaTecnicaLiberada == lote.reservaTecnicaUSDC`. The refund formula reads `lote.reservaTecnicaUSDC` (the gross), not the net. If `lote.reservaTecnicaLiberada > 0`, the contract does NOT actually hold those USDC. The `safeTransfer` will revert with insufficient balance.

Fix: `totalRecaudado = lote.reservaTecnicaUSDC - lote.reservaTecnicaLiberada`.

---

**⚠️ M-05 — marcarFallido from late states**

`marcarFallido` allows transition from `QUALITY_ATTESTED`, `ALMACENADO`, and `REDENCION_PARCIAL`. In these states:
- The technical reserve was likely already released (can call `liberarReservaTecnica` from `QUALITY_ATTESTED`).
- Some buyers may have already redeemed tokens (in `REDENCION_PARCIAL`).

Combined with M-04, if the reserve was released and the lot is then marked FALLIDO, `reembolsarLoteFallido` will attempt to distribute 0 USDC (net reserve = 0), resulting in no refund despite formally completing the flow.

---

**⚠️ M-03 — Tokens in INICIADA redemptions are burned by reembolsarLoteFallido**

If `marcarFallido` is called while `RedemptionManager` has open redemptions in `INICIADA` state for this lot, those buyers' tokens are burned in `reembolsarLoteFallido`. But the `Redencion` records remain in `INICIADA` state — `confirmarExportacion` will later try to burn tokens that no longer exist, reverting.

The expected behavior is: `marcarFallido` should auto-cancel all open redemptions for the lot, releasing buyers' tokens from logical escrow. This is not implemented.

---

**⚠️ M-06 — USDC sent to sanctioned addresses**

If a buyer was sanctioned after their purchase but before the refund, `reembolsarLoteFallido` sends them USDC without checking sanction status. This may constitute a sanctions violation (OFAC/AMLD). The fix is to check `isSanctioned(buyer) || isFrozen(buyer)` before the transfer and skip (with event) if true.

---

## Concrete Numeric Example

```
Lot #7 — Contamination scenario (post-storage, ALMACENADO state)
  8 buyers, 10 tokens each, 20 USDC/token, reservaBps=1500

  Total minted:          80 tokens
  Total collected:       80 × 20 = 1600 USDC
  Reserve retained:      1600 × 0.15 = 240 USDC (in contract)
  Net to producer:       1360 USDC (already transferred)
  Reserve released?      YES (liberarReservaTecnica called at QUALITY_ATTESTED)
  Reserve in contract:   0 USDC  ← problem

At FALLIDO time:
  lote.reservaTecnicaUSDC         = 240_000000
  lote.reservaTecnicaLiberada     = 240_000000
  Net available for refund        = 240 - 240 = 0 USDC  ← per fix
  Without fix (current code)      = 240 USDC used in formula, but 0 actually in contract → REVERT

SRL prefunds contract for full refund:
  Transfer 1600 USDC to AssetVault

After fix (M-04) and prefunding:
  totalRecaudado = 0 (net reserve) → formula gives 0 USDC per buyer via reserve alone.
  Need to change formula to use actual USDC balance or per-lot accounting.

Interim operational workaround (before code fix):
  Do NOT call liberarReservaTecnica before any marcarFallido scenario.
  Keep reserve in contract until lot is in a finalized state (AGOTADO or confirmed complete).

Per-buyer refund (only-reserve path, 15%):
  BUYER_1: 10 tokens → 240 × 10/80 = 30 USDC (30 USDC refund on 200 USDC paid = 15%)
  BUYER_2: 10 tokens → 30 USDC
  ...
  BUYER_8: 10 tokens → 30 USDC
  Total distributed: 8 × 30 = 240 USDC = 100% of reserve
  Buyers' loss collectively: 1360 USDC (85%)
```

---

## Operational Runbook Pre-conditions for Full Refund

Before executing `reembolsarLoteFallido` when a full refund is intended:

1. Confirm `lote.reservaTecnicaLiberada` value (was it already released?).
2. Compute total USDC needed: `totalSupply(loteId) * precioPorTokenUSDC`.
3. Check current USDC balance of `AssetVault`: `USDC.balanceOf(AV_ADDR)`.
4. Gap = total needed - current balance.
5. If gap > 0: Treasury SRL must pre-fund `AssetVault` with the gap amount.
6. Only after pre-funding: trigger `reembolsarLoteFallido`.

Cross-reference: see `02-purchase-b2c.md` for how reserves accumulate, and `04-quality-attestation.md` for when reserves are released.
