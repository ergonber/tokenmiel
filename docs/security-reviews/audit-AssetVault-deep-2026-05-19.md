# Deep Security Audit — AssetVault.sol

**Auditor:** Subagente A (opus)
**Date:** 2026-05-19
**Scope:** `packages/contracts/src/AssetVault.sol` post-refactor v0.2.0 (`InitParams` struct constructor)
**Lines audited:** 572 (incl. blank lines + NatSpec); ~310 effective LOC
**Compiler:** solc 0.8.24 (paris EVM, optimizer 200 runs)
**Dependencies reviewed:** `IIdentityRegistry`, `ILabRegistry`, `IRedemptionManager`, `ComplianceConstants`, `QualityRules`, `DocumentHashes`

---

## Resumen ejecutivo

Se realizó una auditoría profunda de `AssetVault.sol` cubriendo las 12 categorías solicitadas por el orquestador: reentrancy, access control, signature replay, transiciones de estado, edge cases numéricos, override `_update`, reserva técnica, reembolso pro-rata, QualityAttestation, `burnForRedemption`, eventos/audit trail, y ratio costo/poder. La auditoría comparó cada finding contra el `audit-report-2026-05-19.md` previo para distinguir hallazgos persistentes de nuevos.

**Veredicto general:** la arquitectura es sólida y el refactor a `InitParams` no introdujo regresiones. La pareja `Checks-Effects-Interactions` + `nonReentrant` está aplicada correctamente. La protección contra P2P y la gating por KYC funcionan. Sin embargo, esta auditoría profunda **identifica 9 findings nuevos** que el audit previo no detectó, dos de ellos de severidad alta (overmint por precisión + signature replay en re-attestation tras transición), y confirma todos los findings previos vigentes (H-01, M-02, M-03, M-05, I-03, I-05).

**Severidad de hallazgos (esta auditoría):**

- Critical: 0
- High: 3 (1 confirmado previo + 2 nuevos)
- Medium: 8 (3 confirmados previos + 5 nuevos)
- Low: 6 (3 confirmados previos + 3 nuevos)
- Informational: 9 (5 confirmados previos + 4 nuevos)

**Acción crítica antes de mainnet:** H-02 (overmint por precisión decimal) y H-03 (replay de attestation tras re-cosecha) son explotables y requieren fix antes del próximo deploy.

---

## Findings (clasificados por severidad)

### 🔴 Critical

Sin findings de severidad crítica.

---

### 🟠 High

#### H-01 (REAFIRMADO del audit previo) — `reembolsarLoteFallido` solo reembolsa la reserva técnica (15-20%)

**Severidad:** High
**Archivo:** `AssetVault.sol:380-423` (`reembolsarLoteFallido`)
**Estado:** vigente, sin remediar.

**Descripción:**
Como ya documentó el audit previo, el reembolso pro-rata solo distribuye `lote.reservaTecnicaUSDC`. El 80-85% del pago original ya fue transferido al productor SRL en `comprar` (línea 231: `usdc.safeTransfer(lote.productorSRL, montoNeto)`). Si el lote pasa a FALLIDO, el comprador europeo recibe a lo sumo 20% de su capital.

**Confirmación de la PoC del audit previo:**
```
1. Productor crea lote: kgEsperados = 100, precio = 100 USDC/token, reservaBps = 1500 (15%)
2. Comprador A compra 200 tokens = 100 kg = 20000 USDC
   - reservaRetenida = 20000 * 1500 / 10000 = 3000 USDC (queda en vault)
   - montoNeto = 17000 USDC → transferido al productor (línea 231)
3. Cosecha falla. ORACLE marca FALLIDO.
4. reembolsarLoteFallido([A]):
   - totalRecaudado = 3000 (solo reserva)
   - reembolsoUSDC = 3000 * 200 / 200 = 3000 USDC
   - Comprador A pierde 17000 USDC (85% de su capital).
```

**Mitigación propuesta:**
La decisión recomendada (`Opción C` del audit previo) es introducir un **fondo de garantía** prefondeado en USDC controlado por `TREASURY_SRL_ROLE` que cubra el delta hasta el 100%. Alternativamente, retener el 100% del USDC en el contrato hasta `confirmarCosecha` y solo entonces transferir el neto al productor (lo cual cambia la arquitectura de pagos pero garantiza el reembolso). **Requiere decisión de producto + legal antes de auditoría externa.**

---

#### H-02 (NUEVO) — Overmint por división entera temprana en `comprar`

**Severidad:** High
**Archivo:** `AssetVault.sol:213-215`

**Descripción:**
El check de capacidad disponible se computa en kg con división entera antes de la suma:

```solidity
uint256 kgYaVendidos = totalSupply(loteId) * ComplianceConstants.GRAMOS_POR_TOKEN / 1000; // /1000 trunca
uint256 kgSolicitados = cantidadTokens * ComplianceConstants.GRAMOS_POR_TOKEN / 1000;     // /1000 trunca
if (kgYaVendidos + kgSolicitados > lote.kgEsperados) revert KgSolicitadosExcedenSupply();
```

Si `cantidadTokens` es **impar**, la división por 1000 trunca: `cantidadTokens=1` → `kgSolicitados = 1*500/1000 = 0`. Idénticamente para `kgYaVendidos`. El check es **incorrecto para mints menores a 2 tokens** y permite overshoot acumulado.

**PoC:**
```
kgEsperados = 100 kg, GRAMOS_POR_TOKEN = 500.
Capacidad máxima teórica = 200 tokens.

Estado inicial: totalSupply = 200 → kgYaVendidos = 200*500/1000 = 100.
comprar(loteId, 1, alice, 100, ...):
  - kgSolicitados = 1*500/1000 = 0
  - Check: 100 + 0 > 100 → false. PASA.
  - mint 1 token. totalSupply = 201.

Estado: totalSupply = 201 → kgYaVendidos = 201*500/1000 = 100 (trunca).
comprar(loteId, 1, alice, 100, ...):
  - kgSolicitados = 0
  - Check: 100 + 0 > 100 → false. PASA.
  - mint 1 token. totalSupply = 202.

Estado: totalSupply = 202 → kgYaVendidos = 202*500/1000 = 101.
comprar(loteId, 1, ...):
  - Check: 101 + 0 > 100 → true. REVIERTE.

Overshoot total: 2 tokens (1 kg) sobre kgEsperados=100 kg.
```

El attacker debe controlar `BACKEND_SIGNER_ROLE` para explotar, pero un bug operacional (e.g., dust mints, edge cases de UI redondeo) puede producir overshoot accidental. **Esto rompe la invariante "tokens minteados ≤ kg esperados / 0.5"** y crea sobreventa silenciosa.

**Mitigación propuesta (recomendada):** computar todo en gramos para evitar truncado, comparar contra `kgEsperados * 1000`:

```solidity
uint256 gramosYaVendidos = totalSupply(loteId) * ComplianceConstants.GRAMOS_POR_TOKEN;
uint256 gramosSolicitados = cantidadTokens * ComplianceConstants.GRAMOS_POR_TOKEN;
uint256 gramosEsperados = lote.kgEsperados * 1000;
if (gramosYaVendidos + gramosSolicitados > gramosEsperados) revert KgSolicitadosExcedenSupply();
```

Alternativamente, normalizar `kgEsperados` a múltiplos pares de tokens (validar en `crearLote` que `kgEsperados * 1000` sea múltiplo de `GRAMOS_POR_TOKEN`, lo que implica `kgEsperados * 2` ∈ ℤ).

**Acción requerida:** fix obligatorio antes de cualquier deploy. Agregar fuzz test que verifica `sum(totalSupply * 0.5) <= kgEsperados` post-mint.

---

#### H-03 (NUEVO) — Signature replay tras transición FALLIDO no reinicia attestation, pero permite re-uso de firmas viejas si el contrato se redeploya o si se introduce función `resetCalidad`

**Severidad:** High (latente)
**Archivo:** `AssetVault.sol:542-558` (`_computeAttestationHash`)

**Descripción:**
El hash de attestation se computa como:

```solidity
return keccak256(abi.encode(
    loteId,
    attestation.pollenSpecies,
    attestation.pollenPercentage,
    attestation.nmrPassed,
    attestation.c4Passed,
    attestation.residuesPassed,
    attestation.fullReportHashes
));
```

**Faltan tres componentes críticos** para anti-replay robusto:

1. **`block.chainid`** — ya documentado como I-03 en audit previo. Una firma válida para chain A puede replayarse en chain B si el contrato se deploya con la misma `address(this)` (Plume + Polygon en fase 8). Severidad esta auditoría: **promovida a High** porque la roadmap del proyecto ya planea multi-chain.

2. **`address(this)`** — si el contrato es redeployado (v2 tras bug crítico, según el comentario `@custom:security` línea 27: "Bug crítico → pause + migración v2"), las firmas viejas son replayables en el nuevo contrato. Cada lab firma una vez para AssetVault v1 → attacker copia esa firma a AssetVault v2 para un `loteId` distinto con los mismos campos. Aunque el campo `loteId` no colisione, la **ausencia de domain separator** rompe EIP-712 best practices.

3. **`testedAt`** — el struct `QualityAttestation` incluye `testedAt`, pero `_computeAttestationHash` **NO lo incluye en el hash**. Esto significa que dos attestations con timestamps distintos (e.g., re-test del mismo lote) producirían el mismo hash si los datos científicos coinciden, y la misma firma podría usarse.

**PoC compuesta — escenario peor caso (re-attestation):**
Aunque actualmente `confirmarCalidad` requiere estado `COSECHADO` y tras éxito pasa a `QUALITY_ATTESTED` (no se vuelve atrás), considerar dos escenarios:

(a) **Re-deploy v2** del contrato tras incident. Labs no quieren refirmar manualmente. Operator copia las firmas pasando el mismo `attestation` struct. Las firmas se aceptan en v2. Si los datos científicos eran fabricados en v1 (un lab comprometido), siguen siendo válidos en v2.

(b) **Cross-chain replay** una vez en Polygon (fase 6+): copy de firma de Plume a Polygon. Sin chainid → ataque viable.

(c) **Si en el futuro se agrega una función `resetCalidad(loteId)`** (e.g., para corregir errores), el lote vuelve a `COSECHADO` y la misma firma se acepta. Esto no es explotable HOY, pero es un footgun arquitectónico que el siguiente desarrollador podría disparar.

**Mitigación propuesta:** incluir domain separator EIP-712 con chainid y address(this):

```solidity
function _computeAttestationHash(uint256 loteId, QualityAttestation calldata attestation)
    internal view returns (bytes32)
{
    return keccak256(
        abi.encode(
            block.chainid,
            address(this),
            loteId,
            attestation.pollenSpecies,
            attestation.pollenPercentage,
            attestation.nmrPassed,
            attestation.c4Passed,
            attestation.residuesPassed,
            attestation.testedAt,
            attestation.fullReportHashes
        )
    );
}
```

Adicionalmente, considerar registrar `_attestationConsumed[hash] = true` (ya mencionado en CONTRACT-SPECS §4.7 y §4.13 punto 2 pero **no implementado en código actual**) para defense-in-depth incluso si el state machine cambia en el futuro.

**Acción requerida:** fix obligatorio antes de Plume mainnet. CONTRACT-SPECS Decisión D6 (sección 10) ya especifica este diseño con chainid + address(this) — la implementación está **desalineada con la spec**.

---

### 🟡 Medium

#### M-01 (REAFIRMADO previo) — `confirmarCalidad` no valida `isLabCertifiedFor` por especialización

**Severidad:** Medium
**Archivo:** `AssetVault.sol:292-308`
**Estado:** vigente.

**Descripción:**
La función verifica `labRegistry.getLab(labAddr).active`, pero **no** valida que cada lab tenga acreditación específica para los tests que firma. Un lab acreditado solo para `NMR` podría firmar una attestation que incluye un porcentaje de polen (`PALINOLOGIA`).

**Mitigación propuesta:**
```solidity
// Después de validar lab activo, validar que al menos uno de los labs firmantes
// está acreditado para cada Specialization que se está atestiguando.
bool anyPalinologia;
bool anyNMR;
bool anyC4;
bool anyResidues;

for (uint256 i = 0; i < attestation.labAddresses.length; i++) {
    if (labRegistry.isLabCertifiedFor(attestation.labAddresses[i], ILabRegistry.Specialization.PALINOLOGIA)) anyPalinologia = true;
    if (labRegistry.isLabCertifiedFor(attestation.labAddresses[i], ILabRegistry.Specialization.NMR)) anyNMR = true;
    if (labRegistry.isLabCertifiedFor(attestation.labAddresses[i], ILabRegistry.Specialization.C4_SUGAR)) anyC4 = true;
    if (labRegistry.isLabCertifiedFor(attestation.labAddresses[i], ILabRegistry.Specialization.PESTICIDES)) anyResidues = true;
}
if (!anyPalinologia || !anyNMR || !anyC4 || !anyResidues) revert LabNotCertifiedForTest();
```

---

#### M-02 (REAFIRMADO previo) — `confirmarCosecha` no valida `kgRealCosechado < kgVendidos`

**Severidad:** Medium
**Archivo:** `AssetVault.sol:239-271`
**Estado:** vigente.

**Descripción:** ver audit previo M-03. Sin política de shortfall, una cosecha menor a las ventas resulta en redenciones que no se pueden cumplir físicamente.

**Mitigación propuesta:** ya detallada en audit previo. Validar `kgRealCosechado >= kgYaVendidos * 90/100` (shortfall máximo 10%) en `confirmarCosecha`.

---

#### M-03 (REAFIRMADO previo) — Tokens en redención INICIADA pueden ser quemados por `reembolsarLoteFallido`

**Severidad:** Medium
**Archivo:** interacción `AssetVault.sol:reembolsarLoteFallido` + `RedemptionManager`
**Estado:** vigente.

Ver audit previo M-05. Sin auto-cancel de redenciones INICIADA al marcar FALLIDO, hay doble contabilización.

---

#### M-04 (NUEVO) — `reembolsarLoteFallido` no resta la reserva ya liberada antes de reembolsar

**Severidad:** Medium
**Archivo:** `AssetVault.sol:397-409`

**Descripción:**
La fórmula de reembolso es:
```solidity
uint256 totalRecaudado = lote.reservaTecnicaUSDC;
// ...
uint256 reembolsoUSDC = (totalRecaudado * balance) / totalSupplyLote;
```

**El cálculo usa `lote.reservaTecnicaUSDC` (total acumulado) pero NO descuenta `lote.reservaTecnicaLiberada`.** Es decir: si la reserva ya fue liberada al productor (via `liberarReservaTecnica`), el contrato no tiene ese USDC, pero la fórmula la cuenta como disponible. El transfer a buyers fallará por insufficient balance, o peor, el contrato podría tener USDC de otras fuentes y reembolsar mal.

**Escenario explotable:**
1. Lote alcanza QUALITY_ATTESTED. `liberarReservaTecnica` transfiere `reservaTecnicaUSDC = 3000` al productor. Ahora el contrato tiene 0 USDC para este lote.
2. Más tarde, alguien marca el lote como FALLIDO (transición desde QUALITY_ATTESTED es válida, ver punto sobre transiciones).
3. `reembolsarLoteFallido` calcula `totalRecaudado = 3000`. Intenta transfer 3000 USDC a un buyer. Si el contrato no tiene 3000 USDC, revierte por `SafeERC20`. Si tiene (porque otro lote tiene reserva no liberada), reembolsa con dinero ajeno → **rompe la separación contable entre lotes**.

**Mitigación propuesta:**
```solidity
uint256 totalRecaudado = lote.reservaTecnicaUSDC - lote.reservaTecnicaLiberada;
if (totalRecaudado == 0) {
    _reembolsado[loteId] = true;
    return;
}
```

Adicionalmente, considerar bloquear la transición a `FALLIDO` desde estados donde la reserva ya fue liberada, o exigir que el productor devuelva la reserva off-chain antes (workflow legal).

**Acción requerida:** fix antes de mainnet. Test que combina `liberarReservaTecnica` + `marcarFallido` + `reembolsarLoteFallido`.

---

#### M-05 (NUEVO) — `marcarFallido` permite transición desde QUALITY_ATTESTED y ALMACENADO sin protecciones

**Severidad:** Medium
**Archivo:** `AssetVault.sol:365-377`

**Descripción:**
La función solo bloquea transiciones desde `AGOTADO` y `FALLIDO`:
```solidity
if (lote.estado == LoteEstado.AGOTADO || lote.estado == LoteEstado.FALLIDO)
    revert LoteAlreadyFinalized();
```

Esto significa que un lote en `QUALITY_ATTESTED`, `ALMACENADO`, o `REDENCION_PARCIAL` puede pasar a `FALLIDO` en cualquier momento. Combinado con M-04 arriba, esto crea inconsistencias:

- En `ALMACENADO`: la reserva probablemente ya fue liberada al productor (liberable desde `QUALITY_ATTESTED`).
- En `REDENCION_PARCIAL`: hay buyers que ya redimieron parcialmente. El reembolso pro-rata sobre tokens restantes los castiga doblemente (perdieron parte de su capital al redimir; ahora reciben reembolso reducido).

**Mitigación propuesta:** definir explícitamente desde qué estados es legítimo `marcarFallido`:
- Permitido: PREVENTA, COSECHADO (antes de quality attest)
- Bloqueado: QUALITY_ATTESTED, ALMACENADO, REDENCION_PARCIAL (requieren proceso especial documentado en ADR)

Si el negocio requiere "fail después de ALMACENADO" (e.g., contaminación post-storage), introducir un estado separado `FALLIDO_POST_STORAGE` con flujo de reembolso adaptado, o requerir devolución previa de reserva ya liberada via función dedicada.

---

#### M-06 (NUEVO) — `_update` no chequea `isSanctioned` ni `isFrozen` antes de `super._update`

**Severidad:** Medium
**Archivo:** `AssetVault.sol:523-537`

**Descripción:**
El override valida `identityRegistry.canMint(to)` en mints (línea 533), que internamente sí incluye `!sanctioned && !frozen && expiresAt > block.timestamp` (ver `IdentityRegistry.canMint:171-175`). **Esto está correcto para MINTS.**

**Pero NO valida nada en BURNS.** Burns ocurren via:
1. `burnForRedemption` (callable solo por RedemptionManager, que sí valida canRedeem del comprador).
2. `_burn` interno en `reembolsarLoteFallido` (no valida nada del buyer).

Si un buyer queda sancionado **después de la compra** y antes del reembolso, el reembolso le envía USDC. **Esto puede violar regulación OFAC** (transfer a sanctioned address) y genera responsabilidad legal para el operador.

**PoC:**
1. Alice compra 100 tokens del lote X.
2. Alice es agregada a lista OFAC. Compliance officer marca `IdentityRegistry.markSanctioned(alice)`.
3. Lote X pasa a FALLIDO.
4. `reembolsarLoteFallido(X, [alice])` quema los tokens de Alice y le envía USDC.
5. **Operador acaba de transferir USDC a address sancionada.** Violación de TFE/AMLD.

**Mitigación propuesta:**
```solidity
// Dentro del loop de reembolsarLoteFallido, antes del transfer:
if (identityRegistry.isSanctioned(buyer) || identityRegistry.isFrozen(buyer)) {
    // Opción A: skip reembolso, quemar tokens, registrar evento (USDC queda en contrato)
    _burn(buyer, loteId, balance);
    emit ReembolsoBloqueado(loteId, buyer, balance, reembolsoUSDC, "sanctioned_or_frozen");
    continue;
    // Opción B: revert para forzar review manual
    // revert AddressSanctionedOrFrozen(buyer);
}
```

Opción A es preferible operacionalmente (procesar el resto) y deja el USDC en el contrato para release controlado posterior por compliance officer.

---

#### M-07 (NUEVO) — `confirmarCalidad` permite el mismo lab repetido en `labAddresses`

**Severidad:** Medium
**Archivo:** `AssetVault.sol:282-308`

**Descripción:**
El check de diversidad de jurisdicciones (1 BO + 1 no-BO) y el check de `length >= MIN_LABS_PARA_ATTESTATION` (=2) **no validan que los labs sean distintos**. Si dos entries en `attestation.labAddresses` apuntan al mismo lab boliviano + un lab extranjero, el check `hasLocal = true, hasForeign = true` pasa.

**PoC:**
```
labAddresses = [labBO, labBO, labFR]
labSignatures = [sigBO_msg1, sigBO_msg2, sigFR_msg]
```

Ambas firmas del lab BO son válidas (el lab firma 2 veces el mismo hash, lo cual ECDSA permite con nonce determinista, o firma 2 veces con randomness distinto). El minimum-2-labs check pasa (length=3 ≥ 2), pero efectivamente solo 2 labs distintos firmaron. Esto **no rompe la regla 2-labs-distintos directamente porque hay 2 distintos**, pero **rompe la regla "diversidad jurisdiccional 1 BO + 1 no-BO" si el array es `[labBO, labBO]` (length 2, ambos BO)** — espera, no, porque `hasForeign` quedaría `false` y revertiría.

**Realmente el bug es más sutil:** considerar `[labBO, labBO]`:
- length = 2 ≥ MIN. OK.
- iter 0: labBO BO → hasLocal=true
- iter 1: labBO BO → hasLocal=true (sin cambio)
- hasForeign = false → revierte `MissingForeignLab`.

OK, este caso revierte. Pero `[labBO, labFR, labFR]`:
- length = 3 ≥ MIN. OK.
- hasLocal=true (BO), hasForeign=true (FR). No revierte.
- Sin embargo, **dos labs FR son potencialmente la misma entidad firmando 2 veces**, no 2 entidades independientes.

**Impacto:** la garantía de "2 labs INDEPENDIENTES" del MVP se reduce a "≥ 1 BO + ≥ 1 no-BO" sin requerir distinción. La aseguradora europea que confía en doble verificación puede tener una expectativa rota.

**Mitigación propuesta:** agregar check de unicidad de labs:
```solidity
for (uint256 i = 0; i < attestation.labAddresses.length; i++) {
    for (uint256 j = i + 1; j < attestation.labAddresses.length; j++) {
        if (attestation.labAddresses[i] == attestation.labAddresses[j]) revert DuplicateLab();
    }
}
```

O usar un set off-chain (no nativo en Solidity) o un mapping efímero. Para arrays típicos de 2-3 labs, O(n²) inline es aceptable.

---

#### M-08 (NUEVO) — `setApprovalForAll` se puede usar para fingerprinting / liveness probe

**Severidad:** Medium (privacy)
**Archivo:** `AssetVault.sol:513-515`

**Descripción:**
La función revierte siempre con `TransferP2PNoPermitido()`. Mientras esto bloquea aprobaciones efectivamente, **no respeta el patrón EIP-1155** de devolver el evento `ApprovalForAll(owner, operator, false)`. Marketplaces o wallets que llaman `setApprovalForAll(operator, true)` para detectar si el token es transferible recibirán revert, lo cual algunas integraciones interpretan como "contrato roto" en lugar de "transfer-disabled by design".

**Impacto:** menor; afecta UX de wallets que muestran balances + integraciones con indexers genéricos.

**Mitigación propuesta:** considerar emitir un evento informativo en lugar de revertir:
```solidity
function setApprovalForAll(address operator, bool approved) public override {
    // Soft block: emit a no-op event documenting the policy.
    emit ApprovalRejected(msg.sender, operator, approved, "Solo-primario: no P2P approvals");
    revert TransferP2PNoPermitido();
}
```

(Esta es una preferencia de DX; el revert es funcionalmente correcto.)

---

### 🟢 Low

#### L-01 (REAFIRMADO) — Sin tiempo máximo de espera en redención (afecta `RedemptionManager`, no AssetVault directamente)

Ver audit previo L-04.

#### L-02 (REAFIRMADO) — Falta evento `LoteAgotado`

**Archivo:** `AssetVault.sol:467-470`

`burnForRedemption` cambia el estado a AGOTADO en línea 469 pero **no emite evento**. Indexers como Goldsky deberán inferir la transición. Recomendado:
```solidity
emit LoteAgotado(loteId);
```

#### L-03 (REAFIRMADO) — Eventos parciales (faltan campos de tracking)

Ver audit previo L-01.

#### L-04 (NUEVO) — `liberarReservaTecnica` permite re-llamada cuando `reservaTecnicaUSDC` cambió (no debería)

**Archivo:** `AssetVault.sol:428-444`

**Descripción:**
La función chequea `montoLiberable == 0 → revert`. Si tras liberar (`reservaTecnicaLiberada = reservaTecnicaUSDC`) se llama de nuevo, el delta es 0 y revierte. **Correcto.**

Sin embargo, **`reservaTecnicaUSDC` es mutado en cada `comprar`**, no es un total estático. Si el lote está en `QUALITY_ATTESTED` (permitido liberar) y simultáneamente sigue recibiendo compras (estado `PREVENTA` requerido en `comprar`, así que no es posible) — pero si en el futuro se relaja el invariante, podría haber compras post-attestation que aumentan `reservaTecnicaUSDC` y el delta queda como `reservaTecnicaUSDC_new - reservaTecnicaLiberada_old`. Esto es ambiguo.

**Estado actual:** no explotable porque `comprar` requiere `PREVENTA` y `liberarReservaTecnica` requiere ≥ `QUALITY_ATTESTED`. **No hay overlap.** Pero la dependencia entre máquinas de estado es implícita; vale documentar.

**Mitigación propuesta:** agregar invariante test:
```solidity
invariant_releaseEqualsTotalAfterAttestation() public {
    LoteMiel memory l = vault.lotes(loteId);
    if (l.estado >= LoteEstado.QUALITY_ATTESTED) {
        assertEq(l.reservaTecnicaLiberada, l.reservaTecnicaUSDC);
    }
}
```

#### L-05 (NUEVO) — `_computeAttestationHash` es `pure` aunque depende de `block.chainid` futuro

**Archivo:** `AssetVault.sol:542`

Si se implementa el fix de H-03 incluyendo `block.chainid`, la función debe cambiar de `pure` a `view`. Trivial, pero un test que valida `pure` se rompería. Anotar para refactor coordinado.

#### L-06 (NUEVO) — `reembolsarLoteFallido` ignora silenciosamente buyers con balance 0

**Archivo:** `AssetVault.sol:405-407`

```solidity
uint256 balance = balanceOf(buyer, loteId);
if (balance == 0) continue;
```

**Impacto:** un operador que pasa el array incorrecto (e.g., direcciones que nunca compraron, o que ya redimieron) no recibe feedback. El loop salta silenciosamente y marca `_reembolsado[loteId] = true` igual.

**Mitigación propuesta:** emitir evento `ReembolsoSkipped(loteId, buyer, "zero_balance")` para audit trail completo:
```solidity
if (balance == 0) {
    emit ReembolsoSkipped(loteId, buyer);
    continue;
}
```

---

### 🔵 Informational

#### I-01 (REAFIRMADO) — Licencia BUSL-1.1 placeholder

Sin cambio.

#### I-02 (REAFIRMADO) — Bolivia hardcoded como `bytes2("BO")`

Aceptable para MVP, generalizar en fase multi-país.

#### I-03 (REAFIRMADO) — `_computeAttestationHash` no incluye `block.chainid`

**Promovido a High (ver H-03).**

#### I-04 (REAFIRMADO) — Documentación parcial en libraries

Sin cambio.

#### I-05 (REAFIRMADO) — `reembolsarLoteFallido` puede correr out-of-gas con muchos buyers

Sin cambio. Implementar batching antes de tener > 50 buyers por lote.

#### I-06 (NUEVO) — `burnForRedemption` tiene un check redundante teóricamente bypasseable, no explotable en práctica

**Archivo:** `AssetVault.sol:450-453`

**Descripción:**
```solidity
function burnForRedemption(address from, uint256 loteId, uint256 cantidad) external {
    if (msg.sender != redemptionManager) revert OnlyRedemptionCanBurn();
    if (redemptionManager == address(0)) revert RedemptionManagerNotSet();
    // ...
}
```

**Análisis solicitado por el orquestador:** ¿Hay ventana donde `redemptionManager == address(0)` y alguien pueda llamar `burnForRedemption`?

**Para bypasear:** `msg.sender != redemptionManager` debe ser `false` cuando `redemptionManager == address(0)`. Esto requiere que `msg.sender == address(0)`. **En EVM real, `msg.sender == address(0)` NO ES ALCANZABLE desde ninguna transacción externa.** Los únicos contextos donde aparece `address(0)` como sender son:
- Bloque de construcción (constructor de otro contrato), pero el constructor no puede llamar funciones de AssetVault porque `to` debe estar deployado.
- Precompiles internos (no aplicable).

**Conclusión:** el bypass es teóricamente nulo. **No es explotable.** Sin embargo, el orden de los checks es subóptimo: lo correcto sería:
```solidity
if (redemptionManager == address(0)) revert RedemptionManagerNotSet();
if (msg.sender != redemptionManager) revert OnlyRedemptionCanBurn();
```

Esto deja la intención clara y elimina la ambigüedad. **Recomendado fix puramente cosmético.**

#### I-07 (NUEVO) — `nonReentrant` ausente en `marcarFallido` y `confirmarAlmacenamiento`

**Archivo:** `AssetVault.sol:348-362`, `365-377`

**Análisis:** estas funciones no mueven USDC ni llaman a contratos externos arbitrarios. El único external read es `identityRegistry.canMint(to)` invocado vía `_update` (que no aplica aquí porque no hay mint/burn). **No requiere `nonReentrant` por análisis técnico.** Sin embargo, por consistencia y defense-in-depth con el resto del contrato, agregar `nonReentrant` cuesta gas marginal y elimina sorpresas futuras.

**Recomendación:** dejarlo como está (no agregar overhead innecesario), pero documentar en NatSpec por qué no se aplica.

#### I-08 (NUEVO) — Constructor no transfiere `DEFAULT_ADMIN_ROLE` automáticamente; depende del deploy script

**Archivo:** `AssetVault.sol:113-136`

**Descripción:**
El constructor grants `DEFAULT_ADMIN_ROLE` a `p.admin`, pero **no revoca el rol del deployer EOA**. El comentario `@custom:security` línea 109-111 indica que "el deployment script DEBE transferir DEFAULT_ADMIN_ROLE al Safe y revocar el rol del deployer EOA en el mismo tx batch". Esta es una **dependencia operacional fuera del contrato**.

Mitigación más robusta: hacer que el constructor reciba un único parámetro `admin` y `_grantRole(DEFAULT_ADMIN_ROLE, p.admin)` (que ya hace). El deployer NO recibe el rol porque `_grantRole` no auto-asigna a `msg.sender`. **Validación de código actual:** el constructor de `AccessControl` de OZ v5 NO auto-grantea `DEFAULT_ADMIN_ROLE` al deployer (cambio desde v4). **Por lo tanto, este finding NO es vulnerabilidad activa**: solo `p.admin` recibe el rol.

**Conclusión:** comentario del audit es histórico (OZ v4 era el riesgo). Con OZ v5, está bien. **Cerrar como informational confirmatorio.**

#### I-09 (NUEVO) — `confirmarCalidad` hace dos loops sobre `attestation.labAddresses` (gas)

**Archivo:** `AssetVault.sol:292-308, 320-324`

**Descripción:**
Loop 1 (líneas 292-308): valida labs + jurisdicciones + firmas.
Loop 2 (líneas 322-324): copia `labAddresses` a storage.

Para arrays pequeños (2-3 labs) el costo es marginal, pero ambos loops podrían unificarse:
```solidity
for (uint256 i = 0; i < attestation.labAddresses.length; i++) {
    address labAddr = attestation.labAddresses[i];
    // ... validaciones ...
    stored.labAddresses.push(labAddr);
}
```

**Ahorro estimado:** ~5,000 gas por attestation (2 labs). No crítico pero limpio.

---

## Verificaciones positivas

Lo que está implementado correctamente y agrega confianza:

1. **Checks-Effects-Interactions** aplicado correctamente en `comprar`:
   - Línea 225: `lote.reservaTecnicaUSDC += reservaRetenida` (effect) **antes** de `_mint` (línea 228) y `safeTransfer` (línea 231). Aunque `_mint` puede invocar callback `onERC1155Received`, ya está protegido por `nonReentrant`.

2. **`nonReentrant` correcto** en funciones que mueven USDC: `comprar` (202), `confirmarCosecha` (248), `confirmarCalidad` (278), `reembolsarLoteFallido` (383), `liberarReservaTecnica` (428).

3. **`whenNotPaused`** aplicado en `comprar` (línea 202) — única función directamente sensible al estado del contrato. `_update` también heredarea pause via `ERC1155Pausable._update` en la chain de C3.

4. **Constructor con OZ v5 NO auto-grantea `DEFAULT_ADMIN_ROLE` al deployer.** Verificado contra `@openzeppelin/contracts/access/AccessControl.sol@5.x`.

5. **`_requireNonZero` helper** centraliza validaciones del constructor, reduce repetición y bytecode. Refactor a `InitParams` no introduce bugs detectables.

6. **Lock pattern para `setRedemptionManager`** (línea 148): único set, revierte si ya está seteado. Correcto para resolver circular dependency en deploy.

7. **Reentrancy guard en burn flow:** `burnForRedemption` (línea 450) sin `nonReentrant` pero **el caller RedemptionManager sí lo tiene**, y `_burn` no llama callbacks externos en ERC1155 (no hay `onERC1155Burned`). **Seguro por construcción.**

8. **Override `_update`** correctamente bloquea P2P (línea 530) y valida KYC en mints (línea 533). `setApprovalForAll` también revierte. **Doble defensa contra P2P.**

9. **Custom errors gas-efficient** en lugar de string reverts. Cumple regla del proyecto y skill `solidity-security`.

10. **NatSpec presente** en todas las funciones externas con `@notice` + `@dev` + `@custom:security` cuando aplica.

11. **`SafeERC20`** usado en todos los transfers USDC (`safeTransfer` en líneas 231, 416, 441). Maneja USDC quirks (en USDT-like tokens que no retornan bool).

12. **Inmutables correctos** (`usdc`, `identityRegistry`, `labRegistry`). `redemptionManager` es mutable pero solo settable una vez.

13. **`block.timestamp` solo usado para timestamps de auditoría** (`uint64(block.timestamp)` en líneas 181, 333, 478, 484). Nunca para decisiones críticas o randomness. Cumple regla del proyecto.

14. **No `tx.origin`** en ninguna parte del contrato.

15. **No inline assembly** en AssetVault.

16. **No `delegatecall`** a contratos externos.

---

## Comparación vs `audit-report-2026-05-19.md` (audit previo)

| ID anterior | Severidad | Estado actual | Notas |
|---|---|---|---|
| H-01 | High | **Vigente** | Reembolso parcial. Sin resolver. Decisión de producto pendiente. |
| M-01 | Medium | Aceptado | `setApprovalForAll` revierte; decisión consciente para MVP. |
| M-02 | Medium | **Vigente** | `isLabCertifiedFor` por especialización no validado. Renombrado en este audit a M-01. |
| M-03 | Medium | **Vigente** | Shortfall en `confirmarCosecha`. Renombrado a M-02. |
| M-04 | Medium | Mitigado | Signature malleability mitigado por OZ ECDSA v5. |
| M-05 | Medium | **Vigente** | Burns en redención INICIADA por reembolso. Renombrado a M-03. |
| L-01 a L-07 | Low | Varios vigentes | L-02, L-04 confirmados. L-03/L-06 aceptados. |
| I-01 | Info | Sin cambio | Licencia BUSL-1.1 placeholder. |
| I-02 | Info | Sin cambio | Bolivia hardcoded. |
| I-03 | Info | **PROMOVIDO a High (H-03)** | Chainid + address(this) ausentes. Multi-chain ya planeado. |
| I-04 | Info | Sin cambio | NatSpec parcial en libraries. |
| I-05 | Info | Sin cambio | Out-of-gas en reembolso con muchos buyers. |
| I-06 | Info | Validado | `setRedemptionManager` only-once. Correcto. |
| I-07 | Info | Aceptado | No `recoverERC20`. Aceptado para MVP. |
| I-08 | Info | Aceptado | URI fijo. |

### Findings NUEVOS introducidos por esta auditoría profunda

| ID nuevo | Severidad | Descripción corta |
|---|---|---|
| H-02 | High | Overmint por división entera temprana en `comprar` |
| H-03 | High | Domain separator EIP-712 ausente en attestation hash (chainid + address) |
| M-04 | Medium | `reembolsarLoteFallido` no descuenta `reservaTecnicaLiberada` |
| M-05 | Medium | `marcarFallido` transitions desde QUALITY_ATTESTED/ALMACENADO sin protección |
| M-06 | Medium | `reembolsarLoteFallido` envía USDC a addresses sancionadas/frozen |
| M-07 | Medium | `confirmarCalidad` no valida unicidad de labs en el array |
| M-08 | Medium | `setApprovalForAll` UX para wallets/marketplaces |
| L-04 | Low | Acoplamiento implícito entre `comprar` y `liberarReservaTecnica` |
| L-05 | Low | Si se fixea H-03, función debe pasar de `pure` a `view` |
| L-06 | Low | `reembolsarLoteFallido` skip silencioso de balance 0 |
| I-06 | Info | Orden de checks en `burnForRedemption` |
| I-07 | Info | `nonReentrant` ausente en algunas funciones (análisis defensivo) |
| I-08 | Info | OZ v5 ya no auto-grantea `DEFAULT_ADMIN_ROLE` al deployer (confirmatorio) |
| I-09 | Info | Doble loop sobre labs en `confirmarCalidad` (gas opt) |

---

## Recomendaciones priorizadas (top 10 acciones)

1. **H-02 (fix obligatorio antes de cualquier deploy):** computar `kgYaVendidos` y `kgSolicitados` en gramos enteros, comparar contra `kgEsperados * 1000`. Agregar fuzz test que valida invariante `totalSupply * GRAMOS_POR_TOKEN <= kgEsperados * 1000`.

2. **H-03 (fix obligatorio antes de Plume mainnet):** incluir `block.chainid` + `address(this)` + `attestation.testedAt` en `_computeAttestationHash`. Cambiar firma a `view`. Implementar `_attestationConsumed` mapping (ya especificado en CONTRACT-SPECS §4.7) para defense-in-depth.

3. **H-01 (decisión de producto):** definir política de reembolso completo (fondo de garantía + retención 100% hasta cosecha) y actualizar arquitectura. Sin este fix, el riesgo legal con compradores europeos es real.

4. **M-04 (fix antes de mainnet):** restar `reservaTecnicaLiberada` en `reembolsarLoteFallido`. Test de combinación reserve-released + marcar-fallido.

5. **M-05 (definir transiciones):** documentar y enforce qué estados permiten transición a FALLIDO. Idealmente un estado separado para fallas post-storage.

6. **M-06 (compliance OFAC):** chequear `isSanctioned` y `isFrozen` antes de transfer USDC en reembolsos. Skip o revert; preferiblemente skip + evento.

7. **M-07 (lab unicidad):** O(n²) check de unicidad en `attestation.labAddresses`. Para n=2-3 es marginal.

8. **M-01 (M-02 previo, vigente):** validar `isLabCertifiedFor` por especialización en `confirmarCalidad`.

9. **M-02 (M-03 previo, vigente):** implementar política de shortfall en `confirmarCosecha`.

10. **M-03 (M-05 previo, vigente):** auto-cancel de redenciones INICIADA al marcar `FALLIDO`.

---

## Cobertura por las 12 categorías solicitadas

| # | Categoría | Findings nuevos | Verificaciones positivas |
|---|---|---|---|
| 1 | Reentrancy | I-07 (informacional) | nonReentrant correcto en CEI |
| 2 | Access Control | I-08 confirmatorio | OZ v5, no auto-grant |
| 3 | Signature replay | H-03 (promovido) | OZ ECDSA v5 |
| 4 | Transiciones de estado | M-05 | Estados bien gated en cada función |
| 5 | Edge cases numéricos | H-02, L-06 | Solidity 0.8.24 checked math |
| 6 | Override `_update()` | M-06 | Doble defensa P2P |
| 7 | Reserva técnica | M-04, L-04 | Lock pattern correcto |
| 8 | Reembolso pro-rata | H-01 vigente, L-06 | _reembolsado lock OK |
| 9 | QualityAttestation | M-07, M-01 vigente | Diversidad jurisdiccional OK |
| 10 | burnForRedemption | I-06 | Defense-in-depth via `OnlyRedemptionCanBurn` |
| 11 | Eventos / audit trail | L-02, L-03 vigentes | Eventos en funciones críticas |
| 12 | Costo/poder ratio | (analizado) | Compromiso de 1-Safe = aborto, no robo. BACKEND_SIGNER comprometido = mints sin pago (limitado por USDC ya en contrato y validación de monto). |

---

## Análisis costo/poder de roles (categoría 12)

| Rol | Identidad | Compromiso → Impacto | Costo de defensa |
|---|---|---|---|
| `DEFAULT_ADMIN_ROLE` | Safe 2-de-3 (cofundadores) | Total: grant/revoke cualquier rol. Mitigación: hardware wallets + multi-sig. | Alto (3 hardware wallets físicamente seguros) |
| `ADMIN_ROLE` | Safe 2-de-3 | `crearLote` con datos manipulados (productorSRL fake, kgEsperados inflado). Compradores compran lote ficticio. Mitigación: monitoreo on-chain de creaciones. | Compartido con DEFAULT_ADMIN |
| `BACKEND_SIGNER_ROLE` | Wallet HSM (1 EOA) | **Crítico:** mint sin pago real, si USDC ya está en el contrato. Pero el contrato no recibe USDC en `comprar` (es off-chain). Vector real: mintear a wallet propia, vender en mercado secundario... pero no hay secundario (P2P bloqueado). **Daño limitado a tokens no-redimibles sin USDC backing.** | HSM AWS/GCP (uno solo, single point of failure) |
| `ORACLE_ROLE` | Safe 2-de-3 | `confirmarCosecha/Calidad/Almacenamiento/Fallido` con datos falsos. Si attestation fake con isMonofloralCertified=true → reputacional + legal con UE. Si marcarFallido prematuro → reembolso parcial fraudulento. | Alto (3 hardware wallets de cofundadores) |
| `TREASURY_SRL_ROLE` | Hardware wallet | `liberarReservaTecnica` (release a productorSRL). El productorSRL es campo del lote, así que el rol no puede redirigir a wallet propia. **Bajo impacto.** | Una hardware wallet |
| `COMPLIANCE_OFFICER_ROLE` | Hardware wallet (titular + suplente) | `pause`/`unpause`. Pausa maliciosa puede congelar el sistema. Mitigación: pause es reversible por unpause del mismo officer; daño es DoS temporal. | Dos hardware wallets |

**Conclusión:** la separación de poderes es robusta. **Single point of failure: `BACKEND_SIGNER_ROLE`** (es una EOA gestionada por HSM, no multi-sig). Si la HSM se compromete:
- Mints sin pago: contenidos por la lógica `montoUSDCPagado >= cantidadTokens * precioPorTokenUSDC`, que requiere que USDC ya esté en el contrato (es decir, alguien efectivamente pagó). **No es trivialmente explotable.**
- Pero combinado con un compromiso del frontend o del flujo de pago, podría coordinarse un robo. Recomendación: **monitorear mints anómalos** off-chain (alerta si mint sin matching deposit en Stripe/MoonPay/Ramp). Considerar también capacity caps por window (e.g., max 100k USDC/día sin approval adicional).

**Compromiso de un único firmante de Safe 2-de-3 (1 de 3):** insuficiente para ejecutar ninguna función. Diseño correcto.

---

## Resumen para auditoría externa (Sherlock/Trail of Bits)

Antes de auditoría externa, **bloquear releases** hasta resolver:
- H-01 (reembolso completo) — decisión + implementación
- H-02 (overmint precisión) — implementación
- H-03 (chainid + address(this) en attestation) — implementación
- M-01, M-02, M-04, M-05, M-06, M-07 — implementación

Resoluciones recomendadas como parte del próximo iteration cycle:
- M-03 (auto-cancel redemptions on FALLIDO) — requires RedemptionManager changes
- L-02, L-06 — eventos faltantes

Confirmar con tests de coverage 100% líneas/branches + fuzz 10k runs sobre `comprar`, `reembolsarLoteFallido`, `confirmarCalidad`.

---

**Última actualización:** 2026-05-19
**Auditor:** Subagente A (opus) | Deep audit AssetVault.sol v0.2.0
**Estado:** findings comunicados al orquestador. Requiere aprobación de Dany F. para priorizar fixes.
