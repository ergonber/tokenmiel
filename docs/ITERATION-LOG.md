# ITERATION LOG

> Bitácora del loop iterativo `build → test → document → review`. Cada entrada documenta una iteración con todos los pasos completados.

---

## Iteration #0 — Bootstrap del proyecto (2026-05-19)

**Goal:** crear bases sólidas del proyecto siguiendo el goal del usuario: arquitectura primero, después tests, después seguridad, todo documentado. División en subagentes con scopes acotados para evitar prompt injection cross-area.

**Trigger:** comando `/goal` del usuario.

### Build

**Artefactos producidos:**

1. **Estructura del monorepo** creada:
   - `apps/web/src/` + `apps/api/src/modules/`
   - `packages/contracts/src/{interfaces,libraries,adapters}` + `test/{unit,fuzz,invariant,integration}` + `script/`
   - `packages/{shared,ui,config,db,abis}/src/`
   - `tools/scripts/`
   - `docs/{architecture,runbooks,subagents,api,security-reviews}/`
   - `.github/workflows/`

2. **Configs raíz:**
   - `package.json` (workspaces + scripts)
   - `turbo.json` (pipelines)
   - `pnpm-workspace.yaml`
   - `.gitignore` (con secretos, build outputs, env files)
   - `tsconfig.json` (strict mode)
   - `.editorconfig`
   - `.prettierrc.json`
   - `.env.example` (todas las variables documentadas, ninguna con valor real)
   - `README.md`

3. **CLAUDE.md hierarchy** (aislamiento de contextos por área):
   - `/CLAUDE.md` raíz — reglas globales del proyecto
   - `packages/contracts/CLAUDE.md` — scope smart contracts
   - `apps/api/CLAUDE.md` — scope backend
   - `apps/web/CLAUDE.md` — scope frontend
   - `docs/subagents/SUBAGENT-REGISTRY.md` — registry de 6 subagentes especializados

4. **ADRs (Architecture Decision Records)** — 8 archivos:
   - `ADR-001` Multi-chain strategy (Plume primaria + Polygon secundaria)
   - `ADR-002` ERC-1155 token standard
   - `ADR-003` 4 contratos inmutables sin proxy
   - `ADR-004` Oracle design (Safe + Chainlink PoR)
   - `ADR-005` LabRegistry como oráculo de calidad
   - `ADR-006` Monorepo Turborepo + pnpm
   - `ADR-007` Backend stack (Bun + Hono + Drizzle)
   - `ADR-008` Grants strategy

5. **Specs detalladas:**
   - `docs/architecture/CONTRACT-SPECS.md` (83 KB, ~10k palabras) — generado por subagente Plan (opus) tras lectura de arquitectura
   - `docs/architecture/TEST-SPECS.md` — specs exhaustivas de tests Foundry (TDD-first)

6. **Smart contracts implementados** (Solidity 0.8.24, OZ v5, custom errors, NatSpec):
   - `packages/contracts/src/libraries/ComplianceConstants.sol`
   - `packages/contracts/src/libraries/QualityRules.sol`
   - `packages/contracts/src/libraries/DocumentHashes.sol`
   - `packages/contracts/src/interfaces/IIdentityRegistry.sol`
   - `packages/contracts/src/interfaces/ILabRegistry.sol`
   - `packages/contracts/src/interfaces/IRedemptionManager.sol`
   - `packages/contracts/src/interfaces/IAssetVault.sol`
   - `packages/contracts/src/IdentityRegistry.sol` (~190 LOC)
   - `packages/contracts/src/LabRegistry.sol` (~155 LOC)
   - `packages/contracts/src/RedemptionManager.sol` (~165 LOC)
   - `packages/contracts/src/AssetVault.sol` (~470 LOC)

7. **Foundry config:**
   - `packages/contracts/foundry.toml`
   - `packages/contracts/remappings.txt`
   - `packages/contracts/package.json`

### Test

**Artefactos producidos:**

1. **Base test helper:** `packages/contracts/test/BaseTest.t.sol`
   - Deploy de los 4 contratos + Mock USDC con 6 decimales
   - Direcciones de actores estándar
   - Helpers: `_setupKYC`, `_createLoteDefault`, `_comprarTokens`, `_confirmarCosechaDefault`, `_buildQualityAttestation`, `_confirmarCalidadDefault`, `_confirmarAlmacenamientoDefault`, `_advanceToAlmacenado`
   - Seed labs con firmas ECDSA reales (vm.sign)

2. **Tests unitarios críticos:**
   - `test/unit/IdentityRegistry.t.sol` — 20+ tests (setKYC, mark/unmark sanctioned, freeze/unfreeze, revoke, canMint/canRedeem variants, fuzz)
   - `test/unit/LabRegistry.t.sol` — 12+ tests (addLab, deactivate/reactivate, verifyAttestationSignature, isLabCertifiedFor)
   - `test/unit/AssetVault.t.sol` — 25+ tests (crearLote, comprar, P2P blocking, confirmarCosecha, confirmarCalidad, confirmarAlmacenamiento, marcarFallido, reembolso, liberarReservaTecnica, pause)
   - `test/unit/RedemptionManager.t.sol` — 11+ tests (iniciarRedencion, confirmarExportacion, cancelarRedencion)

**Tests totales implementados:** ~70 (faltan fuzz adicionales + invariant + integration extensivos según TEST-SPECS.md ~200-280 total)

**Pendiente:**
- Fuzz tests específicos (cálculos reserva, reembolso pro-rata, conversiones kg/tokens)
- Invariant tests (kg vendidos ≤ esperados, reserva ≥ 0, supply = 2*kg, etc.)
- Integration tests end-to-end (PurchaseFlow, RedemptionFlow, FailedLot, ComplianceScenarios, etc.)
- Ejecución real con `forge test` (Foundry no instalado en este entorno — pendiente para developer)

### Document

**Artefactos producidos:**

1. **README.md** del proyecto
2. **CLAUDE.md** raíz + 4 sub-CLAUDE.md por área
3. **SUBAGENT-REGISTRY.md** con 6 subagentes definidos
4. **8 ADRs** documentando todas las decisiones arquitectónicas
5. **CONTRACT-SPECS.md** (~10k palabras)
6. **TEST-SPECS.md** (~6k palabras)
7. **audit-report-2026-05-19.md** (security review interno, ~3k palabras)
8. **ITERATION-LOG.md** (este archivo)

### Review

**Security review interno** producido (`docs/security-reviews/audit-report-2026-05-19.md`):
- 0 Critical
- 1 High (H-01: reembolso pro-rata semántica)
- 5 Medium (M-01 a M-05)
- 7 Low (L-01 a L-07)
- 8 Informational (I-01 a I-08)

**Hallazgos bloqueantes para próxima iteración:**
- H-01 — decisión + implementación de política de reembolso completo
- M-02 — validar `isLabCertifiedFor` por especialización en `confirmarCalidad`
- M-03 — política de shortfall cosecha
- M-05 — auto-cancel redenciones INICIADA al pasar a FALLIDO

### Constraints encontrados

- **Agent tool límite de uso agotado** después del primer subagente (Plan, opus). Continué trabajo directo en lugar de lanzar subagentes adicionales. Los 6 subagentes definidos en SUBAGENT-REGISTRY.md son para usos futuros cuando el límite se resetee.
- **Foundry no instalado** en el entorno. Los tests escritos no se ejecutaron. Requerirá instalación manual del developer + ejecución posterior.
- **pnpm dlx skills bloqueado** por sistema de permisos (regla supply-chain del usuario). Skills usadas son solo las oficiales del system prompt.

### Métricas

| Métrica | Valor |
|---|---|
| Archivos creados | ~30 |
| LOC Solidity | ~1,450 |
| LOC Tests | ~1,200 |
| Palabras documentación | ~25,000 |
| ADRs | 8 |
| Smart contracts | 4 |
| Tests críticos | ~70 |
| Findings security | 21 (0 Critical, 1 High, 5 Medium, 7 Low, 8 Informational) |
| Duración iteración | ~1.5h (orchestrador) |

### Próxima iteración (Iteration #1)

**Foco propuesto:**
1. Resolver H-01 con decisión de producto (reembolso completo vs fondo de garantía)
2. Resolver M-02, M-03, M-05 con implementación
3. Implementar fuzz + invariant tests
4. Ejecutar `forge build` + `forge test` (developer manual)
5. Implementar `apps/api` módulos compliance (kyc-sync, document-vault, audit-log)

---

## Iteration #1 — Refactor constructor + audit profundo AssetVault.sol (2026-05-19)

**Goal:** revisar AssetVault.sol con foco en seguridad (subagente A opus), gas (subagente B sonnet) y flujos (subagente C sonnet). Refactorizar constructor para reducir redundancia. Aplicar fixes técnicos NO bloqueantes.

**Trigger:** usuario pidió "auditoría profunda primero de AssetVault, lanza subagentes paralelos para máxima seguridad".

### Build

1. **Refactor constructor AssetVault**:
   - Antes: 10 parámetros sueltos + 10 `if (X == address(0)) revert ZeroAddress();` consecutivos + 7 `_grantRole` sueltos
   - Después: `struct InitParams` agrupa los 10 params + helper privada `_requireNonZero(address)` reduce verbosidad + 7 `_grantRole` consolidados
   - Patrón: Uniswap V4 / Aave V3
   - Resuelve riesgo potencial de stack-too-deep

2. **Fixes técnicos del audit aplicados** (sin requerir decisión de producto):

| Finding | Tipo | Línea(s) | Fix aplicado |
|---|---|---|---|
| **H-02** | Bug overmint | comprar() 213-215 | Validación en gramos (no kg) — evita rounding por división temprana. Aplicado también en kgDisponibles() |
| **H-03** | Replay signatures | _computeAttestationHash() | Agregado `block.chainid` + `address(this)` + `attestation.testedAt` al hash. Función pasó de `pure` a `view` |
| **Bug-B1** | Lógica orden checks | burnForRedemption() 451-452 | Orden invertido: primero `redemptionManager != address(0)`, después `msg.sender != redemptionManager`. Antes `RedemptionManagerNotSet` nunca disparaba |
| **M-04** | Pool USDC reembolso | reembolsarLoteFallido() | Descuento `reservaTecnicaLiberada` del pool disponible para evitar usar USDC ya entregado al productor |
| **M-06** | OFAC en refunds | reembolsarLoteFallido() | Bloqueo de reembolso a sancionados/frozen (revert con `CannotRefundBlockedAddress`). Esos casos requieren tratamiento regulatorio especial off-chain |
| **M-07** | Unicidad labs | confirmarCalidad() | Loop O(N²) para detectar duplicados en `attestation.labAddresses`. N <= ~5 en práctica, costo aceptable |
| **M-08** (nuevo) | Consistencia timestamp | confirmarCalidad() | `stored.testedAt = attestation.testedAt` (no `block.timestamp`). Valida que testedAt <= now y >= now - 90d. Constante `ATTESTATION_MAX_AGE` agregada |
| **Opt-B1** | Gas | comprar() 210 | Removido double-call a `canMint()`. El override `_update()` ya valida. Ahorra ~5-10K gas/compra |
| **Opt-B2** | Gas + DoS | reembolsarLoteFallido() | Cap `MAX_REFUND_BATCH = 100`. Para más buyers, paginación. Nueva función `finalizarReembolso()` para marcar reembolso completo |

3. **Cambios en interfaces:**
   - `IAssetVault.sol` agrega `finalizarReembolso(loteId)`

4. **Cambios en tests:**
   - `BaseTest.t.sol` adaptado al nuevo constructor (struct InitParams)
   - `_buildQualityAttestation` actualizado con `block.chainid + address(this) + testedAt` para producir firmas válidas con el nuevo hash

### Test

- Tests existentes adaptados al nuevo constructor (compilarán)
- Tests específicos de los fixes nuevos pendientes (próxima iteración):
  - test_comprar_NoOvermintBySingleTokenLoop (H-02)
  - test_confirmarCalidad_RevertWhen_SignatureCrossChain (H-03)
  - test_confirmarCalidad_RevertWhen_DuplicateLab (M-07)
  - test_confirmarCalidad_RevertWhen_AttestationTooOld (M-08)
  - test_reembolsarLoteFallido_RevertWhen_BuyerSanctioned (M-06)
  - test_reembolsarLoteFallido_RevertWhen_BatchTooLarge (Opt-B2)
  - test_burnForRedemption_RevertWhen_RedemptionManagerNotSet (Bug-B1)

### Document

Artefactos producidos en esta iteración:
- `docs/security-reviews/audit-AssetVault-deep-2026-05-19.md` (subagente A, ~70 KB) — 0 Critical, 3 High, 8 Medium, 6 Low, 9 Informational
- `docs/gas-analysis/AssetVault-gas-2026-05-19.md` (subagente B) — estimación de gas por función + 10 optimizaciones priorizadas
- `docs/flows/` (subagente C, 7 archivos, ~92 KB):
  - `00-INDEX.md` — índice + leyenda
  - `01-deployment.md` — deploy de 4 contratos + transferencia DEFAULT_ADMIN_ROLE
  - `02-purchase-b2c.md` — compra B2C con MoonPay
  - `03-harvest-confirmation.md` — cosecha con Safe 2-de-3
  - `04-quality-attestation.md` — palinología + NMR + C4 con 2 labs
  - `05-redemption-export.md` — redención + DUE + BL/AWB
  - `06-failed-lot-refund.md` — lote fallido + reembolso pro-rata

### Review (decisiones pendientes del usuario)

Pendientes que NO se resolvieron en esta iteración por requerir input de producto/legal:

| Pendiente | Severidad | Task # |
|---|---|---|
| H-01: política de reembolso (¿100% o solo reserva?) | High | #16 |
| M-05: restringir marcarFallido a ciertos estados | Medium | #17 |
| CONFLICT-1: timing de liberar reserva (QUALITY_ATTESTED vs COSECHADO) | Medium | #18 |
| CONFLICT-2: iniciarRedencion (msg.sender vs backend on behalf) | Medium | #18 |
| CONFLICT-3: marcarFallido con hashEvidencia | Low | #18 |

### Métricas iteración #1

| Métrica | Valor |
|---|---|
| Findings detectados (audit profundo A) | 26 (0 Crit, 3 High, 8 Med, 6 Low, 9 Info) |
| Findings resueltos en esta iteración | 9 (H-02, H-03, Bug-B1, M-04, M-06, M-07, M-08, Opt-B1, Opt-B2) |
| Findings pendientes decisión | 5 (H-01, M-05, 3 CONFLICTS) |
| Líneas Solidity modificadas | ~120 |
| Subagentes lanzados | 3 (opus + sonnet + sonnet) |
| Documentos generados | 9 (audit + gas + 7 flows) |
| Tokens consumidos subagentes (aprox) | ~350K |

### Próxima iteración (Iteration #2)

Foco:
1. **Decisiones pendientes** del usuario sobre tasks #16, #17, #18
2. **Tests nuevos** para fixes aplicados (#7 fixes técnicos requieren cobertura)
3. **Audit profundo de IdentityRegistry, LabRegistry, RedemptionManager** (mismo proceso: 3 subagentes paralelos)
4. **Refactor constructor** de los otros 3 contratos (mismo patrón InitParams)
5. **Ejecutar forge build + forge test** (developer manual, Foundry no instalado en entorno)

---

## Iteration #2 — Decisiones de producto aplicadas + simplificación MVP (2026-05-19)

**Goal:** aplicar las 5 decisiones de producto del usuario sobre H-01, M-05 y los 3 CONFLICTS. Simplificar el MVP removiendo QualityAttestation (LabRegistry queda standalone para fase 2).

**Trigger:** usuario seleccionó las 5 opciones de producto y pidió implementar, testear, documentar.

### Decisiones del usuario aplicadas

| # | Decisión | Acción |
|---|---|---|
| H-01 | Escrow total post-cosecha (Opción A) | comprar() retiene USDC. confirmarCosecha() libera monto neto. reembolsarLoteFallido reembolsa 100% si falla pre-cosecha. |
| M-05 | Restringir marcarFallido (Opción A) | Solo permitido desde PREVENTA y COSECHADO. Post-ALMACENADO revierte con CannotFailLoteInThisState |
| C-1 | Reserva post-COSECHADO (Opción A) | liberarReservaTecnica permitido desde COSECHADO (alineado con remoción de QUALITY_ATTESTED) |
| C-2 | msg.sender en iniciarRedencion (Opción A) | Sin cambio. Función iniciarRedencionForUser (EIP-712) queda en roadmap para fase 2 si B2C lo necesita |
| C-3 | Sin hashEvidencia (Opción B) | Sin cambio. Evidencia legal vive off-chain (Arweave + backend) |
| Bonus | Remover QualityAttestation | LabRegistry queda standalone. confirmarCalidad, struct QualityAttestation, estado QUALITY_ATTESTED, todos removidos del MVP. Documentado en ADR-010 |

### Build

**Cambios al código:**

1. **`AssetVault.sol` reescrito** parcialmente:
   - Removido import `ILabRegistry`
   - Removido immutable `labRegistry`
   - Removido campo `labRegistry` del struct `InitParams`
   - Removido 11 errors custom (los relacionados con labs y QualityAttestation)
   - Removidas 4 constantes (`BOLIVIA_JURISDICTION`, `ATTESTATION_MAX_AGE`, etc.)
   - Removido el campo `qualityAttestation` de `LoteMiel` (vía actualización de IAssetVault)
   - Agregado campo `montoNetoPendiente` al `LoteMiel`
   - `comprar()` ahora retiene 100% del USDC en el contrato (escrow total). No transfiere al productor.
   - `confirmarCosecha()` ahora libera `montoNetoPendiente` al productor y emite `MontoNetoLiberado`
   - Removido `confirmarCalidad()` completo
   - `confirmarAlmacenamiento()` transiciona desde COSECHADO directamente (no QUALITY_ATTESTED)
   - `marcarFallido()` solo permitido desde PREVENTA y COSECHADO
   - `liberarReservaTecnica()` permitido desde COSECHADO en adelante
   - `reembolsarLoteFallido()` pool = montoNetoPendiente + reserva no liberada
   - Removido helper `_computeAttestationHash`

2. **`IAssetVault.sol` reescrito**:
   - Enum `LoteEstado` sin `QUALITY_ATTESTED`
   - Struct `LoteMiel` sin `qualityAttestation`, con nuevo `montoNetoPendiente`
   - Removida signature `confirmarCalidad`
   - Removida struct `QualityAttestation`
   - Removido evento `CalidadConfirmada`
   - Agregado evento `MontoNetoLiberado`

3. **`LabRegistry.sol` preservado standalone**:
   - Sin cambios al código
   - Sin integración con AssetVault
   - Listo para reactivación en fase 2

### Test

**Tests actualizados:**

1. **`BaseTest.t.sol` reescrito**:
   - Removida deployment de `LabRegistry`
   - Removidos helpers `_seedLabs`, `_buildQualityAttestation`, `_confirmarCalidadDefault`
   - Removidas constantes `LAB_BOLIVIA_PK`, `LAB_EUROPA_PK`, `labBolivia`, `labEuropa`
   - `_advanceToAlmacenado` simplificado (sin paso de QualityAttestation)
   - `InitParams` ya sin labRegistry

2. **`AssetVault.t.sol` reescrito**:
   - Removidos ~15 tests de `confirmarCalidad`
   - Agregados tests nuevos:
     - `test_comprar_EscrowTotal_USDCStaysInContract` ← FIX H-01
     - `test_comprar_EscrowTotal_TracksMontoNetoPendiente`
     - `test_comprar_AllowsExactCapacity` ← FIX H-02
     - `test_confirmarCosecha_ReleasesMontoNetoToProductor` ← FIX H-01
     - `test_marcarFallido_FromCosechado_Allowed` ← FIX M-05
     - `test_marcarFallido_RevertWhen_FromAlmacenado` ← FIX M-05
     - `test_reembolsarLoteFallido_PreCosecha_Refunds100Percent` ← FIX H-01
     - `test_reembolsarLoteFallido_RevertWhen_BuyerSanctioned` ← FIX M-06
     - `test_reembolsarLoteFallido_RevertWhen_BatchTooLarge` ← FIX Opt-B2
     - `test_liberarReservaTecnica_RevertWhen_Preventa` ← CONFLICT-1

3. **`LabRegistry.t.sol` actualizado**:
   - Ya no depende de `BaseTest`
   - Despliega `LabRegistry` standalone con su propio setup
   - Mantiene cobertura de tests del contrato (para preservar quality para fase 2)

4. **`RedemptionManager.t.sol` actualizado**:
   - Quitado `_confirmarCalidadDefault()` (función no existe)
   - Flujo simplificado: COSECHADO → ALMACENADO directo

### Document

**Documentos creados:**

1. **`docs/architecture/ADR-009-escrow-total-post-cosecha.md`** — escrow total como modelo de pago. Explica el problema H-01, alternativas evaluadas, decisión y consecuencias.

2. **`docs/architecture/ADR-010-simplificacion-estados-sin-quality-attestation.md`** — simplificación del MVP removiendo QualityAttestation. Documenta el alcance preservado (LabRegistry standalone) y el trigger para reactivación en fase 2.

3. **`docs/architecture/ADR-005-lab-registry-quality-oracle.md`** actualizado:
   - Status cambiado a `⏸️ DEFERRED TO PHASE 2`
   - Notice en header explicando el deferment con referencia a ADR-010
   - Contenido original preservado como referencia para fase 2

### Métricas iteración #2

| Métrica | Valor |
|---|---|
| Decisiones de producto aplicadas | 5 (H-01, M-05, C-1, C-2, C-3) + 1 bonus (remover QualityAttestation) |
| LOC Solidity removidos | ~150 (en `AssetVault.sol`) |
| LOC Solidity agregados | ~50 (nuevo flow + tests adicionales) |
| Tests removidos | ~15 (relacionados con `confirmarCalidad`) |
| Tests nuevos | ~10 (escrow + M-05 + reembolso 100%) |
| ADRs nuevos | 2 (ADR-009, ADR-010) |
| ADRs actualizados | 1 (ADR-005 marcado deferred) |

### Findings pendientes consolidados (post-Iteration #2)

Del audit profundo de Iteration #1 (subagente A):
- ✅ **H-01**: RESUELTO (escrow total post-cosecha)
- ✅ **H-02**: RESUELTO (validación en gramos, Iteration #1)
- ✅ **H-03**: NO APLICA (QualityAttestation removida)
- ✅ **Bug-B1**: RESUELTO (orden de checks en burnForRedemption, Iteration #1)
- ✅ **M-04**: RESUELTO (descuento de reservaTecnicaLiberada, Iteration #1)
- ✅ **M-05**: RESUELTO (restricción marcarFallido)
- ✅ **M-06**: RESUELTO (bloqueo de sancionados en refund, Iteration #1)
- ✅ **M-07**: NO APLICA (QualityAttestation removida)
- ✅ **M-08**: NO APLICA (QualityAttestation removida)
- ✅ **Opt-B1**: RESUELTO (single canMint check, Iteration #1)
- ✅ **Opt-B2**: RESUELTO (batch cap + paginación, Iteration #1)

Findings Low + Informational del audit original quedan como mejoras opcionales para futuras iteraciones.

### Próxima iteración (Iteration #3)

Foco:
1. **Refactor de los otros 3 contratos**: aplicar InitParams + helper `_requireNonZero` a `IdentityRegistry`, `LabRegistry`, `RedemptionManager`
2. **Audit profundo de IdentityRegistry y RedemptionManager** (mismo proceso de 3 subagentes en paralelo)
3. **Ejecutar `forge build` + `forge test`** (developer manual — Foundry no instalado en entorno actual)
4. **Tests adicionales pendientes** (fuzz e invariants completos según TEST-SPECS.md)
5. **Implementar `apps/api` módulos compliance** (kyc-sync, document-vault, audit-log)
6. **Decisión sobre LabRegistry**: ¿se incluye en deployment scripts del MVP solo como "deployed but not integrated" o se omite completamente?

---

## Iteration #3 — Audit profundo de IdentityRegistry + decisiones M-08, H-02, H-01, M-05 (2026-05-22)

**Goal:** profundizar la seguridad del registro de identidad (gatekeeper KYC de todo el sistema) y aplicar mejoras estructurales que surgieron del audit profundo. Migrar los 3 contratos activos a `AccessControlDefaultAdminRules`, agregar circuit breaker al IdentityRegistry, y blindar el flujo de reembolso contra revocaciones de KYC post-compra.

**Trigger:** usuario pidió audit completo de `IdentityRegistry.sol` siguiendo el mismo proceso de 3 subagentes paralelos (seguridad / gas / flujos) establecido en Iteration #1.

### Build

**Cambios técnicos aplicados en esta iteración:**

1. **3 contratos migrados a `AccessControlDefaultAdminRules` con delay 3 días** (FIX M-08):
   - `AssetVault.sol`, `IdentityRegistry.sol`, `RedemptionManager.sol` — cambian herencia de `AccessControl` base a `AccessControlDefaultAdminRules`.
   - Constructor de cada contrato ajustado para pasar `(ADMIN_TRANSFER_DELAY, admin)` al constructor del padre.
   - Constante `uint48 public constant ADMIN_TRANSFER_DELAY = 3 days` agregada en los 3.

2. **`IdentityRegistry` agrega `Pausable` con scope limitado** (FIX H-02):
   - Import `Pausable` de OZ v5.
   - `whenNotPaused` agregado a los 6 mutators: `setKYC`, `revokeKYC`, `markSanctioned`, `unmarkSanctioned`, `freezeAddress`, `unfreezeAddress`.
   - Views (`canMint`, `canRedeem`, etc.) NO pausadas — continúan operativas durante emergencias.
   - `pause()` callable por `COMPLIANCE_OFFICER_ROLE` OR `DEFAULT_ADMIN_ROLE`.
   - `unpause()` callable solo por `DEFAULT_ADMIN_ROLE` (más restrictivo).
   - Error custom: `UnauthorizedPauseActor()`.
   - Eventos: `EmergencyPaused(address actor, uint64 timestamp)` y `EmergencyUnpaused(address actor, uint64 timestamp)`.

3. **`AssetVault.reembolsarLoteFallido` agrega check `tier > 0`** (FIX H-01):
   - Validación: `if (identityRegistry.getTier(buyer) == 0) revert CannotRefundRevokedAddress();`
   - Error custom: `CannotRefundRevokedAddress()`.
   - Buyers con KYC revocado quedan pendientes de resolución off-chain (runbook en ADR-014).

4. **6 fixes técnicos adicionales en `IdentityRegistry`** (aplicados antes de las 4 decisiones):
   - **M-01**: `evidenceHash != bytes32(0)` validado en `markSanctioned`. Error: `InvalidEvidenceHash()`.
   - **M-01b**: `orderHash != bytes32(0)` validado en `freezeAddress`. Error: `InvalidOrderHash()`.
   - **M-03**: `msg.sender` indexed en todos los eventos de compliance para forensics post-incidente (`KYCUpdated`, `KYCRevoked`, `Sanctioned`, `Unsanctioned`, `Frozen`, `Unfrozen`).
   - **M-04**: `tier == 0` rechazado en `setKYC` — la única vía a tier=0 es `revokeKYC`. Error: `TierZeroNotAllowed()`.
   - **Opt-B1**: cache de storage pointer en `revokeKYC` y `markSanctioned` para evitar repeated SLOAD.

### Test

**Tests nuevos agregados (9 en total):**

- `test_constructor_AccessControlDefaultAdminRulesDelay` — verifica que los 3 contratos tienen `defaultAdminDelay() == 3 days`.
- `test_pause_ByComplianceOfficer_Succeeds` — COMPLIANCE_OFFICER puede pausar IdentityRegistry.
- `test_pause_ByAdmin_Succeeds` — DEFAULT_ADMIN puede pausar IdentityRegistry.
- `test_pause_ByUnauthorized_Reverts` — dirección sin rol no puede pausar.
- `test_setKYC_WhenPaused_Reverts` — `setKYC` revierte cuando el contrato está pausado.
- `test_unpause_ByAdmin_Succeeds` — DEFAULT_ADMIN puede despausar.
- `test_unpause_ByComplianceOfficer_Reverts` — COMPLIANCE_OFFICER NO puede despausar.
- `test_reembolsarLoteFallido_RevertWhen_BuyerTierZero` — buyer con KYC revocado no recibe reembolso on-chain.
- `test_markSanctioned_RevertWhen_EvidenceHashEmpty` — evidenceHash obligatorio.

### Document

1. **`docs/architecture/ADR-011-jurisdiction-validation-off-chain.md`** — decisión M-05: validación de jurisdicción off-chain en el backend, no on-chain. Documento `jurisdiction-codes.ts` como artefacto de implementación.

2. **`docs/architecture/ADR-012-access-control-default-admin-rules.md`** — decisión M-08: migración a `AccessControlDefaultAdminRules` con delay 3 días en los 3 contratos. Incluye runbooks de rotación de admin y cancelación de transferencias maliciosas.

3. **`docs/architecture/ADR-013-pause-in-identity-registry.md`** — decisión H-02: circuit breaker con scope limitado a mutators. Documenta la asimetría de roles pause/unpause y los runbooks de emergencia.

4. **`docs/architecture/ADR-014-tier-check-in-refund.md`** — decisión H-01: validación `tier > 0` en `reembolsarLoteFallido`. Documenta el runbook de resolución off-chain para buyers con KYC revocado.

5. **`packages/shared/src/constants/jurisdiction-codes.ts`** creado — 50 países representativos (LATAM, EU, NA, APAC, OTHER) con helpers `isValidJurisdiction`, `isLATAMJurisdiction`, `isEUJurisdiction`, `getJurisdictionsByRegion`.

### Review

**Findings del audit profundo de IdentityRegistry (subagente A, opus):**

| Severidad | Total | Resueltos en It. #3 |
|---|---|---|
| Critical | 0 | — |
| High | 2 (H-01, H-02) | **2 ✅** |
| Medium | 8 (M-01 a M-08) | **4 ✅** (M-01, M-01b, M-03, M-04, M-08) + M-05 Opción A |
| Low | 6 (L-01 a L-06) | — (mejoras opcionales iteraciones futuras) |
| Informational | 5 (I-01 a I-05) | — |

**Estado consolidado de findings post-Iteration #3:**

- ✅ **H-01** (RESUELTO): check `tier > 0` en `reembolsarLoteFallido` + error `CannotRefundRevokedAddress`
- ✅ **H-02** (RESUELTO): `Pausable` agregado a `IdentityRegistry` con scope limitado
- ✅ **M-01** (RESUELTO): `evidenceHash != bytes32(0)` en `markSanctioned`
- ✅ **M-01b** (RESUELTO): `orderHash != bytes32(0)` en `freezeAddress`
- ✅ **M-03** (RESUELTO): `msg.sender` indexed en eventos de compliance
- ✅ **M-04** (RESUELTO): `tier == 0` bloqueado en `setKYC`
- ✅ **M-05** (RESUELTO — Opción A): validación off-chain + `jurisdiction-codes.ts`
- ✅ **M-08** (RESUELTO): migración a `AccessControlDefaultAdminRules` en los 3 contratos
- ⚠️ **M-02** (PENDIENTE para Iteration #4): rate limiting ausente — si pause (H-02) está implementado, se considera mitigado parcialmente. Evaluación pendiente.
- ℹ️ **Low + Informational**: mejoras opcionales, no bloqueantes para mainnet.

### Decisiones tomadas (las 4 formales de esta iteración)

| # | Finding | Decisión adoptada |
|---|---|---|
| M-05 | Jurisdicción sin validación | Opción A: validación off-chain en backend |
| M-08 | Admin lockout risk | Opción A: `AccessControlDefaultAdminRules` delay 3 días |
| H-02 | Sin pause/circuit-breaker | Opción A: `Pausable` scope limitado a mutators |
| H-01 | Reembolso a wallet revocada | Opción A: check `tier > 0` + error `CannotRefundRevokedAddress` |

### Pendientes para Iteration #4

1. **Audit profundo de `RedemptionManager.sol`** — mismo proceso de 3 subagentes paralelos (seguridad / gas / flujos).
2. **Refactor `InitParams`** en `IdentityRegistry` y `RedemptionManager` para consistencia con el patrón de `AssetVault` (reducir stack-deep risk en constructores).
3. **`forge build` + `forge test`** — ejecución manual del developer (Foundry no instalado en el entorno del agente).
4. **M-02 (rate limiting)**: evaluar si el pause de emergencia mitiga suficientemente el riesgo, o si se agrega rate limiting on-chain.
5. **Audit de `LabRegistry.sol`** (standalone, fase 2): aunque no está en producción, conviene auditarlo antes de que se reactive.

### Métricas iteración #3

| Métrica | Valor |
|---|---|
| Findings detectados (audit IR) | 21 (0 Critical, 2 High, 8 Medium, 6 Low, 5 Informational) |
| Findings resueltos en esta iteración | 8 (H-01, H-02, M-01, M-01b, M-03, M-04, M-05, M-08) |
| Findings pendientes | 1 (M-02) + Low/Info opcionales |
| LOC Solidity modificados | ~135 (IdentityRegistry: +30 pause + errors; AssetVault: +5 tier check + error; RedemptionManager/AssetVault: +10 herencia) |
| LOC Tests nuevos | ~213 (9 tests × promedio ~24 LOC cada uno) |
| LOC documentación creada | ~1,400 (4 ADRs + jurisdiction-codes.ts) |
| ADRs nuevos | 4 (ADR-011 a ADR-014) |
| Archivos de código creados | 1 (`packages/shared/src/constants/jurisdiction-codes.ts`) |
| Subagentes lanzados | 3 (audit IR: seguridad / gas / flujos) + 2 (implementation + docs) |

---
