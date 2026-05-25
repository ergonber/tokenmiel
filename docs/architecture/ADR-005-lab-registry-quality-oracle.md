# ADR-005: LabRegistry como oráculo de calidad (palinología + NMR)

**Status:** ⏸️ **DEFERRED TO PHASE 2** (originalmente Accepted 2026-05-19)
**Date:** 2026-05-19 (deferred via ADR-010 en Iteration #2)
**Author:** Daniel Hidalgo Carrasco
**Tags:** smart-contracts, oracle, quality, lab-registry, moat, palinology, nmr, phase-2

---

## ⚠️ Update (Iteration #2, 2026-05-19)

**Esta decisión fue diferida a fase 2.** Ver `ADR-010-simplificacion-estados-sin-quality-attestation.md` para el razonamiento. El contrato `LabRegistry.sol` queda **standalone (no integrado con AssetVault)** en el MVP. Para reactivación en fase 2 se requiere:
- Re-integrar dependencia en `AssetVault` (deploy v2 con campo `labRegistry`)
- Reagregar `confirmarCalidad()` function
- Reagregar estado `QUALITY_ATTESTED` al enum
- Migración a contrato v2 si AssetVault ya está en mainnet

El contenido original de este ADR se mantiene como referencia para la fase 2.

---

---

## Context

La industria mielera global enfrenta un problema estructural de adulteración. China exporta volumen masivo de "miel" mezclada con jarabes (HFCS, jarabe de arroz, jarabe de remolacha) etiquetada falsamente como monofloral premium. Tests rutinarios de aduana no detectan adulteración sofisticada. Resultado: compradores europeos que pagan premium reciben mezclas, confianza estructural dañada.

**Sin un oráculo de calidad verificable, nuestro token compite contra commodity genérico y pierde el premium price.** No hay diferenciador real vs miel china barata.

**Con un oráculo de calidad verificable on-chain, nuestro token es la única certificación cryptográfica de monofloralidad disponible en el mercado.** Este es el **moat real** del producto.

---

## Decision

**Implementar `LabRegistry.sol` como cuarto contrato del sistema y estructura `QualityAttestation` dentro de `LoteMiel`.**

### Componentes
1. **`LabRegistry.sol`** — whitelist on-chain de laboratorios certificados con función de verificación de firmas
2. **Struct `QualityAttestation`** dentro de `AssetVault.LoteMiel` con datos estructurados on-chain
3. **Función `confirmarCalidad()`** en `AssetVault` callable solo por oracle Safe multi-sig
4. **Doble verificación obligatoria:** mínimo 2 labs independientes (1 boliviano + 1 europeo)
5. **Estándar UE adoptado:** ≥45% polen dominante + NMR passed + C4 passed + residues passed = `isMonofloralCertified = true`

### Labs candidatos (seed inicial del LabRegistry)
- **IBNORCA** (Bolivia) — laboratorio nacional acreditado
- **Eurofins** (Alemania / global) — líder mundial en NMR spectroscopy para alimentos
- **Intertek** (UK / global) — multi-test acreditado
- **SGS** (Suiza / global) — fuerte presencia LATAM
- **TÜV** (Alemania) — multi-test para mercado europeo

---

## Alternatives considered

### Sin oráculo de calidad estructurado
- ✅ Más simple, menos código
- ❌ Pierde el moat del producto
- ❌ Token compite contra commodity genérico, no captura premium price

### Hash del certificado on-chain (sin datos estructurados)
- ✅ Simple
- ❌ El comprador tiene que descargar el PDF y leerlo manualmente
- ❌ No es verificable cryptográficamente vs criterios objetivos (45% polen)

### EAS Attestations (Ethereum Attestation Service)
- ✅ Estándar emergente para attestations
- ❌ Más complejo que custom solution para este caso
- ❌ Menor adopción en RWA específicamente
- → Reconsiderable en fase 2

### Chainlink Functions para llamar API del lab
- ✅ Trustless via descentralized oracle network
- ❌ Latencia + complejidad + LINK costs
- ❌ Adapter custom es más directo
- → Reconsiderable en fase 2 si Chainlink BUILD program aprueba

### Un solo lab
- ✅ Más rápido, más barato (USD 100-300 vs USD 200-600 por lote)
- ❌ Riesgo de colusión entre lab y operador
- ❌ Menor credibilidad institucional

---

## Consequences

### Positive

- **Transparencia total:** cualquier comprador puede verificar on-chain qué labs analizaron el lote, qué % de polen tiene, si pasó NMR y C4.
- **Doble verificación reduce riesgo de colusión** (lab boliviano valida origen, lab europeo valida estándar de destino).
- **Cryptográficamente verificable:** cada lab firma con clave privada registrada on-chain. Manipular reporte requiere comprometer la clave del lab.
- **Cadena de custodia documental:** reportes completos en Arweave permiten auditoría detallada por terceros.
- **Estándar UE adoptado:** regla `pollenPct >= 45% && nmrPassed && c4Passed` consistente con Directiva 2014/63/UE. No inventamos estándar propio.
- **Moat defendible:** este es el diferenciador que justifica premium price vs miel china adulterada.

### Negative

- **Costo adicional por lote:** USD 200-600 (depende de labs y tests). Suele ser una sola vez al inicio del lote, no por kg.
- **Tiempo adicional:** 2-4 semanas entre cosecha y attestation (envío de muestras, análisis, recepción de reportes).
- **Dependencia operacional con labs:** integración con APIs (o ingesta manual de reportes firmados).
- **Onboarding de labs nuevos:** requiere proceso técnico-legal (registro en LabRegistry on-chain + integración API).

### Neutral

- **Costo recuperable:** se justifica con los primeros 10-15 kg vendidos del lote dado el diferencial premium (USD 35-60/kg adicional vs commodity).
- **Cumplimiento de regulación UE de origen** facilitado por la transparencia on-chain.

---

## Implementation notes

### Tests científicos relevantes

| Test | Qué detecta | Estándar |
|---|---|---|
| **Palinología** (pollen analysis) | % de polen de la especie monofloral | ≥45% para "monofloral" (UE) |
| **NMR Spectroscopy** | Adulteración con jarabes | Pass/Fail (perfil isotópico) |
| **C4 Sugar Analysis (AOAC 998.12)** | Adulteración con jarabe de caña/maíz | δ¹³C ratio natural |
| **Pesticidas y antibióticos** | Residuos | EU MRL compliance |
| **HMF, diastasa, humedad** | Frescura y procesamiento | Codex Alimentarius |

### Struct `QualityAttestation` (en `AssetVault.LoteMiel`)

```solidity
struct QualityAttestation {
    address[]  labAddresses;          // labs que firmaron (mín 2)
    bytes2     pollenSpecies;          // código botánico de la especie
    uint8      pollenPercentage;       // 0-100, real
    bool       nmrPassed;
    bool       c4Passed;
    bool       residuesPassed;
    bytes32[]  fullReportHashes;       // 1 hash por reporte completo
    uint64     testedAt;
    bool       isMonofloralCertified;  // computed
}
```

`isMonofloralCertified = (pollenPercentage >= 45 && nmrPassed && c4Passed && residuesPassed)`

### `LabRegistry.sol` — design clave

```solidity
struct Lab {
    address    signerAddress;       // clave pública ECDSA del lab
    bytes32    nameHash;            // hash del nombre legal
    bytes2     jurisdiction;        // ISO 3166-1 alpha-2
    uint8[]    specializations;     // enum: PALINOLOGIA, NMR, C4, PESTICIDES
    bytes32    accreditationHash;   // hash de credenciales acreditadas
    bool       active;
    uint64     addedAt;
    uint64     deactivatedAt;
}

mapping(address => Lab) public labs;

function addLab(...) external onlyRole(ADMIN_ROLE);
function deactivateLab(...) external onlyRole(COMPLIANCE_OFFICER_ROLE);
function verifyAttestationSignature(address lab, bytes32 attestationHash, bytes signature) external view returns (bool);
function isLabCertifiedFor(address lab, uint8 specialization) external view returns (bool);
```

### Función `confirmarCalidad()` en `AssetVault`

```solidity
function confirmarCalidad(
    uint256 loteId,
    QualityAttestation calldata attestation,
    bytes[] calldata labSignatures  // 1 firma por lab en attestation.labAddresses[]
) external onlyRole(ORACLE_ROLE);
```

Validaciones:
1. `attestation.labAddresses.length >= 2`
2. Al menos 1 lab boliviano + 1 lab no-boliviano (verificar `jurisdiction` de cada lab)
3. Cada lab está active en LabRegistry
4. Cada lab está autorizado para los tests aplicables
5. Cada firma del lab es válida (vía `LabRegistry.verifyAttestationSignature()`)
6. Estado del lote es `COSECHADO` (transiciona a `QUALITY_ATTESTED`)
7. Computa `isMonofloralCertified` automáticamente

### Onboarding de labs (proceso operativo)

1. Identificar lab certificado con acreditación demostrable
2. Acuerdo comercial off-chain (LSA — Lab Services Agreement)
3. Lab genera par de claves ECDSA exclusivo para este propósito (clave privada NUNCA sale del HSM del lab)
4. Admin ejecuta `LabRegistry.addLab(...)` con metadatos del lab
5. Setup técnico de integración (API o ingesta manual de reportes firmados)
6. Test en testnet con lote de prueba
7. Habilitar en mainnet

---

## References

- ARQUITECTURA-TECNICA-MVP.md §7B (decisión técnica #4B: oráculo de calidad)
- ADR-003 (4 contratos inmutables)
- ADR-004 (oracle design)
- Directiva UE 2014/63/UE sobre miel monofloral
- Codex Alimentarius para estándares de miel
- Eurofins NMR methodology: https://www.eurofins.com/food-testing/
- IBNORCA (acreditación Bolivia): https://www.ibnorca.org/
