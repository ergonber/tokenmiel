# ADR-010: Simplificación de estados (sin QualityAttestation en MVP)

**Status:** Accepted
**Date:** 2026-05-19 (Iteration #2)
**Author:** Daniel Hidalgo Carrasco
**Tags:** smart-contracts, scope-reduction, lab-registry, phase-2

---

## Context

El diseño original (ADR-005) incluía un **oráculo de calidad** implementado vía `LabRegistry.sol` + struct `QualityAttestation` dentro del lote + función `confirmarCalidad()` en `AssetVault.sol`. Este oráculo era el **moat del producto**: certificación cryptográfica de monofloralidad vía palinología + NMR + C4 sugar test + residuos, firmado por 2 labs independientes (1 boliviano + 1 internacional).

Sin embargo, en la decisión del usuario tras la auditoría profunda de Iteration #1 + análisis de las 5 decisiones pendientes, se determinó:

> "El QualityAttestation no lo siento tan obligatorio, entonces, por el momento, no vamos a implementarlo."

Esto requirió simplificar el flujo del lote y el contrato `AssetVault`.

---

## Decision

**Remover la integración de `QualityAttestation` del MVP. Reservar `LabRegistry.sol` como contrato standalone para fase 2.**

### Cambios concretos al flujo del lote

| Antes (MVP original) | Después (MVP simplificado v2) |
|---|---|
| `PREVENTA → COSECHADO → QUALITY_ATTESTED → ALMACENADO → REDENCION_PARCIAL → AGOTADO/FALLIDO` | `PREVENTA → COSECHADO → ALMACENADO → REDENCION_PARCIAL → AGOTADO/FALLIDO` |

### Componentes removidos del MVP

| Componente | Status | Razón |
|---|---|---|
| `confirmarCalidad()` function | Removido | Sin uso en flujo simplificado |
| Struct `QualityAttestation` | Removido | Sin campo asociado |
| Estado `QUALITY_ATTESTED` | Removido del enum | Sin uso en flujo |
| Evento `CalidadConfirmada` | Removido | Sin uso |
| Helper `_computeAttestationHash` | Removido | Sin uso |
| Constantes `ATTESTATION_MAX_AGE`, `MIN_LABS_PARA_ATTESTATION`, `MIN_POLLEN_PERCENTAGE_MONOFLORAL`, `BOLIVIA_JURISDICTION` | Removidas | Sin uso |
| Errors `InsufficientLabs`, `MissingLocalLab`, `MissingForeignLab`, `LabNotRegistered`, `InvalidLabSignature`, `DuplicateLab`, `InvalidAttestationTimestamp`, `AttestationTooOld`, `LoteNotInQualityAttested` | Removidos | Sin uso |
| Import `ILabRegistry` en `AssetVault.sol` | Removido | Sin dependencia |
| Immutable `labRegistry` en `AssetVault.sol` | Removido | Sin dependencia |
| Campo `labRegistry` en `InitParams` | Removido | Sin dependencia |
| Tests `confirmarCalidad_*` | Removidos | Función no existe |

### Componentes preservados (standalone para fase 2)

- **`LabRegistry.sol`**: contrato funcional completo. Tests propios (`test/unit/LabRegistry.t.sol`) ahora deploya el contrato standalone, sin integración con `AssetVault`. Listo para activarse en fase 2.
- **`ILabRegistry.sol`**: interface preservada.
- **Libraries `QualityRules.sol`**: preservada (sigue usándose para `calcularReservaTecnica` y conversiones tokens/kg).

---

## Alternatives considered

### B) Eliminar LabRegistry completamente
Eliminar todo el código relacionado con labs, incluyendo `LabRegistry.sol`, su interface y tests.

**Descartada:** perderíamos trabajo ya construido y bien probado. El usuario indicó "por el momento" → la posibilidad de reactivación en fase 2 justifica preservar el código.

### C) Mantener QualityAttestation pero opcional
Hacer `confirmarCalidad()` opcional (puede saltarse) y el lote puede ir a ALMACENADO sin él.

**Descartada:** complejidad innecesaria. Tener una función que puede saltarse complica el contrato. Más limpio removerla y reactivarla cuando se decida.

---

## Consequences

### Positive

- **Reducción de complejidad del MVP**: menos LOC (~150 LOC removidos de `AssetVault`), menos errors custom, menos eventos, menos funciones a auditar.
- **Costo de auditoría reducido**: menos código → menos horas-auditor.
- **Time-to-market acelerado**: el bottleneck operacional de coordinar labs (envío de muestras 2-4 semanas) se elimina del MVP.
- **Liberación de reserva técnica más rápida**: ahora desde `COSECHADO` directamente (en lugar de esperar `QUALITY_ATTESTED`).
- **Modelo MVP defensible**: el flujo `PREVENTA → COSECHADO → ALMACENADO → REDENCION → AGOTADO` con escrow total + hashes de SENASAG + acta de cosecha es coherente y completo.

### Negative

- **Pérdida temporal del moat de producto**: sin QualityAttestation, el token compite contra commodity genérico. La narrativa de "certificación cryptográfica de monofloralidad" se difiere a fase 2.
- **Riesgo de competencia**: si un competidor activa oráculo de calidad antes, podría capturar el segmento premium B2B europeo.
- **El comprador no tiene verificación on-chain de calidad** — debe confiar en los hashes de `analisisLab` y `senasag` publicados por el oracle multi-sig. Calidad sí se puede verificar off-chain (descargando PDFs desde Arweave), pero sin firma criptográfica de labs.

### Neutral

- **`LabRegistry.sol` queda standalone**: el contrato y sus tests siguen funcionales. Si en fase 2 se reactiva, se requiere:
  - Re-integrar dependencia en `AssetVault` (deploy con campo `labRegistry`)
  - Reagregar `confirmarCalidad()` function
  - Reagregar estado `QUALITY_ATTESTED` al enum
  - Probable migración a contrato v2 si el AssetVault ya está en mainnet (debido a inmutabilidad)

---

## Implementation notes

### Estructura de archivos resultante

```
packages/contracts/src/
├── AssetVault.sol           ✅ activo (sin labRegistry dependency)
├── IdentityRegistry.sol     ✅ activo
├── RedemptionManager.sol    ✅ activo
├── LabRegistry.sol          ⏸️  standalone (no deployable en MVP, fase 2)
├── interfaces/
│   ├── IAssetVault.sol      ✅ activa
│   ├── IIdentityRegistry.sol ✅ activa
│   ├── IRedemptionManager.sol ✅ activa
│   └── ILabRegistry.sol     ⏸️  standalone (fase 2)
└── libraries/
    ├── ComplianceConstants.sol ✅ activa
    ├── QualityRules.sol     ✅ activa
    └── DocumentHashes.sol   ✅ activa
```

### Deployment scripts

- `script/DeployPlume.s.sol` (fase 1-5) y `script/DeployPolygon.s.sol` (fase 8+) deben **NO deployar `LabRegistry.sol`** en el MVP.
- Cuando se reactive en fase 2, agregar `DeployLabRegistry.s.sol` separado + script de migración del `AssetVault` si necesario.

### Documentación impactada

- ADR-003 (4 contratos inmutables) → actualizar a "3 contratos activos + 1 standalone para fase 2"
- ADR-005 (LabRegistry como oráculo de calidad) → marcar status "Deferred to Phase 2"
- `ARQUITECTURA-TECNICA-MVP.md` §7B → actualizar referencia
- `CONTRACT-SPECS.md` → versionar como v2 con sección de QualityAttestation marcada "Phase 2"

### Trigger para reactivación

Reactivar QualityAttestation cuando:
1. Volumen B2B premium europeo lo justifique (compradores institucionales pidiendo certificación cryptográfica)
2. Acuerdo comercial con al menos 1 lab boliviano (IBNORCA) + 1 lab internacional (Eurofins / Intertek / SGS)
3. Decisión de producto + legal de re-deployar `AssetVault v2` con la integración

---

## References

- ADR-003 (arquitectura de contratos)
- ADR-005 (LabRegistry como oráculo de calidad — status update a "Deferred to Phase 2")
- ADR-009 (escrow total post-cosecha)
- `docs/ITERATION-LOG.md` (Iteration #2)
