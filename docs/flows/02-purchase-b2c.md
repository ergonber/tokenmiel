# Flow 02: B2C Purchase via MoonPay → Token Mint

## Executive Summary

A retail buyer discovers a honey lot on the platform, selects the quantity of tokens, and pays via MoonPay (credit card → USDC). The backend confirms the payment, deducts a technical reserve (15-20% of payment), transfers the net amount to the producer SRL wallet, and mints ERC-1155 tokens to the buyer's wallet. The entire on-chain operation is one transaction signed by the backend signer (HSM), not by the buyer. The buyer only needs a wallet address — gas is paid by the backend.

This flow requires an active lot in `PREVENTA` state. See `01-deployment.md` and the `crearLote` prerequisite below.

---

## Actors Involved

- **👤 Buyer** — End user. Needs a wallet (EOA or Plume Smart Wallet) and has completed KYC Tier 1. Country: EU or LATAM.
- **🤖 Backend** — Backend signer wallet (HSM). Holds `BACKEND_SIGNER_ROLE` on `AssetVault`.
- **📜 AssetVault** — ERC-1155 contract. Manages lot state and mints tokens.
- **📜 IdentityRegistry** — KYC whitelist consulted by `AssetVault` before every mint.
- **💰 MoonPay** — Payment provider. Converts card payment to USDC. Delivers USDC to backend's operational wallet.
- **🏢 Producer SRL** — Honey producer. Receives USDC net amount after reserve deduction.

---

## Pre-conditions

- `IdentityRegistry` has the buyer's wallet with `tier >= 1`, not sanctioned, not frozen, not expired.
- `AssetVault` has an active lot with `estado == LoteEstado.PREVENTA`.
- Lot `kgDisponibles > 0` (tokens available).
- Backend has pre-transferred USDC (from MoonPay payout) to the `AssetVault` contract before calling `comprar()`.

> **Architecture note:** The contract does NOT pull USDC from MoonPay. The payment flow is: MoonPay → backend operational wallet → `AssetVault` contract address → `comprar()` distributes internally. The `comprar()` function assumes USDC is already in the contract.

---

## Sequence Diagram

```
👤 Buyer    --> 🌐 Frontend  : GET /catalog/:lotId → select quantity (e.g. 10 tokens)

👤 Buyer    --> 🤖 Backend   : POST /payments/intent { lotId: 7, amount: 10, method: "moonpay" }

🤖 Backend  --> 📜 IR        : canMint(buyer)  [view, off-chain pre-check]
📜 IR       --> 🤖 Backend   : true (tier=1, not sanctioned, not frozen, not expired)

🤖 Backend  --> 📜 AV        : kgDisponibles(7)  [view]
📜 AV       --> 🤖 Backend   : 80 kg remaining

🤖 Backend  --> 📜 DB        : INSERT payment_intent { status: "pending", ... }

🤖 Backend  --> 👤 Buyer     : { moonpayUrl: "https://buy.moonpay.com/?..." }

👤 Buyer    --> 💰 MoonPay   : complete card payment (USD 200 for 10 tokens × USD 20)

💰 MoonPay  --> 🤖 Backend   : POST /webhooks/moonpay { type: "transaction_completed", amount: 200 USDC }
🤖 Backend  --> 🤖 Backend   : validate HMAC-SHA256 signature
🤖 Backend  --> 📜 DB        : UPDATE payment_intent { status: "confirmed" }

🤖 Backend  --> 📜 AV        : USDC.transfer(assetVaultAddress, 200_000000)  [SafeERC20]
                               (transfer 200 USDC to contract BEFORE calling comprar)

🤖 Backend  --> 📜 AV        : comprar(loteId=7, cantidadTokens=10, comprador=BUYER_1,
                                       montoUSDCPagado=200_000000, paymentRefHash=keccak256("MP-TX-9821"))
                               [BACKEND_SIGNER_ROLE, nonReentrant, whenNotPaused]

📜 AV       --> 📜 AV        : validate lote.estado == PREVENTA  ✓
📜 AV       --> 📜 AV        : validate cantidadTokens > 0  ✓
📜 AV       --> 📜 AV        : validate paymentRefHash != 0  ✓

📜 AV       --> 📜 IR        : canMint(BUYER_1)  [external call]
📜 IR       --> 📜 AV        : true

📜 AV       --> 📜 AV        : kgYaVendidos = totalSupply(7) * 500 / 1000 = 40 kg
📜 AV       --> 📜 AV        : kgSolicitados = 10 * 500 / 1000 = 5 kg
📜 AV       --> 📜 AV        : 40 + 5 > 100 kg? → false ✓

NOTE ⚠️ H-02: This calculation truncates for odd token amounts. If kgSolicitados=1,
      1*500/1000=0, allowing silent capacity overshoot. Fix required before mainnet.

📜 AV       --> 📜 AV        : montoEsperado = 10 * 20_000000 = 200_000000 USDC
📜 AV       --> 📜 AV        : 200_000000 >= 200_000000 ✓

📜 AV       --> 📜 AV        : reservaRetenida = QualityRules.calcularReservaTecnica(200_000000, 1500)
                               = 200_000000 * 1500 / 10000 = 30_000000 USDC (15%)
📜 AV       --> 📜 AV        : montoNeto = 200_000000 - 30_000000 = 170_000000 USDC

📜 AV       --> 📜 AV        : lote.reservaTecnicaUSDC += 30_000000  [EFFECT]

📜 AV       --> 📜 AV        : _mint(BUYER_1, loteId=7, cantidadTokens=10, "")  [EFFECT]

  (inside _mint, _update is called)
  📜 AV._update --> 📜 AV    : isMint=true, isBurn=false
  📜 AV._update --> 📜 IR    : canMint(BUYER_1)  [double-check in _update]
  📜 IR         --> 📜 AV    : true
  📜 AV._update --> ERC1155  : super._update(address(0), BUYER_1, [7], [10])  [EFFECT]

🎫 Token    ~~> 🚨 Event     : TransferSingle(BACKEND_SIGNER, 0x0, BUYER_1, 7, 10)

📜 AV       --> 💰 USDC      : safeTransfer(lote.productorSRL, 170_000000)  [INTERACTION]
💰 USDC     ~~> 🚨 Event     : Transfer(AV_ADDR, PRODUCTOR_SRL, 170_000000)

📜 AV       ~~> 🚨 Event     : LoteComprado(loteId=7, comprador=BUYER_1, cantidadTokens=10,
                                            montoUSDCPagado=200_000000,
                                            reservaRetenida=30_000000,
                                            paymentRefHash=0x9821...)

🤖 Backend  <-- 📜 AV        : tx confirmed

🤖 Backend  --> 📜 DB        : UPDATE payment_intent { status: "minted", txHash: "0x..." }

🤖 Backend  --> 👤 Buyer     : email "Your 10 tokens for Lot #7 are in your wallet"

👤 Buyer    --> 🌐 Frontend  : wallet refreshes via wagmi, sees balance = 10
```

---

## Detailed Steps

### Step 1 — Pre-validation (off-chain)

- **Actor:** Backend
- **Checks performed:**
  - `IdentityRegistry.canMint(buyer)` → must return `true`
  - `AssetVault.kgDisponibles(loteId) >= cantidadTokens * 0.5` → must have capacity
  - `lote.estado == PREVENTA` → via `AssetVault.lotes(loteId).estado`
  - Rate limits, duplicate payment detection
- **If any check fails:** backend returns HTTP 422 with error code; no blockchain interaction

### Step 2 — MoonPay Payment

- **Actor:** Buyer via MoonPay widget
- **Off-chain:** Buyer enters card details, MoonPay processes payment, delivers USDC to backend operational wallet
- **Webhook received:** backend validates MoonPay HMAC-SHA256 signature before processing
- **14-day withdrawal hold (EU buyers only):** If buyer is EU resident (jurisdiction `DE`, `FR`, `ES`, etc.), backend inserts a `withdrawal_hold` record. Token mint is deferred until hold expiry or buyer cancels the hold.

### Step 3 — USDC Transfer to AssetVault

- **Actor:** Backend
- **Why:** `comprar()` expects USDC already present in the contract. The net amount is then forwarded to the producer SRL, and the reserve is retained.
- **Function:** `USDC.transfer(assetVaultAddress, montoUSDCPagado)` — signed by backend HSM
- **Gas estimated:** ~50k (ERC-20 transfer)

### Step 4 — `comprar()` on-chain

- **Actor:** Backend (BACKEND_SIGNER_ROLE)
- **Function called:** `AssetVault.comprar(loteId, cantidadTokens, comprador, montoUSDCPagado, paymentRefHash)`
- **Validations (ordered, gas-efficient fail-fast):**
  1. `lote.productorSRL != address(0)` — lot exists
  2. `lote.estado == PREVENTA` — lot is in presale
  3. `cantidadTokens > 0`
  4. `paymentRefHash != bytes32(0)`
  5. `identityRegistry.canMint(comprador)` — KYC check
  6. Capacity check (kg sold + kg requested <= kgEsperados) ⚠️ H-02
  7. `montoUSDCPagado >= cantidadTokens * lote.precioPorTokenUSDC` — payment sufficient
- **State changes:**
  - `lote.reservaTecnicaUSDC += reservaRetenida`
  - `ERC-1155 balanceOf(buyer, loteId) += cantidadTokens`
- **USDC flows:**
  - Retained in contract: `reservaRetenida` (15-20%)
  - Transferred to producer SRL: `montoNeto` (80-85%)
- **Events emitted:**
  - `LoteComprado(loteId, comprador, cantidadTokens, montoUSDCPagado, reservaRetenida, paymentRefHash)`
  - `TransferSingle(operator, 0x0, comprador, loteId, cantidadTokens)` (from ERC-1155 mint)
  - `Transfer(assetVaultAddr, productorSRL, montoNeto)` (from USDC)
- **Gas estimated:** ~110k

---

## Post-conditions

- Buyer's wallet holds `cantidadTokens` of `loteId` in `AssetVault`.
- `AssetVault.reservaTecnicaActual(loteId)` increased by `reservaRetenida`.
- Producer SRL wallet received `montoNeto` USDC.
- `AssetVault.totalSupply(loteId)` increased by `cantidadTokens`.
- `payment_intent` record in DB marked `minted` with on-chain tx hash.
- Audit log entry in PostgreSQL with tx hash, Arweave reference, buyer address (hashed for privacy).

---

## Error Cases

| Cause | Result | Reverts with |
|-------|--------|-------------|
| Buyer KYC tier = 0 or expired | mint blocked | `NotKYCVerified()` |
| Buyer sanctioned | mint blocked | (canMint returns false) → `NotKYCVerified()` |
| Buyer frozen | mint blocked | (canMint returns false) → `NotKYCVerified()` |
| Lot not in PREVENTA | purchase blocked | `LoteNotInPreventa()` |
| Lot capacity exceeded | purchase blocked | `KgSolicitadosExcedenSupply()` |
| USDC amount insufficient | purchase blocked | `MontoUSDCInsuficiente()` |
| `cantidadTokens == 0` | purchase blocked | `CantidadTokensCero()` |
| Contract paused | purchase blocked | `EnforcedPause()` (ERC1155Pausable) |
| MoonPay webhook HMAC invalid | payment ignored | no blockchain action |

---

## Concrete Numeric Example

```
Lot:              #7 — Bolivian monofloral rosemary honey, Q2-2026
kgEsperados:      100 kg
Tokens available: 200 (100 kg / 0.5 kg per token)
Price per token:  20_000000 USDC (20 USDC, 6 decimals)
Reserve BPS:      1500 (15%)
Current supply:   80 tokens minted (40 kg sold)

Buyer:            BUYER_1 = 0xABC... (Tier 1, jurisdiction DE — EU)
Quantity:         10 tokens = 5 kg
Payment:          10 × 20 USDC = 200 USDC

Reserve calc:
  reservaRetenida = 200_000000 × 1500 / 10000 = 30_000000 USDC (30 USDC)
  montoNeto       = 200_000000 - 30_000000     = 170_000000 USDC (170 USDC)

Post-tx state:
  BUYER_1.balance(loteId=7)  = 10 tokens
  totalSupply(7)             = 90 tokens
  lote.reservaTecnicaUSDC    += 30 USDC  (total reserve if 0 before: 30 USDC)
  productorSRL received       = 170 USDC

EU withdrawal hold:
  14-day hold inserted (MiCA consumer protection).
  If BUYER_1 does not cancel within 14 days, tokens remain in wallet.
  If BUYER_1 cancels: backend calls RedemptionManager.cancelarRedencion (special cancel flow, TBD).
```

---

## Known Bugs Relevant to This Flow

**⚠️ H-02 — Overmint due to integer division in capacity check**

File: `AssetVault.sol:213-215`

The current check divides by 1000 before summing. For odd token counts (e.g., 1 token), `1 * 500 / 1000 = 0` due to integer truncation, bypassing the capacity guard.

Practical impact at scale: after exactly 200 tokens minted (100 kg), a 1-token purchase is blocked correctly (100 + 0 > 100 → fails). But between 199 and 200 tokens, a 1-token purchase computes `199*500/1000 = 99` + `0` = `99 <= 100` → passes, minting token 200 correctly. The bug manifests only at the exact boundary. Under normal backend operation (which controls the flow), this is unlikely to be triggered accidentally, but it breaks the formal invariant.

Fix pending before mainnet (see audit H-02).
