# Gas Analysis — IdentityRegistry.sol v0.1.0

**Analyst:** Subagente B (claude-sonnet-4-6)
**Date:** 2026-05-22
**Compiler:** Solidity 0.8.24, optimizer enabled, runs=200, evm_version=paris
**Source:** `packages/contracts/src/IdentityRegistry.sol`

---

## Resumen ejecutivo

Los tres mayores costos en IdentityRegistry son:

1. **`setKYC()` first-time** — escribe 5 campos sobre un slot KYCData nuevo (2 SSTOREs fríos en total por el packing de slot 0 y slot 1). Costo total ~75 000–85 000 gas frío, incluyendo el role check de AccessControl que cuesta ~4 200 gas por 2 SLOADs fríos de mapping de roles.

2. **Cross-contract calls desde AssetVault/RedemptionManager** — cada llamada a `canMint()` o `canRedeem()` desde otro contrato agrega ~7 000–12 000 gas al caller (2 600 base + ejecución interna con 1 SLOAD frío del mapping `_kyc`). En el flujo `comprar()` de AssetVault, `canMint()` se invoca DOS veces (bug identificado en AssetVault-gas-2026-05-19.md). El IdentityRegistry en sí no puede evitar esto, pero el costo de la view se puede reducir.

3. **`markSanctioned()` / `freezeAddress()`** — funciones que hacen 2 SLOADs del mismo slot `_kyc[user]` sin cachear el storage pointer en el check. La función hace `_kyc[user].sanctioned` (SLOAD 1 en el check) y luego `_kyc[user].sanctioned = true` + `_kyc[user].updatedAt = ...` (SSTORE sobre el mismo slot). Son accesos cálidos (warm) por ser el mismo slot, pero el patrón de acceso doble podría consolidarse.

**Top recomendación:** el storage layout de `KYCData` es casi óptimo (2 slots) pero tiene 11 bytes libres en slot 0 que pueden absorber campos futuros como `revoked: bool` y `bytes2 countrySubdivision` sin costo adicional. El único anti-patrón relevante es el acceso doble al mismo slot en las funciones de compliance sin cachear el storage pointer (líneas 101–104, 113–116, 129–132, 141–144).

---

## Gas estimado por función

> Convenciones: **cold** = slot jamás tocado en esta tx (SLOAD = 2 100 gas, SSTORE new = 22 100 gas); **warm** = slot ya cargado (SLOAD = 100 gas, SSTORE dirty = 5 000 gas, SSTORE clean-to-nonzero = 20 000 gas).
> AccessControl `onlyRole` modifier cuesta ~4 200 gas (2 SLOADs fríos: mapping `_roles[role][account]` + `_roles[DEFAULT_ADMIN_ROLE][account]` para la herencia).

### Funciones mutating

#### `setKYC()` — primer registro (first-time)

| Componente | Gas estimado |
|---|---|
| Base tx + calldata (5 params × 32 bytes aprox) | ~3 500 |
| `onlyRole(BACKEND_SIGNER_ROLE)` check (2 SLOADs fríos) | ~4 200 |
| `user == address(0)` check (pure) | ~30 |
| `tier > MAX_KYC_TIER` check (ComplianceConstants constant, no SLOAD) | ~30 |
| `expiresAt <= block.timestamp` check (TIMESTAMP opcode) | ~10 |
| `KYCData storage data = _kyc[user]` — mapping slot derivation | ~0 (pure arithmetic, no SLOAD yet) |
| **SSTORE slot 0 frío**: tier(1) + sanctioned(1) + frozen(1) + jurisdiction(2) + expiresAt(8) + updatedAt(8) = 21 bytes — todos en slot 0 | ~22 100 (1 SSTORE frío, escribe slot completo) |
| **SSTORE slot 1 frío**: sumsubApplicantHash(32) — slot 1 completo | ~22 100 (1 SSTORE frío) |
| Event `KYCUpdated` (1 indexed + 3 non-indexed) | ~1 800 |
| **Total (first-time, slots fríos)** | **~53 000 – 58 000 gas** |

> Nota: el SSTORE de slot 0 escribe TODOS los campos pequeños del slot en una sola operación. `data.tier`, `data.expiresAt`, `data.updatedAt`, `data.jurisdiction` están todos en el mismo slot 0 — el EVM escribe el slot completo una vez. Sin embargo, en el código actual hay 5 asignaciones separadas (`data.tier = tier`, `data.expiresAt = expiresAt`, etc.). El compilador con optimizer=200 y paris target DEBERÍA consolidarlas en 1 SSTORE para slot 0 + 1 SSTORE para slot 1. Si el optimizer no las fusiona, podrían ser hasta 5 SSTOREs, elevando el costo a ~110 500 gas. Ver sección de patrones costosos.

#### `setKYC()` — actualización de KYC existente (update)

| Componente | Gas estimado |
|---|---|
| `onlyRole` + checks pure | ~4 270 |
| Slot 0 ya existe → SSTORE warm (dirty): tier + expiresAt + updatedAt + jurisdiction | ~5 000 (1 SSTORE warm, slot ya cargado) |
| Slot 1 ya existe → SSTORE warm: sumsubApplicantHash | ~5 000 |
| Event `KYCUpdated` | ~1 800 |
| **Total (update, slots warm)** | **~16 000 – 20 000 gas** |

#### `revokeKYC()`

| Componente | Gas estimado |
|---|---|
| `onlyRole(BACKEND_SIGNER_ROLE)` | ~4 200 |
| `user == address(0)` + `bytes(reason).length == 0` (calldata length check) | ~200 |
| `_kyc[user].tier == 0` check — SLOAD frío de slot 0 del mapping | ~2 100 |
| `_kyc[user].tier = 0` — SSTORE warm (slot ya cargado, escribe 0 en campo empaquetado) | ~5 000 |
| `_kyc[user].updatedAt = uint64(block.timestamp)` — SSTORE warm (mismo slot 0) | ~100 (slot ya dirty en esta tx) |
| Event `KYCRevoked` (1 indexed + 1 string arg) | ~1 800 + calldata_string_cost |
| **Total (con reason corta < 32 bytes)** | **~14 000 – 18 000 gas** |

> El campo `reason` es `calldata` — NO se almacena en storage. Solo se paga calldata gas (4 gas/zero byte, 16 gas/nonzero byte) + el costo del evento que lo loggea. Una reason de 50 chars ≈ ~800 gas en calldata + ~1 200 gas en el log. Una reason larga de 200 chars ≈ ~3 200 gas en calldata + ~4 000 gas en el log.

#### `markSanctioned()` — first-time (usuario no estaba sancionado)

| Componente | Gas estimado |
|---|---|
| `onlyRole(COMPLIANCE_OFFICER_ROLE)` | ~4 200 |
| `user == address(0)` check | ~30 |
| `bytes(reason).length == 0` check (calldata) | ~100 |
| `_kyc[user].sanctioned` check — **SLOAD frío slot 0** | ~2 100 |
| `_kyc[user].sanctioned = true` — **SSTORE warm** (slot 0 ya cargado) | ~5 000 |
| `_kyc[user].updatedAt = uint64(block.timestamp)` — SSTORE warm (mismo slot 0, dirty) | ~100 |
| Event `Sanctioned` (1 indexed + string + bytes32 + uint64) | ~2 500 |
| **Total (reason corta ~50 chars)** | **~15 000 – 18 000 gas** |

> Con `reason` larga (200 chars): add ~3 000 gas en calldata + evento. Máximo razonable: ~22 000 gas.

#### `unmarkSanctioned()`

| Componente | Gas estimado |
|---|---|
| `onlyRole` + checks | ~4 330 |
| `_kyc[user].sanctioned` check — SLOAD frío slot 0 | ~2 100 |
| `_kyc[user].sanctioned = false` — SSTORE warm (nonzero → zero = refund 4 800) | ~5 000 – 4 800 = ~200 neto (más exactamente: SSTORE dirty ~5 000, refund al final) |
| `_kyc[user].updatedAt` SSTORE warm dirty | ~100 |
| Event `Unsanctioned` | ~1 800 |
| **Total (neto, considerando refund)** | **~10 000 – 14 000 gas** |

#### `freezeAddress()` — first-time

| Componente | Gas estimado |
|---|---|
| `onlyRole(COMPLIANCE_OFFICER_ROLE)` | ~4 200 |
| `user == address(0)` + `bytes(regulatoryOrder).length == 0` | ~130 |
| `_kyc[user].frozen` check — SLOAD frío slot 0 | ~2 100 |
| `_kyc[user].frozen = true` — SSTORE warm | ~5 000 |
| `_kyc[user].updatedAt` — SSTORE warm dirty | ~100 |
| Event `Frozen` (1 indexed + string + bytes32) | ~2 500 |
| **Total** | **~15 000 – 18 000 gas** |

#### `unfreezeAddress()`

Idéntico a `unmarkSanctioned()` en estructura. El `frozen = false` genera el mismo refund parcial.

| **Total (neto)** | **~10 000 – 14 000 gas** |
|---|---|

### Funciones view

Las funciones view no cuestan gas cuando se llaman off-chain (eth_call). El costo relevante es cuando son llamadas CROSS-CONTRACT desde AssetVault o RedemptionManager (sección dedicada más adelante).

#### `canMint()` y `canRedeem()` — las más críticas

```solidity
function canMint(address user) external view returns (bool) {
    KYCData storage data = _kyc[user];                        // slot pointer (no SLOAD aún)
    return data.tier >= MIN_KYC_TIER_PARA_COMPRAR             // SLOAD slot 0 (tier)
        && !data.sanctioned                                    // warm (mismo slot 0)
        && !data.frozen                                        // warm (mismo slot 0)
        && data.expiresAt > block.timestamp;                   // warm (mismo slot 0)
}
```

El storage pointer `data` se resuelve a `keccak256(abi.encode(user, mapping_slot))`. El acceso a `data.tier`, `data.sanctioned`, `data.frozen`, `data.expiresAt` lee TODOS del mismo slot 0 del struct. El optimizer reconoce que todos estos campos están en el mismo slot de 32 bytes y debería generar UN SOLO SLOAD.

| Componente | Gas estimado |
|---|---|
| Función selector + JUMPDEST | ~30 |
| keccak256 del mapping key (address + slot position) | ~36 |
| **1 SLOAD frío slot 0** (carga tier + sanctioned + frozen + expiresAt + updatedAt) | ~2 100 |
| 4 comparaciones sobre el valor cargado | ~40 |
| RETURN | ~10 |
| **Total ejecución interna** | **~2 200 – 2 500 gas** |

`canRedeem()` es structuralmente idéntico (usa `MIN_KYC_TIER_PARA_REDIMIR = 2` en lugar de `1`). Mismo costo: **~2 200 – 2 500 gas**.

#### `getTier(address user)`

| Componente | Gas estimado |
|---|---|
| SLOAD frío slot 0 | ~2 100 |
| Isolate `uint8 tier` from packed slot | ~10 |
| **Total ejecución interna** | **~2 150 – 2 200 gas** |

#### `isSanctioned(address user)` y `isFrozen(address user)`

Mismo costo que `getTier` — leen el mismo slot 0. **~2 150 – 2 200 gas cada una.**

#### `isExpired(address user)`

Lee `expiresAt` de slot 0 (SLOAD) + `block.timestamp` (TIMESTAMP opcode = 2 gas). **~2 150 – 2 200 gas.**

#### `getJurisdiction(address user)`

Lee `jurisdiction` de slot 0. **~2 150 – 2 200 gas.**

#### `getKYCData(address user)` — retorna struct completo

| Componente | Gas estimado |
|---|---|
| SLOAD frío slot 0 (tier + sanctioned + frozen + jurisdiction + expiresAt + updatedAt) | ~2 100 |
| SLOAD frío slot 1 (sumsubApplicantHash) | ~2 100 |
| Memory allocation para KYCData struct (2 words) | ~12 |
| RETURN con ABI encoding de struct | ~200 |
| **Total ejecución interna** | **~4 400 – 4 600 gas** |

Cuando `getKYCData()` se llama cross-contract, ambos slots se cargan fríos en la primera llamada de la tx. Si `canMint()` fue llamado antes en la misma tx, slot 0 ya está warm: costo cae a ~2 200 gas.

---

## Storage packing analysis

### Layout actual de KYCData

```
Struct KYCData (IIdentityRegistry.sol líneas 12–20):
  uint8   tier               = 1 byte
  bool    sanctioned         = 1 byte
  bool    frozen             = 1 byte
  bytes2  jurisdiction       = 2 bytes
  uint64  expiresAt          = 8 bytes
  uint64  updatedAt          = 8 bytes
  ─────────────────────────────────────
  Subtotal slot 0            = 21 bytes   → 11 bytes libres en slot 0
  ─────────────────────────────────────
  bytes32 sumsubApplicantHash = 32 bytes  → slot 1 completo
```

**Total: 2 slots de storage por usuario.** Esto es excelente — es el mínimo posible para este conjunto de datos dado que `bytes32` no puede empaquetarse con nada.

### ¿Es óptimo el orden actual?

**Sí, con matices.** El orden actual agrupa todos los campos pequeños en slot 0 y el hash en slot 1. Cualquier reordenamiento que pusiera `bytes32` primero lo empujaría a slot 0, y los campos pequeños deberían ir todos a slot 1 de todas formas (ya que `bytes32` ocupa un slot completo). El orden actual es correcto.

### Bytes libres en slot 0 — capacidad de expansión

Slot 0 tiene **11 bytes disponibles** (32 - 21 = 11). Esto permite agregar futuros campos sin costo de storage adicional:

| Campo potencial | Tamaño | Costo de agregar |
|---|---|---|
| `bool revoked` | 1 byte | **0 SSTOREs extra** — entra en slot 0 |
| `bytes2 countrySubdivision` | 2 bytes | **0 SSTOREs extra** — entra en slot 0 |
| `uint32 lastActivityTs` (timestamp reducido) | 4 bytes | **0 SSTOREs extra** — entra en slot 0 |
| `uint8 accreditedInvestorFlag` | 1 byte | **0 SSTOREs extra** — entra en slot 0 |

Hasta agregar ~11 bytes de campos nuevos, no se necesita un tercer slot de storage. Esto tiene valor económico importante: las operaciones de escritura/lectura de KYC futuras NO aumentarán de costo si los nuevos campos caben en slot 0.

**Recomendación:** documentar en `IIdentityRegistry.sol` los 11 bytes disponibles como comentario de capacidad. Reservar explícitamente para `bool revoked` (previsto en el flujo `revokeKYC`) y `bytes2 countrySubdivision` (posible requerimiento regulatorio futuro).

### ¿Podría reordenarse para mayor eficiencia?

El orden actual ya es óptimo. Una alternativa sería:

```solidity
// Alternativa equivalente — mismo packing, diferente legibilidad
struct KYCData {
    uint64  expiresAt;      // 8 bytes  ─┐
    uint64  updatedAt;      // 8 bytes   │ slot 0
    bytes2  jurisdiction;   // 2 bytes   │ 21 bytes ocupados
    uint8   tier;           // 1 byte    │ 11 bytes libres
    bool    sanctioned;     // 1 byte    │
    bool    frozen;         // 1 byte   ─┘
    bytes32 sumsubApplicantHash; // 32 bytes → slot 1
}
```

Mismo resultado de packing. El orden actual (tier primero) es más legible desde la perspectiva del dominio.

---

## Cross-contract call cost (consumidores)

Cada vez que un contrato externo llama a `canMint()` o `canRedeem()`, paga:

| Componente | Gas |
|---|---|
| `CALL` opcode overhead (EIP-2929) — frío | ~2 600 |
| Warm call (segunda llamada al mismo contrato en la tx) | ~100 |
| Ejecución de `canMint()` / `canRedeem()` internamente | ~2 200 – 2 500 |
| RETURN overhead | ~30 |
| **Total cold call** | **~4 800 – 5 200 gas** |
| **Total warm call** | **~2 400 – 2 700 gas** |

### Impacto en AssetVault.`comprar()`

Según AssetVault-gas-2026-05-19.md, `comprar()` llama `canMint()` DOS veces: una en línea explícita y otra dentro de `_update()`. Costo añadido al caller por ambas llamadas:

| Escenario | Costo añadido |
|---|---|
| Primera llamada en la tx (cold) | ~4 800 – 5 200 gas |
| Segunda llamada (warm, mismo contrato) | ~2 400 – 2 700 gas |
| **Total por `comprar()` (doble call actual)** | **~7 200 – 7 900 gas** |
| **Total si se elimina el check redundante (single call)** | **~4 800 – 5 200 gas** |
| **Ahorro de eliminar la llamada duplicada** | **~2 400 – 2 700 gas por transacción** |

### Impacto en RedemptionManager.`iniciarRedencion()`

Asumiendo `canRedeem()` se llama una vez por transacción:

| Llamada | Costo añadido al caller |
|---|---|
| Cold call (primera vez) | ~4 800 – 5 200 gas |
| Warm call (si ya llamó canMint u otra función del registry) | ~2 400 – 2 700 gas |

### Costo por view individual (getTier, isSanctioned, etc.)

Si AssetVault o RedemptionManager alguna vez llaman a views individuales en lugar de `canMint/canRedeem`:

| View | Costo cold call | Costo warm call |
|---|---|---|
| `getTier()` | ~4 300 gas | ~2 250 gas |
| `isSanctioned()` | ~4 300 gas | ~2 250 gas |
| `isFrozen()` | ~4 300 gas | ~2 250 gas |
| `getKYCData()` | ~7 000 – 7 200 gas | ~4 600 gas |

`canMint()` es más eficiente que llamar `getTier()` + `isSanctioned()` + `isFrozen()` + `isExpired()` por separado (4 calls cold = ~17 200 gas vs 1 call = ~5 000 gas). El diseño actual de consolidar la lógica en `canMint()` es correcto y eficiente.

---

## Patrones costosos identificados

### 1. Acceso doble al mismo mapping slot sin cachear `KYCData storage`

**Funciones afectadas:** `markSanctioned()`, `unmarkSanctioned()`, `freezeAddress()`, `unfreezeAddress()`, `revokeKYC()`.

**Patrón actual en `markSanctioned()` (líneas 101–104):**

```solidity
if (_kyc[user].sanctioned) revert AlreadySanctioned();   // SLOAD frío slot 0
_kyc[user].sanctioned = true;                             // SSTORE warm slot 0
_kyc[user].updatedAt = uint64(block.timestamp);           // SSTORE warm slot 0 (ya dirty)
```

El primer acceso `_kyc[user].sanctioned` genera el SLOAD del mapping (cálculo de `keccak256(user || mapping_slot)` + SLOAD del slot resultante). Los accesos posteriores `_kyc[user].sanctioned = true` y `_kyc[user].updatedAt = ...` también generan el keccak256 del mapping key aunque ahora sea warm. En EVM post-EIP-2929 los SLOADs warm cuestan 100 gas y los SSTOREs dirty cuestan 5 000 gas, pero el cómputo del mapping key (keccak256) se realiza en cada acceso a menos que el compilador la cachee.

El código usa `KYCData storage data = _kyc[user]` SOLO en `setKYC()`, `canMint()` y `canRedeem()`. Las funciones de compliance (`markSanctioned`, `freezeAddress`, etc.) acceden a `_kyc[user]` directo en cada línea.

**El optimizer con runs=200 DEBERÍA reconocer los accesos repetidos al mismo mapping slot y cachear el slot address.** Sin embargo, no se puede garantizar que el optimizer elimine completamente el overhead de keccak256 en cada acceso, especialmente si las escrituras están en diferentes statements.

**Solución recomendada (bajo esfuerzo):**

```solidity
function markSanctioned(address user, string calldata reason, bytes32 evidenceHash)
    external onlyRole(COMPLIANCE_OFFICER_ROLE)
{
    if (user == address(0)) revert ZeroAddressUser();
    if (bytes(reason).length == 0) revert EmptyReason();

    KYCData storage data = _kyc[user];        // cachea el slot pointer
    if (data.sanctioned) revert AlreadySanctioned();

    data.sanctioned = true;
    data.updatedAt = uint64(block.timestamp);

    emit Sanctioned(user, reason, evidenceHash, uint64(block.timestamp));
}
```

Aplicar en: `markSanctioned()`, `unmarkSanctioned()`, `freezeAddress()`, `unfreezeAddress()`, `revokeKYC()`.
**Ahorro estimado:** 50–200 gas por función (principalmente en clarity para el optimizer), bajo en valor absoluto pero costoso cero en esfuerzo.

### 2. `revokeKYC()` — doble acceso sin storage pointer

**Código (líneas 84–89):**

```solidity
if (_kyc[user].tier == 0) revert AlreadyRevoked();  // SLOAD frío slot 0
_kyc[user].tier = 0;                                  // SSTORE warm slot 0
_kyc[user].updatedAt = uint64(block.timestamp);       // SSTORE warm slot 0
```

Tres accesos a `_kyc[user]` sin cachear. El SLOAD frío inicial (2 100 gas) es inevitable, pero el costo del keccak256 del mapping key se podría calcular una sola vez. Misma solución: agregar `KYCData storage data = _kyc[user]` al inicio.

### 3. `string calldata reason` — no hay problema de storage

La revisión confirma que `reason` y `regulatoryOrder` son parámetros `calldata` en TODAS las funciones mutating. **NO se almacenan en storage.** El costo es solo:
- Calldata gas: 4 gas/byte-zero + 16 gas/byte-nonzero
- Log gas si se incluye en evento: 8 gas/byte aproximado

Esto es correcto y eficiente. No hay string storage innecesario.

### 4. `bytes(reason).length == 0` — check redundante posible

Las funciones de compliance validan `bytes(reason).length == 0`. Esta conversión `bytes(reason)` sobre un parámetro `calldata string` en Solidity 0.8.24 es una operación de bajo costo (puntero de calldata, no copia). El costo es ~30–50 gas. No es un problema.

### 5. Role constants — SLOADs fríos en AccessControl

`BACKEND_SIGNER_ROLE` y `COMPLIANCE_OFFICER_ROLE` son `bytes32` constantes calculadas con `keccak256`. Al ser `public constant`, están embebidas en el bytecode (no en storage) — **costo: 0 SLOADs**. El costo del `onlyRole` modifier viene del AccessControl heredado que lee `_roles[role][account]` (mapping de mapping = 2 keccak256 + SLOAD). Esto es inherente a OpenZeppelin AccessControl y no optimizable sin cambiar el mecanismo de autorización.

---

## Costo de deployment

### Estimación de bytecode size

IdentityRegistry hereda de `AccessControl` y implementa `IIdentityRegistry`.

| Componente | Bytecode aprox. |
|---|---|
| AccessControl (OZ v5) — roles, grants, revokes | ~3 000 bytes |
| IIdentityRegistry interface (solo tipos/events, no bytecode) | ~0 bytes |
| IdentityRegistry logic propio (8 funciones mutating + 7 views) | ~4 500 – 5 500 bytes |
| Constructor (4 validaciones + 4 grantRole calls) | ~800 bytes |
| Custom errors (9 errores, 4 bytes cada uno en selector) | ~200 bytes |
| **Total estimado** | **~8 500 – 9 500 bytes** |

Muy por debajo del límite EIP-170 de 24 576 bytes. IdentityRegistry es el contrato más pequeño del sistema por diseño (registro puro, sin lógica de negocio compleja).

### Gas de deployment

| Red | Gas estimado deployment | Costo a precio típico |
|---|---|---|
| Plume mainnet (L2) | ~900 000 – 1 200 000 gas | $0.001 – $0.012 (trivial en L2) |
| Polygon PoS mainnet | ~900 000 – 1 200 000 gas | $0.27 – $1.20 (a 30–100 gwei) |

El deployment es simple. El constructor hace 4 zero-checks (pure) + 4 `_grantRole()` calls, cada uno con 1 SSTORE frío (~22 100 gas × 4 = ~88 400 gas solo en grants).

### Bytecode comparison con otros contratos del sistema

No hay duplicación de bytecode entre IdentityRegistry, AssetVault y RedemptionManager porque comparten solo AccessControl (que se compila por separado en cada uno). Las libraries `ComplianceConstants` son `internal` — sus constantes se inline en el bytecode de cada contrato que las usa. Dado que son constantes (no código ejecutable), el overhead es mínimo (~50–100 bytes por uso).

---

## Recomendaciones priorizadas

| # | Optimización | Función afectada | Ahorro estimado | Esfuerzo | Riesgo |
|---|---|---|---|---|---|
| 1 | Cachear `KYCData storage data = _kyc[user]` en `markSanctioned()`, `unmarkSanctioned()`, `freezeAddress()`, `unfreezeAddress()`, `revokeKYC()` (líneas 101, 113, 129, 141, 84) | 5 funciones compliance | 50–200 gas/tx (optimizer consistency) | Mínimo | Ninguno |
| 2 | Documentar los 11 bytes libres en slot 0 de `KYCData` como comentario de capacidad en `IIdentityRegistry.sol` — reservar explícitamente para `bool revoked` y `bytes2 countrySubdivision` | IIdentityRegistry.sol | 0 gas runtime, previene slot extra futuro (22 100 gas ahorrado por campo nuevo que cabe en slot 0) | Mínimo (doc only) | Ninguno |
| 3 | Verificar que el optimizer fusione los 5 SSTOREs en `setKYC()` (slot 0: tier + expiresAt + updatedAt + jurisdiction, slot 1: sumsubApplicantHash) corriendo `forge snapshot` para medir. Si el optimizer genera 5 SSTOREs en vez de 2, consolidar con asignación explícita del struct completo. | `setKYC()` | Potencial ~66 300 gas (3 SSTOREs duplicados evitados) si el optimizer falla | Bajo | Bajo — solo cambia la forma de escritura, no la lógica |
| 4 | Activar `via_ir = true` en foundry.toml — el Yul IR optimizer es más agresivo fusionando SSTOREs de slots empaquetados y eliminando keccak256 duplicados | Global | 5–15% en funciones complejas; ~500–800 gas en setKYC | Bajo (config) | Bajo — requiere re-ejecutar Slither |
| 5 | En `setKYC()`, agregar validación `if (tier == 0) revert InvalidTier()` además del check `tier > MAX_KYC_TIER`. Actualmente `tier = 0` es un valor válido pero semánticamente equivale a "sin KYC". Debería bloquearse en `setKYC` (actualmente solo `revokeKYC` pone tier=0). | `setKYC()` | Correctness fix, no gas | Mínimo | Bajo — alineación de invariante |
| 6 | Mover `bytes(reason).length == 0` check ANTES del `user == address(0)` check en funciones donde `user` viene después de `reason` — el calldata check es más barato que la address check (puntero vs valor) | `revokeKYC()`, `markSanctioned()`, etc. | ~20–50 gas en revert paths | Mínimo | Ninguno |
| 7 | Agregar `bool revoked` en slot 0 de `KYCData` para tracking explícito de revocaciones (actualmente `revokeKYC` solo pone `tier = 0`, lo que es ambiguo con "nunca tuvo KYC") | `IIdentityRegistry.sol`, `revokeKYC()` | 0 gas extra (entra en slot 0 existente), mejora semántica | Medio (breaking change en struct layout) | Medio — requiere ADR |
| 8 | Considerar `optimizer_runs = 1000` si el registry se llama frecuentemente (cada comprar + cada redención = N+M calls por sesión de trading). Con runs=1000 el optimizer prioriza el costo de call sobre el costo de deployment. Para el registry (deploy 1 vez, call N×M veces), runs alto es preferible. | Global | ~300–500 gas por llamada a canMint/canRedeem | Bajo (config) | Bajo — solo afecta bytecode size (+10–20%) |
| 9 | Agregar evento `KYCExpired` emitido off-chain o en un job periódico (no en el contrato) para detectar KYC vencidos proactivamente. El contrato no puede hacer esto on-chain sin un pull pattern, pero el backend debería monitorear `expiresAt` y llamar `revokeKYC` cuando vence. | Off-chain / backend | Previene operaciones fallidas por KYC vencido | Medio (backend) | Bajo |
| 10 | Evaluar si `getKYCData()` necesita ser external o podría ser marcado `public`. Como el sistema es multi-chain (Plume + Polygon), los contratos en la misma chain pueden llamarla directamente. No cambia el gas cross-contract, pero clarifica la API. | `getKYCData()` | ~0 gas (solo API clarity) | Mínimo | Ninguno |

---

## Comparación con industria

| Sistema / Patrón | Storage por identity | Gas canMint/verify equivalente | SSTOREs en write | Notas |
|---|---|---|---|---|
| **IdentityRegistry (este contrato)** | 2 slots (64 bytes útiles, 11 bytes libres en slot 0) | ~2 200 gas (internal) / ~5 000 gas (cross-contract) | 2 SSTOREs en setKYC | Óptimo para el scope |
| **T-REX / ERC-3643 (Tokeny)** | 3–5 slots (ClaimTopicsRegistry + IdentityStorage separados) | ~8 000–15 000 gas (múltiples contratos) | 3–5 SSTOREs | Más modular pero más costoso |
| **Polymath (ST-20)** | 2–4 slots (SecurityTokenRegistry + WhitelistTransferManager) | ~10 000–20 000 gas (verificación en transferencias) | 3–6 SSTOREs | Arquitectura más pesada, más features |
| **OpenZeppelin AccessControl** | 1 slot por role×account (mapping de mapping) | ~2 100 gas (1 SLOAD) | 1 SSTORE por grant | Solo roles, sin datos KYC |
| **ENS Registry (storage pattern)** | 3 slots por node (owner + resolver + TTL) | N/A (no tiene canMint) | 1–3 SSTOREs | Referencia de packing simple |
| **Compound (Comptroller whitelist)** | 1 slot por address (bool) | ~2 100 gas (1 SLOAD) | 1 SSTORE | Mínimo pero sin tiers ni timestamps |
| **MakerDAO (KYC-like: CDPManager)** | 1 slot por urn (sin compliance checks) | N/A | 1 SSTORE | Sin modelo de compliance |

### Análisis comparativo

IdentityRegistry logra **2 slots por identidad** con un modelo de compliance más rico que los sistemas comparables:
- T-REX ERC-3643 requiere 3–5 slots y múltiples contratos porque separa ClaimTopicsRegistry, TrustedIssuersRegistry e IdentityStorage. El costo de verificación cross-contract es 3–5× más alto.
- Polymath almacena datos similares pero distribuidos en más contratos con overhead mayor.
- El diseño actual es comparable a "Compound whitelist" en eficiencia de storage, pero con tier + expiry + sanctions + freeze en el mismo slot — una optimización de packing que los systems más simples no necesitan porque no tienen esos campos.

El overhead respecto a sistemas DeFi puros (~2 100 gas por bool check) es de ~2 400–2 700 gas adicionales por call, justificado por el modelo de compliance (tier + expiry + sanctions + freeze en una sola lectura de slot). El diseño es eficiente dado su scope regulatorio.

**El punto más débil relativo a la industria** es que T-REX ERC-3643 tiene un mecanismo de actualización de claims sin reescribir todo el struct (solo actualiza el claim específico). En IdentityRegistry, `setKYC()` sobreescribe todos los campos del slot 0 y slot 1 incluso si solo cambió la fecha de expiración. Para updates frecuentes de `expiresAt` sería más eficiente tener una función `renewKYC(address user, uint64 newExpiresAt)` que escriba solo el campo que cambió dentro del slot 0 ya warm. Esto se traduce en un SSTORE warm (~5 000 gas) en lugar de potencialmente múltiples SSTOREs si el optimizer no fusiona las escrituras.

---

## Notas finales

- **Garantía de 2 SSTOREs en `setKYC()`:** ejecutar `forge snapshot` antes y después de cualquier cambio al struct para confirmar que el optimizer genera exactamente 2 SSTOREs (slot 0 + slot 1). Si genera 5 SSTOREs separados, hay un costo oculto de ~66 300 gas (3 SSTOREs innecesarios × 22 100 gas frío).

- **`canMint()` y `canRedeem()` son correctos por diseño:** leen exactamente 1 SLOAD (slot 0 del mapping) y evalúan 4 condiciones sobre ese valor. No hay SLOAD duplicado. Esta es la implementación óptima para una view de compliance multi-campo.

- **El contrato no tiene estado que pueda corromperse parcialmente:** si una transacción falla a mitad de `setKYC()`, el EVM revierte todos los SSTOREs. No hay riesgo de estado inconsistente entre slot 0 y slot 1.

- **`optimizer_runs = 200` vs `1000+`:** para IdentityRegistry, dado que es llamado en cada operación del sistema (comprar, redimir, transferir), aumentar runs a 500–1000 reduciría el gas de `canMint()`/`canRedeem()` a costa de un deployment ~10–15% más grande (~1 000–1 400 bytes extra). Con el volumen esperado de operaciones, el break-even se alcanza rápidamente.
