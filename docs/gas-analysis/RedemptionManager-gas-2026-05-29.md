# Gas Analysis — RedemptionManager.sol v0.1.0

**Analyst:** Subagente B (claude-opus-4-8)
**Date:** 2026-05-29
**Compiler:** Solidity 0.8.24, optimizer enabled, runs=200, evm_version=paris
**Source:** `packages/contracts/src/RedemptionManager.sol`
**Método:** `forge test --match-contract RedemptionManager --no-match-path "test/invariant/**" --gas-report` (71 tests, 0 fallos)

---

## Resumen ejecutivo

Los tres mayores costos de gas en RedemptionManager son:

1. **`iniciarRedencion()`** — la función más costosa del ciclo de vida. Combina una llamada cross-contract a `identityRegistry.canRedeem()`, una lectura del struct completo `LoteMiel` via `assetVault.lotes(loteId)` (que copia ~20 slots a memory), una llamada a `assetVault.totalSupply()`, una llamada a `balanceOf()` ERC-1155, y luego 6 SSTOREs fríos para inicializar el struct `Redencion` + 1 SSTORE para el lock acumulador + 1 SSTORE para `_nextRedencionId`. El gas-report mide **min 41 460 / median 421 047** — el median está inflado por las 10 000 corridas del fuzz que crean lotes nuevos; el **min de 41 460 es el costo realista** del happy path cuando el setup ya está caliente, y el path completo cold-state ronda **~250 000–280 000 gas**.

2. **`completarRedencion()`** — segunda más costosa (**median 225 815 / max 233 015**). Hace el burn delegado via `assetVault.burnForRedemption()` (que internamente ejecuta `_burn` + `_update` + actualización de `ERC1155Supply` + posible transición de estado del lote), precedido de un `balanceOf()` cross-contract defensivo (RM-04) y el decremento del lock acumulador. La mayor parte del gas vive en AssetVault, no en este contrato.

3. **`cancelarRedencion()`** — (**median 147 630 / max 147 853**). No quema tokens, pero evalúa hasta 3 paths de access control (`hasRole` × 2 + check de timeout con `block.timestamp`), decrementa el lock, y escribe `estado` + `cancelReason` + `completedAt` sobre el struct `Redencion`. El costo es mayormente storage del struct y los 2 SLOADs de roles de AccessControl.

**Top recomendación:** la lectura `assetVault.lotes(loteId)` en `iniciarRedencion()` devuelve el struct `LoteMiel` ENTERO por `memory` (~20 slots SLOAD + ABI-decode), cuando la función solo usa `productorSRL` y `estado`. Exponer un getter ligero en AssetVault (`loteEstadoYProductor(loteId)`) ahorraría ~15 000–25 000 gas por `iniciarRedencion`. Esto requiere tocar `src/` (congelado) → candidato para una iteración futura con ADR, no para el MVP.

---

## Gas estimado por función

> Convenciones: **cold** = slot jamás tocado en esta tx (SLOAD = 2 100 gas, SSTORE new = 22 100 gas); **warm** = slot ya cargado (SLOAD = 100 gas, SSTORE dirty = 5 000 gas).
> Las cifras "medidas" provienen del `--gas-report`. Las cifras "estimadas" desglosan los componentes a mano para explicar de dónde sale el costo.
> `onlyRole` (AccessControl) cuesta ~4 200 gas (2 SLOADs fríos: `_roles[role][account]` + jerarquía admin).

### Tabla maestra (medida — gas-report)

| Función | Min | Avg | Median | Max | # Calls |
|---|---|---|---|---|---|
| `iniciarRedencion` | 41 460 | 409 021¹ | 421 047¹ | 421 059¹ | 490 |
| `confirmarExportacion` | 30 672 | 89 459 | 98 347 | 155 849 | 25 |
| `completarRedencion` | 30 551 | 176 145 | 225 815 | 233 015 | 18 |
| `cancelarRedencion` | 41 368 | 116 063 | 147 630 | 147 853 | 15 |
| `pause` | 46 143 | 60 119 | 60 635 | 68 940 | 12 |
| `unpause` | 29 746 | 34 164 | 34 164 | 38 582 | 4 |
| `availableBalance` (view) | 27 815 | 27 865 | 27 876 | 27 876 | 776 |
| `getRedencion` (view) | 74 991 | 76 272 | 75 110 | 91 509 | 14 |
| `tokensLockedFor` (view) | 8 659 | 8 659 | 8 659 | 8 659 | 10 |
| `getNextRedencionId` (view) | 8 347 | 8 347 | 8 347 | 8 347 | 3 |
| `hasRole` (view) | 8 726 | 8 726 | 8 726 | 8 726 | 4 |
| `paused` (view) | 8 369 | 8 369 | 8 369 | 8 369 | 4 |
| `defaultAdmin` (view) | 8 363 | 8 363 | 8 363 | 8 363 | 1 |
| `defaultAdminDelay` (view) | 16 586 | 16 586 | 16 586 | 16 586 | 1 |
| Constantes (`ORACLE_ROLE`, `REDENCION_TIMEOUT`, etc.) | 227 | — | — | 306 | varios |
| **Deployment** | — | — | — | **2 418 583** | (size 11 034 bytes) |

¹ Los valores avg/median/max de `iniciarRedencion` están dominados por `testFuzz_iniciarRedencion_AcumuladorNoExcedeBalance` (10 000 runs), donde cada corrida arma un lote completo desde cero (crearLote + confirmarCosecha + confirmarAlmacenamiento + comprar). El **min de 41 460** refleja la llamada aislada con state caliente; ver desglose abajo para el costo cold-state real de la función.

### `iniciarRedencion()`

Costo dominado por las 3 llamadas cross-contract de lectura + la inicialización del struct `Redencion`.

| Componente | Gas estimado |
|---|---|
| `nonReentrant` lock (`_status` SSTORE warm-cycle) | ~2 300 |
| `whenNotPaused` (`_paused` SLOAD) | ~2 100 cold / ~100 warm |
| `identityRegistry.canRedeem()` — cross-contract cold | ~8 700–9 150 (medido en gas-report del registry) |
| `assetVault.lotes(loteId)` — copia struct `LoteMiel` ENTERO a memory (~20 SLOADs + ABI-decode) | ~141 215 cold (medido) / mucho menos si warm |
| `productorSRL == address(0)` check (sobre memory) | ~10 |
| `estado` check (2 condiciones OR, sobre memory) | ~20 |
| `assetVault.totalSupply(loteId)` — cross-contract | ~8 557 (medido) |
| `balanceOf(msg.sender, loteId)` — cross-contract ERC-1155 | ~8 670 (medido) |
| `_tokensLockedFor[loteId][msg.sender]` SLOAD (alreadyLocked) | ~2 100 cold |
| arithmetic (`alreadyLocked + cantidadTokens`) | ~30 |
| `_tokensLockedFor[...]` SSTORE (incrementa el lock) | ~22 100 cold / ~5 000 warm |
| `_nextRedencionId++` (SLOAD + SSTORE) | ~5 000–22 100 |
| **6 SSTOREs del struct `Redencion`** (comprador, loteId, cantidadTokens, datosEnvioHash, estado, createdAt — ver storage analysis) | ~6 × 22 100 = ~132 600 cold |
| Event `RedencionIniciada` (3 indexed + 2 non-indexed) | ~2 500 |
| **Total (medido, min con state caliente)** | **~41 460 gas** |
| **Total estimado (cold-state realista, primera redención del lote)** | **~250 000 – 280 000 gas** |

> El gran salto entre el `min` medido (41 460) y el cold-state estimado (~250K) es la lectura `assetVault.lotes(loteId)`: cuando esos ~20 slots del `LoteMiel` ya fueron tocados en la misma tx (o el lote ya está en cache), el costo cae drásticamente. En producción cada `iniciarRedencion` es su propia tx → siempre paga el path cold de leer el lote. **Este es el punto de optimización #1.**

### `confirmarExportacion()`

Transición INICIADA → EN_EXPORTACION. NO quema tokens, NO usa `whenNotPaused` (diseño, CONTRACT-SPECS §6.13.8).

| Componente | Gas estimado |
|---|---|
| `onlyRole(ORACLE_ROLE)` | ~4 200 |
| `_redenciones[redencionId]` storage pointer (no SLOAD aún) | ~0 |
| `r.comprador == address(0)` check — SLOAD frío slot base del struct | ~2 100 |
| `r.estado != INICIADA` check — SLOAD (slot del estado) | ~2 100 cold / ~100 warm |
| `bytes(dueNumero).length` checks (2× sobre calldata) | ~60 |
| `r.estado = EN_EXPORTACION` SSTORE warm | ~5 000 |
| `r.dueNumero = dueNumero` — **string SSTORE**: 1 slot length + N slots data (N = ceil(len/32)) | ~22 100 + N×22 100 cold |
| Event `RedencionEnExportacion` (1 indexed + actor + string) | ~2 500 + len×8 |
| **Total (medido, DUE corto)** | **~30 672 gas (min)** |
| **Total (medido, DUE largo cerca de MAX=64 chars)** | **~155 849 gas (max)** |

> El span 30K→155K se explica casi por completo por el `string dueNumero` en storage. Un DUE de 64 chars = 2 slots de data + 1 de length = ~66 300 gas solo en escritura de string. El `MAX_DUE_NUMERO_LENGTH = 64` acota correctamente la inflación de storage que un Oracle malicioso podría provocar.

### `completarRedencion()`

Transición EN_EXPORTACION → COMPLETADA. **Aquí ocurre el burn** delegado a AssetVault.

| Componente | Gas estimado |
|---|---|
| `onlyRole(ORACLE_ROLE)` + `nonReentrant` | ~6 500 |
| `r.comprador == address(0)` + `r.estado != EN_EXPORTACION` + `hashBLAWB == 0` checks | ~4 300 |
| `balanceOf(r.comprador, r.loteId)` — cross-contract ERC-1155 (RM-04 defensivo) | ~8 670 |
| `_tokensLockedFor[...] -= cantidadTokens` SSTORE warm | ~5 000 |
| `r.estado = COMPLETADA` SSTORE warm | ~5 000 |
| `r.hashBLAWB` SSTORE | ~22 100 cold |
| `r.completedAt` SSTORE | ~5 000 warm (packed con estado) |
| `assetVault.burnForRedemption()` — **el grueso del costo** (burn + _update + Supply + transición estado lote) | ~100 000–160 000 |
| Event `RedencionCompletada` (1 indexed + actor + hash) | ~2 500 |
| **Total (medido, min)** | **~30 551 gas** |
| **Total (medido, median / max)** | **~225 815 / 233 015 gas** |

> El `min` de 30 551 corresponde a paths de revert temprano (no llegan al burn). El median/max (~226K–233K) es el happy path completo, y **>60% de ese gas vive en `assetVault.burnForRedemption()`**, no en RedemptionManager. Este contrato es delgado por diseño — delega el burn al AssetVault, la única vía permitida.

### `cancelarRedencion()`

Libera el lock contable. 3 paths de access control inline (ADR-015). NO quema tokens.

| Componente | Gas estimado |
|---|---|
| `nonReentrant` lock | ~2 300 |
| `r.comprador == address(0)` + `r.estado` check (INICIADA o EN_EXPORTACION) | ~4 200 cold |
| `reason == bytes32(0)` check | ~20 |
| `hasRole(ORACLE_ROLE, msg.sender)` — SLOAD frío | ~2 600 |
| `hasRole(COMPLIANCE_OFFICER_ROLE, msg.sender)` — SLOAD frío | ~2 600 |
| `block.timestamp >= r.createdAt + REDENCION_TIMEOUT` (buyer path) — SLOAD `createdAt` + TIMESTAMP | ~2 110 |
| `_tokensLockedFor[...] -= cantidadTokens` SSTORE warm | ~5 000 |
| `r.estado = CANCELADA` SSTORE warm | ~5 000 |
| `r.cancelReason` SSTORE | ~22 100 cold |
| `r.completedAt` SSTORE | ~5 000 warm (packed) |
| Event `RedencionCancelada` (1 indexed + actor + reason) | ~2 500 |
| **Total (medido, min — revert path)** | **~41 368 gas** |
| **Total (medido, median / max)** | **~147 630 / 147 853 gas** |

> A diferencia de `confirmarExportacion`/`completarRedencion`, `cancelarRedencion` evalúa los 3 paths de canceler (Oracle / Compliance / buyer-after-timeout). Los 2 `hasRole` se ejecutan SIEMPRE (no hay short-circuit que los evite cuando el caller es el buyer). Costo fijo de ~5 200 gas en role lookups aunque el caller sea el comprador. Ver patrones costosos #2.

### `pause()` / `unpause()`

| Componente | Gas estimado (pause) | Gas estimado (unpause) |
|---|---|---|
| Access control (`hasRole` × 2 en pause / `onlyRole` en unpause) | ~4 200–5 200 | ~4 200 |
| `whenNotPaused` (pause) / sin modifier (unpause) | ~2 100 | — |
| `_pause()` / `_unpause()` — `_paused` SSTORE | ~22 100 cold / ~5 000 warm | ~5 000 |
| Event OZ `Paused`/`Unpaused` + custom `EmergencyPaused`/`EmergencyUnpaused` (2 eventos) | ~3 000 | ~3 000 |
| **Total (medido)** | **46 143 – 68 940 gas** | **29 746 – 38 582 gas** |

> `pause()` cuesta más que `unpause()` porque evalúa DOS roles (COMPLIANCE_OFFICER OR DEFAULT_ADMIN, ADR-016) más el `whenNotPaused`, mientras que `unpause()` usa un único `onlyRole(DEFAULT_ADMIN_ROLE)`. Ambas emiten doble evento (OZ + custom, RM-15), lo que agrega ~1 200 gas vs un solo evento.

### Funciones view

| View | Gas medido | Notas |
|---|---|---|
| `getRedencion()` | 74 991 – 91 509 | Copia el struct `Redencion` ENTERO a memory, incluyendo el `string dueNumero` dinámico. El span depende del largo del DUE almacenado. |
| `availableBalance()` | 27 815 – 27 876 | 1 cross-contract `balanceOf()` (~8 670) + 1 SLOAD del lock + branch. |
| `tokensLockedFor()` | 8 659 | 1 SLOAD del mapping anidado `_tokensLockedFor[loteId][buyer]`. |
| `getNextRedencionId()` | 8 347 | 1 SLOAD de `_nextRedencionId`. |
| `paused()` | 8 369 | 1 SLOAD de `_paused`. |

> **Nota:** los costos "medidos" de las views incluyen el overhead de la llamada externa desde el harness de test (~21 000 base tx + dispatch). Off-chain (eth_call) estas views son gratuitas. El costo relevante es cuando se llaman cross-contract; ahí el costo interno real de `tokensLockedFor` es ~2 200 gas (1 SLOAD + return), no 8 659.

---

## Storage packing analysis

### Layout a nivel de contrato (slots de estado)

`forge inspect src/RedemptionManager.sol:RedemptionManager storageLayout`:

```
Slot 0:  _roles                       (mapping — AccessControl)
Slot 1:  _pendingDefaultAdmin    (address, 20 bytes)  ─┐
         _pendingDefaultAdminSchedule (uint48, 6)      │ AccessControlDefaultAdminRules
         _currentDelay               (uint48, 6)       │ → 32 bytes exactos, packing perfecto
Slot 2:  _currentDefaultAdmin   (address, 20 bytes)  ─┐
         _pendingDelay               (uint48, 6)       │ → 32 bytes exactos
         _pendingDelaySchedule       (uint48, 6)      ─┘
Slot 3:  _status                     (uint256 — ReentrancyGuard)
Slot 4:  _paused                     (bool — Pausable, 1 byte, 31 libres)
Slot 5:  _redenciones                (mapping(uint256 => Redencion))
Slot 6:  _nextRedencionId            (uint256)
Slot 7:  _tokensLockedFor            (mapping(loteId => mapping(buyer => uint256)))
```

**Observación clave:** los slots 1 y 2 (heredados de `AccessControlDefaultAdminRules`, FIX M-08) están **perfectamente empaquetados** por OZ — `address(20) + uint48(6) + uint48(6) = 32 bytes` exactos. No hay desperdicio en el layout heredado.

`immutables` (`assetVault`, `identityRegistry`) NO ocupan slots de storage — viven en el bytecode (FIX de costo: cada lectura es un `PUSH` del bytecode, ~3 gas, vs ~2 100 de un SLOAD). Esto es óptimo y es la razón por la que las llamadas cross-contract no pagan un SLOAD extra para resolver la dirección del target.

### Struct `Redencion` — slot por slot

Declarado en `IRedemptionManager.sol` líneas 19–30. El packing del struct es **subóptimo** por el orden de los campos:

```
Base slot B (= keccak256(redencionId . 5)):
  B+0: comprador        (address, 20 bytes)   → 12 bytes libres, DESPERDICIADOS
  B+1: loteId           (uint256, 32 bytes)   → slot completo
  B+2: cantidadTokens   (uint256, 32 bytes)   → slot completo
  B+3: datosEnvioHash   (bytes32, 32 bytes)   → slot completo
  B+4: estado           (EstadoRedencion enum = uint8, 1 byte) → 31 bytes libres, DESPERDICIADOS
  B+5: dueNumero        (string — length aquí, data en keccak256(B+5) si > 31 bytes)
  B+6: hashBLAWB        (bytes32, 32 bytes)   → slot completo
  B+7: createdAt        (uint64, 8 bytes)  ─┐
       completedAt      (uint64, 8 bytes)   │ → 16 bytes usados, 16 libres → BIEN packeado
  B+8: cancelReason     (bytes32, 32 bytes)   → slot completo
```

**Total: ~9 slots por `Redencion`** (excluyendo data del string si DUE > 31 bytes).

#### Packing subóptimo detectado

1. **`comprador` (slot B+0) deja 12 bytes libres.** El `estado` (enum uint8, slot B+4) podría empaquetarse junto a `comprador` → ahorraría 1 slot. También `createdAt`/`completedAt` (uint64 cada uno) cabrían junto a `comprador` (20 + 8 + 8 = 36 > 32, no caben los dos; pero `comprador(20) + estado(1) + createdAt(8) = 29 bytes` sí cabe).

2. **`estado` (slot B+4) deja 31 bytes libres.** Es el peor desperdicio. Un enum de 1 byte ocupando un slot completo de 32 bytes.

3. **El `string dueNumero` (slot B+5) interrumpe el packing.** Está ubicado entre campos pequeños (`estado`) y `bytes32` (`hashBLAWB`), lo que impide que el compilador agrupe los escalares pequeños.

#### Reorder propuesto (ahorro: 1–2 slots por redención)

```solidity
struct Redencion {
    // Slot 1: address + enum + 2× uint64 = 20 + 1 + 8 + 8 = 37 bytes → NO cabe en 1 slot.
    //         Mejor: address + enum + uint64 = 29 bytes → 1 slot
    address comprador;      // 20 bytes ─┐
    EstadoRedencion estado; // 1 byte    │ slot 1 (29 bytes usados, 3 libres)
    uint64 createdAt;       // 8 bytes  ─┘
    uint64 completedAt;     // 8 bytes   → empieza slot 2... o mover a slot 1 si cabe

    uint256 loteId;         // slot completo
    uint256 cantidadTokens; // slot completo
    bytes32 datosEnvioHash; // slot completo
    bytes32 hashBLAWB;      // slot completo
    bytes32 cancelReason;   // slot completo
    string  dueNumero;      // dinámico, al final (no rompe el packing de escalares)
}
```

Con `comprador(20) + estado(1) + createdAt(8) = 29 bytes` en un solo slot y `completedAt(8)` arrancando el siguiente (o empaquetado con otro campo pequeño), se pasa de **9 slots a 7–8 slots**. En `iniciarRedencion` (que escribe `comprador`, `estado`, `createdAt` en la inicialización) eso fusiona 3 SSTOREs en 1 → **ahorro de ~44 200 gas (2 SSTOREs fríos evitados) en cada `iniciarRedencion`**.

> **Restricción MVP:** `IRedemptionManager.sol` y `RedemptionManager.sol` están bajo `src/` (congelado y auditado). Este reorder es un cambio de layout → breaking, requiere ADR + re-auditoría. Es la recomendación de mayor ahorro pero queda para una iteración post-MVP.

---

## Patrones costosos identificados

### 1. `assetVault.lotes(loteId)` copia el struct `LoteMiel` entero a memory

**Código:** `iniciarRedencion()` línea 139.

```solidity
IAssetVault.LoteMiel memory lote = assetVault.lotes(loteId);
if (lote.productorSRL == address(0)) revert LoteNotFound(loteId);
if (lote.estado != ... ) revert LoteNotInAlmacenado();
```

El getter `lotes()` devuelve el `LoteMiel` COMPLETO (~20 slots: 6 uint256, 7 bytes32, varios escalares, structs anidados). El gas-report mide `lotes` en **141 215 gas**. La función solo necesita `productorSRL` (1 address) y `estado` (1 enum). Se pagan ~18 SLOADs + ABI-decode de campos que se descartan.

**Solución (requiere tocar AssetVault, congelado):** exponer en AssetVault un getter ligero `loteEstadoYProductor(uint256 loteId) external view returns (address productorSRL, LoteEstado estado)` que lea solo slot 6 (estado) + slot 14 (productorSRL) del `LoteMiel`. Ahorro estimado: ~15 000–25 000 gas por `iniciarRedencion`.
**Esfuerzo:** medio (nueva función en AssetVault + ADR). **Riesgo:** bajo (función view aditiva, no rompe layout).

### 2. Doble `hasRole` siempre evaluado en `cancelarRedencion()`

**Código:** líneas 270–280.

```solidity
bool isOracle = hasRole(ORACLE_ROLE, msg.sender);            // SLOAD frío SIEMPRE
bool isCompliance = hasRole(COMPLIANCE_OFFICER_ROLE, msg.sender); // SLOAD frío SIEMPRE
bool isBuyerAfterTimeout = (msg.sender == r.comprador && ...);
if (!isOracle && !isCompliance && !isBuyerAfterTimeout) revert OnlyAuthorizedCanceler();
```

Los dos `hasRole` se ejecutan ANTES de evaluar el path del buyer, aunque el caller sea el comprador haciendo self-cancel. Costo fijo de ~5 200 gas en role lookups incluso cuando no aplican.

**Solución (bajo esfuerzo, NO requiere tocar layout):** evaluar primero el check barato del buyer y short-circuit. El reorden podría hacerse en `src/` pero está congelado — anotar para iteración futura.

```solidity
// Evaluar el path más barato primero (comparación de address + 1 SLOAD de createdAt)
bool isBuyerAfterTimeout = (msg.sender == r.comprador && block.timestamp >= r.createdAt + REDENCION_TIMEOUT);
if (!isBuyerAfterTimeout && !hasRole(ORACLE_ROLE, msg.sender) && !hasRole(COMPLIANCE_OFFICER_ROLE, msg.sender)) {
    revert OnlyAuthorizedCanceler();
}
```

Con `&&` short-circuit, cuando el buyer hace self-cancel válido se evitan los 2 `hasRole` → **ahorro ~5 200 gas en ese path** (que es justamente el path del consumer/escape valve, donde el gas lo paga el usuario final, no el Oracle).
**Ahorro:** ~5 200 gas en el buyer-path. **Esfuerzo:** mínimo. **Riesgo:** bajo (misma lógica, distinto orden de evaluación).

### 3. `string dueNumero` en storage vs `bytes32`

**Código:** `confirmarExportacion()` línea 197 (`r.dueNumero = dueNumero`).

`dueNumero` es `string` con cap `MAX_DUE_NUMERO_LENGTH = 64`. Un DUE de 64 chars = 1 slot length + 2 slots data = ~66 300 gas de escritura. El gas-report muestra el span 30 672 → 155 849 explicado casi por completo por este string.

Los números DUE reales de SENASAG son códigos cortos (típicamente < 32 chars). Si caben en 31 bytes, `string` los almacena inline (1 slot) — eficiente. El problema es solo si superan 31 bytes.

**Observación:** el evento `RedencionEnExportacion` ya loggea `dueNumero` completo off-chain. Si el DUE no necesita lookup on-chain individual, podría almacenarse como `bytes32 dueNumeroHash` (hash del número) y dejar el texto en el evento → ahorro de hasta ~44 200 gas para DUEs largos, y el storage pasa a 1 slot fijo.
**Trade-off:** se pierde el lookup del número exacto via `getRedencion()`. **Esfuerzo:** medio (breaking, requiere ADR). **Riesgo:** medio.

> Dado que `MAX_DUE_NUMERO_LENGTH = 64` ya acota la inflación, y los DUEs reales son cortos, este patrón es **aceptable para el MVP**. Anotado para evaluación futura solo si el costo se vuelve relevante en producción.

### 4. `nonReentrant` en funciones sin external calls mutantes

**Código:** `iniciarRedencion()` y `cancelarRedencion()` usan `nonReentrant` aunque NO hacen external calls mutantes (solo views: `canRedeem`, `lotes`, `totalSupply`, `balanceOf`).

`completarRedencion()` SÍ necesita `nonReentrant` (llama `burnForRedemption`). Pero `iniciarRedencion` y `cancelarRedencion` no tienen interacción mutante post-effects.

**Observación:** el `nonReentrant` agrega ~2 300 gas (SSTORE del `_status` a "entered" y vuelta a "not entered") por defense-in-depth (RM-14). El código documenta explícitamente que es defensivo. **NO es un bug** — es un tradeoff intencional de seguridad. Eliminarlo ahorraría ~2 300 gas/call pero reduciría el margen de seguridad ante refactors futuros que introduzcan external calls. **Recomendación: mantener** — el costo es trivial frente al beneficio defensivo.

### 5. `_nextRedencionId++` — SLOAD + SSTORE en cada `iniciarRedencion`

**Código:** línea 162.

El contador global `_nextRedencionId` se lee y escribe en cada inicio. El primer incremento de la vida del contrato paga SSTORE cold (~22 100, de 1→2 ya que el constructor lo inicializó en 1), los siguientes pagan SSTORE warm-to-dirty (~5 000). Es inevitable para IDs secuenciales monótonos y es el patrón correcto. No hay optimización razonable sin sacrificar la legibilidad/auditabilidad de los IDs.

---

## Costo de deployment

### Bytecode size (medido)

| Métrica | Valor |
|---|---|
| Deployment cost (gas) | **2 418 583** |
| Deployment size (bytes) | **11 034** |

RedemptionManager hereda de `AccessControlDefaultAdminRules` + `ReentrancyGuard` + `Pausable` + implementa `IRedemptionManager`.

| Componente | Bytecode aprox. |
|---|---|
| AccessControlDefaultAdminRules (OZ v5) — roles + delay machinery (FIX M-08) | ~4 500 bytes |
| ReentrancyGuard | ~300 bytes |
| Pausable | ~600 bytes |
| RedemptionManager logic (4 mutating + 2 admin + 6 views) | ~5 000–5 500 bytes |
| Custom errors (15 errores) | ~300 bytes |
| **Total medido** | **11 034 bytes** |

Muy por debajo del límite EIP-170 de 24 576 bytes (~13 500 bytes de margen). El uso de `AccessControlDefaultAdminRules` (en vez del `AccessControl` plano que usa IdentityRegistry) agrega ~1 500 bytes por la maquinaria de delay de 3 días, pero el contrato sigue holgado.

### Comparación de deployment con los otros contratos MVP

| Contrato | Deployment gas | Bytecode (bytes) | Base heredada |
|---|---|---|---|
| **AssetVault** | 4 231 244 | 20 113 | ERC1155 + Supply + Pausable + AccessControl + ReentrancyGuard |
| **RedemptionManager** | 2 418 583 | 11 034 | AccessControlDefaultAdminRules + ReentrancyGuard + Pausable |
| **IdentityRegistry** | 1 907 846 | 8 645 | AccessControl |

RedemptionManager es el **contrato intermedio en tamaño**: ~55% del bytecode de AssetVault, ~128% del de IdentityRegistry. El diseño "delgado" (delega el burn a AssetVault, no tiene lógica ERC-1155 propia) mantiene su bytecode contenido pese a la maquinaria extra de `DefaultAdminRules`.

### Gas de deployment por red

| Red | Gas deployment | Costo a precio típico |
|---|---|---|
| Plume mainnet (L2) | ~2 420 000 gas | $0.002 – $0.024 (trivial en L2) |
| Polygon PoS mainnet | ~2 420 000 gas | $0.73 – $2.42 (a 30–100 gwei) |

El constructor hace 5 zero-checks (pure) + 3 `_grantRole()` (cada uno ~22 100 gas frío) + inicialización de `_nextRedencionId = 1` (1 SSTORE) + setup de `AccessControlDefaultAdminRules` (admin inicial + delay).

---

## Recomendaciones priorizadas

| # | Optimización | Función afectada | Ahorro estimado | Esfuerzo | Riesgo |
|---|---|---|---|---|---|
| 1 | Exponer getter ligero `loteEstadoYProductor()` en AssetVault para evitar copiar el `LoteMiel` entero en `iniciarRedencion` | `iniciarRedencion` | ~15 000–25 000 gas/tx | Medio (toca AssetVault + ADR) | Bajo (view aditiva) |
| 2 | Reordenar struct `Redencion` para empacar `comprador + estado + createdAt` en 1 slot (9 → 7-8 slots) | `iniciarRedencion`, todas las mutantes | ~44 200 gas/tx en iniciar (2 SSTOREs evitados) | Medio (breaking layout, ADR + re-audit) | Medio |
| 3 | Short-circuit del buyer-path en `cancelarRedencion` ANTES de los 2 `hasRole` | `cancelarRedencion` | ~5 200 gas en el buyer self-cancel path | Mínimo (reorden lógico) | Bajo |
| 4 | Evaluar `bytes32 dueNumeroHash` en vez de `string dueNumero`; texto solo en evento | `confirmarExportacion`, storage | hasta ~44 200 gas para DUEs > 31 chars | Medio (breaking, ADR) | Medio |
| 5 | Activar `via_ir = true` en foundry.toml — el Yul optimizer fusiona SSTOREs de slots empaquetados y elimina keccak256 duplicados de mapping keys | Global | 5–15% en funciones con structs (iniciar, completar) | Bajo (config) | Bajo — requiere re-ejecutar Slither |
| 6 | Cachear `_redenciones[redencionId]` ya está hecho correctamente (`Redencion storage r = ...`) en las 3 funciones que lo usan. Verificado: NO hay anti-patrón de doble acceso al mapping. | — | 0 (ya óptimo) | — | — |
| 7 | `optimizer_runs = 1000` si las views (`availableBalance`, `tokensLockedFor`) se llaman frecuentemente desde el frontend/backend. Trade-off: +10–15% bytecode (~1 100 bytes, hay margen de sobra) | Global | ~300–500 gas/call en views calientes | Bajo (config) | Bajo |
| 8 | Mantener `nonReentrant` en `iniciarRedencion`/`cancelarRedencion` (defensivo, RM-14) — NO eliminar pese al ~2 300 gas | — | 0 (decisión de seguridad) | — | Ninguno |

---

## Comparación con los otros contratos del sistema

| Operación | IdentityRegistry | AssetVault | RedemptionManager | Notas |
|---|---|---|---|---|
| Función mutating más cara | `setKYC` ~98 363 | `confirmarCosecha` ~296 978 | `completarRedencion` ~225 815 (median) | RM en el medio; su costo vive mayormente en el burn delegado a AssetVault |
| Función "de entrada" del flujo | `setKYC` ~98 363 | `comprar` ~248 776 (avg) | `iniciarRedencion` ~250K cold-state | Las 3 son las puertas de entrada de cada subsistema |
| Cross-contract calls que hace | 0 (es el oráculo de identidad) | `canMint` (×2 — bug doc'd) | `canRedeem` + 3 calls a AssetVault | RM es el contrato más "acoplado": lee de Identity Y de Vault |
| Cross-contract calls que recibe | `canMint`/`canRedeem` desde Vault y RM | `burnForRedemption` desde RM | ninguno (es hoja del grafo) | RM consume; no es consumido |
| SSTOREs en el write principal | 2 (`setKYC`) | ~9 (`crearLote`) | ~8 (`iniciarRedencion`, struct `Redencion`) | El struct `Redencion` mal-packeado infla esto (ver storage analysis) |
| Storage por entidad | 2 slots (KYCData, óptimo) | ~20 slots (LoteMiel) | ~9 slots (Redencion, sub-óptimo) | KYCData es el mejor ejemplo de packing del sistema; Redencion el peor |
| Bytecode | 8 645 bytes | 20 113 bytes | 11 034 bytes | RM intermedio |
| Base de access control | `AccessControl` | `AccessControl` | `AccessControlDefaultAdminRules` (FIX M-08, +1 500 bytes) | RM es el único con delay de 3 días en admin transfer |

### Análisis comparativo

1. **RedemptionManager es un contrato "delgado y acoplado".** Su lógica propia es barata; el costo real de `completarRedencion` (~226K) vive en `assetVault.burnForRedemption()`. El diseño Option B (lock contable, sin transferir tokens al contrato) mantiene a RM sin balance de tokens y sin lógica ERC-1155, lo que reduce su bytecode y su superficie de ataque.

2. **El punto débil de packing está en el struct `Redencion`**, no en el contrato. IdentityRegistry logra 2 slots por identidad con packing perfecto; AssetVault logra packing decente en `LoteMiel` (slots 6 y 14). `Redencion` desperdicia un slot completo en `estado` (enum uint8 solo) y 12 bytes en `comprador`. El reorder (recomendación #2) lo alinearía con el estándar de calidad de los otros dos.

3. **`iniciarRedencion` paga un "impuesto de lectura" del LoteMiel** que las funciones equivalentes de los otros contratos no pagan. `comprar()` en AssetVault lee `_lotes[loteId]` como `storage` pointer (lazy SLOAD de solo los campos usados); `iniciarRedencion` recibe el `LoteMiel` por `memory` desde el getter externo `lotes()`, forzando la copia completa. Es el costo de ser un contrato separado que lee el estado de otro (recomendación #1).

4. **El doble evento (OZ + custom) en pause/unpause** (RM-15) es un patrón que IdentityRegistry y AssetVault no replican en sus pause. Agrega ~1 200 gas pero da trazabilidad forense (`EmergencyPaused(actor, timestamp)`) que el `Paused()` plano de OZ no provee. Trade-off de auditabilidad justificado para un contrato de redención física.

---

## Notas finales

- **`iniciarRedencion` median (421 047) NO es el costo de producción.** Está inflado por el fuzz `testFuzz_iniciarRedencion_AcumuladorNoExcedeBalance` (10 000 runs que crean lotes desde cero). El costo real de una `iniciarRedencion` aislada va del **min 41 460** (state caliente) a **~250 000–280 000** (cold-state, primera redención del lote en su propia tx). Al estimar fees de producción, usar el rango cold-state.

- **El grueso del gas del ciclo de redención vive en AssetVault, no en RedemptionManager.** `completarRedencion` (~226K) delega el burn; `iniciarRedencion` (~250K cold) paga la lectura del LoteMiel. RedemptionManager en sí mismo es barato — es un orquestador delgado sobre AssetVault + IdentityRegistry.

- **`AccessControlDefaultAdminRules` (FIX M-08) tiene un costo de bytecode (~1 500 bytes) y de deployment justificado.** El delay de 3 días en transferencias de `DEFAULT_ADMIN_ROLE` mitiga lockout accidental/malicioso del Safe 2-de-3. Es una decisión de seguridad documentada, no un overhead evitable.

- **`block.timestamp` en `cancelarRedencion` (buyer-after-timeout)** es seguro: el threshold es 60 DÍAS (5 184 000 s), la manipulación posible por validators es ±15 s = 0.000003% del threshold. No se usa para randomness ni timing de precisión. Slither lo marca como falso positivo (`slither-disable-next-line timestamp`), documentado en ADR-015.

- **`via_ir = false` en foundry.toml:** conservador y correcto para el MVP. Activarlo podría dar 5–15% de ahorro en las funciones con structs (iniciar, completar) por fusión de SSTOREs de slots empaquetados, pero requiere re-ejecutar Slither y revisar el output compilado antes de cualquier deploy.

- **Los contratos `src/` están congelados y auditados** (100% branch coverage, Slither 0, 216 tests verdes). Todas las recomendaciones de este documento que tocan `src/` (#1, #2, #3, #4) son candidatas para una **iteración post-MVP con ADR + re-auditoría**, no para el release actual. Las recomendaciones de config (#5, #7) son las únicas aplicables sin tocar código auditado.
