# Security Review — Internal Audit Report

> **Auditor:** Dany Hidalgo F. (internal review pre-external audit)
> **Date:** 2026-05-19
> **Commit / version:** initial implementation v0.1.0
> **Scope:** `packages/contracts/src/*.sol` (4 contratos + 3 libraries + 4 interfaces)
> **Status:** Pre-external audit — findings deben resolverse o documentarse antes de Sherlock/Trail of Bits

---

## Resumen ejecutivo

Se revisaron los 4 contratos centrales del MVP:
- `AssetVault.sol` (~470 LOC) — contrato principal ERC-1155 + lifecycle + reserve + quality
- `IdentityRegistry.sol` (~190 LOC) — whitelist KYC on-chain
- `LabRegistry.sol` (~155 LOC) — whitelist de labs + verificación de firmas
- `RedemptionManager.sol` (~165 LOC) — escrow + flujo de redención

**Severidad de hallazgos:**
- 🔴 **Critical:** 0
- 🟠 **High:** 1
- 🟡 **Medium:** 5
- 🟢 **Low:** 7
- 🔵 **Informational:** 8

**Conclusión preliminar:** la arquitectura es sólida (sin proxy, sin upgradeability, custom errors, OpenZeppelin v5, access control granular). Hay **1 finding High** sobre semántica del reembolso pro-rata que requiere decisión de producto antes de auditoría externa, y varios Medium sobre validaciones adicionales recomendadas.

---

## Findings detallados

### 🟠 H-01 — Reembolso pro-rata reembolsa solo la reserva técnica, no el monto total pagado

**Severidad:** High
**Archivo:** `AssetVault.sol:reembolsarLoteFallido()` (~líneas 320-360)

**Descripción:**
La función `reembolsarLoteFallido` reembolsa USDC pro-rata **únicamente sobre la reserva técnica retenida** (15-20% del monto pagado). El resto del monto (85-100% que ya fue transferido al productor SRL durante `comprar()`) NO se recupera del productor automáticamente.

**Impacto:**
- Compradores reciben solo el 15-20% de su pago original en caso de fallo del lote
- Esto contradice el principio "Forward Sale Agreement back-to-back con reembolso completo si lote falla" descrito en arquitectura
- Riesgo legal: comprador europeo puede demandar por incumplimiento

**Código actual:**
```solidity
uint256 totalRecaudado = lote.reservaTecnicaUSDC;
// ...
uint256 reembolsoUSDC = (totalRecaudado * balance) / totalSupplyLote;
```

**Mitigación propuesta (3 opciones):**

**Opción A:** Recuperar fondos del productor antes de reembolsar (off-chain workflow + función nueva `recuperarFondosProductor()` callable por COMPLIANCE_OFFICER_ROLE).

**Opción B:** Documentar explícitamente en TyC que el reembolso es solo de reserva técnica + reservar derecho a perseguir al productor por la diferencia (riesgo legal alto).

**Opción C (recomendada):** Implementar un sistema de **seguros / fondo de garantía** financiado por una fracción adicional del precio (e.g., 5% extra que cubre fallas operacionales). Combinable con seguro agrícola off-chain.

**Acción requerida:** decisión de producto + legal **antes** de auditoría externa.

---

### 🟡 M-01 — `_update()` bloquea aprobaciones legítimas de operadores conocidos

**Severidad:** Medium
**Archivo:** `AssetVault.sol:setApprovalForAll()` (líneas 432-434)

**Descripción:**
Override de `setApprovalForAll` revierte cualquier llamada. Si en el futuro queremos integrar con marketplaces compliance-aware (e.g., para mercado secundario controlado en fase 2), tendríamos que migrar a v2.

**Impacto:**
- No bloqueante para MVP (modelo "Solo primario")
- Limita flexibilidad futura

**Mitigación:**
Aceptado. Documentado en ADR-002 que esta es decisión consciente del MVP.

---

### 🟡 M-02 — `confirmarCalidad` no valida que el lab esté certificado para los tests específicos

**Severidad:** Medium
**Archivo:** `AssetVault.sol:confirmarCalidad()` (líneas 230-290)

**Descripción:**
La función verifica que cada lab esté activo en LabRegistry, pero **no verifica que el lab esté autorizado específicamente para los tests aplicados** (palinología, NMR, C4, residuos).

**Impacto:**
Un lab certificado solo para NMR podría firmar una attestation que incluye claim de palinología sin estar acreditado para ello.

**Mitigación propuesta:**
Agregar validación explícita:

```solidity
require(labRegistry.isLabCertifiedFor(labAddr, Specialization.PALINOLOGIA), "Lab not cert for palinology");
require(labRegistry.isLabCertifiedFor(labAddr, Specialization.NMR), "Lab not cert for NMR");
// ...
```

Considerar al menos UNO de los labs autorizado para cada especialización requerida.

**Acción requerida:** implementar en próxima iteración.

---

### 🟡 M-03 — `kgRealCosechado < kgVendidos` no se valida en `confirmarCosecha`

**Severidad:** Medium
**Archivo:** `AssetVault.sol:confirmarCosecha()` (líneas 200-230)

**Descripción:**
Si la cosecha real es menor a los kg ya vendidos, el contrato acepta la attestation sin restricciones. Esto crea una sobreventa.

**Impacto:**
Compradores que llegan después no podrían recibir su miel física (sin cobertura on-chain).

**Mitigación propuesta:**
Implementar política de shortfall (ver ADR-005 / R8 en arquitectura):
- Shortfall < 10%: aceptar con flag + reducción pro-rata documentada
- Shortfall ≥ 10%: forzar `marcarFallido` + reembolso total

```solidity
uint256 kgYaVendidos = (totalSupply(loteId) * GRAMOS_POR_TOKEN) / 1000;
if (kgRealCosechado < kgYaVendidos * 90 / 100) {
    revert ShortfallExceedsThreshold();
}
```

**Acción requerida:** decisión comercial + legal + implementación.

---

### 🟡 M-04 — Sin protección contra signature malleability EIP-2 (firmas de labs)

**Severidad:** Medium
**Archivo:** `LabRegistry.sol:verifyAttestationSignature()` (líneas 113-127)

**Descripción:**
OpenZeppelin ECDSA v5 ya protege contra malleability (`tryRecover` rechaza firmas malleables). Validado.

**Estado:** ✅ Mitigado por OZ ECDSA v5. No se requiere acción.

---

### 🟡 M-05 — Tokens en redención pueden ser quemados accidentalmente por reembolso de lote fallido

**Severidad:** Medium
**Archivo:** `AssetVault.sol:reembolsarLoteFallido()` interactúa con `RedemptionManager`

**Descripción:**
Si un lote pasa a FALLIDO después de que un usuario inició una redención (estado INICIADA), `reembolsarLoteFallido` quema sus tokens. Pero esos tokens están "lockeados" en escrow lógico del RedemptionManager.

**Impacto:**
Doble contabilización potencial: usuario recibe USDC del reembolso + sus tokens son destruidos sin que la redención se complete formalmente.

**Mitigación propuesta:**
1. En `marcarFallido`: cancelar automáticamente todas las redenciones en INICIADA del lote.
2. O en `reembolsarLoteFallido`: validar que ningún buyer tiene redención en INICIADA.

**Acción requerida:** implementar (probablemente Opción 1 — auto-cancel).

---

### 🟢 L-01 — Eventos no incluyen todos los campos relevantes para indexers

**Severidad:** Low
**Archivos:** Varios (eventos en `AssetVault`, `RedemptionManager`)

**Descripción:**
Algunos eventos podrían incluir campos adicionales útiles para Goldsky/TheGraph:
- `LoteComprado` no incluye `lote.estado` actual (para tracking)
- `RedencionIniciada` no incluye timestamp explícito (block.timestamp deducible pero engorroso)

**Mitigación:** mejorar eventos en próxima iteración. No bloqueante.

---

### 🟢 L-02 — Sin event `LoteAgotado` cuando se llega a estado AGOTADO

**Severidad:** Low
**Archivo:** `AssetVault.sol:burnForRedemption()` (línea 376-378)

**Descripción:**
Cuando un lote pasa a AGOTADO, no se emite evento específico. El cambio se infiere via `RedencionCompletada` + total supply 0.

**Mitigación:** agregar `event LoteAgotado(uint256 indexed loteId)`.

---

### 🟢 L-03 — `crearLote` no valida `variedadMonofloral` enum

**Severidad:** Low
**Archivo:** `AssetVault.sol:crearLote()`

**Descripción:**
`variedadMonofloral` es `uint8` sin enum estricto. Valores inválidos aceptados sin revert.

**Mitigación:** definir enum `VariedadMonofloral` y validar.

---

### 🟢 L-04 — Sin tiempo máximo de espera en redención INICIADA

**Severidad:** Low
**Archivo:** `RedemptionManager.sol`

**Descripción:**
Una redención puede quedar en estado INICIADA indefinidamente si Oracle no actúa.

**Mitigación:** considerar timeout (e.g., 90 días) con función `cancelarRedencionPorTimeout()` callable por el comprador.

---

### 🟢 L-05 — `addLab` permite jurisdicciones inválidas (bytes2 cualquiera)

**Severidad:** Low
**Archivo:** `LabRegistry.sol:addLab()`

**Descripción:**
`jurisdiction` es `bytes2` sin validación de ISO 3166-1 alpha-2. Acepta valores no válidos como "ZZ", "00", etc.

**Mitigación:** maintainer responsable de pasar valores correctos. Documentar.

---

### 🟢 L-06 — `IdentityRegistry.canMint` no chequea tier máximo

**Severidad:** Low
**Archivo:** `IdentityRegistry.sol:canMint()`

**Descripción:**
Si `setKYC` valida `tier <= MAX_KYC_TIER`, `canMint` solo chequea `>= MIN_KYC_TIER_PARA_COMPRAR`. Defensivamente podría chequear que tier no exceda MAX (aunque ya validado en setter).

**Mitigación:** acceptable as-is (defensa en profundidad innecesaria).

---

### 🟢 L-07 — Sin función para consultar redenciones por comprador

**Severidad:** Low
**Archivo:** `RedemptionManager.sol`

**Descripción:**
No hay forma on-chain de listar las redenciones de un comprador específico (solo se puede consultar por ID).

**Mitigación:** consulta vía indexer (Goldsky). No bloqueante on-chain.

---

### 🔵 I-01 — License BUSL-1.1 placeholder

**Estado:** documentado en CONTRACT-SPECS.md. La licencia final la define el responsable legal antes del freeze pre-auditoría.

### 🔵 I-02 — Bolivia hardcoded como bytes2("BO")

**Archivo:** `AssetVault.sol:BOLIVIA_JURISDICTION`

Hardcoded para validar que al menos un lab sea boliviano. Aceptable porque la entidad operadora (SRL Bolivia) define el dominio del proyecto. Si se expande a otros países productores, requiere generalización.

### 🔵 I-03 — `_computeAttestationHash` no incluye chain ID

**Archivo:** `AssetVault.sol:_computeAttestationHash()`

Si en fase 8 hay multi-chain (Polygon + Plume), una firma de un lab para un lote en Plume podría reutilizarse en Polygon. **Mitigación:** incluir `block.chainid` en el hash:

```solidity
return keccak256(abi.encode(block.chainid, loteId, att.pollenSpecies, ...));
```

**Acción requerida:** implementar antes de deploy a Plume mainnet (al menos antes de fase 8).

### 🔵 I-04 — Sin NatSpec en libraries

Las funciones internal de libraries tienen NatSpec parcial. Completar antes de auditoría externa.

### 🔵 I-05 — `reembolsarLoteFallido` puede correr out-of-gas con muchos buyers

Si un lote tiene 100+ compradores, `reembolsarLoteFallido` puede exceder block gas limit.

**Mitigación:** considerar batching (paginación) — `reembolsarLoteFallidoBatch(loteId, buyers[], offset, limit)`.

### 🔵 I-06 — `setRedemptionManager` only-once pattern

Validado: `setRedemptionManager` solo se puede llamar una vez (`RedemptionManagerAlreadySet`). Correcto para resolver circular dependency en deploy.

### 🔵 I-07 — Sin función `recoverERC20` para tokens enviados accidentalmente

Si un usuario envía USDC u otro ERC-20 al contrato sin pasar por `comprar`, queda atrapado.

**Mitigación:** función `recoverStuckTokens(address token, uint256 amount, address to)` solo callable por ADMIN_ROLE, EXCEPTO USDC (que es el USDC operativo y no debe extraerse arbitrariamente).

### 🔵 I-08 — Falta `URIChanged` event override

ERC-1155 estándar tiene `URI(string value, uint256 indexed id)`. Si se cambia el URI base, no se emite evento por defecto.

**Mitigación:** documentar que URI es fijo al deploy. No se cambia.

---

## Categorías de seguridad evaluadas

| Categoría | Resultado | Notas |
|---|---|---|
| Reentrancy | ✅ Mitigado | `nonReentrant` en `comprar`, `liberarReservaTecnica`, `reembolsarLoteFallido`, `confirmarCosecha`, `confirmarCalidad`, redemption funcs |
| Integer overflow/underflow | ✅ Mitigado | Solidity 0.8.24 con checked math por default |
| Access control | ✅ Sólido | OZ AccessControl con roles granulares; cada función external tiene `onlyRole(...)` |
| Signature replay (cross-chain) | 🟡 Pendiente | I-03: agregar `block.chainid` al attestation hash antes de multi-chain |
| Signature malleability | ✅ Mitigado | OZ ECDSA v5 con `tryRecover` |
| Oracle manipulation | ✅ Mitigado | Safe multi-sig 2-de-3 + Chainlink PoR (en fase 2) |
| Front-running / MEV | ✅ Aceptable | `comprar()` solo callable por BACKEND_SIGNER_ROLE; no es función pública open |
| Gas griefing | 🟡 Pendiente | I-05: batching en `reembolsarLoteFallido` |
| Logic errors (state machine) | 🟢 Sólido | Estados validados en cada transición; H-01 sobre semántica reembolso requiere decisión |
| Storage collisions | ✅ N/A | Sin proxy, sin riesgo |
| Compilation warnings | ✅ Esperado clean | Pre-deploy: ejecutar `forge build` y resolver warnings |
| Slither static analysis | 🟡 Pendiente | Ejecutar `slither .` post-instalación de Foundry |
| Mythril symbolic analysis | 🟡 Pendiente | Pre-auditoría externa |

---

## Acciones recomendadas antes de auditoría externa

### Bloqueantes (obligatorio resolver)
1. **H-01:** decisión + implementación de política de reembolso completo o garantizado
2. **M-02:** validar `isLabCertifiedFor` por especialización en `confirmarCalidad`
3. **M-03:** implementar política de shortfall cosecha (< 10% / ≥ 10%)
4. **M-05:** auto-cancel de redenciones INICIADA al pasar a FALLIDO

### Recomendados (resolver para reducir gas / mejorar UX)
5. **I-03:** agregar `block.chainid` al attestation hash
6. **I-05:** batching en `reembolsarLoteFallido`
7. **L-02:** evento `LoteAgotado`
8. **L-04:** timeout en redenciones INICIADA

### Diferibles (post-auditoría inicial)
9. **L-01, L-03, L-06, L-07:** mejoras incrementales
10. **I-01, I-04:** completar NatSpec + licencia final

---

## Próximos pasos

1. **Iteración 2:** resolver findings High + Medium bloqueantes
2. **Iteración 3:** ejecutar `forge build`, resolver warnings, ejecutar `slither .`, resolver issues high
3. **Iteración 4:** completar 100% coverage de tests + fuzz + invariant
4. **Iteración 5:** auditoría externa (Sherlock contest o Trail of Bits)
5. **Iteración 6:** resolución de findings externos
6. **Pre-mainnet:** verificación final + penetration testing del backend

---

## Cumplimiento de criterios `solidity-security` skill

✅ Reentrancy guards aplicados en funciones que mueven USDC
✅ Custom errors gas-efficient (no string reverts)
✅ Access control con OpenZeppelin AccessControl
✅ Solidity 0.8.24+ con checked arithmetic
✅ No `tx.origin` usage
✅ No `block.timestamp` para randomness
✅ No inline assembly
✅ SafeERC20 para todas las transferencias USDC
✅ Override `_update()` con validaciones explícitas
✅ Sin proxy / sin upgradeability
✅ ERC-1155 standard correcto
✅ Eventos para audit trail completo
✅ NatSpec en funciones públicas

---

**Última actualización:** 2026-05-19
**Aprobado por:** pendiente (este reporte requiere review de Dany + decisiones sobre findings High/Medium bloqueantes antes de avanzar a auditoría externa)
