# Flow 03: Harvest Confirmation via Safe Multi-sig

## Executive Summary

After the honey has been physically harvested, the operating company (SRL) collects the required documentation (SENASAG phytosanitary certificate, lab analysis, harvest minutes, apiary photos, origin certificate), uploads them, and the backend prepares an on-chain transaction for the Oracle Safe (2-of-3). Two of three signers must approve with their hardware wallets. Upon confirmation, the lot transitions from `PREVENTA` to `COSECHADO`, unlocking the technical reserve release to the producer and enabling the next phase (quality attestation).

This is a high-trust operation: the lot's physical existence and certificate authenticity are legally attested by the SRL and the Bolivian SENASAG authority.

---

## Actors Involved

- **🏢 SRL Operator** — Company employee managing the admin panel. Uploads documents.
- **🤖 Backend** — Prepares the Safe transaction proposal. Computes document hashes. Uploads to Arweave.
- **🔐 Oracle Safe** — Gnosis Safe 2-of-3 at `ORACLE_SAFE_ADDR`. Holds `ORACLE_ROLE` on `AssetVault`. Two of three hardware-wallet signers must approve.
- **📜 AssetVault** — Executes `confirmarCosecha()`.
- **🏢 Producer SRL** — Honey producer. Receives the USDC net amount from the technical reserve upon harvest confirmation. (Handled off-chain: Safe TREASURY_SRL_ROLE triggers a direct wallet transfer.)

---

## Pre-conditions

- Lot exists in `AssetVault` with `estado == LoteEstado.PREVENTA`.
- Physical honey has been harvested and officially weighed.
- SENASAG certificate issued and signed.
- Standard lab analysis completed (HMF, moisture, diastase).
- Harvest minutes signed by the producer and an SRL representative.
- Apiary photos taken and archived.
- Origin certificate (DO, GI, or certificate of origin) available.
- All documents uploaded to Cloudflare R2 (operational) and Arweave (permanent legal record).
- Arweave readback verified (download + re-hash + compare).

---

## Sequence Diagram

```
🏢 Operator --> 🌐 AdminPanel : SELECT lot #7 → "Confirm Harvest"
🌐 AdminPanel --> 🏢 Operator : upload form (5 document slots)

🏢 Operator --> 🤖 Backend   : POST /oracle/harvest { lotId: 7, kgReal: 95,
                                  files: [senasag, labAnalysis, actaCosecha, fotos, certOrigen],
                                  tipoCertificado: "DO" }

🤖 Backend  --> 🤖 Backend   : SHA-256 hash each file locally
                               hashSenasag     = 0xAAA...
                               hashAnalisisLab = 0xBBB...
                               hashActaCosecha = 0xCCC...
                               hashFotosApiario = 0xDDD...
                               hashCertOrigen  = 0xEEE...

🤖 Backend  --> ☁️ R2        : PUT each file (parallel, operational access)
🤖 Backend  --> 🌐 Arweave   : POST each file via Bundlr/Irys (parallel, permanent)
🌐 Arweave  --> 🤖 Backend   : { txId: "ar://..." } per file

🤖 Backend  --> 🌐 Arweave   : GET each file, re-hash, compare  [readback verification]
🤖 Backend  --> 🤖 Backend   : all hashes match ✓

🤖 Backend  --> 🔐 OracleSafe : Safe SDK: createTransaction({
                                  to: AV_ADDR,
                                  data: AV.confirmarCosecha.encode(
                                    7, 95000, hashSenasag, hashAnalisisLab,
                                    hashActaCosecha, hashFotosApiario,
                                    hashCertOrigen, TipoCertificado.DO) })
🔐 OracleSafe --> 📜 SafeDB  : Store pending tx proposal

🤖 Backend  --> 📨 Firmantes : Slack DM + email "Harvest confirmation pending for lot #7"

🔐 Signer1  --> 🌐 SafeUI   : Open pending tx
🌐 SafeUI   --> 🔐 Signer1  : Display: lotId=7, kgReal=95, document hashes
🔐 Signer1  --> 🔐 Signer1  : Verify documents (download from R2/Arweave, cross-check hashes)
🔐 Signer1  --> 🔐 Ledger1  : Connect hardware wallet → sign
🔐 OracleSafe --> 📜 SafeDB : confirmations: 1/3

🔐 Signer2  --> 🌐 SafeUI   : (same verification + sign)
🔐 OracleSafe --> 📜 SafeDB : confirmations: 2/3 → threshold reached → EXECUTE

🔐 OracleSafe --> 📜 AV     : confirmarCosecha(loteId=7, kgRealCosechado=95000,
                                                hashSenasag=0xAAA..., hashAnalisisLab=0xBBB...,
                                                hashActaCosecha=0xCCC..., hashFotosApiario=0xDDD...,
                                                hashCertificadoOrigen=0xEEE...,
                                                tipoCertificado=TipoCertificado.DO)
                              [ORACLE_ROLE, nonReentrant]

📜 AV       --> 📜 AV       : validate lote exists (productorSRL != 0x0) ✓
📜 AV       --> 📜 AV       : validate lote.estado == PREVENTA ✓
📜 AV       --> 📜 AV       : validate kgRealCosechado > 0 ✓
📜 AV       --> 📜 AV       : validate all 5 hashes are non-zero via DocumentHashes.isValid() ✓

📜 AV       --> 📜 AV       : lote.kgCosechadosReal = 95000  [EFFECT]
📜 AV       --> 📜 AV       : lote.hashSenasag = 0xAAA...    [EFFECT]
📜 AV       --> 📜 AV       : lote.hashAnalisisLab = 0xBBB.. [EFFECT]
📜 AV       --> 📜 AV       : lote.hashActaCosecha = 0xCCC.. [EFFECT]
📜 AV       --> 📜 AV       : lote.hashFotosApiario = 0xDDD. [EFFECT]
📜 AV       --> 📜 AV       : lote.hashCertificadoOrigen = 0xEEE... [EFFECT]
📜 AV       --> 📜 AV       : lote.tipoCertificadoOrigen = DO  [EFFECT]
📜 AV       --> 📜 AV       : lote.estado = COSECHADO  [EFFECT: PREVENTA → COSECHADO]

📜 AV       ~~> 🚨 Event    : CosechaConfirmada(loteId=7, kgRealCosechado=95000,
                                hashSenasag=0xAAA..., hashAnalisisLab=0xBBB...,
                                hashActaCosecha=0xCCC..., hashCertificadoOrigen=0xEEE...)

🤖 Backend  <-- 🔐 OracleSafe : tx confirmed, txHash=0xFFF...

--- Reserve release (off-chain, triggered by on-chain event) ---

🤖 Backend  --> 🤖 Backend  : Goldsky event listener detects CosechaConfirmada(loteId=7)
🤖 Backend  --> 📜 AV       : reservaTecnicaActual(7)  [view] → returns current reserve amount

NOTE: The reserve release (transfer of USDC from reserve to producer SRL) is
      executed OFF-CHAIN by the Treasury SRL wallet. The on-chain call
      AssetVault.liberarReservaTecnica() transfers USDC from the vault to
      lote.productorSRL. This must be triggered by TREASURY_SRL_ROLE.

🔐 TreasurySRL --> 📜 AV    : liberarReservaTecnica(loteId=7)  [TREASURY_SRL_ROLE, nonReentrant]
📜 AV          --> 📜 AV    : validate lote.estado == QUALITY_ATTESTED or ALMACENADO or
                               REDENCION_PARCIAL or AGOTADO  ← NOTE: estado is COSECHADO here.

CONFLICT: The contract requires estado >= QUALITY_ATTESTED to call liberarReservaTecnica.
          But arquitectura.md section 23.3 says the reserve is released upon confirmarCosecha.
          Current code: liberarReservaTecnica() checks for QUALITY_ATTESTED/ALMACENADO/REDENCION_PARCIAL/AGOTADO.
          This means the reserve CANNOT be released at COSECHADO state.
          The release must wait until after confirmarCalidad() transitions to QUALITY_ATTESTED.
          
          CONFLICT: see docs/architecture/CONTRACT-SPECS.md §10 CONFLICT 1 and ARQUITECTURA-TECNICA-MVP §23.3.

📜 AV       ~~> 🚨 Event    : ReservaTecnicaLiberada(loteId=7, montoUSDC=XXX, productorSRL=0x...)
```

---

## Detailed Steps

### Step 1 — Document Upload and Hashing

- **Actor:** SRL Operator + Backend
- **Process:**
  1. Operator selects lot in admin panel, triggers "Confirm Harvest" wizard.
  2. Uploads five files (SENASAG cert, standard lab analysis, harvest minutes, apiary photos, origin certificate).
  3. Backend computes SHA-256 of each file locally before uploading.
  4. Files uploaded in parallel to Cloudflare R2 (operational access) and Arweave (permanent legal record via Bundlr/Irys).
  5. Backend performs Arweave readback: downloads each file, re-hashes, compares with original hash. Fails loudly if mismatch.
- **Output:** five `bytes32` hashes ready for on-chain inclusion.

### Step 2 — Safe Transaction Proposal

- **Actor:** Backend
- **Process:**
  1. Backend encodes the `confirmarCosecha` calldata.
  2. Creates a Safe transaction proposal via Safe SDK (no gas spent yet).
  3. Proposal stored in Safe's off-chain transaction service.
  4. Sends notifications (Slack DM + email) to all three Safe signers with the lot details and document links.

### Step 3 — Safe Signing (2 of 3)

- **Actor:** Oracle Safe Signers (hardware wallets)
- **Process per signer:**
  1. Opens Safe Web UI, locates the pending transaction.
  2. Reviews the lot details, downloads documents from R2/Arweave, manually cross-checks hashes visible in calldata.
  3. Connects Ledger Nano X, approves the transaction via hardware wallet.
- **Threshold:** first signer provides confirmation #1; second signer provides confirmation #2 → Safe executes automatically.
- **Note:** Third signer does not need to act unless one of the first two is unavailable.

### Step 4 — `confirmarCosecha()` on-chain

- **Actor:** Oracle Safe (ORACLE_ROLE)
- **Function called:** `AssetVault.confirmarCosecha(loteId, kgRealCosechado, hashSenasag, hashAnalisisLab, hashActaCosecha, hashFotosApiario, hashCertificadoOrigen, tipoCertificado)`
- **Validations:**
  1. `lote.productorSRL != address(0)` — lot exists
  2. `lote.estado == PREVENTA` — correct state
  3. `kgRealCosechado > 0` — valid harvest
  4. All five hashes pass `DocumentHashes.isValid()` (non-zero check)
- **State changes:**
  - `lote.kgCosechadosReal = kgRealCosechado`
  - Five hash fields set
  - `lote.tipoCertificadoOrigen = tipoCertificado`
  - `lote.estado = COSECHADO`
- **Events emitted:** `CosechaConfirmada(loteId, kgRealCosechado, hashSenasag, hashAnalisisLab, hashActaCosecha, hashCertificadoOrigen)`
- **Gas estimated:** ~180k

### Step 5 — Reserve Release (post-QUALITY_ATTESTED)

See `04-quality-attestation.md`. The technical reserve can only be released after the lot reaches `QUALITY_ATTESTED` state, not at `COSECHADO`. This is a CONFLICT between the architecture document and the current code implementation.

---

## Post-conditions

- Lot `#7` in `AssetVault` has `estado == COSECHADO`.
- Five document hashes stored on-chain (verifiable by anyone).
- `lote.kgCosechadosReal` recorded (may differ from `kgEsperados`).
- Arweave permanent links stored in backend database with Goldsky-indexed on-chain reference.
- Goldsky subgraph indexes the `CosechaConfirmada` event.
- Buyers can query the lot and see the harvest documentation hashes.

---

## Error Cases

| Cause | Result | Reverts with |
|-------|--------|-------------|
| Lot not in PREVENTA | state check fails | `LoteNotInPreventa()` |
| Any hash is zero | validation fails | `InvalidHash()` |
| `kgRealCosechado == 0` | validation fails | `InvalidKgEsperados()` |
| Caller lacks ORACLE_ROLE | unauthorized | AccessControl revert |
| Contract paused | blocked | `EnforcedPause()` |
| Arweave readback mismatch | backend aborts before Safe proposal | no blockchain action |

---

## Known Issues and Conflicts

**CONFLICT: Reserve release timing**

`ARQUITECTURA-TECNICA-MVP.md §23.3` step 14-15 describes the reserve release happening right after `confirmarCosecha`. However, `AssetVault.liberarReservaTecnica()` (line 430-434) requires `estado` to be `QUALITY_ATTESTED`, `ALMACENADO`, `REDENCION_PARCIAL`, or `AGOTADO` — NOT `COSECHADO`.

This means the reserve is NOT released at harvest confirmation but at quality attestation. The architecture document and the code disagree.

Resolution: the reserve is released after `confirmarCalidad()` (see `04-quality-attestation.md`), not at `confirmarCosecha`. This is actually safer — the producer receives full payment only after quality is confirmed, not just after physical harvest. The architecture document should be updated to reflect this.

**M-02 — No shortfall protection in `confirmarCosecha`**

If `kgRealCosechado < kgYaVendidosTotales` (harvest yields less than what was pre-sold), the code does not prevent confirmation. Example: 100 kg pre-sold, only 80 kg harvested. The lot proceeds to `COSECHADO` with 20 kg "missing". This creates redemption risk — some token holders cannot receive the physical honey.

Mitigation pending: add `kgRealCosechado >= kgYaVendidos * 90/100` guard (max 10% shortfall). Until then, operators must manually verify kg consistency before signing.

---

## Concrete Numeric Example

```
Lot #7:
  kgEsperados:        100 kg
  totalSupply(7):     80 tokens = 40 kg sold (pre-harvest)
  kgRealCosechado:    95 kg  (5% below expected, within acceptable range)

Documents submitted:
  hashSenasag:         keccak256(SENASAG-cert-2026-Q2.pdf)  = 0xAAA...
  hashAnalisisLab:     keccak256(lab-analysis-HMF-07.pdf)   = 0xBBB...
  hashActaCosecha:     keccak256(acta-cosecha-lote7.pdf)    = 0xCCC...
  hashFotosApiario:    keccak256(fotos-bundle-07.zip)       = 0xDDD...
  hashCertOrigen:      keccak256(certificado-origen-DO.pdf) = 0xEEE...
  tipoCertificado:     TipoCertificadoOrigen.DO

Post-tx state:
  lote.estado:           COSECHADO  (was PREVENTA)
  lote.kgCosechadosReal: 95000      (stored as gramos: 95 * 1000)
  All five hashes stored on-chain.

Gas paid by:   Oracle Safe (Plume native gas)
Gas estimated: 180k ≈ USD 0.09

Note: 40 kg sold vs 95 kg harvested → 55 kg still available for additional presale in COSECHADO
state? NO — presale (comprar()) only works in PREVENTA. After confirmarCosecha, no new
purchases can be made. Remaining kg are available for redemption by token holders.
```

Cross-reference: see `04-quality-attestation.md` for the next step.
