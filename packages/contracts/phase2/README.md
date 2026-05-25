# `phase2/` — Código preservado para fase 2

> **Esta carpeta NO se compila ni se testea en el MVP.** Está deliberadamente fuera del directorio `src/` y `test/` de Foundry para que `forge build` y `forge test` la ignoren completamente.

---

## ¿Qué hay acá?

Código y tests del **oráculo de calidad** (`LabRegistry` + `QualityAttestation`) que se diseñó originalmente como el "moat" del producto pero se difirió a fase 2 por decisión del usuario (Iteration #2).

Ver:
- `docs/architecture/ADR-005-lab-registry-quality-oracle.md` (status: ⏸️ DEFERRED TO PHASE 2)
- `docs/architecture/ADR-010-simplificacion-estados-sin-quality-attestation.md` (razón del deferment)

## Archivos

```
phase2/
├── README.md                              ← este archivo
├── src/
│   ├── LabRegistry.sol                    ← contrato whitelist de labs certificados
│   └── interfaces/
│       └── ILabRegistry.sol               ← interface pública
└── test/
    └── LabRegistry.t.sol                  ← tests standalone (no depende de BaseTest)
```

## ¿Cuándo se reactiva?

Cuando se cumpla AL MENOS UNO de estos triggers:

1. **Volumen B2B premium europeo** lo justifique (compradores institucionales pidiendo certificación cryptográfica de monofloralidad)
2. **Acuerdo comercial off-chain** con al menos 1 lab boliviano (IBNORCA) + 1 lab internacional (Eurofins / Intertek / SGS)
3. **Decisión de producto + legal** de re-deployar `AssetVault v2` con la integración de `LabRegistry`
4. **Aplicación a Plume Foundation Grants** donde uno de los milestones sea "activar oráculo de calidad"

## Cómo reactivarlo (instrucciones futuras)

Cuando se decida reactivar, los pasos son:

1. **Mover archivos de vuelta a `src/` y `test/`:**
   ```bash
   mv packages/contracts/phase2/src/LabRegistry.sol packages/contracts/src/
   mv packages/contracts/phase2/src/interfaces/ILabRegistry.sol packages/contracts/src/interfaces/
   mv packages/contracts/phase2/test/LabRegistry.t.sol packages/contracts/test/unit/
   ```

2. **Modificar `AssetVault.sol`:**
   - Reagregar import `ILabRegistry`
   - Reagregar `immutable labRegistry`
   - Reagregar campo `labRegistry` en `InitParams`
   - Reagregar errors: `InsufficientLabs`, `MissingLocalLab`, `MissingForeignLab`, `LabNotRegistered`, `InvalidLabSignature`, `DuplicateLab`, `InvalidAttestationTimestamp`, `AttestationTooOld`
   - Reagregar constantes: `BOLIVIA_JURISDICTION`, `ATTESTATION_MAX_AGE`, `MIN_LABS_PARA_ATTESTATION`, `MIN_POLLEN_PERCENTAGE_MONOFLORAL`
   - Reagregar función `confirmarCalidad()`
   - Reagregar struct `QualityAttestation` en `LoteMiel`
   - Reagregar helper `_computeAttestationHash` (con `block.chainid + address(this) + testedAt` — ver FIX H-03)
   - Reagregar estado `QUALITY_ATTESTED` en `LoteEstado` enum
   - Modificar `confirmarAlmacenamiento`: ahora requiere estado `QUALITY_ATTESTED` (no `COSECHADO`)
   - Modificar `liberarReservaTecnica`: ahora permitir desde `QUALITY_ATTESTED` (no desde `COSECHADO`)

3. **Modificar `IAssetVault.sol`:**
   - Reagregar `QUALITY_ATTESTED` al enum `LoteEstado`
   - Reagregar struct `QualityAttestation`
   - Reagregar evento `CalidadConfirmada`
   - Reagregar signature `confirmarCalidad`
   - Reagregar campo `qualityAttestation` en `LoteMiel`

4. **Modificar `BaseTest.t.sol`:**
   - Deploy de `LabRegistry`
   - Helpers `_seedLabs`, `_buildQualityAttestation`, `_confirmarCalidadDefault`
   - Actualizar `_advanceToAlmacenado` para incluir paso de QualityAttestation

5. **Re-deployar contratos como v2**: el contrato `AssetVault` original es inmutable, así que la reactivación requiere nuevo deploy + migración de balances (re-mint pro-rata).

6. **Auditoría externa incremental** de los cambios.

## Estado actual del código en `phase2/`

- ✅ `LabRegistry.sol` (149 LOC) — implementación completa con AccessControl + ECDSA signature verification + lifecycle de labs
- ✅ `ILabRegistry.sol` — interface completa
- ✅ `LabRegistry.t.sol` — tests standalone que cubren happy paths + edge cases

**Coverage de tests:** funcional (no medido formalmente). Cuando se reactive, ejecutar `forge coverage` para validar.

---

**Última actualización:** 2026-05-19 (Iteration #2 — movimiento a phase2)
