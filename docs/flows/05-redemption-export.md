# Flow 05: Redemption + DUE + BL/AWB → Token Burn

## Executive Summary

A token holder with KYC Tier 2 or higher initiates a physical redemption by calling `iniciarRedencion()` directly. Tokens are NOT transferred — a logical lock (`_tokensLockedFor`) is recorded to prevent double-redemption. The Oracle Safe then registers the DUE (Bolivian customs export number) via `confirmarExportacion()`, transitioning the redemption to `EN_EXPORTACION`. Once the BL/AWB is received, `completarRedencion()` permanently burns the tokens via `AssetVault.burnForRedemption()`. The lot transitions from `ALMACENADO` to `REDENCION_PARCIAL` (and eventually `AGOTADO` when all tokens are burned).

**Model: Option B — Lock Acumulator.** The functions `lockForRedemption`, `burnRedemptionTokens`, and `returnRedemptionTokens` do NOT exist. Tokens never leave the buyer's wallet until the burn in `completarRedencion`.

---

## Actors Involved

- **👤 Buyer** — Token holder. KYC Tier 2+. Calls `iniciarRedencion()` directly (msg.sender is the buyer). No backend role involved.
- **🏢 SRL Operator** — Coordinates customs export, courier, DUE, BL/AWB off-chain.
- **🔐 Oracle Safe** — Calls `confirmarExportacion()` and `completarRedencion()` (ORACLE_ROLE, Safe 2-de-3).
- **📜 RedemptionManager** — Lock accounting + 2-phase state tracking per redemption.
- **📜 AssetVault** — Burns tokens when instructed by `RedemptionManager` via `burnForRedemption()`.
- **📜 IdentityRegistry** — Checked by `RedemptionManager` for `canRedeem(msg.sender)` at initiation.

> **Note:** The Backend is NOT involved in the on-chain redemption initiation. `iniciarRedencion` takes no `buyer` parameter — it uses `msg.sender`. There is no `BACKEND_SIGNER_ROLE` in `RedemptionManager`. The backend only performs off-chain tasks (hashing the shipping data, uploading documents to Arweave, triggering the Oracle Safe workflow via the API).

---

## Pre-conditions

- Lot `#7` in `AssetVault` with `estado == ALMACENADO` (or `REDENCION_PARCIAL` for subsequent redemptions).
- `confirmarAlmacenamiento()` was called (see flow 04, post-quality-attestation step).
- Buyer's wallet has `balanceOf(buyer, loteId) >= cantidadTokens`.
- `IdentityRegistry.canRedeem(buyer) == true`:
  - `tier >= 2` (MIN_KYC_TIER_PARA_REDIMIR)
  - not sanctioned, not frozen, not expired
- `RedemptionManager` contract address is set in `AssetVault.redemptionManager`.
- `tokensLockedFor(buyer, loteId) + cantidadTokens <= balanceOf(buyer, loteId)` (no over-commit).

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
--- Buyer initiates redemption (calls directly — no backend intermediary on-chain) ---

👤 Buyer    --> 🌐 Frontend  : /account/lots/7 → click "Redeem" → form: quantity=5, shipping address

🌐 Frontend --> 🌐 Frontend  : datosEnvioHash = keccak256("BUYER_1 | Strasse 12 | 10115 Berlin | DE")
                                             = 0xDAT...

👤 Buyer    --> 📜 RM        : iniciarRedencion(loteId=7, cantidadTokens=5, datosEnvioHash=0xDAT...)
                              [msg.sender == BUYER_1 — no buyer param, no role required]
                              [nonReentrant, whenNotPaused]

📜 RM       --> 📜 IR        : canRedeem(msg.sender=BUYER_1)  [check 1: KYC tier >= 2]
📜 IR       --> 📜 RM        : true ✓

📜 RM       --> 📜 RM        : validate cantidadTokens > 0 ✓  [check 2]
📜 RM       --> 📜 RM        : validate datosEnvioHash != bytes32(0) ✓  [check 3]

📜 RM       --> 📜 AV        : lotes(7)  [check 4: lote exists + estado]
📜 AV       --> 📜 RM        : LoteMiel { productorSRL: 0xSRL..., estado: ALMACENADO, ... }
📜 RM       --> 📜 RM        : productorSRL != address(0) → lote exists ✓
📜 RM       --> 📜 RM        : estado == ALMACENADO ✓

📜 RM       --> 📜 AV        : totalSupply(7)  [check 5: defense-in-depth RM-19]
📜 AV       --> 📜 RM        : 80
📜 RM       --> 📜 RM        : cantidadTokens (5) <= 80 ✓

📜 RM       --> 📜 AV        : balanceOf(BUYER_1, 7)  [check 6: available balance RM-01/RM-02]
📜 AV       --> 📜 RM        : 10 tokens
📜 RM       --> 📜 RM        : _tokensLockedFor[7][BUYER_1] = 0 (no prior lock)
📜 RM       --> 📜 RM        : 0 + 5 <= 10 → balance sufficient ✓

--- Effects (all checks passed, no reentrancy risk — no mutant external calls after this point) ---

📜 RM       --> 📜 RM        : _tokensLockedFor[7][BUYER_1] = 0 + 5 = 5  [EFFECT: lock registered]
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

👤 Buyer    <-- 📜 RM        : returns redencionId=1

🤖 Backend  --> 📜 DB        : INSERT redemption { id:1, status:"initiated", buyer:BUYER_1, ... }
                               (backend listens to RedencionIniciada event)

👤 Buyer    --> 🌐 Frontend  : "Redemption #1 initiated. Awaiting export confirmation."

--- SRL coordinates export (off-chain) ---

🏢 SRL      --> 🏢 SRL       : Contact bonded warehouse → prepare shipment (5 tokens × 0.5 kg = 2.5 kg)
🏢 SRL      --> 🏛 Aduana    : Submit export declaration → receive DUE number "DUE-2026-007821"
🏢 SRL      --> 📦 Courier   : Book DHL Express → receive Airway Bill AWB-001234567
🏢 SRL      --> 🤖 Backend   : POST /oracle/redemption/1/confirm-export {
                                 dueNumero: "DUE-2026-007821",
                                 blawbFile: airwaybill.pdf }

🤖 Backend  --> 🤖 Backend   : hashBLAWB = keccak256(airwaybill.pdf) = 0xBLAWB...
🤖 Backend  --> 🌐 Arweave   : upload airwaybill.pdf
🤖 Backend  --> 🤖 Backend   : Arweave readback verification ✓

--- Oracle Safe confirms DUE (Phase 1 of 2: INICIADA → EN_EXPORTACION, NO burn yet) ---

🤖 Backend  --> 🔐 OracleSafe : createTransaction({
                                  to: RM_ADDR,
                                  data: RM.confirmarExportacion.encode(
                                    redencionId=1,
                                    dueNumero="DUE-2026-007821" ) })
                                NOTE: NO hashBLAWB here — that arrives in completarRedencion

🔐 Signer1 + Signer2 --> 🔐 OracleSafe : sign + execute

🔐 OracleSafe --> 📜 RM      : confirmarExportacion(redencionId=1, "DUE-2026-007821")
                              [ORACLE_ROLE — no whenNotPaused by design (§6.13.8)]

📜 RM       --> 📜 RM        : validate r.comprador != address(0) → redencion exists ✓
📜 RM       --> 📜 RM        : validate r.estado == INICIADA ✓
📜 RM       --> 📜 RM        : validate dueNumero.length > 0 ✓
📜 RM       --> 📜 RM        : validate dueNumero.length <= 64 ✓

📜 RM       --> 📜 RM        : r.estado = EN_EXPORTACION  [INICIADA → EN_EXPORTACION]  [EFFECT]
📜 RM       --> 📜 RM        : r.dueNumero = "DUE-2026-007821"  [EFFECT]
                              NOTE: NO hashDUE field. NO burn. NO _tokensLockedFor change.

📜 RM       ~~> 🚨 Event     : RedencionEnExportacion(redencionId=1, actor=OracleSafe_addr,
                                dueNumero="DUE-2026-007821")

--- Oracle Safe completes redemption (Phase 2 of 2: EN_EXPORTACION → COMPLETADA, burn here) ---

🤖 Backend  --> 🔐 OracleSafe : createTransaction({
                                  to: RM_ADDR,
                                  data: RM.completarRedencion.encode(
                                    redencionId=1,
                                    hashBLAWB=0xBLAWB... ) })

🔐 Signer1 + Signer2 --> 🔐 OracleSafe : sign + execute

🔐 OracleSafe --> 📜 RM      : completarRedencion(redencionId=1, hashBLAWB=0xBLAWB...)
                              [ORACLE_ROLE, nonReentrant — no whenNotPaused by design]

📜 RM       --> 📜 RM        : validate r.comprador != address(0) ✓
📜 RM       --> 📜 RM        : validate r.estado == EN_EXPORTACION ✓
📜 RM       --> 📜 RM        : validate hashBLAWB != bytes32(0) ✓

📜 RM       --> 📜 AV        : balanceOf(BUYER_1, 7)  [RM-04 pre-validation — fail fast]
📜 AV       --> 📜 RM        : 10 tokens >= 5 ✓

--- CEI: Effects before the external burn call ---

📜 RM       --> 📜 RM        : _tokensLockedFor[7][BUYER_1] -= 5 → 0  [EFFECT: lock released]
📜 RM       --> 📜 RM        : r.estado = COMPLETADA  [EN_EXPORTACION → COMPLETADA]  [EFFECT]
📜 RM       --> 📜 RM        : r.hashBLAWB = 0xBLAWB...  [EFFECT]
📜 RM       --> 📜 RM        : r.completedAt = block.timestamp  [EFFECT]

--- Interactions: burn via AssetVault ---

📜 RM       --> 📜 AV        : burnForRedemption(BUYER_1, loteId=7, cantidadTokens=5)
                              [external call — only callable by redemptionManager]

📜 AV       --> 📜 AV        : validate msg.sender == redemptionManager ✓
📜 AV       --> 📜 AV        : validate cantidadTokens > 0 ✓

📜 AV       --> 📜 AV        : kgRedimidos += 5 × 500 / 1000 = 2500 grams (2.5 kg)  [EFFECT]

📜 AV       --> 📜 AV        : lote.estado == ALMACENADO → set to REDENCION_PARCIAL  [EFFECT]

📜 AV       --> 📜 AV        : _burn(BUYER_1, loteId=7, 5)  [EFFECT]

  (inside _burn, _update is called)
  📜 AV._update --> 📜 AV    : isBurn=true, from=BUYER_1, to=address(0)
  📜 AV._update --> ERC1155  : super._update(BUYER_1, address(0), [7], [5])

🎫 Token    ~~> 🚨 Event     : TransferSingle(RM_ADDR, BUYER_1, 0x0, 7, 5)  (burn)

📜 AV       --> 📜 AV        : totalSupply(7) == 0? → NO (75 tokens remain)
                               Estado stays REDENCION_PARCIAL

📜 RM       ~~> 🚨 Event     : RedencionCompletada(redencionId=1, actor=OracleSafe_addr, hashBLAWB=0xBLAWB...)

🤖 Backend  <-- 📜 RM        : tx confirmed (listens to RedencionCompletada event)

🤖 Backend  --> 📜 DB        : UPDATE redemption { status: "completed", txHash: "0x...", dueNumero, blawb }
🤖 Backend  --> 👤 Buyer     : email "Your honey (2.5 kg) has been shipped. AWB: DHL-001234567"
```

---

## Detailed Steps

### Step 1 — `confirmarAlmacenamiento()` (Oracle Safe)

Transitions lot from `QUALITY_ATTESTED` to `ALMACENADO`. Required before any redemption.

### Step 2 — Buyer Initiates Redemption

- **Actor:** Buyer (EOA) — calls directly. `msg.sender` is the buyer. No `buyer` parameter exists. No role required.
- **Function called:** `RedemptionManager.iniciarRedencion(uint256 loteId, uint256 cantidadTokens, bytes32 datosEnvioHash)`
- **Modifiers:** `nonReentrant`, `whenNotPaused`
- **Validations (in order):**
  1. `canRedeem(msg.sender)` → tier >= 2, not sanctioned, not frozen, not expired → `CannotRedeem()`
  2. `cantidadTokens > 0` → `CantidadCero()`
  3. `datosEnvioHash != bytes32(0)` → `InvalidHash()`
  4. `lote.productorSRL != address(0)` → `LoteNotFound(loteId)`
  5. `lote.estado == ALMACENADO || REDENCION_PARCIAL` → `LoteNotInAlmacenado()`
  6. `cantidadTokens <= totalSupply(loteId)` → `CantidadExcedeSupply()` (defense-in-depth RM-19)
  7. `_tokensLockedFor[loteId][msg.sender] + cantidadTokens <= balanceOf(msg.sender, loteId)` → `BalanceInsuficiente()` (RM-01/RM-02)
- **State changes:**
  - `_tokensLockedFor[loteId][msg.sender] += cantidadTokens` (lock accumulator)
  - New `Redencion` record created with `estado = INICIADA`
  - `_nextRedencionId` incremented
- **Events emitted:** `RedencionIniciada(redencionId, comprador, loteId, cantidadTokens, datosEnvioHash)`
- **Gas estimated:** ~120k

**Option B Lock Acumulator:** Tokens remain in the buyer's wallet. The lock is a purely accounting construct in `_tokensLockedFor`. It prevents double-redemption by ensuring that the sum of all active locked amounts does not exceed the buyer's real balance. No tokens are transferred to `RedemptionManager`.

### Step 3 — Off-chain Export Coordination

The SRL:
1. Retrieves the lot from the authorized bonded warehouse.
2. Packages for international export (IATA/IMDG compliance if applicable).
3. Submits DUE (Declaración Única de Exportación) to Bolivian customs (SENASAG).
4. Books courier (DHL, FedEx, or freight forwarder for bulk).
5. Receives BL (Bill of Lading for sea freight) or AWB (Airway Bill for air).
6. Uploads BL/AWB to the system via backend API.

### Step 4 — `confirmarExportacion()` on-chain (Phase 1 of 2)

- **Actor:** Oracle Safe (ORACLE_ROLE)
- **Function called:** `RedemptionManager.confirmarExportacion(uint256 redencionId, string calldata dueNumero)`
- **Modifiers:** `onlyRole(ORACLE_ROLE)` — **no `whenNotPaused`** by design (§6.13.8: in-flight redemptions must be resolvable during an incident)
- **Validations:**
  - Redemption exists: `r.comprador != address(0)` → `RedencionNotIniciada()`
  - `r.estado == INICIADA` → `RedencionAlreadyFinalized()`
  - `dueNumero.length > 0` → `EmptyDUE()`
  - `dueNumero.length <= MAX_DUE_NUMERO_LENGTH (64)` → `DUENumeroTooLong()`
- **State changes in RM:**
  - `r.estado = EN_EXPORTACION` (INICIADA → EN_EXPORTACION)
  - `r.dueNumero = dueNumero`
  - `_tokensLockedFor` is NOT changed here
- **NO burn in this step.** Tokens remain locked in buyer's wallet.
- **Events emitted:** `RedencionEnExportacion(redencionId, actor, dueNumero)`
- **Gas estimated:** ~45k

> **ADR-017:** `hashDUE` does NOT exist. The DUE number is stored as a `string` (human-readable customs number). The BL/AWB hash arrives separately in `completarRedencion`.

### Step 5 — `completarRedencion()` on-chain (Phase 2 of 2)

- **Actor:** Oracle Safe (ORACLE_ROLE)
- **Function called:** `RedemptionManager.completarRedencion(uint256 redencionId, bytes32 hashBLAWB)`
- **Modifiers:** `onlyRole(ORACLE_ROLE)`, `nonReentrant` — **no `whenNotPaused`** by design (§6.13.8)
- **Validations:**
  - `r.comprador != address(0)` → `RedencionNotIniciada()`
  - `r.estado == EN_EXPORTACION` → `NotInExportacion()`
  - `hashBLAWB != bytes32(0)` → `InvalidHash()`
  - `balanceOf(r.comprador, r.loteId) >= r.cantidadTokens` → `BalanceInsuficiente()` (RM-04 pre-validation)
- **State changes in RM (CEI — Effects before Interactions):**
  - `_tokensLockedFor[r.loteId][r.comprador] -= r.cantidadTokens` (lock released)
  - `r.estado = COMPLETADA` (EN_EXPORTACION → COMPLETADA)
  - `r.hashBLAWB = hashBLAWB`
  - `r.completedAt = block.timestamp`
- **Calls to AssetVault:** `assetVault.burnForRedemption(comprador, loteId, cantidadTokens)` (Interaction, after Effects)
- **State changes in AV:** `kgRedimidos` updated, `estado` → `REDENCION_PARCIAL` (or `AGOTADO` if last tokens), tokens burned
- **Events emitted:**
  - `RedencionCompletada(redencionId, actor, hashBLAWB)`
  - `TransferSingle(RM_ADDR, buyer, 0x0, loteId, cantidadTokens)` from ERC-1155 burn
- **Gas estimated:** ~95k (includes burn in AssetVault)

### Step 6 — AGOTADO Transition (when all tokens burned)

When `totalSupply(loteId) == 0` after a burn, `burnForRedemption` sets `lote.estado = AGOTADO`.

This is a terminal state. No further operations are possible on the lot.

**L-02 (audit finding):** No `LoteAgotado` event is emitted at this transition. Goldsky indexers must infer the AGOTADO state from the `TransferSingle` burn event + `totalSupply = 0` query. A dedicated event should be added in a future iteration.

---

## Cancellation Sub-flow

Cancellation can occur from **INICIADA or EN_EXPORTACION** (ADR-017 operational checkpoint: if goods are held at customs after DUE has been issued, Oracle or Compliance can still cancel).

### Who can cancel

| Actor | Condition |
|-------|-----------|
| ORACLE_ROLE | Always, from INICIADA or EN_EXPORTACION |
| COMPLIANCE_OFFICER_ROLE | Always, from INICIADA or EN_EXPORTACION (ADR-015 + CONTRACT-SPECS §6.3) |
| Buyer (msg.sender == r.comprador) | Only after `REDENCION_TIMEOUT = 60 days` from `r.createdAt` (ADR-015 escape valve, closes RM-06/RM-07 HIGH findings) |

### Cancellation from INICIADA (e.g. customs pre-DUE rejection)

```
🔐 OracleSafe --> 📜 RM     : cancelarRedencion(redencionId=1, reason=keccak256("customs_rejected"))
                              [ORACLE_ROLE — no role modifier, access control is inline]
                              [nonReentrant — no whenNotPaused by design]

📜 RM       --> 📜 RM       : validate r.comprador != address(0) ✓
📜 RM       --> 📜 RM       : validate r.estado == INICIADA ✓
📜 RM       --> 📜 RM       : validate reason != bytes32(0) ✓
📜 RM       --> 📜 RM       : isOracle = true ✓ (access control passes)

📜 RM       --> 📜 RM       : _tokensLockedFor[7][BUYER_1] -= 5 → 0  [EFFECT: lock released]
📜 RM       --> 📜 RM       : r.estado = CANCELADA  [EFFECT]
📜 RM       --> 📜 RM       : r.cancelReason = reason  [EFFECT]
📜 RM       --> 📜 RM       : r.completedAt = block.timestamp  [EFFECT]

📜 RM       ~~> 🚨 Event    : RedencionCancelada(redencionId=1, actor=OracleSafe_addr, reason)
```

### Cancellation from EN_EXPORTACION (e.g. customs rejection post-DUE)

```
🏛 Compliance --> 📜 RM    : cancelarRedencion(redencionId=1, reason=keccak256("aduana_rechazada"))
                              [COMPLIANCE_OFFICER_ROLE]

📜 RM       --> 📜 RM       : validate r.estado == EN_EXPORTACION ✓ (INICIADA or EN_EXPORTACION both valid)
📜 RM       --> 📜 RM       : isCompliance = true ✓
📜 RM       --> 📜 RM       : [same Effects as above — lock released, CANCELADA]

📜 RM       ~~> 🚨 Event    : RedencionCancelada(redencionId=1, actor=Compliance_addr, reason)
```

### Buyer self-cancel after 60-day timeout

```
👤 Buyer    --> 📜 RM       : cancelarRedencion(redencionId=1, reason=keccak256("timeout_expired"))

📜 RM       --> 📜 RM       : isOracle = false, isCompliance = false
📜 RM       --> 📜 RM       : isBuyerAfterTimeout = (msg.sender == r.comprador &&
                                                      block.timestamp >= r.createdAt + 60 days) ✓
📜 RM       --> 📜 RM       : [same Effects — lock released, CANCELADA]

📜 RM       ~~> 🚨 Event    : RedencionCancelada(redencionId=1, actor=BUYER_1, reason)
```

After cancellation, the buyer's tokens remain in their wallet (the lock accumulator decrements — there was no physical escrow). They can initiate a new redemption when the issue is resolved.

**Note:** `cancelarRedencion` does NOT call any `returnRedemptionTokens()` or similar function. That function does not exist in either `RedemptionManager` or `AssetVault`. Since tokens never left the buyer's wallet, no return is needed — decrementing `_tokensLockedFor` is sufficient.

---

## `EstadoRedencion` state machine

```
                     confirmarExportacion()
INICIADA ──────────────────────────────────► EN_EXPORTACION ──────► COMPLETADA
    │                                               │        completar
    │  cancelarRedencion()                          │  cancelarRedencion()
    │  (Oracle | Compliance | buyer ≥60d)           │  (Oracle | Compliance only)
    ▼                                               ▼
CANCELADA ◄─────────────────────────────────────── CANCELADA
```

Valid terminal states: `COMPLETADA`, `CANCELADA`.

---

## Post-conditions

**After `iniciarRedencion()`:**
- `RedemptionManager._redenciones[redencionId].estado == INICIADA`
- `_tokensLockedFor[loteId][buyer] == previous_locked + cantidadTokens`
- Buyer's tokens still in their wallet — no transfer occurred

**After `confirmarExportacion()`:**
- `Redencion.estado == EN_EXPORTACION`
- `Redencion.dueNumero == "DUE-2026-007821"` (human-readable string, no hashDUE)
- `_tokensLockedFor` unchanged — lock is still held
- Buyer's tokens still in their wallet — no burn yet

**After `completarRedencion()`:**
- `Redencion.estado == COMPLETADA`
- `Redencion.hashBLAWB == 0xBLAWB...`
- `_tokensLockedFor[loteId][buyer] == 0` (lock released)
- `AssetVault.balanceOf(buyer, loteId) -= cantidadTokens` (burned)
- `lote.kgRedimidos += kgFromBurn`
- `lote.estado == REDENCION_PARCIAL` (or `AGOTADO` if last)
- DUE number and BL/AWB hash permanently on-chain

---

## Error Cases

| Cause | Result | Reverts with |
|-------|--------|-------------|
| Buyer KYC tier < 2, sanctioned, frozen, or expired | `iniciarRedencion` blocked | `CannotRedeem()` |
| Lot does not exist (productorSRL == 0) | `iniciarRedencion` blocked | `LoteNotFound(loteId)` |
| Lot not in ALMACENADO or REDENCION_PARCIAL | `iniciarRedencion` blocked | `LoteNotInAlmacenado()` |
| `cantidadTokens == 0` | `iniciarRedencion` blocked | `CantidadCero()` |
| `cantidadTokens > totalSupply(loteId)` | `iniciarRedencion` blocked | `CantidadExcedeSupply()` |
| `locked + cantidadTokens > balanceOf` | `iniciarRedencion` blocked | `BalanceInsuficiente()` |
| `datosEnvioHash == bytes32(0)` | `iniciarRedencion` blocked | `InvalidHash()` |
| `confirmarExportacion` on non-existent redemption | blocked | `RedencionNotIniciada()` |
| `confirmarExportacion` on non-INICIADA redemption | blocked | `RedencionAlreadyFinalized()` |
| Empty `dueNumero` | `confirmarExportacion` blocked | `EmptyDUE()` |
| `dueNumero.length > 64` | `confirmarExportacion` blocked | `DUENumeroTooLong()` |
| `completarRedencion` on non-EN_EXPORTACION redemption | blocked | `NotInExportacion()` |
| `hashBLAWB == bytes32(0)` | `completarRedencion` blocked | `InvalidHash()` |
| Buyer balance < cantidadTokens at completion time | `completarRedencion` blocked | `BalanceInsuficiente()` |
| `cancelarRedencion` on COMPLETADA or CANCELADA | blocked | `RedencionAlreadyFinalized()` |
| `cancelarRedencion` — caller has no role and is not buyer-after-timeout | blocked | `OnlyAuthorizedCanceler()` |
| `cancelarRedencion` with `reason == bytes32(0)` | blocked | `EmptyReason()` |
| `burnForRedemption` caller is not redemptionManager | `AssetVault` blocked | `OnlyRedemptionCanBurn()` |
| `iniciarRedencion` when RM is paused | blocked | `EnforcedPause()` |

---

## Concrete Numeric Example

```
Lot #7 — Bolivian monofloral rosemary honey (ALMACENADO)
Total supply:      80 tokens
Reserve released:  240 USDC (already transferred to producer at QUALITY_ATTESTED)

Redemption #1 — Full 2-phase flow:
  Buyer:           BUYER_1 = 0xABC... (Tier 2, jurisdiction DE)
  Quantity:        5 tokens = 2.5 kg honey
  Shipping:        DHL Express, Berlin DE → estimated 4-5 business days
  datosEnvioHash:  keccak256("BUYER_1 | Strasse 12 | 10115 Berlin | DE") = 0xDAT...

  Phase 1 — confirmarExportacion:
    DUE number:    "DUE-2026-007821"  (Bolivian customs — stored as string, NO hashDUE)
    Estado after:  EN_EXPORTACION

  Phase 2 — completarRedencion:
    hashBLAWB:     keccak256(AWB-724-12345678.pdf) = 0xBLAWB1...
    Estado after:  COMPLETADA, tokens burned

Post-tx state:
  BUYER_1.balance(7)              = 10 - 5 = 5 tokens remaining
  totalSupply(7)                  = 80 - 5 = 75 tokens
  lote.kgRedimidos                = 2500 grams (2.5 kg)
  lote.estado                     = REDENCION_PARCIAL
  _tokensLockedFor[7][BUYER_1]    = 0 (released)

Redemption #2 (different buyer):
  BUYER_2 redeems 75 tokens → totalSupply = 0 → estado = AGOTADO

Gas total for full redemption cycle:
  confirmarAlmacenamiento: ~80k
  iniciarRedencion:        ~120k
  confirmarExportacion:    ~45k
  completarRedencion:      ~95k (includes burn in AV)
  Total: ~340k ≈ USD 0.17
```

Cross-reference: see `06-failed-lot-refund.md` for the alternative exit path when the lot fails.
