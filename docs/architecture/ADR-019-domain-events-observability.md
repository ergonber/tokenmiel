# ADR-019: Eventos de dominio para observabilidad del indexer en AssetVault

**Status:** Accepted
**Date:** undefined
**Author:** Daniel Hidalgo Carrasco
**Tags:** events, observability, indexer, audit-trail, asset-vault, redemption, refund, pre-deploy
**Resuelve:** GAP-1, GAP-2, GAP-3, GAP-4 (mutaciones de estado de `AssetVault` sin evento de dominio, detectadas por la CIS v1)
**Relacionado:** ADR-002 (ERC-1155 "Solo primario"), ADR-003 (4 contratos inmutables sin proxy), ADR-009 (escrow total post-cosecha), ADR-014 (reembolso de lote fallido), ADR-017 (state machine de 3 fases de redención), ADR-018 (lock accumulator Option B)
**Supersedes:** N/A
**Superseded by:** N/A

---

## Context

La **Contract Interface Specification (CIS) v1** (`docs/architecture/CIS-v1.md`) es la descripción congelada de la superficie de contratos a partir de la cual el backend (fase 2) construye su read model. El principio rector es que **el indexer reconstruye TODO el estado on-chain a partir de logs de eventos**: ante cualquier divergencia, gana la cadena, y el backend nunca es la fuente de verdad. Para que eso funcione, cada mutación de estado relevante debe emitir un evento de dominio indexable.

La verificación adversarial de la CIS v1 dio verdict **CONFIRMED (cero huecos materiales)** para `IdentityRegistry` y `RedemptionManager`, pero **corrections-needed** para `AssetVault`: detectó **4 mutaciones de estado que NO emitían evento de dominio**. Esos son huecos de indexabilidad — el backend no puede reconstruir esas transiciones sólo por logs.

### Los 4 gaps detectados

- **GAP-1 (HIGH) — `setRedemptionManager` no emite evento.** El cableado one-time del `RedemptionManager` (resuelve la dependencia circular vault ↔ manager, D3/Opción B) es configuración crítica. Sin evento, el backend no puede indexar el wiring por logs: tiene que leer `redemptionManager()` en bootstrap o capturarlo en el artefacto de deploy. Una pieza de configuración de seguridad central queda invisible en el audit trail.

- **GAP-2 (HIGH) — `burnForRedemption` no emite evento de dominio.** Las transiciones `ALMACENADO → REDENCION_PARCIAL → AGOTADO` y el incremento del acumulador `kgRedimidos` sólo producían un `TransferSingle(to=0)`, que es **indistinguible** del burn que emite `reembolsarLoteFallido`. El indexer no podía separar redención de reembolso por el log de transfer; tampoco veía el avance de `kgRedimidos` ni la transición de estado del lote. El indexer quedaba ciego frente al ciclo de redención física del lote. El workaround previo era correlacionar por tx-hash contra `RedencionCompletada` (RedemptionManager) y `ReembolsoEjecutado` (AssetVault) — frágil y dependiente de que ambos eventos ocurran en el mismo tx.

- **GAP-3 (MEDIUM) — `reembolsarLoteFallido` caso `totalSupply == 0`.** Cuando un lote FALLIDO ya no tiene supply (caso degenerado), la función seteaba `_reembolsado[loteId] = true` y retornaba **sin emitir nada**: mutación terminal silenciosa.

- **GAP-4 (MEDIUM) — `finalizarReembolso` no emite evento.** El cierre de la paginación del reembolso (`_reembolsado[loteId] = true`) es una mutación terminal sin evento. El backend no podía saber por logs que el reembolso quedó cerrado: tenía que leer estado o inferirlo.

### Ventana de oportunidad

`AssetVault` es uno de los 3 contratos INMUTABLES del MVP (ADR-003), pero **NO está deployado en ninguna red** (CIS v1, estado de deploy: NO deployado). La inmutabilidad aplica una vez deployado; hoy el código todavía es modificable. Agregar eventos antes del deploy NO viola ADR-003 — lo viola hacerlo *después*. Esta ventana se cierra con el deploy, así que la decisión es **ahora o nunca-sin-redeploy**.

---

## Decision

Se agregan **3 eventos de dominio a `AssetVault`** ANTES del deploy, cubriendo los 4 gaps. Los eventos se DECLARAN en la interfaz `IAssetVault.sol` (con NatSpec completo) y los EMITE el contrato `AssetVault` (que `is IAssetVault`), siguiendo CEI estricto: el `emit` va al final de la función o del branch, después de los effects.

### Los 3 eventos nuevos

```solidity
// IAssetVault.sol

/// @notice Emitido cuando se setea (one-time) el RedemptionManager autorizado para quemar tokens.
event RedemptionManagerSet(address indexed redemptionManager);

/// @notice Emitido cuando el RedemptionManager quema tokens de un lote durante una redención.
event TokensRedimidos(
    uint256 indexed loteId,
    address indexed from,
    uint256 cantidad,
    uint256 kgRedimidosTotal,
    LoteEstado nuevoEstado
);

/// @notice Emitido cuando un lote FALLIDO queda marcado como reembolso finalizado.
event ReembolsoFinalizado(uint256 indexed loteId);
```

### Mapeo evento → gap

| Evento | Gap que tapa | Emisor | Significado |
|---|---|---|---|
| `RedemptionManagerSet(address indexed redemptionManager)` | **GAP-1** | `setRedemptionManager` | Cableado one-time del RM, ahora indexable por logs |
| `TokensRedimidos(loteId◆, from◆, cantidad, kgRedimidosTotal, nuevoEstado)` | **GAP-2** | `burnForRedemption` | Señala las transiciones `ALMACENADO → REDENCION_PARCIAL` y `→ AGOTADO`, expone `kgRedimidos` acumulado, y distingue redención de reembolso |
| `ReembolsoFinalizado(uint256 indexed loteId)` | **GAP-3 + GAP-4** | `reembolsarLoteFallido` (branch `totalSupply == 0`) **y** `finalizarReembolso` | Cierre de la paginación del reembolso, ahora visible en ambos paths |

Un solo evento (`ReembolsoFinalizado`) tapa **dos** gaps: la función `finalizarReembolso` (GAP-4) y el branch degenerado `totalSupply == 0` de `reembolsarLoteFallido` (GAP-3) representan exactamente la misma transición terminal (`_reembolsado[loteId] = true`), así que emiten el mismo evento. El indexer no necesita saber por cuál de los dos paths se cerró el reembolso — sólo que se cerró.

### Por qué `TokensRedimidos` lleva `nuevoEstado` y `kgRedimidosTotal`

`TokensRedimidos` se emite al final de `burnForRedemption`, después de que el estado del lote y `kgRedimidos` ya fueron actualizados (CEI). Llevar `nuevoEstado` (el `LoteEstado` resultante: `REDENCION_PARCIAL` o `AGOTADO`) permite al indexer derivar la transición del lote **sin leer storage**: si el evento previo del lote era `AlmacenamientoConfirmado` y ahora llega `TokensRedimidos` con `nuevoEstado == REDENCION_PARCIAL`, la transición `ALMACENADO → REDENCION_PARCIAL` queda reconstruida sólo por logs. `kgRedimidosTotal` expone el acumulador `kgRedimidos` tras la operación, que antes era invisible al indexer.

`loteId` y `from` van indexed (filtrado eficiente por lote y por titular); `cantidad`, `kgRedimidosTotal` y `nuevoEstado` van sin indexar (datos del payload).

---

## Alternatives considered

### Opción A — Compensar off-chain en el indexer (rechazada)

Vivir con los 4 gaps y compensarlos en el backend: correlacionar `TransferSingle(to=0)` por tx-hash contra `RedencionCompletada`/`ReembolsoEjecutado` (GAP-2), leer `redemptionManager()` en bootstrap (GAP-1), y hacer polling periódico de estado para detectar las mutaciones silenciosas (GAP-3/GAP-4).

**Por qué se rechazó:**
- ❌ **Complejidad permanente en el indexer** — la correlación por tx-hash es frágil: depende de que redención y reembolso emitan en el mismo tx, y de heurísticas que hay que mantener para siempre.
- ❌ **Polling no es event-sourcing** — GAP-3/GAP-4 obligarían a lecturas de estado periódicas para detectar mutaciones que un evento resolvería con un log. Rompe el principio "el read model se reconstruye 100% desde logs".
- ❌ **Audit trail incompleto** — el wiring del RM (GAP-1) y el cierre del reembolso (GAP-4) quedarían fuera del trail de eventos, debilitando la trazabilidad forense.
- ❌ **El costo lo paga el equipo equivocado** — se traslada complejidad estructural del contrato (barata de arreglar hoy) al backend (cara de mantener para siempre).

### Opción C — Agregar los eventos en una v2 post-deploy (rechazada)

Deployar `AssetVault` tal cual y resolver los gaps en un futuro redeploy con un nuevo ADR.

**Por qué se rechazó:**
- ❌ **Carísimo** — `AssetVault` es inmutable (ADR-003). Cambiarlo post-deploy implica `pause()` + migración a v2 redeployada + re-auditoría completa + re-pin de bytecode/ABI (el playbook de la sección 7 de la CIS). Todo eso para agregar 3 `emit`.
- ❌ **Tira la ventana de oportunidad** — el contrato todavía no está deployado. Hacerlo ahora es trivial; hacerlo después es una migración.
- ❌ **El indexer arrancaría con huecos conocidos** — diseñar la fase 2 sobre una superficie que ya sabemos incompleta es deuda técnica autoinfligida.

---

## Consequences

### Positive

1. **Read model 100% reconstruible desde logs** — con los 3 eventos, el backend reconstruye el ciclo completo de redención y reembolso de `AssetVault` sólo desde eventos, sin correlaciones frágiles ni polling de estado. Se respeta el principio rector de la CIS.
2. **GAP-2 resuelto de raíz** — redención y reembolso dejan de ser indistinguibles: `TokensRedimidos` (redención) vs `ReembolsoEjecutado` (reembolso) son eventos de dominio separados. El indexer ya no depende de correlacionar `TransferSingle(to=0)` por tx-hash.
3. **Transiciones del lote indexables** — `TokensRedimidos.nuevoEstado` señala `ALMACENADO → REDENCION_PARCIAL → AGOTADO` directamente en el log; el indexer no necesita leer `lotes()` para seguir la máquina de estados de redención.
4. **`kgRedimidos` observable** — el acumulador de kg redimidos viaja en cada evento, dando visibilidad exacta del avance físico del lote.
5. **Audit trail completo** — el wiring del RM (config crítica) y el cierre del reembolso (mutación terminal) quedan en el trail de eventos. Mejor forensics.
6. **Costo mínimo y aprovecha la ventana pre-deploy** — 3 declaraciones de evento + 3 sitios de `emit`, sin tocar lógica de negocio ni semántica. No viola ADR-003 porque el contrato aún no es inmutable-en-producción.

### Negative

1. **+Gas marginal por `emit`** — cada `burnForRedemption` y cada `setRedemptionManager`/`finalizarReembolso`/branch-degenerado paga el costo de un `LOG`. Es marginal (un log con pocos topics + payload pequeño) y se justifica de sobra por la observabilidad ganada. `TokensRedimidos` es el de mayor frecuencia (per-redención), pero sigue siendo un costo de log estándar.
2. **El ABI de `AssetVault` cambió** — el event count del ABI pasó de **23 → 26**. Todo artefacto derivado del ABI (typed bindings del backend, la CIS v1) debe refrescarse. Ya hecho: `packages/abis/AssetVault.abi.json` regenerado y CIS v1 actualizada (sección 2 y 5).
3. **Re-verificación de tests/coverage** — al ser eventos nuevos, los tests deben cubrir su emisión (`vm.expectEmit`) para mantener el 100% de coverage no negociable. Ya contemplado en el cambio que introdujo los eventos (verificación: PASS).

### Neutral

1. **`ReembolsoFinalizado` se emite desde dos sitios** — `reembolsarLoteFallido` (branch `totalSupply == 0`) y `finalizarReembolso`. Es intencional: ambos representan la misma transición terminal (`_reembolsado = true`). El indexer trata ambos por igual.
2. **No se tocó la semántica de ningún flujo** — los eventos son puramente observacionales. El bytecode de lógica de negocio (checks, effects salvo el `emit`, interactions) es idéntico al pre-ADR-019. Sólo se agregó observabilidad.
3. **Gaps menores quedan fuera de scope** — GAP-5 (catálogo de eventos OZ heredados incompleto en la prosa), el bug de NatSpec del param `actor` en `IRedemptionManager`, y los 3 lints de unsafe-typecast NO los toca este ADR. Son pendientes menores (no bloquean el indexer ni afectan el flujo de negocio) y se completan/corrigen por separado.

---

## Implementation notes

### Declaración en interfaz, emisión en contrato

Per convención del proyecto: los 3 eventos se DECLARAN en `IAssetVault.sol` (líneas ~98-112, con NatSpec `@notice`/`@param` completo) y los EMITE `AssetVault.sol` (que `is IAssetVault`). El `emit` respeta CEI: va después de los effects.

| Evento | Sitio de emisión en `AssetVault.sol` |
|---|---|
| `RedemptionManagerSet` | `setRedemptionManager` (tras setear `redemptionManager`) |
| `TokensRedimidos` | `burnForRedemption` (al final, tras actualizar `kgRedimidos`, estado, y el `_burn`) |
| `ReembolsoFinalizado` | `reembolsarLoteFallido` (branch `totalSupply == 0`) **y** `finalizarReembolso` (tras `_reembolsado = true`) |

### Refresco del ABI

```bash
cd "packages/contracts"
forge build
forge inspect AssetVault abi --json > "../abis/AssetVault.abi.json"
```

Conteo de eventos del ABI nuevo: **26** (23 previos + 3 nuevos). Confirmado que `RedemptionManagerSet`, `TokensRedimidos` y `ReembolsoFinalizado` están presentes en el ABI regenerado.

### Documentos a refrescar

- `packages/abis/AssetVault.abi.json` — regenerado (event count 23 → 26).
- `docs/architecture/CIS-v1.md` — sección 2 (ABI capture: event count de AssetVault 23 → 26), sección 5 (EVENT CATALOG: 3 entradas nuevas), sección 8 (state machines: transiciones de redención del lote ahora con `evento: TokensRedimidos`), sección final (GAPS: GAP-1/2/3/4 movidos a "RESUELTOS (ADR-019)").

---

## References

- `packages/contracts/src/interfaces/IAssetVault.sol` (declaración de los 3 eventos, líneas ~98-112)
- `packages/contracts/src/AssetVault.sol` (`setRedemptionManager` ~L169, `reembolsarLoteFallido` branch ~L382, `finalizarReembolso` ~L435, `burnForRedemption` ~L493)
- `packages/abis/AssetVault.abi.json` (ABI regenerado, 26 eventos)
- `docs/architecture/CIS-v1.md` (origen de GAP-1/2/3/4; secciones 2, 5, 8 y GAPS actualizadas)
- ADR-002 (ERC-1155 "Solo primario" — origen de la indistinguibilidad de `TransferSingle` entre redención y reembolso)
- ADR-003 (4 contratos inmutables sin proxy — por qué la ventana pre-deploy es la única barata)
- ADR-014 (reembolso de lote fallido — flujo cubierto por `ReembolsoFinalizado`)
- ADR-017 (state machine de 3 fases — transiciones de redención que `TokensRedimidos` señala)
- ADR-018 (lock accumulator Option B — `burnForRedemption` como único path de burn de redención)
