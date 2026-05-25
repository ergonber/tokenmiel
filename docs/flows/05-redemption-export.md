# Flow 05: Redemption + DUE + BL/AWB → Token Burn

## Executive Summary

A token holder with KYC Tier 2 or higher initiates a physical redemption: they want to receive their honey physically. Tokens are logically locked (no transfer possible — tracked in escrow by `RedemptionManager`). The SRL arranges customs export (DUE document), hires a courier, and obtains the Bill of Lading or Airway Bill (BL/AWB). Once the Oracle Safe confirms the export with the DUE number and BL/AWB hash, the tokens are permanently burned by `AssetVault.burnForRedemption()`, called by `RedemptionManager`. The lot transitions from `ALMACENADO` to `REDENCION_PARCIAL` (and eventually `AGOTADO` when all tokens are burned).

This is the final on-chain step of the product lifecycle for tokens that are redeemed physically.

---

## Actors Involved

- **👤 Buyer** — Token holder. KYC Tier 2+. Initiates the redemption from the frontend.
- **🤖 Backend** — Signs the `iniciarRedencion()` call on behalf of the buyer.
- **🏢 SRL Operator** — Coordinates customs export, courier, DUE, BL/AWB.
- **🔐 Oracle Safe** — Confirms export on-chain via `confirmarExportacion()`.
- **📜 RedemptionManager** — Escrow logic + state tracking per redemption.
- **📜 AssetVault** — Burns tokens on instruction from `RedemptionManager`.
- **📜 IdentityRegistry** — Checked by `RedemptionManager` for `canRedeem()` at initiation.

---

## Pre-conditions

- Lot `#7` in `AssetVault` with `estado == ALMACENADO` (or `REDENCION_PARCIAL` for subsequent redemptions).
- `confirmarAlmacenamiento()` was called (see flow 04, post-quality-attestation step).
- Buyer's wallet has `balanceOf(buyer, loteId) >= cantidadTokens`.
- `IdentityRegistry.canRedeem(buyer) == true`:
  - `tier >= 2` (MIN_KYC_TIER_PARA_REDIMIR)
  - not sanctioned, not frozen, not expired
- `RedemptionManager` contract address is set in `AssetVault.redemptionManager`.

---

## Pre-step: confirmarAlmacenamiento (from flow 04 conclusion)

Before redemptions can begin, the lot must be moved from `QUALITY_ATTESTED` to `ALMACENADO`:

```
🔐 OracleSafe --> 📜 AV     : confirmarAlmacenamiento(loteId=7, hashContratoDeposito, almacenAutorizado)
                              [ORACLE_ROLE]

📜 AV       --> 📜 AV       : validate estado == QUALITY_ATTESTED ✓
📜 AV       --> 📜 AV       : validate hashContratoDeposito valid ✓
📜 AV       --> 📜 AV       : validate almacenAutorizado != address(0) ✓
📜 AV       --> 📜 AV       : lote.hashContratoDeposito = hash  [EFFECT]
📜 AV       --> 📜 AV       : lote.estado = ALMACENADO  [QUALITY_ATTESTED → ALMACENADO]
📜 AV       ~~> 🚨 Event    : AlmacenamientoConfirmado(loteId=7, hashContratoDeposito, almacenAutorizado)
```

Gas estimated: ~80k.

---

## Sequence Diagram

```
--- Buyer initiates redemption ---

👤 Buyer    --> 🌐 Frontend  : /account/lots/7 → click "Redeem" → form: quantity=5, shipping address

🤖 Backend  --> 📜 IR        : canRedeem(BUYER_1)  [off-chain pre-check]
📜 IR       --> 🤖 Backend   : true (tier=2, active)

🤖 Backend  --> 📜 AV        : balanceOf(BUYER_1, 7)  [view]
📜 AV       --> 🤖 Backend   : 10 tokens

🤖 Backend  --> 🤖 Backend   : hash shipping data
                               datosEnvioHash = keccak256("BUYER_1 | Strasse 12 | 10115 Berlin | DE")
                                             = 0xDAT...

🤖 Backend  --> 📜 RM        : iniciarRedencion(loteId=7, cantidadTokens=5, datosEnvioHash=0xDAT...)
                              [caller=BUYER_1 or BACKEND — see note]
                              [nonReentrant, whenNotPaused]

NOTE: In the actual RedemptionManager code, iniciarRedencion() uses msg.sender as the comprador
      and validates canRedeem(msg.sender). This means the BUYER must call it directly
      (or a meta-tx relayer is used). The architecture doc (§23.4) shows the backend
      calling on behalf of the user, but the current code requires msg.sender == buyer for
      the KYC check. See CONFLICT note below.

📜 RM       --> 📜 IR        : canRedeem(msg.sender=BUYER_1)
📜 IR       --> 📜 RM        : true ✓

📜 RM       --> 📜 RM        : validate cantidadTokens > 0 ✓
📜 RM       --> 📜 RM        : validate datosEnvioHash != 0 ✓

📜 RM       --> 📜 AV        : lotes(7)  [view, check estado]
📜 AV       --> 📜 RM        : LoteMiel { estado: ALMACENADO, ... }
📜 RM       --> 📜 RM        : estado == ALMACENADO ✓

NOTE: RM does NOT verify buyer has sufficient balance before the call.
      Balance check is absent in current RedemptionManager code (line 94 comment:
      "Nota: requiere consulta a ERC1155 vía interface — simplificado para MVP").
      This is a known gap — if buyer redeems more tokens than they hold, the
      burn in confirmarExportacion will fail.

📜 RM       --> 📜 RM        : redencionId = _nextRedencionId++ = 1  [EFFECT]
📜 RM       --> 📜 RM        : _redenciones[1] = Redencion {
                                 comprador: BUYER_1,
                                 loteId: 7,
                                 cantidadTokens: 5,
                                 datosEnvioHash: 0xDAT...,
                                 estado: INICIADA,
                                 createdAt: block.timestamp }  [EFFECT]

📜 RM       ~~> 🚨 Event     : RedencionIniciada(redencionId=1, BUYER_1, loteId=7,
                                cantidadTokens=5, datosEnvioHash=0xDAT...)

🤖 Backend  <-- 📜 RM        : returns redencionId=1

🤖 Backend  --> 📜 DB        : INSERT redemption { id:1, status:"initiated", buyer:BUYER_1, ... }

👤 Buyer    --> 🌐 Frontend  : "Redemption #1 initiated. Awaiting export confirmation."

--- SRL coordinates export (off-chain) ---

🏢 SRL      --> 🏢 SRL       : Contact bonded warehouse → prepare shipment (5 tokens × 0.5 kg = 2.5 kg)
🏢 SRL      --> 🏛 Aduana    : Submit export declaration → receive DUE number "DUE-2026-007821"
🏢 SRL      --> 📦 Courier   : Book DHL Express → receive Airway Bill AWB-001234567
🏢 SRL      --> 🤖 Backend   : POST /oracle/redemption/1/export {
                                 dueNumero: "DUE-2026-007821",
                                 blawbFile: airwaybill.pdf }

🤖 Backend  --> 🤖 Backend   : hashBLAWB = SHA-256(airwaybill.pdf) = 0xBLAWB...
🤖 Backend  --> 🌐 Arweave   : upload airwaybill.pdf
🤖 Backend  --> 🤖 Backend   : Arweave readback verification ✓

--- Oracle Safe confirms export ---

🤖 Backend  --> 🔐 OracleSafe : createTransaction({
                                  to: RM_ADDR,
                                  data: RM.confirmarExportacion.encode(
                                    redencionId=1,
                                    dueNumero="DUE-2026-007821",
                                    hashBLAWB=0xBLAWB... ) })

🔐 Signer1 + Signer2 --> 🔐 OracleSafe : sign + execute

🔐 OracleSafe --> 📜 RM      : confirmarExportacion(redencionId=1, "DUE-2026-007821", 0xBLAWB...)
                              [ORACLE_ROLE, nonReentrant]

📜 RM       --> 📜 RM        : validate r.comprador != address(0) (redencion exists) ✓
📜 RM       --> 📜 RM        : validate r.estado == INICIADA ✓
📜 RM       --> 📜 RM        : validate dueNumero.length > 0 ✓
📜 RM       --> 📜 RM        : validate hashBLAWB != bytes32(0) ✓

📜 RM       --> 📜 RM        : r.estado = COMPLETADA  [EFFECT]
📜 RM       --> 📜 RM        : r.dueNumero = "DUE-2026-007821"  [EFFECT]
📜 RM       --> 📜 RM        : r.hashBLAWB = 0xBLAWB...  [EFFECT]
📜 RM       --> 📜 RM        : r.completedAt = block.timestamp  [EFFECT]

📜 RM       --> 📜 AV        : burnForRedemption(BUYER_1, loteId=7, cantidadTokens=5)
                              [external call — only callable by redemptionManager]

📜 AV       --> 📜 AV        : validate msg.sender == redemptionManager ✓
📜 AV       --> 📜 AV        : validate cantidadTokens > 0 ✓

📜 AV       --> 📜 AV        : kgRedimidos += 5 * 500 / 1000 = 2500 grams (2.5 kg)  [EFFECT]

📜 AV       --> 📜 AV        : lote.estado == ALMACENADO → set to REDENCION_PARCIAL  [EFFECT]

📜 AV       --> 📜 AV        : _burn(BUYER_1, loteId=7, 5)  [EFFECT]

  (inside _burn, _update is called)
  📜 AV._update --> 📜 AV    : isBurn=true, from=BUYER_1, to=address(0)
  📜 AV._update --> ERC1155  : super._update(BUYER_1, address(0), [7], [5])

🎫 Token    ~~> 🚨 Event     : TransferSingle(RM_ADDR, BUYER_1, 0x0, 7, 5)  (burn)

📜 AV       --> 📜 AV        : totalSupply(7) == 0? → NO (75 tokens remain)
                               Estado stays REDENCION_PARCIAL

📜 RM       ~~> 🚨 Event     : RedencionEnExportacion(redencionId=1, "DUE-2026-007821")
📜 RM       ~~> 🚨 Event     : RedencionCompletada(redencionId=1, 0xBLAWB...)

🤖 Backend  <-- 📜 RM        : tx confirmed

🤖 Backend  --> 📜 DB        : UPDATE redemption { status: "completed", txHash: "0x...", dueNumero, blawb }
🤖 Backend  --> 👤 Buyer     : email "Your honey (2.5 kg) has been shipped. AWB: DHL-001234567"
```

---

## Detailed Steps

### Step 1 — `confirmarAlmacenamiento()` (Oracle Safe)

Transitions lot from `QUALITY_ATTESTED` to `ALMACENADO`. Required before any redemption.

### Step 2 — Buyer Initiates Redemption

- **Actor:** Buyer (EOA) — must call directly (msg.sender validation)
- **Function called:** `RedemptionManager.iniciarRedencion(loteId, cantidadTokens, datosEnvioHash)`
- **Validations:**
  - `canRedeem(msg.sender)` → tier >= 2, not sanctioned, not frozen, not expired
  - `cantidadTokens > 0`
  - `datosEnvioHash != bytes32(0)`
  - `lote.estado == ALMACENADO or REDENCION_PARCIAL`
- **State changes:**
  - New `Redencion` record created, `estado = INICIADA`
  - `redencionId` incremented
- **Events emitted:** `RedencionIniciada(redencionId, comprador, loteId, cantidadTokens, datosEnvioHash)`
- **Gas estimated:** ~120k

**Note on "logical escrow":** Unlike a typical escrow, the tokens are NOT transferred to the `RedemptionManager` contract (which would require disabling the P2P transfer block selectively). Instead, the system tracks the obligation: the buyer is expected to hold the tokens until `confirmarExportacion()` burns them. The contract trusts that `balanceOf(buyer, loteId) >= cantidadTokens` will be true at burn time. If the buyer transfers (impossible) or another redemption drains their balance first, the burn in step 4 would revert.

### Step 3 — Off-chain Export Coordination

The SRL:
1. Retrieves the lot from the authorized bonded warehouse.
2. Packages for international export (IATA/IMDG compliance if applicable).
3. Submits DUE (Declaración Única de Exportación) to Bolivian customs.
4. Books courier (DHL, FedEx, or freight forwarder for bulk).
5. Receives BL (Bill of Lading for sea freight) or AWB (Airway Bill for air).
6. Uploads BL/AWB to the system.

### Step 4 — `confirmarExportacion()` on-chain

- **Actor:** Oracle Safe (ORACLE_ROLE)
- **Function called:** `RedemptionManager.confirmarExportacion(redencionId, dueNumero, hashBLAWB)`
- **Validations:**
  - Redemption exists and is `INICIADA`
  - `dueNumero` non-empty
  - `hashBLAWB != bytes32(0)`
- **Calls to AssetVault:** `assetVault.burnForRedemption(comprador, loteId, cantidadTokens)`
- **State changes in RM:** `estado = COMPLETADA`, DUE and BL/AWB hash recorded
- **State changes in AV:** `kgRedimidos` updated, `estado` → `REDENCION_PARCIAL` (or `AGOTADO` if last tokens)
- **Events emitted:**
  - `RedencionEnExportacion(redencionId, dueNumero)`
  - `RedencionCompletada(redencionId, hashBLAWB)`
  - `TransferSingle(RM_ADDR, buyer, 0x0, loteId, cantidadTokens)` from ERC-1155 burn
- **Gas estimated:** ~95k (includes burn in AssetVault)

### Step 5 — AGOTADO Transition (when all tokens burned)

When `totalSupply(loteId) == 0` after a burn, `burnForRedemption` sets `lote.estado = AGOTADO`.

This is a terminal state. No further operations are possible on the lot.

**⚠️ L-02 (audit finding):** No `LoteAgotado` event is emitted at this transition. Goldsky indexers must infer the AGOTADO state from the `TransferSingle` burn event + `totalSupply = 0` query. A dedicated event should be added.

---

## Cancellation Sub-flow

If the export cannot proceed (customs rejection, commodity inspection failure, force majeure):

```
🔐 OracleSafe --> 📜 RM     : cancelarRedencion(redencionId=1, reason=keccak256("customs_rejected"))
                              [ORACLE_ROLE]

📜 RM       --> 📜 RM       : validate r.estado == INICIADA ✓
📜 RM       --> 📜 RM       : r.estado = CANCELADA  [EFFECT]
📜 RM       --> 📜 RM       : r.cancelReason = reason  [EFFECT]
📜 RM       ~~> 🚨 Event    : RedencionCancelada(redencionId=1, reason)
```

After cancellation, the buyer's tokens remain in their wallet. They can initiate a new redemption when the issue is resolved.

**Note:** `cancelarRedencion` does NOT call `assetVault.returnRedemptionTokens()` (that function is not implemented in the current `AssetVault.sol`). Since tokens were never physically moved to the RM contract, no "return" is needed — tokens stayed with the buyer throughout.

---

## Post-conditions

**After `iniciarRedencion()`:**
- `RedemptionManager._redenciones[redencionId].estado == INICIADA`
- Buyer's tokens still in their wallet (logical escrow only)

**After `confirmarExportacion()`:**
- `Redencion.estado == COMPLETADA`
- `AssetVault.balanceOf(buyer, loteId) -= cantidadTokens` (burned)
- `lote.kgRedimidos += kgFromBurn`
- `lote.estado == REDENCION_PARCIAL` (or `AGOTADO` if last)
- DUE number and BL/AWB hash permanently on-chain
- Buyer's honey shipped physically

---

## Error Cases

| Cause | Result | Reverts with |
|-------|--------|-------------|
| Buyer KYC tier < 2 | redemption blocked | `CannotRedeem()` |
| Lot not in ALMACENADO/REDENCION_PARCIAL | blocked | `LoteNotInAlmacenado()` |
| `cantidadTokens == 0` | blocked | `CantidadCero()` |
| `datosEnvioHash == 0` | blocked | `InvalidHash()` |
| `confirmarExportacion` on non-INICIADA redemption | blocked | `RedencionAlreadyFinalized()` |
| `hashBLAWB == 0` | blocked | `InvalidHash()` |
| Empty `dueNumero` | blocked | `EmptyDUE()` |
| `burnForRedemption` caller is not RM | blocked | `OnlyRedemptionCanBurn()` |
| Buyer balance < cantidadTokens at burn time | blocked | ERC-1155 burn reverts |
| RedemptionManager paused | `iniciarRedencion` blocked | `EnforcedPause()` |

---

## Conflicts Detected

**CONFLICT: Who calls `iniciarRedencion()`?**

`ARQUITECTURA-TECNICA-MVP.md §23.4` step 5 says: "Backend ejecuta `RedemptionManager.iniciarRedencion()` (signed)". This implies the backend calls on behalf of the user.

However, `RedemptionManager.sol:83` does `identityRegistry.canRedeem(msg.sender)` — using `msg.sender` as the buyer. If the backend calls this function, `msg.sender = BACKEND_SIGNER_ADDR`, and the KYC check is against the backend address (which has tier 0).

The current code requires the buyer to be the direct caller. This conflicts with the "backend abstracts the wallet interaction" UX model described in the architecture.

Resolution options:
- (A) Buyer calls directly (requires gas — may conflict with gasless UX).
- (B) Add a `buyer` parameter to `iniciarRedencion`, callable by `BACKEND_SIGNER_ROLE`: `iniciarRedencion(loteId, buyer, cantidadTokens, datosEnvioHash)`.
- (C) Use Plume Smart Wallets / meta-transactions to abstract gas but preserve `msg.sender`.

The flow document assumes option (B) is the intended design (matching the architecture doc), but the current code implements option (A). This is a **CONFLICT** that requires a code fix.

---

## Concrete Numeric Example

```
Lot #7 — Bolivian monofloral rosemary honey (ALMACENADO)
Total supply:      80 tokens
Reserve released:  240 USDC (already transferred to producer at QUALITY_ATTESTED)

Redemption #1:
  Buyer:           BUYER_1 = 0xABC... (Tier 2, jurisdiction DE)
  Quantity:        5 tokens = 2.5 kg honey
  Shipping:        DHL Express, Berlin DE → estimated 4-5 business days
  DUE number:      DUE-2026-007821  (Bolivian customs)
  AWB:             724-12345678 DHL  (IATA Airway Bill)
  hashBLAWB:       keccak256(AWB-724-12345678.pdf) = 0xBLAWB1...

Post-tx state:
  BUYER_1.balance(7)     = 10 - 5 = 5 tokens remaining
  totalSupply(7)         = 80 - 5 = 75 tokens
  lote.kgRedimidos       = 2500 grams (2.5 kg)
  lote.estado            = REDENCION_PARCIAL

Redemption #2 (different buyer):
  BUYER_2 redeems 75 tokens → totalSupply = 0 → estado = AGOTADO

Gas total for full redemption cycle:
  confirmarAlmacenamiento: ~80k
  iniciarRedencion:        ~120k
  confirmarExportacion:    ~95k (+ ~50k for burn in AV)
  Total: ~345k ≈ USD 0.17
```

Cross-reference: see `06-failed-lot-refund.md` for the alternative exit path when the lot fails.
