# ADR-030: Allowlist de jurisdicciones permitidas (gate KYC off-chain)

**Status:** Accepted
**Date:** 2026-06-02
**Author:** Daniel Hidalgo Carrasco
**Tags:** backend, identity, kyc, jurisdiction, allowlist, compliance, off-chain-gate, packages-shared, legal-signoff
**Resuelve:** Gap de cobertura: ADR-011 delegó la *validación* de jurisdicción al backend pero NUNCA definió qué jurisdicciones están **permitidas para operar** (allowlist de admisión), ni dónde vive esa lista, ni quién la aprueba.
**Relacionado:** ADR-011 (jurisdiction validation off-chain), CIS §9 (authority boundary), `packages/shared/src/constants/jurisdiction-codes.ts`, ARQUITECTURA-BACKEND-FASE2 §`ResolveKYCDecision`
**Supersedes:** N/A
**Superseded by:** N/A

---

## Context

ADR-011 cerró el finding **M-05** del audit de `IdentityRegistry.sol`: el campo `jurisdiction: bytes2` del struct `KYCData` se acepta on-chain **sin validar** contra ISO 3166-1, y la decisión fue que el backend valide el código ISO **off-chain** antes de llamar `setKYC`. ADR-011 produjo `packages/shared/src/constants/jurisdiction-codes.ts` con `isValidJurisdiction()` — un helper que verifica que el código sea un **ISO 3166-1 alpha-2 sintácticamente válido y conocido**.

El audit de cobertura de Fase 2 detectó que ahí queda un **hueco que ningún documento cierra**: ADR-011 valida que `jurisdiction` sea un código bien-formado (`"BO"`, `"DE"`, etc.), pero **NO decide si un applicant de esa jurisdicción puede o no operar en la plataforma**. Dicho de otro modo: `isValidJurisdiction("KP")` → ya hoy puede devolver `false` solo porque Corea del Norte no está en la lista del MVP, pero esa exclusión es un **efecto colateral** de cuáles países cargamos en `JURISDICTION_CODES`, no una **política de admisión explícita, documentada y firmada por legal**. El propio comentario de cabecera de `jurisdiction-codes.ts` y la Consequence "Neutral" de ADR-011 dejan en claro que ese archivo lista TODOS los ISO válidos que cargamos y que **la decisión de bloquear/permitir países es responsabilidad del backend** — pero ese backend nunca tuvo una allowlist formal.

Esto importa porque, según CIS §9 (authority boundary), la jurisdicción es uno de los **dos comportamientos OFF-CHAIN** del sistema (junto a la recuperación de reembolso a address revocado). La puerta de KYC/allowlist de inversores se enforcea ON-CHAIN (`canMint`/`canRedeem`), pero el `jurisdiction: bytes2` que el backend escribe vía `setKYC` es **metadata, no un gate on-chain**. Por lo tanto, si queremos rechazar a un applicant por su jurisdicción, el ÚNICO punto de enforcement posible es el backend, ANTES de `setKYC`. ARQUITECTURA-BACKEND-FASE2 ubica ese punto con precisión: `ResolveKYCDecision` (capa `application`) "valida jurisdicción OFF-CHAIN contra lista ISO 3166-1 alpha-2 (ADR-011)" antes de que `IdentityRegistryWriter` firme `setKYC` con `BACKEND_SIGNER_ROLE`.

### Gap a cerrar

1. **Definir la allowlist de admisión** (no solo el set de códigos ISO válidos): qué jurisdicciones pueden onboardear en el MVP.
2. **Decidir dónde vive** esa lista y cómo se actualiza (alineado a ADR-011: como código en `packages/shared`, sin transacción on-chain).
3. **Definir el punto de enforcement** en el pipeline KYC y el comportamiento ante rechazo.
4. **Fijar el sign-off legal** como gate de release: la lista del MVP es **provisional** y NO puede ir a mainnet sin aprobación de legal.

---

## Decision

Se adopta una **allowlist de jurisdicciones permitidas, enforced OFF-CHAIN en el backend, como código configurable en `packages/shared`** (extiende el artefacto ya existente de ADR-011). El `jurisdiction: bytes2` on-chain **sigue siendo metadata** y NO se valida on-chain — esto es continuación directa de ADR-011 y CIS §9, no un cambio de boundary.

### Mecánica

**1. Artefacto — extensión de `packages/shared/src/constants/jurisdiction-codes.ts`:**

`JURISDICTION_CODES` (ADR-011) sigue siendo el catálogo de códigos ISO conocidos por la plataforma para validación sintáctica y para poblar selects de UI. Se **agrega encima** una capa de admisión explícita:

```typescript
/**
 * Allowlist de admisión del MVP. Subconjunto de JURISDICTION_CODES que tiene
 * permiso OPERATIVO para onboardear. PROVISIONAL: requiere sign-off legal
 * antes de mainnet (ADR-030).
 */
export const ALLOWED_JURISDICTIONS: ReadonlySet<JurisdictionCode> = new Set([
  // Mercado primario (sede operativa)
  'BO',
  // Mercados de exportación objetivo de miel monofloral premium — PLACEHOLDER
  // razonable a confirmar con legal: UE + hubs premium de miel.
  'DE', 'ES', 'IT', 'FR', 'NL', 'BE', 'AT',
]);

/**
 * Returns true si la jurisdicción es un ISO válido Y está habilitada para operar.
 * Distinto de isValidJurisdiction (que solo chequea sintaxis/conocimiento ISO).
 */
export function isAllowedJurisdiction(code: string): boolean {
  if (!isValidJurisdiction(code)) return false;
  return ALLOWED_JURISDICTIONS.has(code.toUpperCase());
}
```

La lista MVP inicial es **provisional**: `BO` (Bolivia, sede operativa y mercado primario) más un placeholder razonable de mercados de exportación de miel monofloral premium (núcleo UE). La lista definitiva la **define legal**; los códigos de arriba son un punto de partida, no la verdad final.

**2. Separación de conceptos — clave:**

- `isValidJurisdiction(code)` (ADR-011): ¿el código es un ISO 3166-1 alpha-2 conocido? → **calidad de dato**.
- `isAllowedJurisdiction(code)` (ADR-030): ¿esa jurisdicción tiene permiso para operar? → **política de admisión**.

Son **dos checks distintos** con dos responsabilidades distintas. Un código puede ser válido (`"KR"`) y no estar permitido (no está en `ALLOWED_JURISDICTIONS`). El gate de admisión es `isAllowedJurisdiction`.

**3. Punto de enforcement — `ResolveKYCDecision` (capa `application`):**

`ResolveKYCDecision` valida la jurisdicción del applicant contra la allowlist **ANTES** de delegar a `IdentityRegistryWriter.setKYC`. Si la jurisdicción no está permitida, la decisión es **rechazo**: NO se escribe `setKYC` (y si el address ya estaba aprobado, procede `revokeKYC` con razón documentada). El pipeline es el descrito en ARQUITECTURA-BACKEND-FASE2: inbound de evidencia Sumsub → `ResolveKYCDecision` → (si pasa) outbound `setKYC` confirmado por el evento `KYCUpdated`.

```typescript
// apps/api/src/modules/identity/application/resolve-kyc-decision.ts (ejemplo)
import { isAllowedJurisdiction } from '@tokenization/shared/constants/jurisdiction-codes';

if (!isAllowedJurisdiction(applicant.jurisdiction)) {
  // Rechazo de admisión: NO se llama setKYC. Se registra en audit_log y
  // se notifica a compliance. NO es un error de dato — es policy.
  return KYCDecision.rejected(RejectionReason.JURISDICTION_NOT_ALLOWED);
}
// ... continúa: map tier, expiresAt, sumsubApplicantHash → setKYC
```

Este check es **complementario** del screening continuo (`identity/screening`, OFAC SDN nightly): la allowlist es admisión por **país de jurisdicción**; el screening es exclusión por **individuo/entidad sancionada**. Ambos viven off-chain en el backend; ninguno reemplaza al otro.

**4. Actualización de la lista:**

Igual que ADR-011: modificar `ALLOWED_JURISDICTIONS` y redesplegar el backend. **Cero transacciones on-chain.** El frontend (`apps/web`) usa `isAllowedJurisdiction` para filtrar el select de onboarding y no ofrecer jurisdicciones que serán rechazadas (mejor UX, pero el enforcement autoritativo es el del backend, no la UI).

### Gate de release — SIGN-OFF LEGAL OBLIGATORIO

La lista MVP es **provisional y NO debe ir a producción/mainnet sin aprobación formal de legal**. La definición de qué jurisdicciones admite la plataforma tiene implicancias regulatorias (MiCA/AMLD6 en UE, normativa de valores y AML por país, capacidad de exportación de miel boliviana a cada mercado) que exceden el scope técnico de este repo y son responsabilidad del compañero legal (per CLAUDE.md raíz §1). El sign-off legal sobre `ALLOWED_JURISDICTIONS` es un **gate de release bloqueante** para mainnet.

---

## Alternatives considered

### A — Whitelist mutable on-chain de jurisdicciones permitidas (rechazada)

Agregar `mapping(bytes2 => bool) allowedJurisdictions` en `IdentityRegistry` y rechazar `setKYC` si la jurisdicción no está permitida.

**Por qué se rechazó:**
- ❌ **Contradice ADR-011 y CIS §9** — la jurisdicción es deliberadamente OFF-CHAIN; el `bytes2` on-chain es metadata, no un gate. Convertirlo en gate on-chain reabre exactamente el debate que ADR-011 ya cerró (Opción B descartada por gas, bootstrap de 250+ tx, y overhead de governance).
- ❌ **Modifica un contrato congelado** — `IdentityRegistry.sol` es uno de los 3 contratos inmutables del MVP (ADR-003). Tocarlo implica re-auditoría completa.
- ❌ **Falsa sensación de compliance** — replica el anti-patrón ya identificado en ADR-011: el compliance real (admisión + sanciones) es más granular que "por país on-chain".
- ❌ **Latencia de actualización** — cuando legal cambie la lista, requeriría una transacción de `COMPLIANCE_OFFICER_ROLE` por cambio, vs. un redeploy de backend.

### B — Solo confiar en el contenido de `JURISDICTION_CODES` como allowlist implícita (rechazada)

No agregar `ALLOWED_JURISDICTIONS`; tratar "estar en `JURISDICTION_CODES`" como "estar permitido".

**Por qué se rechazó:**
- ❌ **Mezcla dos responsabilidades** — `JURISDICTION_CODES` existe para validación sintáctica de ISO y para poblar selects de UI; convertirlo en allowlist de admisión acopla "código válido" con "país permitido". Agregar un país al catálogo de UI obligaría a permitirlo operativamente, o viceversa.
- ❌ **Sin sign-off explícito** — la admisión quedaría como un efecto colateral del catálogo, sin un artefacto que legal pueda revisar y firmar como "esta es la lista de países que admitimos".
- ❌ **Es precisamente el gap que este ADR cierra** — ADR-011 y el comentario de `jurisdiction-codes.ts` ya advierten que ese archivo NO es la política de admisión.

### C — Listas de screening del backend (`screening/`) como único filtro (rechazada como sustituto)

Confiar exclusivamente en el módulo `screening/` (OFAC SDN, EU, ONU) para excluir jurisdicciones.

**Por qué se rechazó como sustituto (sigue siendo complementario):**
- ❌ **Granularidad equivocada** — el screening opera sobre individuos/entidades sancionadas, no sobre "qué países admitimos por estrategia comercial/regulatoria". Un país puede no tener sanciones y aun así estar fuera de nuestra allowlist (no es mercado objetivo, no tenemos cobertura regulatoria allí).
- ❌ **No es una decisión de admisión** — el screening responde "¿esta persona está sancionada?", no "¿admitimos clientes de este país?". Son preguntas distintas; necesitamos ambas.

---

## Consequences

### Positive

1. **Cierra un gap real de cobertura** — por primera vez existe una política de admisión por jurisdicción explícita, ubicada y atribuible, que antes vivía solo como efecto colateral del catálogo ISO.
2. **Consistente con ADR-011 y CIS §9** — el boundary no cambia: la jurisdicción sigue OFF-CHAIN, el `bytes2` on-chain sigue siendo metadata, y `IdentityRegistry` no se toca (ADR-003 intacto).
3. **Separación de conceptos limpia** — `isValidJurisdiction` (calidad de dato) vs. `isAllowedJurisdiction` (política de admisión) son funciones distintas con responsabilidades distintas; el screening OFAC queda como tercera capa complementaria.
4. **Cero gas, actualización sin redeploy on-chain** — cambiar la allowlist es modificar `packages/shared` y redesplegar el backend, igual que la lista ISO de ADR-011.
5. **Testeable de forma aislada** — `isAllowedJurisdiction` es una función TypeScript pura, testeable con Vitest sin dependencia de blockchain ni de Sumsub.
6. **Punto de enforcement único y documentado** — `ResolveKYCDecision` es el único lugar donde se decide la admisión por jurisdicción, antes de `setKYC`; el frontend lo refleja en UX pero el backend es autoritativo.
7. **Gate de release explícito para legal** — el sign-off legal queda formalizado como bloqueante de mainnet, no como un "ojalá alguien lo revise".

### Negative

1. **El backend es el único enforcement point** — como en ADR-011, si `ResolveKYCDecision` tiene un bug y omite el check, un applicant de jurisdicción no permitida podría recibir `setKYC` con tier > 0 y operar. Mitigado por: (a) el check es una función pura testeable con cobertura; (b) el indexer Goldsky puede alertar `jurisdiction` fuera de `ALLOWED_JURISDICTIONS` en el evento `KYCUpdated`; (c) `COMPLIANCE_OFFICER_ROLE` puede `revokeKYC` ante detección.
2. **Sin defensa on-chain para jurisdicción no permitida** — un auditor externo leyendo solo los contratos no verá esta política; vive enteramente en `packages/shared` + backend. Es una consecuencia aceptada y heredada del boundary de ADR-011/CIS §9.
3. **Lista MVP provisional y posiblemente incorrecta hasta el sign-off** — el placeholder (UE núcleo + BO) es una conjetura técnica, no una decisión legal. Operar con esta lista en producción ANTES del sign-off sería un riesgo regulatorio; por eso el sign-off es un gate bloqueante explícito.

### Neutral

1. **Doble check de jurisdicción en el pipeline** — `isValidJurisdiction` (calidad de dato, puede correr en validación de DTO/Zod) e `isAllowedJurisdiction` (admisión, en `ResolveKYCDecision`) son dos llamadas distintas en momentos distintos. Es intencional: rechazar un código mal-formado es un 4xx de validación; rechazar una jurisdicción no permitida es una decisión de policy registrada en `audit_log` y notificada a compliance.
2. **El catálogo `JURISDICTION_CODES` puede ser superset de `ALLOWED_JURISDICTIONS`** — la UI puede seguir mostrando más países de los admitidos si así se decide; lo que importa es que el gate de `ResolveKYCDecision` use `isAllowedJurisdiction`. Mantener `ALLOWED_JURISDICTIONS ⊆ JURISDICTION_CODES` es un invariante deseable (un test de `packages/shared` debería verificarlo).
3. **Relación con screening continuo** — la allowlist (admisión por país) y el screening nightly (exclusión por individuo/entidad) coexisten sin solaparse. Ninguno reemplaza al otro; este ADR no modifica el flujo de screening de ARQUITECTURA-BACKEND-FASE2.

---

## Implementation notes

### Artefacto (extiende ADR-011)

- Extender `packages/shared/src/constants/jurisdiction-codes.ts`: agregar `ALLOWED_JURISDICTIONS: ReadonlySet<JurisdictionCode>` e `isAllowedJurisdiction(code: string): boolean`. NO modificar la semántica de `JURISDICTION_CODES` ni de `isValidJurisdiction` (siguen siendo de ADR-011).
- Documentar en el doc-comment del artefacto que `ALLOWED_JURISDICTIONS` es **provisional** y requiere sign-off legal antes de mainnet (referenciar ADR-030).
- Test en `packages/shared` (Vitest): (a) `ALLOWED_JURISDICTIONS ⊆` set de `JURISDICTION_CODES`; (b) `isAllowedJurisdiction('BO') === true`; (c) un código ISO válido pero no admitido devuelve `false`; (d) código mal-formado devuelve `false`.

### Punto de integración en el backend (Bun + Hono / capa `application`)

- `ResolveKYCDecision` importa `isAllowedJurisdiction` de `@tokenization/shared` y lo evalúa ANTES de delegar a `IdentityRegistryWriter`. Rechazo → no escribe `setKYC` (o `revokeKYC` si ya estaba aprobado), con `RejectionReason.JURISDICTION_NOT_ALLOWED` registrado en `audit_log` (append-only, hash chain — CLAUDE.md raíz §9) y notificación a compliance.
- El `IdentityRegistryWriter` (infraestructura, viem + `BACKEND_SIGNER_ROLE` KMS) **no cambia**: sigue firmando `setKYC(user, tier, expiresAt, jurisdiction, sumsubApplicantHash)` solo cuando `ResolveKYCDecision` devolvió aprobación. El `jurisdiction: bytes2` escrito sigue siendo metadata on-chain.

### Punto de integración en el frontend (Next.js)

- `apps/web` usa `isAllowedJurisdiction` (o `[...ALLOWED_JURISDICTIONS]`) para poblar/filtrar el select de onboarding, evitando que el usuario elija una jurisdicción que será rechazada. UX, no enforcement: el gate autoritativo es el backend.

### Monitoreo

- Goldsky/indexer: alertar si un evento `KYCUpdated` trae `jurisdiction` fuera de `ALLOWED_JURISDICTIONS` (señal de bug en el gate o de cambio de lista no propagado). Encaja con el monitoreo de `KYCUpdated` ya descrito en ARQUITECTURA-BACKEND-FASE2.

### Gate de release

- Antes de mainnet: obtener sign-off legal escrito sobre el contenido final de `ALLOWED_JURISDICTIONS`. Bloqueante. La lista del MVP en este ADR es un placeholder técnico, no la lista aprobada.

---

## References

- ADR-011 (`docs/architecture/ADR-011-jurisdiction-validation-off-chain.md`) — validación de jurisdicción off-chain; origen de `jurisdiction-codes.ts` e `isValidJurisdiction`; este ADR lo extiende sin contradecirlo
- CIS §9 (`docs/architecture/CIS-v1.md`, "Authority boundary") — la jurisdicción es OFF-CHAIN; el `jurisdiction: bytes2` on-chain es metadata, no un gate
- `packages/shared/src/constants/jurisdiction-codes.ts` — artefacto a extender con `ALLOWED_JURISDICTIONS` e `isAllowedJurisdiction`
- ARQUITECTURA-BACKEND-FASE2 (`docs/architecture/ARQUITECTURA-BACKEND-FASE2.md`) — `ResolveKYCDecision` (punto de enforcement), `IdentityRegistryWriter` (`setKYC` vía KMS), pipeline KYC inbound/outbound, screening continuo `identity/screening`
- ADR-003 (4 contratos inmutables sin proxy) — por qué la allowlist NO va on-chain en `IdentityRegistry`
- CLAUDE.md raíz §1 y §9 — responsabilidad legal fuera del scope técnico; `audit_log` append-only con hash chain
