# ADR-012: AccessControlDefaultAdminRules con delay 3 días en los 3 contratos (M-08)

**Status:** Accepted
**Date:** 2026-05-22 (Iteration #3)
**Author:** Daniel Hidalgo Carrasco
**Tags:** smart-contracts, access-control, admin-lockout, security, openzeppelin, asset-vault, identity-registry, redemption-manager

---

## Context

El audit profundo de `IdentityRegistry.sol` (Iteration #3) identificó el finding **M-08** — y el mismo problema existe en `AssetVault.sol` y `RedemptionManager.sol`. Los tres contratos heredaban de `AccessControl` (OZ v5 base), lo que los deja expuestos al escenario de **admin lockout permanente**:

OpenZeppelin v5 `AccessControl` expone `renounceRole(role, account)` con la única restricción `require(account == msg.sender)`. Si el único holder de `DEFAULT_ADMIN_ROLE` (el Safe 2-de-3) llama `renounceRole` por error o como resultado de un multisig attack:

- El contrato queda sin `DEFAULT_ADMIN_ROLE` **para siempre**.
- Nadie puede `grantRole` ni `revokeRole` en ninguno de los roles del contrato.
- Los roles existentes siguen activos (BACKEND_SIGNER puede seguir operando, COMPLIANCE_OFFICER puede seguir sancionando), pero si una clave se compromete, **no hay forma de revocarla**.
- Esto es incompatible con los requerimientos de seguridad operacional del proyecto (rotación periódica de claves, gestión de incidentes).

OpenZeppelin v5 introdujo `AccessControlDefaultAdminRules` precisamente para este caso. Implementa un proceso de dos pasos con time-lock para cualquier cambio de `DEFAULT_ADMIN_ROLE`.

---

## Decision

**Los 3 contratos del MVP (`AssetVault`, `IdentityRegistry`, `RedemptionManager`) heredan de `AccessControlDefaultAdminRules` en lugar de `AccessControl` base. El delay es de 3 días.**

```solidity
import {AccessControlDefaultAdminRules} from
    "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";

contract AssetVault is /* ... */, AccessControlDefaultAdminRules, /* ... */ {
    uint48 public constant ADMIN_TRANSFER_DELAY = 3 days;

    constructor(/* ... */) AccessControlDefaultAdminRules(ADMIN_TRANSFER_DELAY, admin) {
        // admin == address(0) ya lo revierte AccessControlDefaultAdminRules
    }
}
```

El flujo resultante para transferir `DEFAULT_ADMIN_ROLE`:

1. Holder actual (Safe v1) llama `beginDefaultAdminTransfer(newAdmin)`.
2. Se inicia un timer de 3 días.
3. Pasados 3 días, el nuevo admin llama `acceptDefaultAdminTransfer()` para completar la transferencia.
4. En cualquier momento antes de que el nuevo admin acepte, el holder actual puede llamar `cancelDefaultAdminTransfer()` para cancelar.

`renounceRole(DEFAULT_ADMIN_ROLE, ...)` también está sujeto al mismo delay bajo `AccessControlDefaultAdminRules`.

---

## Alternatives considered

### B) Override `renounceRole` para impedir renuncia del último admin

```solidity
function renounceRole(bytes32 role, address account) public override {
    if (role == DEFAULT_ADMIN_ROLE && getRoleMemberCount(DEFAULT_ADMIN_ROLE) == 1) {
        revert CannotRenounceLastAdmin();
    }
    super.renounceRole(role, account);
}
```

Requiere también `AccessControlEnumerable` para acceder a `getRoleMemberCount`, lo que agrega complejidad y gas adicional. **Descartada**: `AccessControlDefaultAdminRules` resuelve el mismo problema de forma más elegante, sin enumerable, y con la ventaja adicional del time-lock que permite detectar transferencias maliciosas.

### C) Mantener AccessControl base + runbook operacional

Documentar el riesgo y confiar en que el Safe 2-de-3 no ejecute `renounceRole` accidentalmente.

**Descartada**: el Safe multi-sig puede ejecutar transacciones arbitrarias. Un atacante que comprometa 2 de los 3 signers puede ejecutar `renounceRole`. El time-lock de 3 días es la única defensa técnica real contra este vector.

---

## Consequences

### Positive

- **Previene admin lockout permanente**: la renuncia accidental o maliciosa del `DEFAULT_ADMIN_ROLE` es cancelable dentro de los 3 días.
- **Time-lock como defensa contra compromiso del Safe**: si un attacker compromete 2 de 3 hardware wallets del Safe e inicia una transferencia a una wallet controlada por el attacker, el equipo tiene 3 días para detectarlo (via monitoring en Goldsky/Tenderly) y cancelar la transferencia.
- **Estándar OpenZeppelin v5**: `AccessControlDefaultAdminRules` es el estándar de producción para contratos que manejan activos. Auditores externos (Sherlock, Trail of Bits) lo esperan.
- **Compatible con el Safe existente**: el proceso `beginDefaultAdminTransfer` → `acceptDefaultAdminTransfer` es compatible con ejecución desde Gnosis Safe UI.

### Negative

- **Rotación de admin requiere 3+ días**: si se necesita rotar el Safe urgentemente (compromiso de 1 signer, cambio organizacional), la transferencia tarda al menos 3 días en completarse. Esto es aceptable dado que la rotación del Safe no debería ser una operación urgente de menos de 3 días.
- **Constructor diferente**: `AccessControlDefaultAdminRules` requiere que el `admin` se pase al constructor del padre. Esto significa que `_grantRole(DEFAULT_ADMIN_ROLE, admin)` ya no se llama explícitamente — el padre lo maneja. Rompe el patrón anterior si el constructor no se actualiza correctamente. Ya aplicado en los 3 contratos.

### Neutral

- **`DEFAULT_ADMIN_ROLE` del padre no es `bytes32(0)`**: `AccessControlDefaultAdminRules` define su propio `defaultAdmin()` getter. El `DEFAULT_ADMIN_ROLE = 0x00` (bytes32(0)) se mantiene igual — compatibilidad total con el resto del sistema de roles.
- **Gas de deployment marginalmente mayor**: el constructor del padre requiere más lógica. Impacto negligible (deployment es one-time cost).

---

## Implementation notes

### Delay elegido: 3 días — justificación

| Criterio | Por qué 3 días |
|---|---|
| Monitoreo con PagerDuty/Tenderly | Alert → equipo → reunión coordinada: ~2-4 horas realistas. 3 días es holgado. |
| Coordinación de cofundadores (Safe 2-de-3) | Si están en husos horarios distintos, 72h garantiza al menos 3 días hábiles |
| Operación legítima urgente | La rotación del Safe (operación más urgente) NO requiere < 3 días en ningún escenario real |
| Precedentes del ecosistema | Compound: 2 días. Aave: 1 día. Openzeppelin default example: no especifica. 3 días es conservador pero razonable |

### Runbook: Rotación normal del DEFAULT_ADMIN_ROLE

Escenario: reemplazar Safe v1 por Safe v2 (por ejemplo, agregar un signer).

```
Día 0:
  Safe v1 ejecuta beginDefaultAdminTransfer(safe_v2_address)
  Evento: DefaultAdminTransferScheduled(newAdmin, uint48 acceptSchedule)
  Monitoring: alerta automática en PagerDuty

Día 0 - Día 3:
  Equipo verifica que la transacción es legítima
  Si hay duda: Safe v1 ejecuta cancelDefaultAdminTransfer()

Día 3+:
  Safe v2 ejecuta acceptDefaultAdminTransfer()
  Evento: DefaultAdminTransferred(previousAdmin, newAdmin)
  Verificar on-chain que DEFAULT_ADMIN_ROLE del contrato ahora es safe_v2
```

### Runbook: Cancelar transferencia maliciosa del DEFAULT_ADMIN_ROLE

Escenario: un attacker comprometió 2 de 3 signers del Safe actual y ejecutó `beginDefaultAdminTransfer` a su wallet.

```
T=0: Monitoring detecta DefaultAdminTransferScheduled con dirección desconocida
     PagerDuty alerta inmediatamente

T=0-4h: Equipo valida que la transacción es maliciosa
         Identificar al signer comprometido (forensics Ledger)

T=4h: Tercer signer (no comprometido) encuentra signer de emergencia
       O: si el Safe tiene 3-de-5, el quorum se puede reconstruir sin los 2 comprometidos

T=4h: Safe (con quorum restaurado) ejecuta cancelDefaultAdminTransfer()
      Evento: DefaultAdminTransferCanceled()

Post-incidente: Rotar Safe. Rotar todos los roles comprometidos.
```

### Contratos afectados

- `packages/contracts/src/AssetVault.sol` — ya aplicado en Iteration #3
- `packages/contracts/src/IdentityRegistry.sol` — ya aplicado en Iteration #3
- `packages/contracts/src/RedemptionManager.sol` — ya aplicado en Iteration #3

`LabRegistry.sol` (standalone, fase 2) debería también adoptarlo cuando se reactive, pero no es prioritario para el MVP.

---

## References

- `docs/security-reviews/audit-IdentityRegistry-deep-2026-05-22.md` (finding M-08)
- [OpenZeppelin AccessControlDefaultAdminRules docs](https://docs.openzeppelin.com/contracts/5.x/api/access#AccessControlDefaultAdminRules)
- ADR-003 (4 contratos inmutables — arquitectura de base)
- ADR-013 (pause en IdentityRegistry — otro finding de Iteration #3)
- `docs/ITERATION-LOG.md` (Iteration #3)
