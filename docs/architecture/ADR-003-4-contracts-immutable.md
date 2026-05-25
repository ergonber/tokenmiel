# ADR-003: 4 contratos inmutables sin proxy

**Status:** Accepted
**Date:** 2026-05-19
**Author:** Dany Hidalgo F.
**Tags:** smart-contracts, architecture, immutable, no-proxy

---

## Context

El sistema requiere lógica on-chain dividida en responsabilidades claras. Las opciones de arquitectura van desde monolítico (un solo contrato) hasta máximamente modular (Diamond Pattern con N facetas). Cada opción trade-off entre simplicidad, separation of concerns, costo de auditoría y mantenibilidad.

---

## Decision

**Adoptar 4 contratos inmutables sin proxy:**

1. **`AssetVault.sol`** — ERC-1155 + ciclo de vida de lotes + reserve técnica embebida + compliance hook embebido + QualityAttestation
2. **`IdentityRegistry.sol`** — whitelist on-chain con tiers + sanctions + frozen + bridge con Plume Arc
3. **`RedemptionManager.sol`** — escrow + flujo de redención + DUE/BL-AWB
4. **`LabRegistry.sol`** — whitelist de labs certificados + verificación de firmas para QualityAttestation

**Sin proxy upgradeable.** Si aparece bug crítico: `pause()` + migración a v2 con re-mint pro-rata.

---

## Alternatives considered

### Monolítico (1 contrato)
- ✅ Máxima simplicidad
- ❌ Acopla todas las responsabilidades, viola SRP
- ❌ Auditoría más larga (un solo blob de lógica)

### 5 contratos (separación máxima)
- AssetVault + IdentityRegistry + ComplianceHook + RedemptionEscrow + ReserveVault
- ✅ Máxima separation of concerns
- ❌ Over-engineering para MVP
- ❌ `ComplianceHook` no requiere contrato propio (hook vive como override `_update()` en AssetVault)
- ❌ `ReserveVault` no requiere contrato propio (state variable interna de AssetVault)
- ❌ Costo de auditoría mayor (USD 8-15K vs USD 4-8K)

### 3 contratos (v1.0 propuesta inicial)
- AssetVault + IdentityRegistry + RedemptionManager
- ✅ Simple
- ❌ **No incluye LabRegistry** — sin oráculo de calidad estructurado, perdemos el moat del producto (palinología + NMR + attestations firmadas por labs)
- → Por eso evolucionamos a 4 contratos en v2.0

### Diamond Pattern (EIP-2535)
- ✅ Máxima flexibilidad, upgradeability granular
- ❌ Auditoría compleja, "magic" del proxy
- ❌ Storage layout collisions posibles
- ❌ Overkill para MVP inmutable

### UUPS proxy upgradeable
- ✅ Permite arreglar bugs sin migración
- ❌ Confianza del usuario reducida (admin puede cambiar reglas)
- ❌ Mayor superficie de ataque
- ❌ Storage layout debe gestionarse cuidadosamente

---

## Consequences

### Positive (inmutables)

- **Confianza máxima del usuario:** nadie puede cambiar las reglas después del deploy.
- **Auditoría simplificada:** sin proxy patterns, sin storage slots conflictivos.
- **Menos superficie de ataque:** sin admin functions de upgrade.
- **Defensible legalmente:** "el contrato no se modifica" es promesa simple y verificable.

### Positive (4 contratos)

- **Separation of concerns clara:** cada contrato tiene una responsabilidad bien definida.
- **`IdentityRegistry` separado:** consultado por múltiples contratos (`AssetVault`, `RedemptionManager`).
- **`RedemptionManager` separado:** encapsula flujo complejo de exportación con su propio estado.
- **`LabRegistry` separado:** permite agregar/desactivar labs sin tocar `AssetVault`. Es el pilar del moat (oráculo de calidad).
- **Auditoría granular:** cada contrato se puede auditar independientemente.

### Negative

- **Bug crítico requiere migración compleja:** `pause()` + deploy v2 + re-mint pro-rata + reconciliación de USDC.
- **Cambios de reglas requieren nueva versión completa.**
- **Costo de deploy ligeramente mayor que monolítico** (4 contratos vs 1).

### Neutral

- Roles via `AccessControl` de OpenZeppelin para todas las funciones administrativas.
- Sin governance on-chain en MVP (decisiones fuera del Safe multi-sig requieren consenso off-chain de cofundadores).

---

## Implementation notes

### Mitigación de bugs (sin proxy)

Si aparece bug crítico post-deploy:
1. **`COMPLIANCE_OFFICER_ROLE` ejecuta `pause()`** en `AssetVault` (bloquea compras nuevas).
2. **Análisis del bug.**
3. **Deploy v2** con el fix.
4. **Migración:**
   - Snapshot del estado on-chain (eventos via Goldsky).
   - Re-mint pro-rata en v2 con balances exactos.
   - Comunicación a usuarios via email + frontend.
   - Reembolso de gas si aplica.
5. **Auditoría externa del v2** antes de hacer público.

### Estructura básica

```
packages/contracts/src/
├── AssetVault.sol             (~600-800 LOC con QualityAttestation)
├── IdentityRegistry.sol       (~200-300 LOC con Plume Arc bridge)
├── RedemptionManager.sol      (~200-300 LOC)
├── LabRegistry.sol            (~150-250 LOC)
├── interfaces/
│   ├── IAssetVault.sol
│   ├── IIdentityRegistry.sol
│   ├── IRedemptionManager.sol
│   └── ILabRegistry.sol
├── libraries/
│   ├── ComplianceConstants.sol
│   ├── DocumentHashes.sol
│   └── QualityRules.sol
└── adapters/
    ├── PlumeArcAdapter.sol
    └── ChainlinkPoRAdapter.sol
```

### Costos estimados

| Métrica | Valor |
|---|---|
| LOC Solidity total | ~1,400-2,050 |
| Tiempo implementación | 3-4 semanas |
| Coverage objetivo | 100% líneas + branches |
| Fuzz runs | ≥ 10,000 |
| Invariant runs | ≥ 50,000 |
| Auditoría externa (Plume) | USD 6,000-18,000 |
| Auditoría incremental (Polygon fase 8) | USD 4,000-10,000 |

### Cross-references

- `AssetVault` llama `IdentityRegistry.canMint(addr)` en `_update()`
- `AssetVault` llama `LabRegistry.verifyAttestationSignature()` en `confirmarCalidad()`
- `RedemptionManager` consulta `IdentityRegistry.canRedeem(addr)` en `iniciarRedencion()`
- `RedemptionManager` llama `AssetVault.burn()` en `confirmarExportacion()`

---

## References

- ARQUITECTURA-TECNICA-MVP.md §6 (decisión técnica #3: arquitectura de contratos)
- ADR-002 (ERC-1155)
- ADR-004 (oracle design)
- ADR-005 (LabRegistry)
- OpenZeppelin AccessControl: https://docs.openzeppelin.com/contracts/5.x/access-control
