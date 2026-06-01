# ADR-018: Modelo de lock contable (Option B) para redención sin escrow físico

**Status:** Accepted
**Date:** 2026-05-29
**Author:** Daniel Hidalgo Carrasco
**Tags:** redemption, redemption-manager, lock-accumulator, escrow, erc-1155, no-p2p, audit-trail
**Resuelve:** RM-01, RM-02 (prevención de doble-redención sin escrow)
**Relacionado:** ADR-002 (ERC-1155), ADR-003 (4 contratos inmutables sin proxy), ADR-009 (escrow total post-cosecha), ADR-015 (Timeout Policy), ADR-017 (state machine de 3 fases)
**Supersedes:** N/A
**Superseded by:** N/A

---

## Context

El `RedemptionManager` debe garantizar que un comprador no pueda redimir **más tokens de los que realmente posee**, ni redimir dos veces los mismos tokens (doble-redención). Esto es la invariante central del flujo de redención física (almacenamiento → exportación → quema).

El problema concreto: cuando un comprador llama `iniciarRedencion(loteId, cantidadTokens, datosEnvioHash)`, el contrato registra la intención de redimir. Pero entre ese momento y la quema final (`completarRedencion`) pueden pasar **30-45 días** (el ciclo de export Bolivia → UE descrito en ADR-017). Durante esa ventana, el sistema necesita "reservar" esos tokens para que el comprador no los pueda comprometer en otra redención simultánea.

### Restricción arquitectónica heredada

El token de la plataforma es **ERC-1155 "Solo primario"** (ADR-002): el override de `_update()` en `AssetVault.sol` **bloquea toda transferencia P2P** y solo permite `mint` (from == address(0)) y `burn` (to == address(0)):

```solidity
// AssetVault.sol — _update() override
bool isMint = (from == address(0));
bool isBurn = (to == address(0));
if (!isMint && !isBurn) revert TransferP2PNoPermitido();
```

Además, `setApprovalForAll` está overrideado para revertir siempre con `TransferP2PNoPermitido()`. Esto significa que **el token NO se puede transferir a NINGÚN address que no sea `address(0)` (burn)** — ni siquiera al `RedemptionManager`.

Esta restricción tiene una consecuencia directa sobre el diseño de la redención: **un escrow físico tradicional (transferir el ERC-1155 al `RedemptionManager` al iniciar la redención) es IMPOSIBLE sin romper el invariante "Solo primario"** del `AssetVault`. Para implementar escrow físico habría que:

- Agregar una excepción en `_update()` que permita transferir al `RedemptionManager` (debilita la invariante P2P más importante del sistema), o
- Hacer al `RedemptionManager` un address whitelisted con un path de transfer especial (superficie de ataque nueva, y `AssetVault` es inmutable bajo ADR-003).

Cualquiera de las dos opciones **modifica `AssetVault.sol`**, que es uno de los 3 contratos congelados del MVP (auditado, 100% branch coverage, Slither 0 findings). Tocarlo requiere re-auditoría completa y rompe la inmutabilidad declarada en ADR-003.

### Gap a resolver

Necesitamos un mecanismo de "reserva" de tokens durante la redención que:

1. Prevenga la doble-redención (RM-01, RM-02).
2. NO transfiera el token físicamente (respeta "Solo primario").
3. NO modifique `AssetVault.sol` (respeta ADR-003).
4. Mantenga el único path de burn legítimo centralizado en `AssetVault.burnForRedemption` (callable solo por el `RedemptionManager`).

---

## Decision

Se adopta la **Opción B — Lock Acumulator (lock contable)**: los tokens **permanecen en el wallet del comprador durante todo el ciclo de redención**. No hay transferencia del ERC-1155 al `RedemptionManager` en `iniciarRedencion`. En su lugar, el `RedemptionManager` lleva un **acumulador contable** de tokens "lockeados" por par `(loteId, comprador)`, y deriva un **balance disponible** = `balanceOf - tokensLockedFor`. Los tokens se queman **únicamente en `completarRedencion`**, vía `AssetVault.burnForRedemption`.

### Mecánica

**Storage en `RedemptionManager.sol`:**

```solidity
/// Invariante: _tokensLockedFor[loteId][buyer] <= IERC1155(assetVault).balanceOf(buyer, loteId)
mapping(uint256 loteId => mapping(address buyer => uint256)) private _tokensLockedFor;
```

**1. `iniciarRedencion(uint256 loteId, uint256 cantidadTokens, bytes32 datosEnvioHash)` — incrementa el lock:**

El check de disponibilidad usa balance real menos lo ya lockeado (RM-01 + RM-02):

```solidity
uint256 currentBalance = IERC1155(address(assetVault)).balanceOf(msg.sender, loteId);
uint256 alreadyLocked = _tokensLockedFor[loteId][msg.sender];
if (alreadyLocked + cantidadTokens > currentBalance) revert BalanceInsuficiente();

// Effects
_tokensLockedFor[loteId][msg.sender] = alreadyLocked + cantidadTokens;
```

No hay `safeTransferFrom` ni `_burn` aquí — **cero external calls mutantes** sobre el token. El lock es puro storage local del `RedemptionManager`.

**2. `confirmarExportacion(uint256 redencionId, string calldata dueNumero)` — NO toca el lock:**

Registra el DUE de SENASAG y transiciona `INICIADA → EN_EXPORTACION` (fase 1 de 2 del ADR-017). **No decrementa el lock ni quema tokens** — los tokens siguen lockeados y en el wallet del comprador.

**3. `completarRedencion(uint256 redencionId, bytes32 hashBLAWB)` — decrementa el lock y QUEMA:**

Único punto donde los tokens salen del wallet del comprador (fase 2 de 2 del ADR-017). El orden es CEI estricto:

```solidity
// RM-04: pre-validación defensiva de balance (fail fast)
uint256 balance = IERC1155(address(assetVault)).balanceOf(r.comprador, r.loteId);
if (balance < r.cantidadTokens) revert BalanceInsuficiente();

// Effects: decrementa el lock ANTES del burn
_tokensLockedFor[r.loteId][r.comprador] -= r.cantidadTokens;
r.estado = EstadoRedencion.COMPLETADA;
// ...

// Interactions: burn delegado al AssetVault (única vía permitida)
assetVault.burnForRedemption(comprador, loteId, cantidadTokens);
```

**4. `cancelarRedencion(uint256 redencionId, bytes32 reason)` — libera el lock SIN quemar:**

Si la redención se cancela (desde `INICIADA` o `EN_EXPORTACION`, per ADR-017), el lock se decrementa y los tokens vuelven a estar disponibles para el comprador. No hay burn:

```solidity
_tokensLockedFor[r.loteId][r.comprador] -= r.cantidadTokens;
r.estado = EstadoRedencion.CANCELADA;
```

**5. Views derivados:**

```solidity
function availableBalance(address buyer, uint256 loteId) external view returns (uint256) {
    uint256 balance = IERC1155(address(assetVault)).balanceOf(buyer, loteId);
    uint256 locked = _tokensLockedFor[loteId][buyer];
    return balance > locked ? balance - locked : 0;  // guardia explícita anti-underflow
}

function tokensLockedFor(address buyer, uint256 loteId) external view returns (uint256) {
    return _tokensLockedFor[loteId][buyer];
}
```

### Naturaleza del lock — punto clave

El lock es **contable (soft lock), NO criptográfico (hard lock)**. La razón por la que un token lockeado "no se puede mover" NO es que el `RedemptionManager` lo bloquee directamente — es que **el token ERC-1155 ya es intransferible P2P por diseño** (`AssetVault._update()` revierte cualquier transfer que no sea mint/burn). El único egreso posible de un token es el burn, y el único path de burn es `AssetVault.burnForRedemption`, callable solo por el `RedemptionManager`.

Por lo tanto, el lock contable **no necesita "congelar" el token** — necesita únicamente impedir que el comprador inicie redenciones que sumen más tokens de los que posee. Eso es exactamente lo que enforcea el check `alreadyLocked + cantidadTokens > currentBalance` en `iniciarRedencion`. El `AssetVault` se mantiene completamente ignorante de la existencia de locks: su invariante "NUNCA P2P" queda intacto.

---

## Alternatives considered

### Opción A — Escrow físico (transferir el ERC-1155 al RedemptionManager) (rechazada)

El modelo "clásico" de redención: en `iniciarRedencion`, transferir los `cantidadTokens` del wallet del comprador al `RedemptionManager` (custodia física). El token vive en el contrato durante la exportación, y se quema desde el escrow en `completarRedencion`.

**Por qué se rechazó:**
- ❌ **Imposible sin romper "Solo primario"** — el override `_update()` de `AssetVault` revierte toda transferencia P2P (incluyendo comprador → `RedemptionManager`). Habría que agregar una excepción que debilita el invariante más importante del token.
- ❌ **Requiere modificar `AssetVault.sol`** — contrato inmutable y congelado bajo ADR-003. Tocarlo implica re-auditoría completa, re-deploy, y rompe la inmutabilidad declarada.
- ❌ **Nueva superficie de ataque** — un `RedemptionManager` que custodia tokens es un honeypot; un bug en su lógica de escrow podría dejar tokens atrapados o permitir egreso indebido.
- ❌ **`setApprovalForAll` está bloqueado** — el escrow ERC-1155 estándar depende de approvals, que `AssetVault` revierte siempre. Habría que reescribir todo el modelo de approval.
- ❌ **Sin beneficio compensatorio** — el escrow físico no agrega ninguna garantía que el lock contable no provea ya, dado que el token es intransferible P2P de todos modos.

### Opción C — Marcar tokens individualmente como "frozen" en AssetVault (rechazada)

Agregar un mapping `frozen[loteId][buyer][amount]` dentro de `AssetVault` y chequearlo en `_update()` para impedir el burn de tokens lockeados por otra redención.

**Por qué se rechazó:**
- ❌ **Modifica `AssetVault.sol`** (ADR-003, mismo motivo que Opción A).
- ❌ **Acopla `AssetVault` al ciclo de redención** — el vault debería ser agnóstico del estado de redención; el lock pertenece conceptualmente al `RedemptionManager`.
- ❌ **Redundante** — el burn ya está restringido a `burnForRedemption` (callable solo por el `RedemptionManager`), que ya valida balance. No hace falta un freeze adicional en el vault.

---

## Consequences

### Positive

1. **`AssetVault` intacto** — la decisión NO toca ninguno de los 3 contratos congelados del MVP. El invariante "NUNCA P2P" del token queda 100% preservado y la inmutabilidad de ADR-003 se respeta.
2. **Doble-redención imposible** — el check `alreadyLocked + cantidadTokens > currentBalance` garantiza que la suma de tokens en redenciones activas nunca excede el balance real (RM-01, RM-02).
3. **Cero custodia, cero honeypot** — el `RedemptionManager` nunca posee tokens. No hay riesgo de tokens atrapados en el contrato ni de egreso indebido desde un escrow.
4. **Separación de responsabilidades limpia** — el lock vive en el `RedemptionManager` (lógica de redención); el `AssetVault` solo conoce mint/burn. El contrato de tokens no sabe nada de redenciones.
5. **El comprador conserva la titularidad on-chain** — durante los 30-45 días de exportación, el token sigue en su wallet (visible en exploradores, indexers, wallets). Mejor UX y mejor audit trail (el holder real nunca cambia hasta el burn).
6. **Burn centralizado y único** — la quema ocurre exclusivamente en `completarRedencion` → `AssetVault.burnForRedemption`. Un solo path auditable de salida de tokens.
7. **Views derivados gratuitos** — `availableBalance` y `tokensLockedFor` dan a frontends/indexers visibilidad exacta de cuántos tokens están comprometidos sin necesidad de eventos adicionales.

### Negative

1. **El lock es "soft" — depende de la disciplina del `RedemptionManager`** — como el token NO está físicamente congelado, la prevención de doble-redención vive enteramente en la lógica de `iniciarRedencion`. Un bug en ese check (o un path futuro que mintee/queme sin pasar por el manager) podría desincronizar `_tokensLockedFor` del balance real. Mitigado por: (a) el token es intransferible P2P, así que el balance solo baja por burn vía `burnForRedemption`; (b) el invariante `_tokensLockedFor <= balanceOf` se verifica con invariant testing (≥ 50,000 runs); (c) la guardia anti-underflow explícita en `availableBalance`.
2. **Desincronización ante quema externa imprevista** — si un lote falla y `AssetVault.reembolsarLoteFallido` quema/reduce balances (flujo de ADR-009/ADR-014) mientras hay un lock activo, el `_tokensLockedFor` podría quedar > `balanceOf`. La pre-validación defensiva de `completarRedencion` (RM-04: `if (balance < r.cantidadTokens) revert BalanceInsuficiente()`) actúa como red de seguridad, pero la coordinación operacional entre redención y reembolso de lote fallido debe documentarse en runbook.
3. **El comprador podría intentar "evadir" el lock con un burn directo** — no aplica: el único burn posible es vía `burnForRedemption`, callable solo por el `RedemptionManager`. El comprador no tiene ningún path para quemar sus propios tokens unilateralmente.

### Neutral

1. **Decremento del lock en dos puntos** — el lock se libera tanto en `completarRedencion` (con burn) como en `cancelarRedencion` (sin burn). Ambos paths decrementan `_tokensLockedFor`. `confirmarExportacion` NO toca el lock (per ADR-017, solo registra el DUE). Esta asimetría es intencional y debe mantenerse al editar el flujo.
2. **NatSpec del header del contrato desactualizado** — el bloque de documentación a nivel de contrato en `RedemptionManager.sol` (encabezado `@dev Workflow`) todavía describe el flujo pre-ADR-017 (afirma que `confirmarExportacion` quema tokens). El comportamiento REAL post-ADR-017 es: `confirmarExportacion` solo registra el DUE, y `completarRedencion` quema. El código es correcto; el comentario de header quedó obsoleto y debería actualizarse en una iteración de documentación (no afecta el bytecode ni la semántica).

---

## Implementation notes

### Ubicación del estado (corrección importante)

El acumulador `_tokensLockedFor` y los views `availableBalance` / `tokensLockedFor` viven en **`RedemptionManager.sol`, NO en `AssetVault.sol`**. El `AssetVault` no tiene ningún conocimiento de locks — su única participación es exponer `balanceOf` (lectura) y `burnForRedemption` (quema delegada). Esto es deliberado: la lógica de redención pertenece al manager, y el vault permanece agnóstico del ciclo de redención.

### Invariante a verificar (invariant testing)

```
∀ (loteId, buyer): _tokensLockedFor[loteId][buyer] <= IERC1155(assetVault).balanceOf(buyer, loteId)
```

Este invariante debe verificarse con ≥ 50,000 runs, depth 100. Es la propiedad de seguridad central del modelo Option B.

### Path único de burn

```
completarRedencion (RedemptionManager)
   → assetVault.burnForRedemption(comprador, loteId, cantidad)
      → _burn(from, loteId, cantidad)  // AssetVault, único _burn del flujo de redención
```

`burnForRedemption` valida `msg.sender == redemptionManager` (`OnlyRedemptionCanBurn`), garantizando que ningún otro actor puede disparar la quema.

---

## References

- `packages/contracts/src/RedemptionManager.sol` (acumulador `_tokensLockedFor`, checks de `iniciarRedencion`, views `availableBalance`/`tokensLockedFor`)
- `packages/contracts/src/interfaces/IRedemptionManager.sol` (NatSpec del modelo Option B en el header de la interface)
- `packages/contracts/src/AssetVault.sol` (override `_update()` con bloqueo P2P líneas ~552-567; `burnForRedemption` líneas ~468-489; `setApprovalForAll` bloqueado línea ~542)
- ADR-002 (ERC-1155 "Solo primario" — origen de la restricción de no-transferencia P2P)
- ADR-003 (4 contratos inmutables sin proxy — por qué no se puede modificar `AssetVault`)
- ADR-009 (escrow total post-cosecha — interacción con el pool de reembolso de lote fallido)
- ADR-015 (Timeout Policy — el buyer-after-timeout libera el lock vía `cancelarRedencion`)
- ADR-017 (state machine de 3 fases — define cuándo se decrementa el lock: en completar/cancelar, NO en confirmar)
