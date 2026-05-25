# ADR-014: Validación tier > 0 en AssetVault.reembolsarLoteFallido (H-01)

**Status:** Accepted
**Date:** 2026-05-22 (Iteration #3)
**Author:** Daniel Hidalgo Carrasco
**Tags:** smart-contracts, asset-vault, refund, kyc, tier, compliance, rwa

---

## Context

El audit profundo de `IdentityRegistry.sol` (Iteration #3) identificó el finding **H-01**: `AssetVault.reembolsarLoteFallido()` validaba correctamente que el buyer no esté `sanctioned` ni `frozen`, pero **no validaba que el buyer tuviera KYC activo** (`tier > 0`).

El escenario concreto:

1. Alice compra tokens de un lote (requiere `canMint` → `tier >= 1`). En ese momento tiene tier 2.
2. Post-compra, el backend llama `revokeKYC(alice, "EDD failure")`. Su `tier` se setea a 0. Alice ya no puede comprar ni redimir. Sus tokens quedan bloqueados.
3. El lote falla (cosecha perdida). El ORACLE marca el lote como `FALLIDO`.
4. ORACLE llama `reembolsarLoteFallido([alice])`.
5. La función chequeaba `isSanctioned(alice) == false` ✅ y `isFrozen(alice) == false` ✅. **No chequeaba `getTier(alice) > 0`.**
6. Alice recibía el USDC de reembolso **a pesar de tener KYC revocado**.

Esto es regulatoriamente ambiguo: si el `revokeKYC` fue por EDD failure con sospecha de lavado de dinero, enviar USDC on-chain a esa dirección puede constituir un breach de compliance AML. El equipo de compliance debería determinar si el reembolso procede (off-chain, con supervisión), no el contrato automaticamente.

---

## Decision

**Agregar validación `identityRegistry.getTier(buyer) > 0` en el loop de `reembolsarLoteFallido()`, como condición adicional a `!isSanctioned` y `!isFrozen`. Si el buyer tiene tier == 0, se revierte con `CannotRefundRevokedAddress()`.**

El check resultante en el loop:

```solidity
if (identityRegistry.isSanctioned(buyer)) revert CannotRefundBlockedAddress();
if (identityRegistry.isFrozen(buyer))     revert CannotRefundBlockedAddress();
if (identityRegistry.getTier(buyer) == 0) revert CannotRefundRevokedAddress();
// ... proceder con el reembolso
```

**Nuevo custom error en `AssetVault.sol`:**

```solidity
/// @notice El buyer tiene KYC revocado (tier == 0). El reembolso on-chain está bloqueado.
/// @dev La recuperación de fondos para este buyer requiere flujo off-chain supervisado
///      por el Compliance Officer. Ver ADR-014 para el runbook.
error CannotRefundRevokedAddress();
```

---

## Alternatives considered

### B) No agregar check (reembolso siempre procede si no es sancionado/frozen)

El argumento es que el reembolso es un derecho de propiedad — Alice pagó por los tokens, le corresponde recuperar su capital si el lote falla, independientemente del estado de su KYC.

**Descartada**: la política de "revokeKYC incluye qué derechos se mantienen" es exactamente lo que el Compliance Officer debe definir caso por caso. Un contrato que automáticamente devuelve dinero a una wallet con `revokeKYC` por EDD-failure elimina el control regulatorio. El check on-chain preserva ese control; la recuperación off-chain sigue siendo posible con la supervisión apropiada.

### C) Agregar flag `revoked` separado (recomendación H-01 del audit)

El audit sugería introducir un campo `bool revoked` y `uint64 revokedAt` en `KYCData`, con una función `isRevoked()` en `IIdentityRegistry`. Esto permitiría distinguir "nunca tuvo KYC" (tier=0, updatedAt=0) de "fue revocado explícitamente" (tier=0, revoked=true).

**No adoptada en esta iteración**: se considera una mejora deseable pero no obligatoria para el MVP. La semántica actual — `tier == 0` significa "no puede operar on-chain" — es suficiente para el check en `reembolsarLoteFallido`. La distinción entre "nunca tuvo KYC" y "tuvo y fue revocado" es relevante para analytics off-chain y para el evento `KYCRevoked` (ya emitido correctamente), no para la lógica on-chain del reembolso.

Puede adoptarse en una iteración futura sin cambios arquitectónicos disruptivos (solo agregar 2 campos al struct y actualizar `revokeKYC`).

---

## Consequences

### Positive

- **Control regulatorio preservado**: el Compliance Officer puede decidir, caso por caso, si el buyer con KYC revocado recibe el reembolso on-chain o mediante un flujo supervisado off-chain.
- **Consistencia con los checks existentes**: la función ya bloqueaba a sancionados y frozen. Agregar el check de tier=0 es coherente con la política de "solo wallets KYC-activas reciben movimientos on-chain".
- **Previene automatización no intencional**: sin este check, el contrato automáticamente liberaba fondos a wallets revocadas cada vez que un lote fallaba, sin intervención humana.
- **Custom error descriptivo**: `CannotRefundRevokedAddress` es diferente de `CannotRefundBlockedAddress` (sancionado/frozen), permitiendo que el ORACLE y los indexers distingan el caso en su lógica de recuperación.

### Negative

- **Gestión operacional**: si un lote falla y hay buyers con KYC revocado, esas porciones del USDC de reembolso **quedan retenidas en el contrato** indefinidamente hasta que el equipo las resuelva off-chain. El contrato no tiene mecanismo automático para reclamar ese USDC.
- **Riesgo de lotes "eternamente parcialmente reembolsados"**: si la recuperación off-chain nunca se completa (e.g., buyer desaparece, dispute legal prolongada), ese USDC puede quedar inmovilizado en el contrato.

### Neutral

- **Compatibilidad con `finalizarReembolso`**: la función `finalizarReembolso(loteId)` (que marca el lote como completamente reembolsado) solo debe llamarse cuando TODOS los buyers hayan recibido su reembolso. Si hay buyers con tier=0, el ORACLE debe manejar el flag de "reembolso parcial" y documentarlo en el runbook.
- **El USDC no se pierde**: queda en el contrato, no se transfiere a ningún tercero. La recuperación es posible, requiere governance.

---

## Implementation notes

### Cambio en `AssetVault.sol`

En el loop de `reembolsarLoteFallido()`, después de los checks de `isSanctioned`/`isFrozen`:

```solidity
for (uint256 i = 0; i < buyers.length; ++i) {
    address buyer = buyers[i];

    // Checks regulatorios: sanciones + freeze + KYC revocado
    if (identityRegistry.isSanctioned(buyer)) revert CannotRefundBlockedAddress();
    if (identityRegistry.isFrozen(buyer))     revert CannotRefundBlockedAddress();
    if (identityRegistry.getTier(buyer) == 0) revert CannotRefundRevokedAddress();

    // ... resto del reembolso (cálculo pro-rata, safeTransfer, etc.)
}
```

### Runbook: Reembolso con buyer KYC-revocado

Escenario: lote X falla, hay 10 buyers, 9 con KYC activo y 1 (Alice) con KYC revocado.

```
Paso 1: ORACLE llama reembolsarLoteFallido([alice, bob, carol, ...])
         → Revierte con CannotRefundRevokedAddress (por Alice).

Paso 2: ORACLE reordena la lista: reembolsarLoteFallido([bob, carol, ...])
         (sin Alice). Los 9 buyers legítimos reciben su reembolso. ✅

Paso 3: ORACLE documenta en el backend que Alice (0xAlice...) tiene USDC pendiente de reembolso.
         Registra en la tabla audit_log con motivo "KYC revocado al momento del reembolso".

Paso 4 (off-chain): Compliance Officer evalúa el caso de Alice:
         - ¿La revocación fue por error operacional? → Ejecutar setKYC nuevamente, luego reembolsarLoteFallido([alice]).
         - ¿La revocación fue por EDD failure justificado? → Iniciar proceso AML: notificación a regulador, decisión de congelar fondos o proceder con transferencia bancaria supervisada.
         - ¿La revocación fue por sanción OFAC? → NO reembolsar. Reportar a autoridades competentes según regulación aplicable.

Paso 5 (si corresponde reembolso): BACKEND_SIGNER llama setKYC(alice, tier=1, ...) para reactivar.
         Luego ORACLE llama reembolsarLoteFallido([alice]).
         Luego ORACLE llama finalizarReembolso(loteId) para marcar el lote como completamente reembolsado.
```

### Impacto en `finalizarReembolso`

Si hay buyers con KYC revocado que no recibieron reembolso, el lote no debería marcarse como "completamente reembolsado" (`_reembolsado[loteId] = true`). El ORACLE es responsable de verificar que todos los buyers con balance > 0 en el lote hayan sido procesados (on-chain o con resolución off-chain documentada) antes de llamar `finalizarReembolso`.

---

## References

- `docs/security-reviews/audit-IdentityRegistry-deep-2026-05-22.md` (finding H-01)
- `packages/contracts/src/AssetVault.sol` (implementación resultante)
- ADR-009 (escrow total post-cosecha — contexto del pool de reembolso)
- ADR-013 (pause en IdentityRegistry — complementario)
- `docs/ITERATION-LOG.md` (Iteration #3)
