# ADR-013: Pause/Unpause en IdentityRegistry con scope limitado a mutators (H-02)

**Status:** Accepted
**Date:** 2026-05-22 (Iteration #3)
**Author:** Daniel Hidalgo Carrasco
**Tags:** smart-contracts, identity-registry, pause, circuit-breaker, emergency-response, compliance, security

---

## Context

El audit profundo de `IdentityRegistry.sol` (Iteration #3) identificó el finding **H-02**: el contrato carecía de cualquier mecanismo de circuit breaker (pause/unpause). Esto era una inconsistencia arquitectónica: `AssetVault.sol` y `RedemptionManager.sol` ya implementaban `Pausable`, pero `IdentityRegistry` — el gatekeeper KYC de todo el sistema — no tenía esta capacidad.

La spec original (CONTRACT-SPECS §5.13.6) decía explícitamente "Sin pause: Diseño deliberado. Para detener emisiones de tokens ante incidente, pausar AssetVault (no este contrato)". El audit argumentó que este razonamiento es insuficiente:

**El problema concreto que Pausar AssetVault NO resuelve:**

Un attacker que compromete `BACKEND_SIGNER_ROLE` (el HSM) puede llamar `setKYC` masivamente, aprobando miles de wallets falsas con tier 3. Pausar AssetVault detiene NUEVAS compras, pero los KYCs fraudulentos ya están escritos en el storage de `IdentityRegistry`. Cuando se "despausa" AssetVault, el sistema queda expuesto al daño acumulado.

Con un pause en `IdentityRegistry` que bloquee SOLO los mutators (no las views), el equipo puede detener la ingesta de nuevos KYCs mientras:
- Las views (`canMint`, `canRedeem`, etc.) siguen funcionando para usuarios legítimos.
- AssetVault y RedemptionManager siguen operativos.
- El equipo investiga, revoca el rol comprometido, rota la clave HSM, y hace batch-revoke de las wallets fraudulentas.

---

## Decision

**Agregar `Pausable` a `IdentityRegistry` con scope limitado: `whenNotPaused` solo en los 6 mutators de KYC/compliance. Las views NO se pausan.**

**Mutators afectados por `whenNotPaused`:**
1. `setKYC` — BACKEND_SIGNER_ROLE
2. `revokeKYC` — BACKEND_SIGNER_ROLE
3. `markSanctioned` — COMPLIANCE_OFFICER_ROLE
4. `unmarkSanctioned` — COMPLIANCE_OFFICER_ROLE
5. `freezeAddress` — COMPLIANCE_OFFICER_ROLE
6. `unfreezeAddress` — COMPLIANCE_OFFICER_ROLE

**Views NO pausadas** (continúan funcionando durante pause):
- `canMint`, `canRedeem`, `getTier`, `isSanctioned`, `isFrozen`, `isExpired`, `getJurisdiction`, `getKYCData`

**Asimetría de roles para pause/unpause:**
- `pause()`: callable por `COMPLIANCE_OFFICER_ROLE` **O** `DEFAULT_ADMIN_ROLE` — defensa cruzada.
- `unpause()`: callable **solo** por `DEFAULT_ADMIN_ROLE` (Safe 2-de-3) — más restrictivo.

---

## Alternatives considered

### A1) Scope original del audit: pause sin aplicar a unmarkSanctioned y unfreezeAddress

El audit H-02 sugería en el párrafo final:

> "Importante: las funciones de unmark/unfreeze NO deben tener whenNotPaused: durante un pause, debemos PODER descongelar/desmarcar manualmente."

Esto tiene mérito operacional: si el sistema está pausado por un compromiso del BACKEND_SIGNER, debería ser posible remediar wallets (descongelar una wallet que fue congelada por error antes del pause).

**No adoptada en esta iteración**: se aplicó `whenNotPaused` a los 6 mutators tal como especificó el ticket de implementación. La lógica es que durante un pause de emergencia, lo más conservador es no realizar NINGUNA modificación de estado. Si se necesita descongelar durante un pause, el DEFAULT_ADMIN puede primero `unpause()`, luego `unfreezeAddress`, luego `pause()` de nuevo. Este flujo preserva el control del multi-sig.

**Riesgo aceptado**: si el equipo necesita desmarcar una sanción durante un pause, requiere pasar por DEFAULT_ADMIN (Safe). Este overhead es aceptable dado que un pause es un evento excepcional.

**Adendum futuro**: si en producción se determina que `unmarkSanctioned` y `unfreezeAddress` deben estar libres de pause, se puede crear un ADR adendum para cambiar esto. Requeriría redeploy del contrato (es inmutable).

### B) Pause global (incluye views)

Agregar `whenNotPaused` a `canMint` y `canRedeem` también.

**Descartada**: si `canMint` revierte cuando el contrato está pausado, `AssetVault._update()` (que llama `canMint`) también revierte, efectivamente pausando el sistema de tokens completo. Esto puede ser deseable en algunos escenarios, pero AssetVault ya tiene su propio pause para ese propósito. Pausar IdentityRegistry no debe tener efecto cascada no intencional en AssetVault.

### C) No agregar pause (mantener diseño original)

Confiar en que pausar AssetVault es suficiente.

**Descartada**: el audit demostró que este argumento es incorrecto. Un compromiso del BACKEND_SIGNER afecta el estado de IdentityRegistry directamente, y AssetVault no puede proteger contra eso. La consistencia arquitectónica (los 3 contratos con pause) también es un argumento de mantenimiento.

---

## Consequences

### Positive

- **Circuit breaker efectivo contra compromiso del BACKEND_SIGNER**: en caso de compromiso del HSM, COMPLIANCE_OFFICER puede pausar en segundos sin esperar al Safe.
- **Defensa cruzada**: tanto COMPLIANCE_OFFICER como DEFAULT_ADMIN pueden pausar. Si uno de los dos está comprometido, el otro puede actuar.
- **Unpause controlado por multi-sig**: el DEFAULT_ADMIN (Safe 2-de-3) debe aprobar el unpause. Esto previene que un Compliance Officer comprometido deshaga un pause de emergencia.
- **Views nunca pausadas**: AssetVault y RedemptionManager siguen consultando `canMint`/`canRedeem` normalmente durante un pause. Las operaciones en curso (redenciones iniciadas, lotes en cosecha) no se ven afectadas.
- **Consistencia arquitectónica**: los 3 contratos activos del MVP tienen `Pausable`.

### Negative

- **Superficie de ataque en pause/unpause**: agregar estas funciones suma 2 entry points al contrato. Mitigado porque el modifier `whenNotPaused` solo restringe — no muta estado sensible.
- **`unmarkSanctioned`/`unfreezeAddress` bloqueados durante pause**: requiere un unpause temporal para desmarcar (con quorum del Safe). Ver Alternatives A1 arriba.
- **Gas marginal**: el modifier `whenNotPaused` agrega ~200 gas a cada mutator. Negligible.

### Neutral

- **Emit de eventos de pause**: `EmergencyPaused(address actor, uint64 timestamp)` y `EmergencyUnpaused(address actor, uint64 timestamp)` permiten que Goldsky alerte en tiempo real cuando el registry se pausa.
- **El contrato puede deployarse pausado**: si se quiere hacer un "dry run" de deployment + configuración antes de activar, se puede pausar el contrato inmediatamente post-deploy y unpaused solo cuando todo esté listo.

---

## Implementation notes

### Cambios aplicados en `IdentityRegistry.sol`

```solidity
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

contract IdentityRegistry is AccessControlDefaultAdminRules, Pausable, IIdentityRegistry {

    error UnauthorizedPauseActor();

    function pause() external whenNotPaused {
        if (!hasRole(COMPLIANCE_OFFICER_ROLE, msg.sender)
            && !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            revert UnauthorizedPauseActor();
        }
        _pause();
        emit EmergencyPaused(msg.sender, uint64(block.timestamp));
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
        emit EmergencyUnpaused(msg.sender, uint64(block.timestamp));
    }

    function setKYC(...) external onlyRole(BACKEND_SIGNER_ROLE) whenNotPaused { ... }
    function revokeKYC(...) external onlyRole(BACKEND_SIGNER_ROLE) whenNotPaused { ... }
    function markSanctioned(...) external onlyRole(COMPLIANCE_OFFICER_ROLE) whenNotPaused { ... }
    function unmarkSanctioned(...) external onlyRole(COMPLIANCE_OFFICER_ROLE) whenNotPaused { ... }
    function freezeAddress(...) external onlyRole(COMPLIANCE_OFFICER_ROLE) whenNotPaused { ... }
    function unfreezeAddress(...) external onlyRole(COMPLIANCE_OFFICER_ROLE) whenNotPaused { ... }
}
```

### Runbook: Pause de emergencia por compromiso de BACKEND_SIGNER

```
T=0: PagerDuty alerta: KYCUpdated rate > 100/hora
     ó
     COMPLIANCE_OFFICER detecta setKYC sospechosos en el dashboard

T=0-15min: Verificar si el volumen es operacional legítimo (campaña de marketing, onboarding masivo)
            Si NO es legítimo: proceder con pause

T=15min: COMPLIANCE_OFFICER ejecuta IdentityRegistry.pause()
          Evento: EmergencyPaused(complianceOfficer, timestamp)

T=15min - T+2h: Investigación
          - Identificar wallets fraudulentas (ej: rango de setKYC entre T-1h y T)
          - Preparar batch de revokeKYC para ejecutar después del unpause
          - Rotar BACKEND_SIGNER_ROLE: DEFAULT_ADMIN revoca el HSM comprometido, grant a nueva clave

T+2h: DEFAULT_ADMIN (Safe) prepara transacción:
       1. revokeRole(BACKEND_SIGNER_ROLE, compromised_hms_wallet)
       2. grantRole(BACKEND_SIGNER_ROLE, new_hsm_wallet)
       3. IdentityRegistry.unpause()
      (estas 3 pueden ir en una sola batch tx del Safe)

T+2h: DEFAULT_ADMIN ejecuta batch tx via Safe UI
       Verificar: paused() == false, BACKEND_SIGNER_ROLE ahora tiene nueva wallet

T+2h+: Backend (con nueva HSM key) ejecuta batch revokeKYC de wallets fraudulentas
```

### Runbook: Pause de emergencia por compromiso de COMPLIANCE_OFFICER

```
T=0: DEFAULT_ADMIN detecta Sanctioned/Frozen masivos o desmarcados sospechosos de sanciones legítimas

T=0-15min: Verificar si son acciones legítimas del titular o suplente

T=15min: DEFAULT_ADMIN (Safe) ejecuta IdentityRegistry.pause()
          [La función pause() acepta DEFAULT_ADMIN_ROLE también]

T+: Mismo flujo que compromiso de BACKEND_SIGNER, pero rotando COMPLIANCE_OFFICER_ROLE
    en lugar de BACKEND_SIGNER_ROLE
```

---

## References

- `docs/security-reviews/audit-IdentityRegistry-deep-2026-05-22.md` (finding H-02)
- `packages/contracts/src/IdentityRegistry.sol` (implementación resultante)
- ADR-012 (AccessControlDefaultAdminRules — complementario a este ADR)
- ADR-014 (check tier en reembolso — otro finding de Iteration #3)
- `docs/ITERATION-LOG.md` (Iteration #3)
