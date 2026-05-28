# ADR-016: Pause/Unpause Asymmetry — Propagación sistémica a los 3 contratos del MVP

**Status:** Accepted
**Date:** 2026-05-27
**Author:** Daniel Hidalgo Carrasco
**Tags:** smart-contracts, pause, circuit-breaker, access-control, defense-in-depth, systemic
**Resuelve:** RM-21 (MEDIUM)
**Relacionado:** ADR-013 (introduce el patrón asimétrico en IdentityRegistry)
**Supersedes:** N/A
**Superseded by:** N/A

---

## Context

`ADR-013` (2026-05-22) estableció una asimetría de roles entre `pause()` y `unpause()` en `IdentityRegistry.sol` como **defensa contra el compromiso de un Compliance Officer**:

- `pause()`: callable por `COMPLIANCE_OFFICER_ROLE` **OR** `DEFAULT_ADMIN_ROLE` (defensa cruzada — respuesta rápida)
- `unpause()`: callable **solo** por `DEFAULT_ADMIN_ROLE` (Safe 2-de-3 — decisión deliberada)

**Razonamiento original:** si un Compliance Officer se ve comprometido (phishing, malware, insider attack), el atacante puede pausar el contrato (causando DoS) pero NO puede despausar a voluntad — la recuperación requiere el Safe multi-sig.

### El problema sistémico (RM-21)

La auditoría profunda de `RedemptionManager.sol` (2026-05-26) identificó que **esta convención NUNCA se propagó** a los otros 2 contratos del MVP. Estado actual:

| Contrato | `pause()` | `unpause()` | Cumple ADR-013? |
|---|---|---|---|
| `IdentityRegistry.sol` | `COMPLIANCE_OFFICER` OR `DEFAULT_ADMIN` | `DEFAULT_ADMIN` only | ✅ |
| `AssetVault.sol` | `COMPLIANCE_OFFICER` only | `COMPLIANCE_OFFICER` only | ❌ Simétrico |
| `RedemptionManager.sol` | `COMPLIANCE_OFFICER` only | `COMPLIANCE_OFFICER` only | ❌ Simétrico |

**Razón histórica:** AssetVault y RedemptionManager fueron implementados ANTES de ADR-013. Cuando se creó ADR-013 para IdentityRegistry, no se propagó hacia atrás. El audit profundo lo flageó como inconsistencia.

### Threat model concreto

**Escenario:** atacante obtiene control de la wallet del Compliance Officer.

| Acción del atacante | Estado actual | Con ADR-013 aplicado |
|---|---|---|
| Pausar AssetVault | ✅ Funciona (DoS) | ✅ Funciona (DoS) |
| Despausar AssetVault al timing óptimo | ✅ **Funciona** — atacante controla el ciclo | ❌ **Bloqueado** — requiere Safe 2-de-3 |
| Pausar/Despausar repetidamente para timing attacks | ✅ **Funciona** | ❌ **Bloqueado** |
| Misma secuencia en RedemptionManager | ✅ **Funciona** | ❌ **Bloqueado** |

**El threat es real.** Ataques a operadores con multi-sig han ocurrido en Curve, Wormhole, Ronin, y muchos otros protocolos mayores. Asumir que el Compliance Officer NUNCA será comprometido es ingenuo.

---

## Decision

Se adopta la **Opción A** (de las 3 evaluadas en la discusión previa): **propagar el patrón de ADR-013 a los 3 contratos del MVP de forma uniforme**.

### Patrón uniforme

Para los 3 contratos (`IdentityRegistry`, `AssetVault`, `RedemptionManager`):

```solidity
error UnauthorizedPauseActor();

/// @dev pause(): defensa cruzada — Compliance Officer o Default Admin pueden pausar.
function pause() external whenNotPaused {
    if (!hasRole(COMPLIANCE_OFFICER_ROLE, msg.sender) && !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
        revert UnauthorizedPauseActor();
    }
    _pause();
    emit EmergencyPaused(msg.sender, uint64(block.timestamp));
}

/// @dev unpause(): solo Default Admin (Safe 2-de-3) — decisión deliberada post-incidente.
function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
    _unpause();
    emit EmergencyUnpaused(msg.sender, uint64(block.timestamp));
}
```

### Cambios concretos

`IdentityRegistry.sol` — **sin cambios** (ya cumple).

`AssetVault.sol`:
- Agregar error `UnauthorizedPauseActor()`
- Modificar `pause()`: eliminar `onlyRole(COMPLIANCE_OFFICER_ROLE)`, agregar `whenNotPaused` + check inline
- Modificar `unpause()`: cambiar de `onlyRole(COMPLIANCE_OFFICER_ROLE)` a `onlyRole(DEFAULT_ADMIN_ROLE)`

`RedemptionManager.sol`:
- Mismos cambios que AssetVault

### Tests afectados

| Test | Contrato | Acción |
|---|---|---|
| `test_pause_OnlyComplianceOfficer` | AssetVault | Renombrar/clarificar; sigue válido (COMPLIANCE_OFFICER aún puede pausar) |
| `test_unpause_RestoresComprar` | AssetVault | Modificar — usar ADMIN para unpause |
| `test_pause_OnlyComplianceOfficer_HappyPath` | RedemptionManager | Sigue válido |
| `test_pause_RevertWhen_NonComplianceOfficer` | RedemptionManager | Sigue válido (random sigue revirtiendo) |
| `test_unpause_OnlyComplianceOfficer_HappyPath` | RedemptionManager | **BREAKING** — renombrar a `_ByDefaultAdmin_HappyPath` |
| `test_unpause_RevertWhen_NonComplianceOfficer` | RedemptionManager | **BREAKING** — renombrar a `_RevertWhen_NonDefaultAdmin`, ajustar caller |
| `test_unpause_EmitsEmergencyUnpausedEvent` | RedemptionManager | **BREAKING** — usar ADMIN para unpause |

### Tests nuevos para cobertura completa

Para cada contrato (AssetVault y RedemptionManager):
- `test_pause_ByDefaultAdmin_HappyPath` — DEFAULT_ADMIN también puede pausar (nuevo path)
- `test_unpause_RevertWhen_ComplianceOfficer` — **cambio de seguridad** — COMPLIANCE_OFFICER ahora REVIERTE en unpause
- `test_pause_RevertWhen_UnauthorizedActor` — random caller revierte con `UnauthorizedPauseActor` (no con AccessControl revert genérico)

---

## Alternatives considered

### Opción B — Limitar ADR-013 a IdentityRegistry, mantener AssetVault/RedemptionManager simétricos

**Argumento:** la asimetría tiene sentido para IdentityRegistry (compromiso del `BACKEND_SIGNER` que escribe KYCs masivamente), pero NO es necesaria para AssetVault y RedemptionManager porque sus mutators críticos ya están protegidos por otros roles (Oracle Safe 2-de-3, Backend Signer).

**Por qué se rechazó:**
- ❌ La inconsistencia entre contratos queda **explícita** y auditores externos la van a cuestionar
- ❌ El threat model **sí aplica** — si COMPLIANCE_OFFICER se compromete, atacante tiene control bidireccional de pause en 2 de 3 contratos
- ❌ Mensaje confuso a auditores: "¿por qué este contrato sí y este no?" — difícil de defender contractualmente
- ❌ Crea precedente: "asimetría es opcional según criticidad percibida" → próximos contratos van a debatir caso por caso

### Opción C — Híbrido: asimetría solo en AssetVault, simétrico en RedemptionManager

**Argumento:** AssetVault es "más crítico" (custodia USDC, mints/burns), entonces aplica la asimetría ahí. RedemptionManager mantiene simetría por simplicidad.

**Por qué se rechazó:**
- ❌ **Peor de los dos mundos** — agrega complejidad sin uniformidad
- ❌ Difícil de explicar a auditores: "¿por qué este sí y este no?"
- ❌ El argumento "RedemptionManager es menos crítico" es debatible (afecta el flujo del usuario final)
- ❌ Crea precedente confuso para futuros contratos

### Opción "no hacer nada"

Dejar el estado actual y aceptar el finding RM-21.

**Por qué se rechazó:**
- ❌ Auditores externos (Sherlock, Trail of Bits, Cantina) van a flagearlo en el primer review
- ❌ Threat model real con consecuencias graves
- ❌ Costo de implementación es bajo — no hay razón para no hacerlo

---

## Consequences

### Positivas

1. **Defensa contra Compliance Officer comprometido** en los 3 contratos uniformemente. Un atacante con la wallet de COMPLIANCE_OFFICER puede pausar (DoS) pero NO puede ejecutar timing attacks pause-unpause.
2. **Consistencia cross-contract** — los 3 contratos del MVP siguen el mismo patrón. Auditores externos decodifican una sola convención.
3. **Cumple `ADR-013` uniformemente** — sin excepciones que justificar, sin complejidad cognitiva extra.
4. **`DEFAULT_ADMIN_ROLE`** (Safe 2-de-3) tiene el control deliberado de la recuperación post-incidente. Es exactamente el rol apropiado para esa decisión.

### Negativas / tradeoffs aceptados

1. **Mayor costo operacional para unpause** — requiere coordinar 3 signers del Safe. Aceptable porque unpause es un evento excepcional (post-incidente) y debe ser deliberado.
2. **Riesgo de permapause** si el Safe se vuelve inaccesible. **Mitigado por `ADR-012`** (delay de 3 días para transferencias de `DEFAULT_ADMIN_ROLE`) que permite recovery vía nuevo admin.
3. **Breaking change en tests** — 5 tests cambian de comportamiento o se renombran. No afecta producción (pre-mainnet).
4. **Cambio de signatura para off-chain tooling** — si algún script asume que `unpause` lo llama COMPLIANCE_OFFICER, ahora va a fallar. Como no hay deploy todavía, costo cero.

---

## Implementation

### Patrón uniforme aplicado a AssetVault y RedemptionManager

```solidity
// Error nuevo (agregar en la sección de errors)
error UnauthorizedPauseActor();

// pause() — defensa cruzada
function pause() external whenNotPaused {
    if (!hasRole(COMPLIANCE_OFFICER_ROLE, msg.sender) && !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
        revert UnauthorizedPauseActor();
    }
    _pause();
    emit EmergencyPaused(msg.sender, uint64(block.timestamp));
}

// unpause() — solo Safe 2-de-3
function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
    _unpause();
    emit EmergencyUnpaused(msg.sender, uint64(block.timestamp));
}
```

### Tests a agregar/modificar

Por contrato (AssetVault y RedemptionManager) — total 4-6 tests nuevos + 2-3 actualizados.

---

## Testing requirements

- ✅ **Cobertura branch 100%** — los 2 paths positivos de pause (COMPLIANCE_OFFICER, DEFAULT_ADMIN) + path negativo deben estar testeados
- ✅ **Compatibilidad con tests existentes** — los tests de mutators bajo pause (todos los _RevertWhen_Paused) siguen sin cambios
- ✅ **Slither** — sin nuevos findings HIGH/MEDIUM
- ✅ **Coverage RedemptionManager.sol** — mantener 100%

---

## Migration plan

**Pre-mainnet:** sin migración necesaria. Cambios se aplican directamente.

**Post-mainnet (no aplica hoy):** este cambio requeriría redeploy de los 2 contratos afectados (AssetVault + RedemptionManager). Como los contratos son **inmutables sin proxy** (ADR-003), la migración sería un breaking change que afecta todos los lotes existentes.

---

## References

- **ADR introductor:** `ADR-013` — Pause/Unpause en IdentityRegistry con scope limitado a mutators
- **ADR de delay admin:** `ADR-012` — AccessControlDefaultAdminRules con delay de 3 días (mitigante de permapause)
- **Audit:** `docs/security-reviews/audit-RedemptionManager-deep-2026-05-26.md` §6 (finding RM-21)
- **ADRs deferidos relacionados:** ADR-017 (Spec Reconciliation, RM-11) — pendiente
