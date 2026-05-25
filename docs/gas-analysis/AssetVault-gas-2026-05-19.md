# Gas Analysis — AssetVault.sol v0.2.0

**Analyst:** Subagente B (claude-sonnet-4-6)
**Date:** 2026-05-19
**Compiler:** Solidity 0.8.24, optimizer enabled, runs=200, evm_version=paris
**Source:** `packages/contracts/src/AssetVault.sol`

---

## Resumen ejecutivo

Los tres mayores costos de gas en AssetVault son:

1. **`confirmarCalidad()`** — la función más costosa del sistema. Por cada lab en el array escribe 2 slots dinámicos de storage (labAddresses + fullReportHashes), llama dos veces a contratos externos por lab, y recalcula el hash de attestation para cada verificación de firma. Con 2 labs, el costo base es ~220K–280K gas.

2. **`comprar()`** — combina una llamada externa a `identityRegistry.canMint()`, una llamada `totalSupply()` que lee de ERC1155Supply, un mint ERC-1155, y un `safeTransfer` de USDC. Cada compra cuesta ~130K–160K gas en frío (slots nuevos) y ~90K–110K en caliente.

3. **`reembolsarLoteFallido()` con muchos compradores** — bucle sin bound sobre array externo. 100 compradores implican ~100 burns + 100 transfers USDC = ~5M gas, peligrosamente cercano al block gas limit de Plume (30M) y muy por encima de lo razonable para un batch único.

**Top recomendación:** dividir `reembolsarLoteFallido` en batches limitados y cachear el storage pointer `_lotes[loteId]` a memory donde se hacen múltiples lecturas sin escritura.

---

## Gas estimado por función

> Convenciones: **cold** = slot jamás tocado (SLOAD = 2100 gas); **warm** = slot ya cargado en tx actual (SLOAD = 100 gas). Cifras con optimizer runs=200.

### `crearLote()`

| Componente | Gas estimado |
|---|---|
| Role check (`onlyRole`) | ~2 400 (1 SLOAD cold) |
| Existencia check (`_lotes[loteId].productorSRL`) | ~2 100 (1 SLOAD cold de mapping) |
| 5 checks de validación (pure/cheapos) | ~200 |
| `DocumentHashes.isValid()` (pure) | ~30 |
| ComplianceConstants checks (constants, no SLOAD) | ~60 |
| **9 SSTOREs fríos** (kgEsperados, precioPorTokenUSDC, fechaCosechaEstimada, estado, fechaCreacion, origenGeografico, reservaBps, hashFSA, productorSRL, variedadMonofloral) — ver storage analysis para packing | ~9 × 22 100 = ~198 900 |
| Event emission (`LoteCreado`, 2 indexed topics) | ~1 800 |
| Calldata + base tx overhead | ~5 000 |
| **Total estimado** | **~210 000 – 220 000 gas** |

Note: los 9 escrituras podrían reducirse a 6–7 slots con mejor packing (ver sección 3).

### `comprar()`

| Componente | Gas estimado |
|---|---|
| Role check + `nonReentrant` lock (2 SLOADs cold) | ~4 200 |
| `_lotes[loteId]` load (mapping SLOAD cold) | ~2 100 |
| `lote.productorSRL` + `lote.estado` reads (warm) | ~200 |
| `identityRegistry.canMint()` (external call cold) | ~2 600 base + ~5 000–10 000 internas |
| `totalSupply(loteId)` — ERC1155Supply mapping read | ~2 200 |
| Arithmetic (kgYaVendidos, montoEsperado, reserva) | ~100 |
| `lote.reservaTecnicaUSDC` SSTORE warm (ya cargado) | ~5 000 (warm dirty slot) |
| `_mint(comprador, loteId, cantidadTokens, "")` — incluye `_update()` | ~35 000–50 000 |
| Dentro de `_update()`: `identityRegistry.canMint()` de nuevo (warm call) | ~3 000–7 000 |
| `ERC1155Supply._update()`: totalSupply SSTORE | ~5 000 warm |
| `usdc.safeTransfer()` — USDC transfer | ~25 000–35 000 |
| Event `LoteComprado` | ~1 800 |
| **Total (slot cold, primer comprador)** | **~130 000 – 160 000 gas** |
| **Total (slots warm, comprador repetido)** | **~80 000 – 110 000 gas** |

**Bug de duplicación:** `identityRegistry.canMint(comprador)` se llama dos veces por `comprar()`: una vez explícitamente en línea 210, y otra dentro de `_update()` en línea 533. Costo extra: ~5 000–10 000 gas innecesarios por tx.

### `confirmarCosecha()`

| Componente | Gas estimado |
|---|---|
| Role check + `nonReentrant` | ~4 200 |
| `_lotes[loteId]` cold SLOAD | ~2 100 |
| 5 × `DocumentHashes.isValid()` (pure) | ~150 |
| 7 SSTOREs: kgCosechadosReal, hashSenasag, hashAnalisisLab, hashActaCosecha, hashFotosApiario, hashCertificadoOrigen, tipoCertificadoOrigen (packing parcial), estado | ~7 × 22 100 = ~154 700 (cold) |
| Event `CosechaConfirmada` | ~2 200 |
| **Total (slots cold)** | **~165 000 – 175 000 gas** |
| **Total (slots warm — si es posterior a crearLote en misma tx)** | **~60 000 – 80 000 gas** |

### `confirmarCalidad()`

Esta es la función más compleja y costosa. El costo varía con `N = attestation.labAddresses.length`. Análisis con N=2 (mínimo requerido por `ComplianceConstants.MIN_LABS_PARA_ATTESTATION`).

| Componente | Gas (N=2) |
|---|---|
| Role check + `nonReentrant` | ~4 200 |
| `_lotes[loteId]` cold SLOAD | ~2 100 |
| Array length checks | ~200 |
| `_computeAttestationHash()` — keccak256 con abi.encode de struct | ~800–2 000 (depende del tamaño de fullReportHashes) |
| **Loop N=2 iterations:** | |
| — `labRegistry.getLab(labAddr)` × 2 external calls | ~2 × 12 000 = ~24 000 |
| — jurisdiction checks (warm, pure) | ~400 |
| — `labRegistry.verifyAttestationSignature()` × 2 (external, ECDSA inside) | ~2 × (2 600 + 6 000) = ~17 200 |
| `delete stored.labAddresses` (SSTORE zero = refund 4 800) | ~5 000 neto con refund |
| `delete stored.fullReportHashes` | ~5 000 neto |
| 2 × `stored.labAddresses.push()` (array slot + length slot) | ~2 × 22 100 = ~44 200 |
| M × `stored.fullReportHashes.push()` (M=2 asumido) | ~2 × 22 100 = ~44 200 |
| 5 SSTOREs escalar: pollenSpecies, pollenPercentage, nmrPassed, c4Passed, residuesPassed, testedAt, isMonofloralCertified | ~5 × 22 100 (algunos packables) = ~80 000–110 000 |
| `lote.estado` SSTORE warm | ~5 000 |
| Event `CalidadConfirmada` (con address[] arg) | ~3 000 |
| **Total N=2, M=2** | **~220 000 – 280 000 gas** |
| **Total N=3, M=3** | **~300 000 – 380 000 gas** |
| **Total N=4, M=4** | **~400 000 – 500 000 gas** |

### `confirmarAlmacenamiento()`

| Componente | Gas estimado |
|---|---|
| Role check (no nonReentrant — OK para esta función) | ~2 400 |
| `_lotes[loteId]` cold SLOAD | ~2 100 |
| 2 checks + `DocumentHashes.isValid()` | ~250 |
| `hashContratoDeposito` SSTORE cold | ~22 100 |
| `estado` SSTORE warm | ~5 000 |
| Event | ~1 800 |
| **Total** | **~35 000 – 45 000 gas** |

### `marcarFallido()`

| Componente | Gas estimado |
|---|---|
| Role check | ~2 400 |
| `_lotes[loteId]` cold SLOAD | ~2 100 |
| `bytes(motivo).length` check | ~200 |
| `estado` SSTORE warm | ~5 000 |
| `motivoFallo` SSTORE string: 1 slot para length + 1 slot por 32 bytes de contenido | ~22 100 + N×22 100 (N = ceil(len/32)) |
| Si motivo = 32 bytes: total strings = ~44 200 | |
| Event `LoteFallido` (string arg en log) | ~2 500 + len×8 gas |
| **Total (motivo corto ~32 bytes)** | **~55 000 – 70 000 gas** |
| **Total (motivo largo ~256 bytes)** | **~120 000 – 150 000 gas** |

### `liberarReservaTecnica()`

| Componente | Gas estimado |
|---|---|
| Role check + `nonReentrant` | ~4 200 |
| `_lotes[loteId]` cold SLOAD | ~2 100 |
| Estado check (4 condiciones OR) warm read | ~400 |
| Arithmetic: `reservaTecnicaUSDC - reservaTecnicaLiberada` | ~100 |
| `reservaTecnicaLiberada` SSTORE | ~22 100 (cold) / ~5 000 (warm) |
| `usdc.safeTransfer()` | ~25 000–35 000 |
| Event | ~1 800 |
| **Total (cold)** | **~60 000 – 75 000 gas** |

### `reembolsarLoteFallido()` — batch refund

Análisis escalado. Asumimos buyer tiene tokens, no ha recibido reembolso antes.

| Buyers (N) | Gas estimado |
|---|---|
| N = 1 | ~90 000 – 110 000 gas |
| N = 10 | ~500 000 – 650 000 gas |
| N = 50 | ~2 400 000 – 3 100 000 gas |
| N = 100 | ~4 800 000 – 6 200 000 gas |

Desglose por iteración (costo marginal por buyer adicional):
- `balanceOf(buyer, loteId)` SLOAD ERC1155 mapping: ~2 100 cold / ~100 warm
- División pro-rata: ~50 gas
- `_burn()` interno: ~25 000 (incluye `_update()`, Supply update)
- `usdc.safeTransfer()`: ~25 000–35 000
- Event: ~1 800
- **Costo marginal por buyer: ~55 000 – 65 000 gas**

Con 100 buyers en un block (limit ~30M en Plume), el batch de 100 ya consume ~6M gas, lo que es manejable per-se pero arriesgado si coexiste con otras txs o si la estimación es conservadora y hay slippage.

### `burnForRedemption()`

| Componente | Gas estimado |
|---|---|
| `msg.sender != redemptionManager` check (warm, immutable-like) | ~2 200 |
| `_lotes[loteId]` cold SLOAD | ~2 100 |
| `kgRedimidos` arithmetic | ~100 |
| `lote.kgRedimidos` SSTORE | ~22 100 (cold) / ~5 000 (warm) |
| `lote.estado` SSTORE warm | ~5 000 |
| `_burn()` + `_update()` | ~25 000 |
| `totalSupply()` post-burn check | ~2 100 warm |
| Estado AGOTADO SSTORE (si aplica) | ~5 000 warm |
| **Total (cold, primer burn del lote)** | **~65 000 – 80 000 gas** |

### `pause()` / `unpause()`

| Componente | Gas estimado |
|---|---|
| Role check | ~2 400 |
| `_paused` SSTORE (1 bool slot) | ~22 100 cold / ~5 000 warm |
| Event | ~1 200 |
| **Total** | **~26 000 – 30 000 gas** |

### Comparación testnet vs mainnet

| Red | Gas price referencia | Costo `comprar()` (150K gas) | Costo `confirmarCalidad()` (250K gas) |
|---|---|---|---|
| Plume testnet (Amoy-like) | ~0.001 gwei | negligible | negligible |
| Plume mainnet | ~0.1–1 gwei (estimado, L2) | $0.000015–$0.00015 (USD equiv.) | $0.000025–$0.00025 |
| Polygon PoS mainnet | ~30–100 gwei | ~$0.006–$0.02 | ~$0.010–$0.033 |
| Ethereum mainnet | ~10–50 gwei | ~$0.45–$2.25 | ~$0.75–$3.75 |

Note: Plume es una L2 RWA-focused, los fees son substancialmente menores que Polygon o Ethereum mainnet. Para operaciones admin/oracle como `confirmarCalidad`, el costo en Plume es económicamente trivial.

---

## Storage packing analysis

### LoteMiel — slot por slot

El struct está declarado en `IAssetVault.sol` líneas 41–65. Analizando el orden actual:

```
Slot 0:  kgEsperados          (uint256 — 32 bytes, slot completo)
Slot 1:  kgCosechadosReal     (uint256 — 32 bytes, slot completo)
Slot 2:  kgRedimidos          (uint256 — 32 bytes, slot completo)
Slot 3:  precioPorTokenUSDC   (uint256 — 32 bytes, slot completo)
Slot 4:  reservaTecnicaUSDC   (uint256 — 32 bytes, slot completo)
Slot 5:  reservaTecnicaLiberada (uint256 — 32 bytes, slot completo)
Slot 6:  fechaCosechaEstimada (uint64 — 8 bytes)
         estado               (LoteEstado enum — uint8 — 1 byte)
         fechaCreacion        (uint64 — 8 bytes)
         origenGeografico     (bytes2 — 2 bytes)
         reservaBps           (uint16 — 2 bytes)
         ← 9 bytes libres en slot 6
Slot 7:  hashFSA              (bytes32 — 32 bytes, slot completo)
Slot 8:  hashSenasag          (bytes32 — 32 bytes, slot completo)
Slot 9:  hashAnalisisLab      (bytes32 — 32 bytes, slot completo)
Slot 10: hashContratoDeposito (bytes32 — 32 bytes, slot completo)
Slot 11: hashCertificadoOrigen (bytes32 — 32 bytes, slot completo)
Slot 12: hashActaCosecha      (bytes32 — 32 bytes, slot completo)
Slot 13: hashFotosApiario     (bytes32 — 32 bytes, slot completo)
Slot 14: productorSRL         (address — 20 bytes)
         variedadMonofloral   (uint8 — 1 byte)
         tipoCertificadoOrigen (TipoCertificadoOrigen — uint8 — 1 byte)
         ← 10 bytes libres en slot 14
Slot 15: motivoFallo string (longitud en este slot, data en slot keccak256(15) si > 31 bytes)
Slot 16: qualityAttestation (slot base del struct anidado)
         → labAddresses: array dinámico, 1 slot para length, data en keccak256(17)
         → pollenSpecies: bytes2
         → pollenPercentage: uint8
         → nmrPassed: bool
         → c4Passed: bool
         → residuesPassed: bool
         → fullReportHashes: array dinámico, 1 slot para length
         → testedAt: uint64
         → isMonofloralCertified: bool
         ← con packing: slots 16–19 aproximadamente
```

**Total slots para LoteMiel:** ~20 slots (excluyendo data de arrays dinámicos y strings largos).

#### Packing actual — ¿es óptimo?

Slot 6 es eficiente: `uint64 + uint8 + uint64 + bytes2 + uint16 = 8+1+8+2+2 = 21 bytes` dentro de 32 bytes. Correcto.

Slot 14 es eficiente: `address(20) + uint8(1) + uint8(1) = 22 bytes`. Correcto.

**Packing subóptimo detectado:** `QualityAttestation` struct anidado tiene scalars `pollenSpecies(2) + pollenPercentage(1) + nmrPassed(1) + c4Passed(1) + residuesPassed(1) + testedAt(8) + isMonofloralCertified(1) = 15 bytes`. Podrían estar todos en un único slot. Sin embargo, dado que los arrays dinámicos (`labAddresses[]`, `fullReportHashes[]`) fuerzan slots separados para sus length + data pointers, la situación real es:

```
QualityAttestation en storage (relativo al base slot B):
  B+0: labAddresses.length (uint256)
  B+1: pollenSpecies (bytes2) + pollenPercentage (uint8) + nmrPassed (bool) +
       c4Passed (bool) + residuesPassed (bool) + testedAt (uint64) +
       isMonofloralCertified (bool)  → 15 bytes, bien empaquetado
  B+2: fullReportHashes.length (uint256)
```

Esto es razonablemente óptimo. Los arrays dinámicos no se pueden empacar — su length ocupa un slot completo cada uno.

#### Recomendación de reorder

El orden actual es mayormente correcto. La única mejora sería mover `productorSRL`, `variedadMonofloral`, y `tipoCertificadoOrigen` a un slot anterior a los hashes, pero dado que los hashes son `bytes32` (full-slot), no hay ahorro ahí. El packing ya está bien para los campos pequeños.

**Un cambio sí valdría la pena:** mover `motivoFallo string` al final absoluto del struct (ya está al final) y considerar si puede ser `bytes32` en lugar de `string` (ver sección siguiente).

### QualityAttestation con arrays dinámicos — costo real

- Cada `stored.labAddresses.push(addr)`: 1 SSTORE para el elemento (slot = `keccak256(base_slot) + index`), y si es el primer push también 1 SSTORE para el length. Total: ~22 100–44 200 gas por push.
- `delete stored.labAddresses`: 1 SSTORE zero para length, refund 4 800 por elemento zerado. Con 2 labs previos: ~2 × 4 800 = 9 600 gas de refund neto, pero aún cuesta ~5 000 gas neto.
- Con N labs en una confirmarCalidad, el costo de escritura de arrays es O(N) SSTOREs fríos.

---

## Patrones costosos identificados

### 1. Doble llamada a `identityRegistry.canMint()` en `comprar()`

**Código:** línea 210 (`comprar()`) + línea 533 (`_update()` interno).

```solidity
// línea 210 — llamada explícita en comprar()
if (!identityRegistry.canMint(comprador)) revert NotKYCVerified();
// ...
// línea 228 — _mint() llama _update() que también llama canMint
_mint(comprador, loteId, cantidadTokens, "");
// línea 533 — dentro de _update()
if (isMint) {
    if (!identityRegistry.canMint(to)) revert NotKYCVerified();
}
```

El check en `_update()` es correcto como defensa en profundidad (protege burns y transfers también), pero en el flujo de `comprar()` se ejecuta dos veces. Costo duplicado: ~5 000–10 000 gas por transacción.

**Solución:** La segunda llamada en `_update()` es la que debe mantenerse (es el guardián universal). La primera llamada explícita en `comprar()` (línea 210) es redundante y puede eliminarse, confiando en que `_update()` la rechazará con `NotKYCVerified`. Ahorro: ~5 000–10 000 gas por compra. Requiere análisis cuidadoso: si se elimina el early-check, el error ocurre más tarde en el stack (dentro de `_mint → _update`), lo cual es igual de correcto pero el gas gastado hasta ese punto es mayor si hay otros checks costosos antes.

**Alternativa preferible:** mantener el check explícito en `comprar()` como early-revert barato, y en `_update()` hacer la llamada solo para mints que NO vienen de `comprar()`. Dado que `_update()` es override genérico, la duplicación es un tradeoff intencional de seguridad, pero debería documentarse explícitamente.

### 2. Cache de `_lotes[loteId]` no usada en funciones con múltiples lecturas

**Código:** funciones como `comprar()` y `confirmarCalidad()` hacen `LoteMiel storage lote = _lotes[loteId]` lo cual es correcto. Sin embargo, en `reembolsarLoteFallido()` se accede a `lote.reservaTecnicaUSDC` y `lote.productorSRL` múltiples veces.

**Patrón actual en `reembolsarLoteFallido`:**
```solidity
LoteMiel storage lote = _lotes[loteId]; // línea 385
// ...
uint256 totalRecaudado = lote.reservaTecnicaUSDC; // línea 397 — SLOAD warm
// dentro del loop:
uint256 reembolsoUSDC = (totalRecaudado * balance) / totalSupplyLote; // OK, usa variable local
usdc.safeTransfer(buyer, reembolsoUSDC); // OK
```

En este caso `totalRecaudado` ya se cachea como variable local. Sin embargo, `totalSupplyLote` se calcula fuera del loop (línea 391) — esto ya es correcto.

**Pero hay un SLOAD problemático en el loop:** `balanceOf(buyer, loteId)` llama a ERC1155 que internamente hace un SLOAD por mapping. Con N=100 compradores, son 100 SLOADs de mapping fríos = 100 × 2 100 = 210 000 gas solo en balances. Esto es inevitable dado el modelo ERC-1155, pero subraya por qué el batch debe limitarse.

### 3. `motivoFallo string` vs `bytes32`

**Código:** `LoteMiel.motivoFallo` es `string` (IAssetVault.sol línea 63). `marcarFallido()` escribe una cadena arbitraria.

`string` en Solidity usa almacenamiento dinámico. Si el motivo tiene ≤ 31 bytes: se almacena inline en el slot (eficiente). Si tiene > 31 bytes: ocupa 1 slot para el length + N slots adicionales en storage extendido.

Si el motivo típico es un código corto (< 31 bytes), `string` es razonablemente eficiente. Si se espera texto libre largo, el costo puede dispararse.

**Recomendación:** cambiar a `bytes32 motivoFalloCode` (un código de falla) y emitir el texto completo en el evento `LoteFallido`. El evento ya tiene `string motivo` que se loggea off-chain. El storage de texto largo en blockchain es caro e innecesario si los datos están en el evento.

Ahorro estimado si motivo > 31 bytes: ~22 100–44 200 gas por slot adicional evitado.

### 4. Loop sin bound en `reembolsarLoteFallido()`

**Código:** líneas 404–421. El bucle itera sobre `compradores` sin límite de tamaño.

```solidity
for (uint256 i = 0; i < compradores.length; i++) {
    // _burn + usdc.safeTransfer por cada buyer
}
```

Cada iteración consume ~55 000–65 000 gas. Con 100 compradores = ~5.5M gas. Con 500 compradores en un escenario pessimista = ~27.5M gas (cercano al block limit de muchas L2s).

**Recomendación:** agregar un parámetro `uint256 batchSize` o un hard cap interno (ej: `require(compradores.length <= 100)`). Alternativamente, implementar el patrón pull-over-push: en lugar de que el oracle empuje los reembolsos, los compradores los claman ellos mismos (`claimRefund(loteId)`).

### 5. Re-hash de attestation en cada iteración del loop de labs

**Código:** `_computeAttestationHash()` se llama una vez fuera del loop (línea 290) — esto ya está bien. El hash se cachea en `attestationHash`. No hay problema aquí.

### 6. `delete + push` en `confirmarCalidad()` arrays dinámicos

**Código:** líneas 320–327.

```solidity
delete stored.labAddresses;    // refund parcial
delete stored.fullReportHashes;
for (uint256 i = 0; i < attestation.labAddresses.length; i++) {
    stored.labAddresses.push(attestation.labAddresses[i]);
}
```

El `delete` de un array dinámico en storage pone a cero la longitud (1 SSTORE = 5 000 gas warm, refund por elementos si ya había datos). El push posterior escribe cada elemento en nuevo slot frío (22 100 gas). Esta es la única forma correcta de actualizar arrays dinámicos en storage — no hay alternativa más barata si se necesita reemplazar el array.

**Observación:** si `confirmarCalidad()` se llama solo una vez por lote (el estado pasa de COSECHADO → QUALITY_ATTESTED y no puede volver), los `delete` previos siempre operan sobre arrays vacíos la primera vez. El `delete` inicial es defensivo pero redundante en ese caso. Con arrays vacíos, `delete` no hace nada costoso. El costo real está en los `push`.

### 7. `confirmarAlmacenamiento()` carece de `nonReentrant`

No es un patrón costoso de gas, pero es un riesgo: la función hace 1 SSTORE y emite un evento sin mutex. Si `almacenAutorizado` fuera un contrato malicioso... dado que la función no llama ningún contrato externo, no hay vector de reentrancy aquí. La ausencia de `nonReentrant` es correcta y ahorra ~100 gas de lock/unlock.

---

## Costo de deployment

### Estimación de bytecode size

AssetVault hereda de: ERC1155, ERC1155Supply, ERC1155Pausable, AccessControl, ReentrancyGuard. Estas bases suman significativo bytecode.

Estimación conservadora con optimizer runs=200:

| Componente | Bytecode aprox. |
|---|---|
| ERC1155 base (OZ v5) | ~6 000 bytes |
| ERC1155Supply extension | ~1 200 bytes |
| ERC1155Pausable extension | ~800 bytes |
| AccessControl | ~2 500 bytes |
| ReentrancyGuard | ~300 bytes |
| AssetVault logic propio | ~6 000–8 000 bytes |
| Libraries inlined (ComplianceConstants, QualityRules, DocumentHashes — todas `internal`) | ~500 bytes |
| **Total estimado** | **~17 000 – 19 000 bytes** |

El límite del EIP-170 es 24 576 bytes. El contrato tiene margen (~5 500–7 500 bytes). Sin embargo, si se agregan más funciones o structs en futuras iteraciones, puede acercarse al límite.

**Recomendación:** correr `forge build --sizes` para obtener la medición exacta.

### Gas de deployment

| Red | Gas estimado de deployment | Costo a precio típico |
|---|---|---|
| Plume mainnet (L2) | ~3 000 000 – 4 000 000 gas | $0.003–$0.04 (muy barato en L2) |
| Polygon PoS mainnet | ~3 000 000 – 4 000 000 gas | $0.90–$12.00 (a 30–100 gwei, MATIC precio variable) |

El gas de deployment se calcula como: `intrinsic (21 000) + calldata (4 gas/zero byte, 16 gas/nonzero) + execution`. Para ~18 000 bytes de bytecode con ~60% bytes no-zero: `18000 × 0.6 × 16 + 18000 × 0.4 × 4 ≈ 172 800 + 28 800 = 201 600` gas solo por calldata. Más `CREATE` opcode y ejecución del constructor: total ~3–4M gas.

### Ahorro potencial de optimizaciones

Si se implementan las principales recomendaciones (motivoFallo → bytes32, eliminación de check KYC duplicado, struct packing refinado), el ahorro en bytecode sería modesto (~200–400 bytes). El ahorro principal es en gas por llamada, no en deployment.

---

## Recomendaciones priorizadas

| # | Optimización | Función afectada | Ahorro estimado | Esfuerzo | Riesgo |
|---|---|---|---|---|---|
| 1 | Limitar batch en `reembolsarLoteFallido` (hard cap 100 o patrón pull) | `reembolsarLoteFallido` | Previene DoS/OOG | Bajo | Bajo (defensivo) |
| 2 | Eliminar check redundante `identityRegistry.canMint()` en línea 210 de `comprar()` — o documentar explícitamente el doble check | `comprar()` | ~5 000–10 000 gas/tx | Bajo | Bajo |
| 3 | Cambiar `motivoFallo string` → `bytes32 motivoFalloCode` en el struct; emitir texto en evento | `marcarFallido()`, storage | ~22 000–44 000 gas por lote fallido | Medio (breaking change en struct) | Medio — requiere ADR |
| 4 | Cache `lote.productorSRL` a `address memory` local en `liberarReservaTecnica()` — evita SLOAD warm extra al emitir el event | `liberarReservaTecnica()` | ~100 gas/tx | Mínimo | Ninguno |
| 5 | Agregar `view` check en `burnForRedemption()`: verificar `redemptionManager != address(0)` antes del `msg.sender` check (orden actual es incorrecto — si `redemptionManager == address(0)`, el primer check nunca revierte con `RedemptionManagerNotSet`) | `burnForRedemption()` | Corrección de bug lógico | Mínimo | Medio (correctness fix) |
| 6 | En `crearLote()`, reordenar checks para ejecutar los más baratos primero (actualmente `_lotes[loteId].productorSRL != address(0)` es el primer check — 1 SLOAD cold — podría ir después de validaciones pure) | `crearLote()` | ~2 000 gas en revert paths | Mínimo | Ninguno |
| 7 | Usar `via_ir = true` en foundry.toml para activar Yul IR optimizer — puede reducir deployment 5–15% y llamadas 2–8% | Global | Variable | Bajo (config only) | Bajo — requiere re-audit Slither |
| 8 | En `confirmarCalidad()`, si el contrato garantiza 1 sola attestation por lote (estado COSECHADO → QUALITY_ATTESTED es one-way), los `delete stored.labAddresses` y `delete stored.fullReportHashes` son operaciones defensivas en slots vacíos. Documentar esto para evitar confusión, no eliminarlos. | `confirmarCalidad()` | ~0 gas real (ya vacíos) | Mínimo (doc only) | Ninguno |
| 9 | En el evento `CalidadConfirmada`, el parámetro `address[] labs` es costoso de loggear con N labs. Considerar loggear solo el hash de la lista. | `confirmarCalidad()` | ~1 000 gas × N labs | Medio | Bajo |
| 10 | Consolidar los 6 hashes de documentos en `LoteMiel` en un Merkle root único `bytes32 documentosRoot` usando `DocumentHashes.rootOf()`. Reduce 5 SSTOREs a 1. Trade-off: pierdes lookup individual on-chain (queries de explorador). | Múltiples funciones | ~110 000 gas en confirmarCosecha (5 SSTOREs → 1) | Alto (cambio de API, ADR requerido) | Alto |

---

## Comparación con benchmarks de industria

| Operación | Benchmark industria | AssetVault | Delta |
|---|---|---|---|
| ERC-1155 mint básico | ~50 000 gas | ~35 000–50 000 gas (dentro de `comprar`) | Comparable |
| USDC safeTransfer | ~45 000–55 000 gas | ~25 000–35 000 gas (warm path) | Mejor (warm slots) |
| SSTORE frío (nuevo slot) | 22 100 gas | 22 100 gas | Igual (EVM estándar) |
| SSTORE cálido (slot dirty) | 5 000 gas (EIP-2929) | 5 000 gas | Igual |
| SLOAD frío | 2 100 gas (EIP-2929) | 2 100 gas | Igual |
| ECDSA ecrecover | ~3 000 gas | ~3 000 gas (dentro de `verifyAttestationSignature`) | Igual |
| keccak256 (32 bytes) | ~30 + 6×1 word = 36 gas | ~36 gas | Igual |
| external call overhead | ~2 600 gas base | ~2 600 gas | Igual |
| Full KYC + mint + USDC transfer (comparable a DeFi buy) | ~100 000–150 000 gas | ~130 000–160 000 gas cold | +15–20% por compliance checks |
| Multi-sig oracle write (5 SSTOREs) | ~110 000 gas | ~165 000–175 000 gas en confirmarCosecha | +50–60% por hashes adicionales de documentos legales |

El overhead respecto a contratos DeFi puros es esperado y justificado: AssetVault tiene compliance mandatory (KYC check en cada mint), documentación legal on-chain (7 hashes de documentos), y QualityAttestation compleja. El costo extra es el precio de la trazabilidad legal.

El mayor desvío positivo es `confirmarCosecha()` vs un oracle write simple: 5 hashes de documentos = 5 SSTOREs extra = ~110 000 gas adicionales. Si la trazabilidad legal lo requiere, el costo es aceptable. La recomendación #10 (Merkle root consolidado) puede reducir esto significativamente si se acepta la pérdida de lookup individual.

---

## Notas finales

- **Bug lógico crítico en `burnForRedemption()`:** el check `if (redemptionManager == address(0)) revert RedemptionManagerNotSet()` está en la línea 452, DESPUÉS del check `if (msg.sender != redemptionManager)` en línea 451. Si `redemptionManager` es address(0) y `msg.sender` es también address(0) (imposible con EOAs, pero teóricamente con contracts), el segundo check pasaría. Aunque improbable, el orden correcto es verificar que `redemptionManager != address(0)` primero. Esto es un correctness fix, no solo gas.

- **`via_ir = false` en foundry.toml:** el optimizer IR pipeline desactivado es conservador pero correcto para compatibilidad. Activarlo podría generar gas savings del 5–15% en funciones complejas como `confirmarCalidad()`, pero requiere re-ejecutar Slither y revisar el output compilado.

- **`optimizer_runs = 200`:** valor estándar que balancea deployment vs call cost. Si el contrato se llama frecuentemente (N compras por lote) podría valer runs=1000+. Para oráculos admin (pocos calls), 200 es razonable.
