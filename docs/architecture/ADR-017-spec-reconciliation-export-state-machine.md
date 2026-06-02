# ADR-017: Reconciliación spec-código de la máquina de estados de redención

**Status:** Accepted
**Date:** 2026-05-27
**Author:** Daniel Hidalgo Carrasco
**Tags:** redemption, state-machine, spec-reconciliation, export-flow, audit-trail
**Resuelve:** RM-11 (MEDIUM)
**Relacionado:** ADR-015 (Timeout Policy), ADR-016 (Pause Asymmetry)
**Supersedes:** N/A
**Superseded by:** N/A

---

## Context

`CONTRACT-SPECS.md` §6.5 (líneas 1099-1110) define un flujo de redención con **3 fases activas** y **2 funciones separadas**:

```
INICIADA → EN_EXPORTACION → COMPLETADA
            (via confirmarExportacion)   (via completarRedencion)
```

- `confirmarExportacion(redencionId, dueNumero)` — registra el DUE emitido por SENASAG, transiciona a `EN_EXPORTACION`. **No quema tokens**.
- `completarRedencion(redencionId, hashBLAWB)` — registra BL/AWB recibido, transiciona a `COMPLETADA`, **quema tokens del comprador**.

La implementación actual (commit `92fd0e0` y siguientes) **colapsó ambas funciones en una sola**:

```solidity
function confirmarExportacion(uint256 redencionId, string calldata dueNumero, bytes32 hashBLAWB) external {
    // ... transiciona INICIADA → COMPLETADA en una sola tx
    // ... burn de tokens aquí
}
```

Resultado:
- El estado `EstadoRedencion.EN_EXPORTACION` está definido en el enum **pero nunca se usa** (dead state).
- El evento `RedencionEnExportacion` se emite pero el estado on-chain nunca lo refleja.
- La spec y el código divergen.

### Gap operacional real

El export Bolivia → UE tiene una secuencia temporal predecible:

| Hito | Cuándo se materializa |
|---|---|
| DUE emitido por SENASAG | Día 1-7 |
| Goods leave Bolivia | Día 5-10 |
| Customs clearance UE | Día 30-40 |
| BL/AWB delivered to oracle | Día 30-45 |

**Hay un gap de ~30 días entre el DUE y el BL/AWB.** Bajo el código actual (1 función), el Oracle Safe debe esperar a tener ambos documentos antes de firmar — durante esos 30+ días el buyer ve el estado de su redención como `INICIADA` sin pista de progreso.

### Impacto del finding RM-11

1. **Inconsistencia spec ↔ código** → auditores externos van a cuestionar la divergencia.
2. **UX pobre para el buyer** → 30+ días sin visibilidad on-chain del progreso.
3. **Sin checkpoint intermedio** → si goods se detienen en aduana DESPUÉS del DUE pero ANTES del BL/AWB, no hay forma de cancelar desde el estado intermedio (el estado intermedio no existe).
4. **Indexers off-chain bugueados** → un filter por `EstadoRedencion.EN_EXPORTACION` siempre devuelve empty set.
5. **Audit trail degradado** → para reporting regulatorio (MiCA, CNV), el estado on-chain no refleja el proceso aduanero real.

---

## Decision

Se adopta la **Opción A** (de las 3 evaluadas en la discusión previa): **implementar el spec original — 2 funciones separadas con flujo de 3 fases activas**.

### Mecánica

**Estado machine resultante:**

```
                  iniciarRedencion()
                       ↓
                   ┌─────────┐
                   │INICIADA │ ←──┐
                   └────┬────┘    │
                        │         │ cancelarRedencion()
        confirmarExportacion(dueNumero)
                        ↓         │
                ┌──────────────┐  │
                │EN_EXPORTACION│ ─┤
                └───────┬──────┘  │
                        │         │ cancelarRedencion() (NEW)
         completarRedencion(hashBLAWB)
                        ↓
                  ┌──────────┐    ┌──────────┐
                  │COMPLETADA│    │CANCELADA │
                  └──────────┘    └──────────┘
```

**Cambios en `RedemptionManager.sol`:**

1. **`confirmarExportacion(uint256 redencionId, string calldata dueNumero)` — refactorizada:**
   - Eliminado parámetro `hashBLAWB`
   - Validación: estado == `INICIADA`, dueNumero no empty + dentro de límite
   - Transición: `INICIADA → EN_EXPORTACION`
   - **No quema tokens, no decrementa lock** — solo registra DUE
   - Emite `RedencionEnExportacion`

2. **`completarRedencion(uint256 redencionId, bytes32 hashBLAWB)` — nueva función:**
   - `onlyRole(ORACLE_ROLE)` + `nonReentrant`
   - Validación: estado == `EN_EXPORTACION`, hashBLAWB no zero
   - Pre-check defensivo de balance (RM-04 path)
   - Transición: `EN_EXPORTACION → COMPLETADA`
   - **Decrementa el lock acumulator** y **quema los tokens** del comprador
   - Emite `RedencionCompletada`

3. **`cancelarRedencion` — ampliada (ADR-017 cambio):**
   - Acepta cancelar desde `INICIADA` **O** desde `EN_EXPORTACION` (checkpoint operacional)
   - El lock se libera correctamente en ambos casos
   - Los 3 paths de access control de ADR-015 (Oracle / Compliance / Buyer-timeout) siguen aplicando

4. **Nuevo error `NotInExportacion()`** — para `completarRedencion` cuando el estado no es `EN_EXPORTACION`.

5. **NatSpec actualizado** en las 3 funciones (confirmar, completar, cancelar) explicando el flujo de 3 fases.

**Cambios en `IRedemptionManager.sol`:**

- Signature de `confirmarExportacion` cambia (sin `hashBLAWB`)
- Nueva signature `completarRedencion(uint256 redencionId, bytes32 hashBLAWB)`
- NatSpec del evento `RedencionEnExportacion` clarifica que se emite cuando estado pasa a `EN_EXPORTACION` (NO cuando completa)

---

## Alternatives considered

### Opción B — Simplificar el spec, eliminar `EN_EXPORTACION` del enum (rechazada)

Mantener el código de 1 función actual y actualizar el spec para matchearlo. Eliminar el estado `EN_EXPORTACION` del enum y el evento `RedencionEnExportacion`.

**Por qué se rechazó:**
- ❌ El buyer queda ciego durante 30-45 días (sin visibilidad del progreso)
- ❌ Sin checkpoint intermedio para recovery de incidentes aduaneros
- ❌ Mata la auditabilidad del proceso real on-chain
- ❌ **Decisión irreversible bajo ADR-003 (inmutabilidad sin proxy)** — si en fase 2+ se quiere agregar el checkpoint, requiere redeploy del contrato
- ❌ El spec original fue diseñado pensando en el flujo real Bolivia → UE; respetarlo es la decisión arquitectónicamente correcta

### Opción C — Híbrido: 1 función con 2 transiciones virtuales (rechazada)

Mantener 1 función `confirmarExportacion(dueNumero, hashBLAWB)` pero escribir las 2 transiciones de estado en la misma tx (`INICIADA → EN_EXPORTACION → COMPLETADA`), emitiendo ambos eventos.

**Por qué se rechazó:**
- ❌ El estado `EN_EXPORTACION` es virtualmente inobservable (se escribe y sobrescribe en la misma tx)
- ❌ Timestamps de los 2 eventos son idénticos → audit trail engañoso
- ❌ No resuelve la UX del buyer (sigue siendo "instantáneo")
- ❌ Solución cosmética que engaña a auditores

---

## Consequences

### Positivas

1. **Spec ↔ código alineados** — implementa el `CONTRACT-SPECS.md` §6.5 al pie de la letra. Cero divergencias para auditores externos.
2. **Buyer ve progreso real** — la redención pasa por `INICIADA → EN_EXPORTACION → COMPLETADA` con timestamps separados (createdAt, evento RedencionEnExportacion, completedAt). Frontend puede mostrar timeline real del export.
3. **Checkpoint intermedio operacional** — si goods se detienen en aduana después del DUE, el Oracle/Compliance puede cancelar desde `EN_EXPORTACION` (refund operation aplicable).
4. **Audit trail completo** — para reporting regulatorio (MiCA, CNV, IRS-equivalent), el estado on-chain refleja fielmente el progreso aduanero.
5. **Indexers funcionan correctamente** — un filter por `EstadoRedencion.EN_EXPORTACION` ahora retorna las redenciones activas en exportación.
6. **Recovery de incidentes** — cancelarRedencion desde `EN_EXPORTACION` libera el lock y devuelve disponibilidad al buyer si el export falla.

### Negativas / tradeoffs aceptados

1. **2× gas operacional para el Oracle** — Safe 2-de-3 firma 2 txs por redención (una con DUE, otra con BL/AWB). En Plume L2 el costo extra es despreciable (~$0.001/tx).
2. **Mayor superficie de auditoría** — 2 funciones en lugar de 1, lógica de transición de estado más explícita, +1 error custom. Trade-off compensado por mejor audit trail.
3. **Más tests** — los ~15 tests existentes de `confirmarExportacion` se split en tests específicos de cada función (~25-30 tests post-cambio).
4. **Breaking change en la interface** — herramientas off-chain (frontends, indexers, monitores) que llamaban `confirmarExportacion(id, due, hashBLAWB)` deben actualizarse. Como NO hay deploy todavía, costo cero.
5. **Coordinación operacional del Safe** — el Safe debe firmar 2 veces por redención. Requiere proceso operacional claro: "firmar DUE cuando llega de SENASAG" + "firmar BL/AWB cuando llega del courier".

### Riesgos secundarios identificados (NO resueltos por este ADR)

1. **Race condition entre completarRedencion y cancelarRedencion** — si Oracle envía `completarRedencion` al mismo tiempo que buyer (post-timeout) o Compliance Officer envía `cancelarRedencion`, una va a fallar por estado ya finalizado. **Aceptable** — el primero gana, el segundo revierte con `RedencionAlreadyFinalized`.
2. **Oracle olvida llamar `completarRedencion`** — si Oracle confirma DUE pero nunca completa, la redención queda en `EN_EXPORTACION` indefinidamente. **Mitigado** por el timeout del ADR-015 (60 días desde `createdAt`) que permite buyer self-cancel desde EN_EXPORTACION.
3. **Estado `EN_EXPORTACION` interactúa con `iniciarRedencion`** — ningún nuevo `iniciarRedencion` se ve afectado, pero un comprador que tenga una redención en `EN_EXPORTACION` ve sus tokens lockeados hasta completar/cancelar. No es bug, es feature.

---

## Implementation

### Cambios en `RedemptionManager.sol`

```solidity
// Nuevo error
error NotInExportacion();

// confirmarExportacion — solo DUE
function confirmarExportacion(uint256 redencionId, string calldata dueNumero) external onlyRole(ORACLE_ROLE) {
    Redencion storage r = _redenciones[redencionId];
    if (r.comprador == address(0)) revert RedencionNotIniciada();
    if (r.estado != EstadoRedencion.INICIADA) revert RedencionAlreadyFinalized();

    bytes memory dueBytes = bytes(dueNumero);
    if (dueBytes.length == 0) revert EmptyDUE();
    if (dueBytes.length > MAX_DUE_NUMERO_LENGTH) revert DUENumeroTooLong();

    r.estado = EstadoRedencion.EN_EXPORTACION;
    r.dueNumero = dueNumero;
    emit RedencionEnExportacion(redencionId, msg.sender, dueNumero);
}

// completarRedencion — solo BL/AWB + burn
function completarRedencion(uint256 redencionId, bytes32 hashBLAWB) external onlyRole(ORACLE_ROLE) nonReentrant {
    Redencion storage r = _redenciones[redencionId];
    if (r.comprador == address(0)) revert RedencionNotIniciada();
    if (r.estado != EstadoRedencion.EN_EXPORTACION) revert NotInExportacion();
    if (hashBLAWB == bytes32(0)) revert InvalidHash();

    // RM-04: pre-validación defensiva de balance
    uint256 balance = IERC1155(address(assetVault)).balanceOf(r.comprador, r.loteId);
    if (balance < r.cantidadTokens) revert BalanceInsuficiente();

    // Effects
    r.estado = EstadoRedencion.COMPLETADA;
    r.hashBLAWB = hashBLAWB;
    r.completedAt = uint64(block.timestamp);
    _tokensLockedFor[r.loteId][r.comprador] -= r.cantidadTokens;

    // Interactions
    assetVault.burnForRedemption(r.comprador, r.loteId, r.cantidadTokens);
    emit RedencionCompletada(redencionId, msg.sender, hashBLAWB);
}

// cancelarRedencion — ampliada (acepta INICIADA O EN_EXPORTACION)
function cancelarRedencion(uint256 redencionId, bytes32 reason) external nonReentrant {
    Redencion storage r = _redenciones[redencionId];
    if (r.comprador == address(0)) revert RedencionNotIniciada();
    if (r.estado != EstadoRedencion.INICIADA && r.estado != EstadoRedencion.EN_EXPORTACION) {
        revert RedencionAlreadyFinalized();
    }
    if (reason == bytes32(0)) revert EmptyReason();

    // ADR-015 access control (sin cambios)
    bool isOracle = hasRole(ORACLE_ROLE, msg.sender);
    bool isCompliance = hasRole(COMPLIANCE_OFFICER_ROLE, msg.sender);
    // slither-disable-next-line timestamp
    bool isBuyerAfterTimeout =
        (msg.sender == r.comprador && block.timestamp >= r.createdAt + REDENCION_TIMEOUT);
    if (!isOracle && !isCompliance && !isBuyerAfterTimeout) revert OnlyAuthorizedCanceler();

    // Effects (sin cambios)
    r.estado = EstadoRedencion.CANCELADA;
    r.cancelReason = reason;
    r.completedAt = uint64(block.timestamp);
    _tokensLockedFor[r.loteId][r.comprador] -= r.cantidadTokens;
    emit RedencionCancelada(redencionId, msg.sender, reason);
}
```

### Cambios en `IRedemptionManager.sol`

- Signature de `confirmarExportacion` actualizada (sin `hashBLAWB`)
- Nueva signature `completarRedencion(uint256 redencionId, bytes32 hashBLAWB)`
- NatSpec del evento `RedencionEnExportacion` aclarado: emitido cuando state transiciona a EN_EXPORTACION (no a COMPLETADA)

---

## Testing requirements

### Tests existentes a actualizar (~15)

Tests de `confirmarExportacion(id, due, hashBLAWB)` se split en:
- Tests específicos de `confirmarExportacion(id, due)` (sin BL/AWB)
- Tests específicos de `completarRedencion(id, hashBLAWB)` (con BL/AWB)
- Tests que necesitan el flujo completo usan un helper `_confirmarYCompletar()`

### Tests nuevos a agregar (~10)

- `test_confirmarExportacion_TransitionsTo_EnExportacion`
- `test_confirmarExportacion_DoesNotBurnTokens`
- `test_confirmarExportacion_DoesNotDecrementLock`
- `test_completarRedencion_HappyPath_BurnsTokens`
- `test_completarRedencion_RevertWhen_RedencionNotInExportacion`
- `test_completarRedencion_RevertWhen_HashBLAWBZero`
- `test_completarRedencion_OnlyOracle_RevertWhen_NonOracle`
- `test_completarRedencion_DecrementsLockAccumulator`
- `test_completarRedencion_DefensiveRevert_WhenBalanceMockedBelowCantidad`
- `test_cancelarRedencion_FromEnExportacion_HappyPath` (cancel from intermediate state)

### Verificación obligatoria

- ✅ `forge test`: 100% passing
- ✅ Coverage RedemptionManager.sol: 100% lines/statements/branches/functions
- ✅ Slither: 0 nuevos findings
- ✅ El test del invariant del lock acumulator sigue verde (cantidad en lock vs balance)

---

## Migration plan

**Pre-mainnet:** sin migración necesaria. Cambio se aplica directamente.

**Post-mainnet (no aplica hoy):** sería breaking change para off-chain tooling (frontends, indexers, monitores) que asume el flujo de 1 función. Requeriría coordinación de actualización con todos los consumidores antes del redeploy. Como el contrato es **inmutable sin proxy** (ADR-003), no hay migración on-chain — sería un redeploy con migración de estado de redenciones existentes.

---

## References

- **Spec:** `docs/architecture/CONTRACT-SPECS.md` §6.5 (flujo de 3 fases con 2 funciones)
- **Audit:** `docs/security-reviews/audit-RedemptionManager-deep-2026-05-26.md` §6 (finding RM-11)
- **ADRs previos:** ADR-015 (Timeout Policy), ADR-016 (Pause Asymmetry)
- **Inmutabilidad:** ADR-003 (4 contratos inmutables sin proxy)
