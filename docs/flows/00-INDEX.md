# Flow Documentation — tokenization-platform

> Last updated: 2026-05-22
> Source contracts: `packages/contracts/src/` v0.2.0
> Compiler: solc 0.8.24, paris EVM, optimizer 200 runs

---

## Index

| File | Flow | Triggered by |
|------|------|-------------|
| `01-deployment.md` | Deploy 4 contracts + role bootstrap | DevOps — once at mainnet launch |
| `02-purchase-b2c.md` | B2C purchase via MoonPay → token mint | Buyer completing payment |
| `03-harvest-confirmation.md` | Harvest confirmation via Safe multi-sig | Oracle Safe 2-of-3 |
| `04-quality-attestation.md` | Quality attestation signed by 2 labs | Oracle Safe 2-of-3 |
| `05-redemption-export.md` | Redemption + DUE + BL/AWB → burn | Buyer requesting physical delivery |
| `06-failed-lot-refund.md` | Failed lot + pro-rata refund | Oracle Safe 2-of-3 |

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

| Contract | Role | Address |
|----------|------|---------|
| `IdentityRegistry` | KYC whitelist | `0x...` |
| `LabRegistry` | Lab whitelist + signature verification | `0x...` |
| `AssetVault` | ERC-1155 token + lot lifecycle | `0x...` |
| `RedemptionManager` | Redemption escrow + export flow | `0x...` |
| `USDC` | Circle USDC on Plume | `0x...` |

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
         confirmarCalidad()
                  |
                  v
       [ QUALITY_ATTESTED ]
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

    marcarFallido() from any non-terminal state:
                  v
           [ FALLIDO ] (terminal) --> reembolsarLoteFallido()
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

| Flow | Pre-requisite flows |
|------|---------------------|
| 02-purchase-b2c | 01-deployment, KYC registered off-flow |
| 03-harvest-confirmation | 02-purchase-b2c (lot must have buyers) |
| 04-quality-attestation | 03-harvest-confirmation |
| 05-redemption-export | 04-quality-attestation + confirmarAlmacenamiento |
| 06-failed-lot-refund | Any state after crearLote, before AGOTADO/FALLIDO |

---

## Known Bugs from Security Audit (2026-05-19)

The following bugs from `docs/security-reviews/audit-AssetVault-deep-2026-05-19.md` are marked with ⚠️ throughout the flow documents where they are relevant:

| ID | Severity | Short description |
|----|----------|-------------------|
| H-01 | High | Refund on FALLIDO covers only 15-20% (reserve), not full purchase price |
| H-02 | High | Overmint possible due to integer division in `comprar` capacity check |
| H-03 | High | Attestation hash missing `block.chainid` + `address(this)` — signature replay risk on multi-chain |
| M-04 | Medium | `reembolsarLoteFallido` does not deduct already-released reserve |
| M-05 | Medium | `marcarFallido` permits transitions from QUALITY_ATTESTED / ALMACENADO without safeguards |
| M-06 | Medium | Refund loop sends USDC to sanctioned/frozen addresses |
| M-07 | Medium | `confirmarCalidad` does not validate uniqueness of labs in the array |

---

## Gas Reference (Plume Testnet estimates)

| Operation | Estimated gas | USD at 0.01 gwei |
|-----------|--------------|-----------------|
| Deploy IdentityRegistry | ~800k | ~$0.40 |
| Deploy LabRegistry | ~900k | ~$0.45 |
| Deploy AssetVault | ~3.5M | ~$1.75 |
| Deploy RedemptionManager | ~1.2M | ~$0.60 |
| `setRedemptionManager` | ~45k | ~$0.02 |
| `setKYC` | ~65k | ~$0.03 |
| `addLab` | ~120k | ~$0.06 |
| `crearLote` | ~160k | ~$0.08 |
| `comprar` (per buyer) | ~110k | ~$0.05 |
| `confirmarCosecha` | ~180k | ~$0.09 |
| `confirmarCalidad` (2 labs) | ~260k | ~$0.13 |
| `confirmarAlmacenamiento` | ~80k | ~$0.04 |
| `iniciarRedencion` | ~120k | ~$0.06 |
| `confirmarExportacion` | ~95k | ~$0.05 |
| `marcarFallido` | ~55k | ~$0.03 |
| `reembolsarLoteFallido` (per buyer in batch) | ~80k | ~$0.04 |
