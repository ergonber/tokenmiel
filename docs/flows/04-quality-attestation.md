# Flow 04: Quality Attestation — 2 Labs, 4 Tests

> **⚠️ FASE 2 — NO MVP (2026-05-28):** Este flujo (QualityAttestation con `LabRegistry`, `confirmarCalidad`, estado `QUALITY_ATTESTED`) fue **diferido a FASE 2** (ADR-010). En el MVP el lote transiciona directo de `COSECHADO` a `ALMACENADO` sin attestation de calidad on-chain, y la reserva técnica se libera vía `liberarReservaTecnica` (TREASURY_SRL_ROLE) post-cosecha. Este documento se conserva como referencia de la fase 2.

## Executive Summary

After harvest confirmation, the lot enters quality verification. Two independent certified laboratories — one Bolivian (IBNORCA or equivalent) and one European (Eurofins, Intertek, or SGS) — independently analyze the honey using four scientific tests: palynology (pollen species and percentage), NMR spectroscopy (adulteration detection), C4 sugar test (AOAC 998.12), and residue analysis (pesticides/antibiotics). Each lab cryptographically signs their findings with their registered ECDSA key. The Oracle Safe collects both signatures and submits `confirmarCalidad()` on-chain. The contract validates both signatures against the LabRegistry, verifies jurisdictional diversity, and computes the `isMonofloralCertified` flag. Upon success, the lot transitions to `QUALITY_ATTESTED` and the technical reserve is released to the producer.

This attestation is the platform's primary quality moat: it creates a tamper-proof on-chain record that the honey met EU monofloral honey standards (Directive 2014/63/EU).

---

## Actors Involved

- **🔬 IBNORCA** — Bolivian national lab. Jurisdiction `"BO"`. Signs with key `IBNORCA_SIGNER`. Specializations: PALINOLOGIA, NMR, C4_SUGAR, PESTICIDAS.
- **🔬 Eurofins** — European lab (Germany). Jurisdiction `"DE"`. Signs with key `EUROFINS_SIGNER`. Specializations: PALINOLOGIA, NMR, C4_SUGAR, PESTICIDAS, ANTIBIOTICOS.
- **🤖 Backend** — Collects signed reports from labs, validates signatures, prepares Safe transaction.
- **🔐 Oracle Safe** — Submits `confirmarCalidad()`. Holds `ORACLE_ROLE`.
- **📜 AssetVault** — Executes `confirmarCalidad()` and calls `LabRegistry` for signature verification.
- **📜 LabRegistry** — Verifies ECDSA signatures against registered lab keys.
- **🏢 Treasury SRL** — After QUALITY_ATTESTED is reached, calls `liberarReservaTecnica()`.

---

## Pre-conditions

- Lot `#7` in `AssetVault` with `estado == COSECHADO`.
- Both labs are active in `LabRegistry`:
  - `LabRegistry.isLabActive(IBNORCA_SIGNER) == true`
  - `LabRegistry.isLabActive(EUROFINS_SIGNER) == true`
- Both labs have submitted their physical analysis reports to the SRL.
- Both labs have signed the `QualityAttestation` struct off-chain with their registered ECDSA keys.

---

## Off-chain Lab Signing Protocol

Before the on-chain transaction is prepared, each lab signs off-chain:

```
attestationHash = keccak256(abi.encode(
    loteId,
    attestation.pollenSpecies,
    attestation.pollenPercentage,
    attestation.nmrPassed,
    attestation.c4Passed,
    attestation.residuesPassed,
    attestation.fullReportHashes
))

labSignature_i = ECDSA.sign(privateKey_lab_i, toEthSignedMessageHash(attestationHash))
```

⚠️ **H-03 — Missing domain separator:** The current `_computeAttestationHash()` (AssetVault.sol:542) does NOT include `block.chainid` or `address(this)`. This creates a cross-chain signature replay vulnerability on Plume + Polygon multi-chain deployment (Phase 6+). Fix required before mainnet. The correct hash should include `chainid`, `address(this)`, and `attestation.testedAt`.

---

## Sequence Diagram

```
--- Off-chain: Lab analysis and signing ---

🔬 IBNORCA  --> 🔬 IBNORCA  : Run palynology → pollenSpecies="RM", pollenPercentage=67
                               Run NMR       → nmrPassed=true
                               Run C4        → c4Passed=true
                               Run residues  → residuesPassed=true
🔬 IBNORCA  --> 🔬 IBNORCA  : Compose fullReport (PDF with all test data)
                               hashReport_IBNORCA = SHA-256(report.pdf) = 0xR1...

🔬 IBNORCA  --> 🔬 IBNORCA  : compute attestationHash (same inputs as contract)
🔬 IBNORCA  --> 🔐 IBNORCAKey : sign(attestationHash)  → sig_IBNORCA = 0xS1...

🔬 Eurofins --> 🔬 Eurofins  : (same independent analysis, same lot sample)
                               pollenPercentage=65, nmrPassed=true, c4Passed=true, residuesPassed=true
                               hashReport_Eurofins = SHA-256(eurofins-report.pdf) = 0xR2...
🔬 Eurofins --> 🔐 EurofinsKey : sign(attestationHash)  → sig_Eurofins = 0xS2...

🔬 IBNORCA  --> 🤖 Backend   : POST /labs/submit { loteId: 7, reportPDF: ..., signature: 0xS1... }
🔬 Eurofins --> 🤖 Backend   : POST /labs/submit { loteId: 7, reportPDF: ..., signature: 0xS2... }

--- Backend validation and preparation ---

🤖 Backend  --> 🤖 Backend  : local signature pre-verification (same hash as contract)
🤖 Backend  --> 🌐 Arweave  : Upload both PDFs → get Arweave tx IDs
🤖 Backend  --> 🤖 Backend  : verify Arweave readback ✓

🤖 Backend  --> 🤖 Backend  : cross-check: IBNORCA pollen=67% and Eurofins pollen=65%
                               delta = 2% → within acceptable variance ✓
                               NOTE: contract does NOT enforce variance; this is off-chain policy.

🤖 Backend  --> 🔐 OracleSafe : createTransaction({
                                  to: AV_ADDR,
                                  data: AV.confirmarCalidad.encode(
                                    loteId=7,
                                    attestation: {
                                      labAddresses: [IBNORCA_SIGNER, EUROFINS_SIGNER],
                                      pollenSpecies: "RM",
                                      pollenPercentage: 67,  (use IBNORCA as primary)
                                      nmrPassed: true,
                                      c4Passed: true,
                                      residuesPassed: true,
                                      testedAt: 1748649600,  (unix timestamp)
                                      isMonofloralCertified: false,  (contract computes this)
                                      fullReportHashes: [0xR1..., 0xR2...]
                                    },
                                    labSignatures: [sig_IBNORCA, sig_Eurofins]
                                  ) })

🔐 Signer1 + Signer2 --> 🔐 OracleSafe : sign + execute (same Safe flow as flow 03)

🔐 OracleSafe --> 📜 AV     : confirmarCalidad(loteId=7, attestation, [sig_IBNORCA, sig_Eurofins])
                              [ORACLE_ROLE, nonReentrant]

--- On-chain execution ---

📜 AV       --> 📜 AV       : validate lote exists ✓
📜 AV       --> 📜 AV       : validate lote.estado == COSECHADO ✓
📜 AV       --> 📜 AV       : validate labAddresses.length >= 2 (MIN_LABS) ✓
📜 AV       --> 📜 AV       : validate labAddresses.length == labSignatures.length ✓

NOTE ⚠️ M-07: No uniqueness check. [IBNORCA, IBNORCA, EUROFINS] with length=3 would pass.
              Fix pending (O(n²) dedup check).

📜 AV       --> 📜 AV       : attestationHash = _computeAttestationHash(7, attestation)

NOTE ⚠️ H-03: Hash missing chainid + address(this). See off-chain section above.

--- Loop over labs ---

--- Lab 0: IBNORCA ---
📜 AV       --> 📜 LR       : getLab(IBNORCA_SIGNER)
📜 LR       --> 📜 AV       : Lab { signerAddress: IBNORCA, jurisdiction: "BO", active: true, ... }

📜 AV       --> 📜 AV       : IBNORCA.jurisdiction == "BO" → hasLocal = true

NOTE ⚠️ M-01: No isLabCertifiedFor check. Contract does NOT verify IBNORCA is certified
             for PALINOLOGIA, NMR, C4_SUGAR, PESTICIDAS. Fix pending.

📜 AV       --> 📜 LR       : verifyAttestationSignature(IBNORCA_SIGNER, attestationHash, sig_IBNORCA)
📜 LR       --> 📜 LR       : ethSignedHash = toEthSignedMessageHash(attestationHash)
📜 LR       --> 📜 LR       : recovered = ECDSA.recover(ethSignedHash, sig_IBNORCA)
📜 LR       --> 📜 LR       : recovered == IBNORCA_SIGNER? → true
📜 LR       --> 📜 AV       : true ✓

--- Lab 1: Eurofins ---
📜 AV       --> 📜 LR       : getLab(EUROFINS_SIGNER)
📜 LR       --> 📜 AV       : Lab { signerAddress: EUROFINS, jurisdiction: "DE", active: true, ... }

📜 AV       --> 📜 AV       : EUROFINS.jurisdiction != "BO" → hasForeign = true

📜 AV       --> 📜 LR       : verifyAttestationSignature(EUROFINS_SIGNER, attestationHash, sig_Eurofins)
📜 LR       --> 📜 AV       : true ✓

--- Post-loop validation ---
📜 AV       --> 📜 AV       : hasLocal == true ✓
📜 AV       --> 📜 AV       : hasForeign == true ✓

--- Compute monofloral certification ---
📜 AV       --> 📜 QR       : QualityRules.isMonofloralCertified(67, true, true, true)
📜 QR       --> 📜 QR       : 67 >= 45 && nmrPassed && c4Passed && residuesPassed → true
📜 QR       --> 📜 AV       : isMonofloral = true

--- Copy attestation to storage ---
📜 AV       --> 📜 AV       : delete stored.labAddresses; delete stored.fullReportHashes
📜 AV       --> 📜 AV       : push IBNORCA_SIGNER, EUROFINS_SIGNER to stored.labAddresses
📜 AV       --> 📜 AV       : push 0xR1..., 0xR2... to stored.fullReportHashes
📜 AV       --> 📜 AV       : stored.pollenSpecies = "RM"
📜 AV       --> 📜 AV       : stored.pollenPercentage = 67
📜 AV       --> 📜 AV       : stored.nmrPassed = true
📜 AV       --> 📜 AV       : stored.c4Passed = true
📜 AV       --> 📜 AV       : stored.residuesPassed = true
📜 AV       --> 📜 AV       : stored.testedAt = 1748649600
📜 AV       --> 📜 AV       : stored.isMonofloralCertified = true  [computed]

📜 AV       --> 📜 AV       : lote.estado = QUALITY_ATTESTED  [COSECHADO → QUALITY_ATTESTED]

📜 AV       ~~> 🚨 Event    : CalidadConfirmada(loteId=7, pollenSpecies="RM",
                                pollenPercentage=67, isMonofloralCertified=true,
                                labAddresses=[IBNORCA, EUROFINS])

--- Reserve Release ---

🤖 Backend  --> Goldsky     : detects CalidadConfirmada event for loteId=7
🤖 Backend  --> 🔐 TreasurySRL : notify: "Reserve releasable for lot #7"

🏢 TreasurySRL --> 📜 AV    : liberarReservaTecnica(loteId=7)  [TREASURY_SRL_ROLE, nonReentrant]
📜 AV          --> 📜 AV    : validate estado == QUALITY_ATTESTED ✓
📜 AV          --> 📜 AV    : montoLiberable = lote.reservaTecnicaUSDC - lote.reservaTecnicaLiberada
                              = 240_USDC - 0 = 240_USDC  (example: 8 buyers × 30 USDC each)
📜 AV          --> 📜 AV    : lote.reservaTecnicaLiberada = lote.reservaTecnicaUSDC  [EFFECT]
📜 AV          --> 💰 USDC  : safeTransfer(lote.productorSRL, 240_000000)  [INTERACTION]
📜 AV          ~~> 🚨 Event : ReservaTecnicaLiberada(loteId=7, montoUSDC=240_000000, productorSRL=0x...)
```

---

## Detailed Steps

### Step 1 — Lab Analysis (Off-chain)

Each lab independently analyzes the honey sample with four tests:

| Test | Standard | Metric | Pass threshold |
|------|----------|--------|---------------|
| Palynology | EU Directive 2014/63/EU | pollen species + % | species identified, % >= 45 for monofloral |
| NMR spectroscopy | DIN EN 14092 | adulteration with syrups | no syrup signal detected |
| C4 sugar | AOAC 998.12 | C4 sugar isotopic ratio | delta-13C < -23.5‰ (no corn/cane syrup) |
| Residues | EU Reg. 396/2005 MRL | pesticides + antibiotics | all below MRL |

### Step 2 — Cryptographic Signing by Each Lab

Each lab computes the same `attestationHash` from the attestation struct fields and signs it with their registered ECDSA key. The signature is 65 bytes (r, s, v).

The hash MUST be computed identically on both sides (lab software + contract). Any discrepancy in field encoding causes `InvalidLabSignature()`.

### Step 3 — Backend Collection and Pre-validation

Backend receives both signed reports, pre-validates signatures locally (same hash computation), uploads PDFs to Arweave, and creates the Safe transaction proposal.

### Step 4 — `confirmarCalidad()` on-chain

- **Actor:** Oracle Safe (ORACLE_ROLE)
- **Function called:** `AssetVault.confirmarCalidad(loteId, attestation, labSignatures)`
- **Validations:** See sequence diagram above
- **State changes:**
  - Full `QualityAttestation` struct written to `lote.qualityAttestation`
  - `isMonofloralCertified` computed by `QualityRules.isMonofloralCertified()`
  - `lote.estado = QUALITY_ATTESTED`
- **Events emitted:** `CalidadConfirmada(loteId, pollenSpecies, pollenPercentage, isMonofloralCertified, labAddresses)`
- **Gas estimated:** ~260k (2 labs, includes two LR external calls)

### Step 5 — Reserve Release

- **Actor:** Treasury SRL (TREASURY_SRL_ROLE)
- **Function called:** `AssetVault.liberarReservaTecnica(loteId)`
- **Requires:** `estado >= QUALITY_ATTESTED`
- **State changes:** `lote.reservaTecnicaLiberada = lote.reservaTecnicaUSDC`
- **USDC transfer:** `reservaTecnicaUSDC - reservaTecnicaLiberada` → `lote.productorSRL`
- **Events emitted:** `ReservaTecnicaLiberada(loteId, montoUSDC, productorSRL)`
- **Gas estimated:** ~70k

---

## Post-conditions

- Lot `#7` `estado == QUALITY_ATTESTED`.
- `lote.qualityAttestation` fully populated:
  - `isMonofloralCertified = true` (if all criteria met)
  - Both lab addresses and report hashes recorded
- Technical reserve transferred to `productorSRL`.
- Frontend can display the quality badge and certification details.
- Goldsky indexes `CalidadConfirmada` event.

---

## Error Cases

| Cause | Result | Reverts with |
|-------|--------|-------------|
| Lot not in COSECHADO | blocked | `LoteNotInCosechado()` |
| Fewer than 2 labs | blocked | `InsufficientLabs()` |
| Lab not registered in LabRegistry | blocked | `LabNotRegistered()` |
| Lab inactive (deactivated) | blocked | `LabNotRegistered()` |
| No Bolivian lab | blocked | `MissingLocalLab()` |
| No non-Bolivian lab | blocked | `MissingForeignLab()` |
| Invalid ECDSA signature | blocked | `InvalidLabSignature()` |
| Same lab in array twice (M-07, pending fix) | passes (incorrectly) | not yet enforced |

---

## Monofloral Certification Rules

```
isMonofloralCertified = (pollenPercentage >= 45)
                        AND nmrPassed
                        AND c4Passed
                        AND residuesPassed
```

Source: EU Directive 2014/63/EU, transposed via QualityRules library (`ComplianceConstants.MIN_POLLEN_PERCENTAGE_MONOFLORAL = 45`).

If `isMonofloralCertified = false`, the lot is still valid but is labeled "multi-floral honey" on the platform. The attestation is still recorded on-chain; only the premium label is affected.

---

## Known Issues

**⚠️ H-03 — Missing chainid + address(this) in attestation hash**

`_computeAttestationHash()` currently omits `block.chainid` and `address(this)`. On multi-chain deployment (Plume + Polygon, Phase 6+), a signature produced for lot #7 on Plume could be replayed on Polygon's AssetVault if the same `loteId` exists. Fix required before multi-chain deployment.

**⚠️ M-01 — No specialization check per lab**

`confirmarCalidad()` verifies that each lab is active and registered, but does NOT call `LabRegistry.isLabCertifiedFor(lab, Specialization.PALINOLOGIA)` etc. A lab certified only for NMR could technically sign an attestation including pollen data. Mitigation: operational discipline + fix in code.

**⚠️ M-07 — No lab uniqueness check**

`labAddresses = [EUROFINS, EUROFINS]` with `length=2` would pass all checks (hasLocal from one, hasForeign from both, signatures verified twice for the same key). The guarantee of "two independent labs" is not formally enforced on-chain.

---

## Concrete Numeric Example

```
Lot #7 — Bolivian monofloral rosemary honey
Total supply: 80 tokens (from 8 buyers, 10 tokens each at 20 USDC/token)
Total USDC received:  80 × 20 = 1600 USDC
Reserve at 15%:       1600 × 0.15 = 240 USDC (in vault)
Net to producer:      1600 × 0.85 = 1360 USDC (transferred at comprar() calls)

Lab results:
  IBNORCA (Bolivia "BO"):
    pollenSpecies: "RM"  (Rosmarinus officinalis)
    pollenPercentage: 67%
    nmrPassed: true
    c4Passed: true
    residuesPassed: true
    reportHash: 0xR1IBNORCA...

  Eurofins (Germany "DE"):
    pollenPercentage: 65%  (independent analysis, slight variance normal)
    all tests: true
    reportHash: 0xR2EUROFINS...

pollenPercentage used on-chain: 67 (IBNORCA, primary / local)
isMonofloralCertified = 67 >= 45 && true && true && true = TRUE

Reserve release:
  montoLiberable = 240_000000 - 0 = 240_000000 USDC
  Transfer to productorSRL: 240 USDC

Total USDC received by producer SRL after all flows:
  At purchase time: 1360 USDC (net)
  At reserve release: 240 USDC
  Total: 1600 USDC = 100% of buyer payments
```

Cross-reference: see `05-redemption-export.md` for the next step (confirmarAlmacenamiento → ALMACENADO).
