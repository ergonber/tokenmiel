# Flow Documentation — tokenization-platform

> Last updated: 2026-05-29
> Source contracts: `packages/contracts/src/` v0.2.0
> Compiler: solc 0.8.24, paris EVM, optimizer 200 runs

---

## Index

| File | Flow | Triggered by | Scope |
|------|------|-------------|-------|
| `01-deployment.md` | Deploy 3 contracts + role bootstrap | DevOps — once at mainnet launch | MVP |
| `02-purchase-b2c.md` | B2C purchase via MoonPay → token mint | Buyer completing payment | MVP |
| `03-harvest-confirmation.md` | Harvest confirmation via Safe multi-sig | Oracle Safe 2-of-3 | MVP |
| `04-quality-attestation.md` | Quality attestation signed by 2 labs (LabRegistry) | Oracle Safe 2-of-3 | **FASE 2** |
| `05-redemption-export.md` | Redemption + DUE + BL/AWB → burn | Buyer requesting physical delivery | MVP |
| `06-failed-lot-refund.md` | Failed lot + pro-rata refund | Oracle Safe 2-of-3 | MVP |

---

## Actor Legend

| Symbol | Actor | Description |
|--------|-------|-------------|
| 👤 | Buyer | End user (EOA, Tier 1+ KYC) |
| 🏢 | SRL | Operating company (Wyoming LLC / SRL Bolivia) |
| 🤖 | Backend | HSM-signed wallet (AWS/GCP KMS) — `BACKEND_SIGNER_ROLE` |
| 🔬 | Lab | Certified laboratory (IBNORCA / Eurofins / Intertek) |
| 🔐 | Safe | Gnosis Safe multi-sig 2-of-3 with hardware wallets |
| ⚖️ | Compliance | Compliance Officer (hardware wallet) — `COMPLIANCE_OFFICER_ROLE` |
| 📜 | Contract | On-chain smart contract |
| 💰 | USDC | USDC transfer (native Circle USDC on Plume) |
| 🎫 | Token | ERC-1155 token mint / burn (1 token = 0.5 kg honey) |
| 📦 | LoteEstado | Lot lifecycle state change |
| 🚨 | Event | On-chain event emission |

---

## Contract Addresses (Plume Mainnet — to be filled post-deploy)

| Contract | Role | Address | Scope |
|----------|------|---------|-------|
| `IdentityRegistry` | KYC whitelist | `0x...` | MVP |
| `AssetVault` | ERC-1155 token + lot lifecycle | `0x...` | MVP |
| `RedemptionManager` | Redemption escrow + export flow | `0x...` | MVP |
| `LabRegistry` | Lab whitelist + signature verification | `0x...` | **FASE 2** (ADR-010) |
| `USDC` | Circle USDC on Plume | `0x...` | external |

---

## Lot Lifecycle State Machine

```
              crearLote()
                  |
                  v
            [ PREVENTA ]  <-- comprar() mints tokens here
                  |
         confirmarCosecha()
                  |
                  v
           [ COSECHADO ]
                  |
      confirmarAlmacenamiento()
                  |
                  v
          [ ALMACENADO ]
                  |
       iniciarRedencion() /
       confirmarExportacion()
                  |
                  v
      [ REDENCION_PARCIAL ]
                  |
     (all tokens burned)
                  |
                  v
           [ AGOTADO ] (terminal)

    marcarFallido() ONLY from PREVENTA or COSECHADO (FIX M-05):
                  v
           [ FALLIDO ] (terminal) --> reembolsarLoteFallido()

NOTE: QUALITY_ATTESTED and confirmarCalidad() are FASE 2 (require LabRegistry — ADR-010).
      MVP path has no quality-attestation state between COSECHADO and ALMACENADO.
```

---

## Sequence Diagram Notation

```
Actor  --> Contract : action / function call
Contract --> Contract : internal call
Contract --> Contract : state change [BEFORE --> AFTER]
Contract ~~> Event   : EventName(params)
Actor  <-- Contract : return value
```

Arrows with `-->` are external calls. Arrows with `-->` inside a contract box are internal transitions.

---

## Cross-References

| Flow | Pre-requisite flows | Scope |
|------|---------------------|-------|
| 02-purchase-b2c | 01-deployment, KYC registered off-flow | MVP |
| 03-harvest-confirmation | 02-purchase-b2c (lot must have buyers) | MVP |
| 04-quality-attestation | 03-harvest-confirmation + LabRegistry deployed | **FASE 2** |
| 05-redemption-export | 03-harvest-confirmation + confirmarAlmacenamiento | MVP |
| 06-failed-lot-refund | PREVENTA or COSECHADO only (FIX M-05) | MVP |

---

## Known Bugs from Security Audit (2026-05-19)

The following bugs from `docs/security-reviews/audit-AssetVault-deep-2026-05-19.md` are marked with ⚠️ throughout the flow documents where they are relevant:

| ID | Severity | Short description |
|----|----------|-------------------|
| H-01 | High | Refund on FALLIDO covers only 15-20% (reserve), not full purchase price |
| H-02 | High | Overmint possible due to integer division in `comprar` capacity check |
| H-03 | High | Attestation hash missing `block.chainid` + `address(this)` — signature replay risk on multi-chain |
| M-04 | Medium | `reembolsarLoteFallido` does not deduct already-released reserve |
| M-05 | Medium | **FIXED** — `marcarFallido` now only permitted from PREVENTA or COSECHADO (not ALMACENADO or beyond) |
| M-06 | Medium | Refund loop sends USDC to sanctioned/frozen addresses |
| M-07 | Medium | `confirmarCalidad` does not validate uniqueness of labs — **FASE 2** (confirmarCalidad is not in MVP) |

---

## Gas Reference (Plume Testnet estimates)

| Operation | Estimated gas | USD at 0.01 gwei | Scope |
|-----------|--------------|-----------------|-------|
| Deploy IdentityRegistry | ~800k | ~$0.40 | MVP |
| Deploy AssetVault | ~3.5M | ~$1.75 | MVP |
| Deploy RedemptionManager | ~1.2M | ~$0.60 | MVP |
| Deploy LabRegistry | ~900k | ~$0.45 | **FASE 2** |
| `setRedemptionManager` | ~45k | ~$0.02 | MVP |
| `setKYC` | ~65k | ~$0.03 | MVP |
| `crearLote` | ~160k | ~$0.08 | MVP |
| `comprar` (per buyer) | ~110k | ~$0.05 | MVP |
| `confirmarCosecha` | ~180k | ~$0.09 | MVP |
| `confirmarAlmacenamiento` | ~80k | ~$0.04 | MVP |
| `iniciarRedencion` | ~120k | ~$0.06 | MVP |
| `confirmarExportacion` | ~95k | ~$0.05 | MVP |
| `marcarFallido` | ~55k | ~$0.03 | MVP |
| `reembolsarLoteFallido` (per buyer in batch) | ~80k | ~$0.04 | MVP |
| `addLab` | ~120k | ~$0.06 | **FASE 2** |
| `confirmarCalidad` (2 labs) | ~260k | ~$0.13 | **FASE 2** |
