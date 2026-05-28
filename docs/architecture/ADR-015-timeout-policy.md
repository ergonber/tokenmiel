# ADR-015: Timeout Policy for Redemption Cancellation

**Status:** Accepted
**Date:** 2026-05-27
**Author:** Daniel Hidalgo Carrasco
**Tags:** redemption, access-control, timeout, consumer-protection, mica, regulatory
**Resuelve:** RM-06 (HIGH), RM-07 (HIGH)
**Supersedes:** N/A
**Superseded by:** N/A

---

## Context

La auditoría de seguridad profunda sobre `RedemptionManager.sol` (2026-05-26, documentada en `docs/security-reviews/audit-RedemptionManager-deep-2026-05-26.md`) identificó dos findings de severidad **HIGH** que comparten causa raíz:

### RM-06 — El comprador no tiene escape si el Oracle desaparece

Hoy, solo `ORACLE_ROLE` puede llamar `cancelarRedencion`. Si el Safe 2-de-3 que controla ese rol se vuelve inaccesible (signers perdidos, multi-sig comprometido, equipo SRL disuelto, sanción regulatoria sobre la SRL), las redenciones en estado `INICIADA` quedan ahí indefinidamente. Bajo el modelo Opción B (lock contable, ADR no formalizado pero implementado en commit `92fd0e0`), esto significa que los tokens del comprador permanecen **lockeados eternamente** en el acumulador `_tokensLockedFor`, sin compensación posible.

### RM-07 — Sin timeout / expiración para redenciones stuck en `INICIADA`

Una vez `iniciarRedencion` crea el registro, no hay mecanismo de cleanup automático. El lote puede transicionar de `ALMACENADO` a `AGOTADO` mientras quedan redenciones huérfanas que nunca se confirman ni cancelan. El lock acumulador queda con tokens "fantasma" para siempre.

### Riesgos compoundeados

1. **Regulatorio (HIGH):** MiCA y la Directiva 2011/83/UE sobre derechos del consumidor exigen mecanismos de reversibilidad en operaciones B2C dentro de ventana razonable. Sin escape valve para el comprador, la plataforma **viola consumer law europeo** desde el primer comprador retail europeo.
2. **Reputacional (HIGH):** un comprador frustrado denunciando públicamente "mis tokens están stuck porque la SRL se desapareció" mata el go-to-market.
3. **Centralización (HIGH):** dependencia única del Oracle Safe es un single point of failure inaceptable para un protocolo RWA serio.
4. **Económico (MEDIUM):** tokens lockeados eternamente representan capital del comprador inmovilizado sin recuperación → equivalente a quemarlos sin compensación.

Ambos findings (RM-06 + RM-07) se resuelven con **un único mecanismo de diseño**: una timeout policy explícita con vías de escape claras.

---

## Decision

Se adopta la **Opción A — Buyer self-cancel + Compliance Officer co-canceler**.

### Mecánica

**Constante nueva en `RedemptionManager.sol`:**

```solidity
uint256 public constant REDENCION_TIMEOUT = 60 days;
```

**Tres paths válidos para cancelar una redención en estado `INICIADA`:**

| # | Caller | Condición temporal | Justificación |
|---|---|---|---|
| 1 | `ORACLE_ROLE` (Safe 2-de-3) | Ninguna — siempre | Operación normal: cancela cuando aduana rechaza, courier falla, etc. |
| 2 | `COMPLIANCE_OFFICER_ROLE` (titular o suplente) | Ninguna — siempre | Motivos regulatorios o compliance (alineación con `CONTRACT-SPECS.md` §6.3) |
| 3 | `msg.sender == r.comprador` (el comprador mismo) | `block.timestamp >= r.createdAt + REDENCION_TIMEOUT` | Escape valve del comprador si Oracle desaparece — garantiza no-lock-eterno |

### Lógica de access control inline

Se **elimina** el modifier `onlyRole(ORACLE_ROLE)` de `cancelarRedencion` y se reemplaza con lógica inline que evalúa los 3 paths:

```solidity
function cancelarRedencion(uint256 redencionId, bytes32 reason) external nonReentrant {
    Redencion storage r = _redenciones[redencionId];
    if (r.comprador == address(0)) revert RedencionNotIniciada();
    if (r.estado != EstadoRedencion.INICIADA) revert RedencionAlreadyFinalized();
    if (reason == bytes32(0)) revert EmptyReason();

    bool isOracle = hasRole(ORACLE_ROLE, msg.sender);
    bool isCompliance = hasRole(COMPLIANCE_OFFICER_ROLE, msg.sender);
    bool isBuyerAfterTimeout =
        (msg.sender == r.comprador && block.timestamp >= r.createdAt + REDENCION_TIMEOUT);
    if (!isOracle && !isCompliance && !isBuyerAfterTimeout) revert OnlyAuthorizedCanceler();

    // Effects: idénticos al flujo anterior
    r.estado = EstadoRedencion.CANCELADA;
    r.cancelReason = reason;
    r.completedAt = uint64(block.timestamp);
    _tokensLockedFor[r.loteId][r.comprador] -= r.cantidadTokens;
    emit RedencionCancelada(redencionId, msg.sender, reason);
}
```

### Decisión sobre el timeout — 60 días

Se eligió **60 días** como timeout default basado en los siguientes datos operacionales:

| Stage del export Bolivia → UE | Tiempo típico |
|---|---|
| DUE emission (SENASAG/Bolivia) | 3-7 días |
| Logistic preparation + courier pickup | 5-10 días |
| Ocean/air freight Bolivia → UE | 15-30 días |
| Customs clearance UE | 3-10 días |
| BL/AWB delivery to oracle | 1-3 días |
| **Total típico** | **30-60 días** |

- **30 días** sería agresivo (apenas cubre el caso medio, deja margen 0)
- **90 días** sería conservador (cubre 99% pero castiga al buyer)
- **60 días** balancea protección del buyer con tolerancia a delays operacionales reales

Si en operación real vemos que 60 días es demasiado o muy poco, ajustar la constante es trivial. Como las redenciones existentes seguirían usando su `createdAt`, no hay riesgo retroactivo.

---

## Alternatives considered

### Opción B — Sistema de timeouts en escalones (rechazada)

**Mecánica propuesta:**
- 30 días → `COMPLIANCE_OFFICER` puede cancelar (escalado a compliance)
- 60 días → comprador puede self-cancel
- 180 días → **cualquiera** puede cancelar (failsafe público)

**Por qué se rechazó:**
- ✅ Más defense-in-depth, failsafe a 180d garantiza no-lock-eterno absoluto
- ❌ Overengineered para MVP — 3 tiers de access control con timing
- ❌ "Anyone can cancel after 180d" es semánticamente raro (¿por qué un random cancelaría?)
- ❌ Mayor superficie de auditoría sin beneficio claro vs Opción A + COMPLIANCE_OFFICER siempre disponible
- ❌ Si en fase 2+ se necesita, se puede agregar como evolution

### Opción C — Oracle-extend + Buyer cancel after timeout (rechazada)

**Mecánica propuesta:**
- Nueva función `extenderRedencion(redencionId, days)` solo para Oracle
- Buyer cancel después de `effectiveDeadline` (que incluye extensions)
- Cap absoluto en lifetime (e.g., 180 días totales)

**Por qué se rechazó:**
- ✅ Alinea con realidad operacional — aduana puede legítimamente tardar más en casos complejos
- ❌ **Más superficie de ataque** — Oracle puede abusar extensions para bloquear al buyer
- ❌ Comprador percibe "Oracle siempre va a extender" → problema de confianza
- ❌ Requiere state adicional (`effectiveDeadline`) y lógica de cap
- ❌ Las extensions reales son raras — overhead no justificado

Si en operación real se identifica que >5% de redenciones legítimamente requieren extensión, esto se puede agregar como evolution sin romper Opción A.

### Opción "no hacer nada" (rechazada)

Mantener el status quo deja los riesgos HIGH RM-06 + RM-07 abiertos. **Bloqueante para mainnet** desde la perspectiva de:
- Auditoría externa (Sherlock / Trail of Bits / Cantina) que va a flagear esto como inaceptable
- Compliance MiCA / UE consumer law
- Confianza del comprador (un sancionado tendría argumentos legales válidos)

---

## Consequences

### Positivas

1. **El comprador SIEMPRE tiene escape.** Después de 60 días, puede recuperar sus tokens del lock acumulador sin depender del Oracle. Esto cierra el riesgo central de los findings RM-06 + RM-07.
2. **`COMPLIANCE_OFFICER_ROLE` puede cancelar por motivos regulatorios** sin esperar timeout. Alineación con `CONTRACT-SPECS.md` §6.3 que estaba divergente en la implementación.
3. **Cumple MiCA + Directiva 2011/83/UE** sobre derechos del consumidor.
4. **Auditores externos lo decodifican rápido** — 3 paths claros, lógica determinista, código simple.
5. **Compatible con Opción B (lock acumulador)** ya implementada. La cancelación libera el lock correctamente.

### Negativas / tradeoffs aceptados

1. **60 días es largo para un comprador frustrado.** Si el Oracle desaparece el día 1, el buyer espera 2 meses para recuperar sus tokens. **Mitigante:** el `COMPLIANCE_OFFICER` (titular + suplente, controlado por la empresa) puede cancelar antes si la situación lo amerita.
2. **No hay recovery si el wallet del comprador se pierde.** Si el buyer pierde acceso a su clave privada, sus tokens lockeados quedan inaccesibles (igual que sus tokens libres, no es problema nuevo).
3. **No hay mecanismo formal de extension legítima.** Si una redención legítimamente tarda más de 60d (caso aduanero excepcional), el Oracle debe coordinar con el comprador off-chain para que no cancele. Se acepta este riesgo operacional para el MVP.
4. **Cambio breaking-ish en el ABI** — `cancelarRedencion` ya no es `onlyRole(ORACLE_ROLE)`. Cualquier herramienta off-chain que asume eso (ej: simuladores de UI, monitoring) tendría que actualizar sus expectations. Como NO hay nada deployado todavía, costo cero.

### Riesgos secundarios identificados (NO resueltos por este ADR)

1. **MEV / front-running:** un comprador que cancela su redención debido al Oracle inactivo podría ser front-run por el Oracle volviéndose activo de golpe (race condition entre `cancelarRedencion(buyer)` y `confirmarExportacion(oracle)`). No hay protección formal — se asume que en práctica el Oracle no va a confirmar exportaciones aleatoriamente sin contexto operacional. Si se vuelve un problema real, agregar `cancelationCommitDelay` o mecanismo similar.
2. **Wallet del buyer comprometido post-timeout:** un atacante con acceso a la wallet podría llamar `cancelarRedencion` antes que el buyer legítimo. Mitigante: con `COMPLIANCE_OFFICER` activo, se puede revertir la cancelación operacionalmente (re-iniciar la redención). Sin compliance officer activo, el buyer queda expuesto — mismo riesgo que cualquier asset que esté en su wallet.

---

## Implementation

### Cambios en `RedemptionManager.sol`

1. Agregar constante:
   ```solidity
   uint256 public constant REDENCION_TIMEOUT = 60 days;
   ```
2. Agregar custom error:
   ```solidity
   error OnlyAuthorizedCanceler();
   ```
3. Modificar `cancelarRedencion`:
   - Eliminar modifier `onlyRole(ORACLE_ROLE)`
   - Agregar lógica inline de 3 paths (ver §Decision arriba)
   - Actualizar NatSpec para reflejar los nuevos paths

### Cambios en `IRedemptionManager.sol`

Declarar la constante en la interface para que sea parte del contrato público:

```solidity
function REDENCION_TIMEOUT() external view returns (uint256);
```

(con `// slither-disable-next-line naming-convention` igual que `MAX_DUE_NUMERO_LENGTH`).

### Cambios en tests

5 tests nuevos en `RedemptionManager.t.sol`:

| # | Test | Cubre |
|---|---|---|
| 1 | `test_cancelarRedencion_ByComplianceOfficer_HappyPath` | Path 2: compliance siempre puede cancelar |
| 2 | `test_cancelarRedencion_ByComplianceOfficerSuplente_HappyPath` | Path 2 con el suplente |
| 3 | `test_cancelarRedencion_ByBuyer_AfterTimeout_HappyPath` | Path 3: comprador self-cancel después de 60d |
| 4 | `test_cancelarRedencion_RevertWhen_BuyerCallsBeforeTimeout` | Path 3 negativo: comprador antes de 60d revierte `OnlyAuthorizedCanceler` |
| 5 | `test_cancelarRedencion_RevertWhen_RandomCallerEvenAfterTimeout` | Path negativo: random address (no oracle, no compliance, no buyer) siempre revierte |

Los tests existentes deben seguir pasando (el path 1 — Oracle — no cambia su comportamiento).

---

## Testing requirements

- ✅ **Cobertura branch 100%** — los 3 paths positivos + 1 negativo deben estar testeados
- ✅ **Compatibilidad con tests existentes** — el path Oracle no cambia
- ✅ **Verificar invariante post-cancel** — `_tokensLockedFor` decrementa correctamente sin importar quién canceló
- ✅ **Slither** — sin nuevos findings HIGH/MEDIUM
- ⏸️ **Fuzz testing del timeout** — opcional, agregar `testFuzz_buyerCancel_RevertsBeforeTimeout(uint256 elapsed)` en próxima iteración

---

## Migration plan

**Pre-mainnet:** sin migración necesaria. El cambio se aplica directamente en el código del contrato y sus tests.

**Post-mainnet (no aplica hoy):** este ADR cambiaría requeriría redeploy del contrato. Como el contrato es **inmutable sin proxy** (ADR-003), la migración sería un breaking change que afecta todos los lotes existentes.

---

## References

- **Audit:** `docs/security-reviews/audit-RedemptionManager-deep-2026-05-26.md` §6 (findings RM-06, RM-07)
- **Spec divergente:** `docs/architecture/CONTRACT-SPECS.md` §6.3 (define `COMPLIANCE_OFFICER_ROLE` como segundo canceler — divergencia que este ADR cierra)
- **ADR previo relacionado:** ADR-013 (pause en IdentityRegistry — patrón de access control con asymmetry)
- **Regulatorio:**
  - [MiCA Regulation 2023/1114](https://eur-lex.europa.eu/eli/reg/2023/1114/oj)
  - [Directiva 2011/83/UE — Derechos del consumidor](https://eur-lex.europa.eu/legal-content/ES/TXT/?uri=CELEX:32011L0083)
- **Findings deferidos relacionados:**
  - RM-11 (Spec Reconciliation — `EN_EXPORTACION` dead state) → ADR-016 futuro
  - RM-21 (Pause Asymmetry sistémica) → ADR-017 futuro
