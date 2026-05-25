# ADR-011: Validación de jurisdicción ISO 3166-1 off-chain (M-05)

**Status:** Accepted
**Date:** 2026-05-22 (Iteration #3)
**Author:** Daniel Hidalgo Carrasco
**Tags:** smart-contracts, identity-registry, kyc, jurisdiction, compliance, off-chain-validation

---

## Context

El audit profundo de `IdentityRegistry.sol` (Iteration #3) identificó el finding **M-05**: el campo `jurisdiction: bytes2` del struct `KYCData` se acepta sin validación contra la lista ISO 3166-1 alpha-2. Esto permite que `BACKEND_SIGNER_ROLE` propague valores arbitrarios (`bytes2(0)`, `0xFFFF`, `"KP"` — Corea del Norte) directamente al estado on-chain sin ningún check.

La spec del contrato (CONTRACT-SPECS §5.13) requería que el campo almacene un código de país válido a los efectos de:

1. **Compliance analítico off-chain**: dashboards jurisdiccionales de exposición regulatoria.
2. **Enforcement de jurisdicciones bloqueadas**: Países bajo sanciones internacionales (OFAC SDN, ONU, UE) no deberían poder comprar tokens.
3. **Quality of data**: indexers como Goldsky consumen el evento `KYCUpdated` e indexan `jurisdiction` para reportes.

El audit propuso tres opciones:

- **Opción A** (elegida): validación off-chain en el backend antes de llamar `setKYC`, usando una lista ISO mantenida en el código fuente del backend compartido.
- **Opción B**: whitelist mutable on-chain (`mapping(bytes2 => bool) public allowedJurisdictions`) con función `setAllowedJurisdiction` callable por `COMPLIANCE_OFFICER_ROLE`.
- **Opción C**: aceptar como está, documentar que el contrato es agnóstico y la responsabilidad recae exclusivamente en el backend.

---

## Decision

**Adoptar Opción A: validación off-chain en el backend usando la lista ISO 3166-1 mantenida en `packages/shared/src/constants/jurisdiction-codes.ts`.**

El contrato NO agrega ningún check adicional para el campo `jurisdiction`. La única defensa on-chain existente (y suficiente para el MVP) es:

- El campo `jurisdiction` es `bytes2`, lo que acota el espacio a 65,536 valores posibles.
- `BACKEND_SIGNER_ROLE` es una clave HSM-managed (AWS KMS) con auditoría operacional. El vector de corrupción de `jurisdiction` requiere compromiso del HSM.

El backend DEBE importar `jurisdiction-codes.ts` de `packages/shared` y validar el código antes de cada llamada a `setKYC`.

---

## Alternatives considered

### B) Whitelist mutable on-chain

Agregar `mapping(bytes2 => bool) allowedJurisdictions` con función de gestión callable por `COMPLIANCE_OFFICER_ROLE`.

**Descartada por las siguientes razones:**

- **Gas**: cada validación en `setKYC` requiere un `SLOAD` adicional (~2,100 gas warm). Multiplicado por el volumen de KYC updates, es overhead innecesario.
- **Bootstrap**: el contrato se deployaría con el mapping vacío; requiere 250+ transacciones adicionales para pre-poblar la lista ISO antes de que sea usable. Riesgo operacional de deployer.
- **Actualización de lista**: cuando ISO 3166-1 actualiza (e.g., un país se divide, un territorio cambia de código), el COMPLIANCE_OFFICER debe ejecutar transacciones on-chain. Esto es overhead de governance sin beneficio real vs actualización off-chain.
- **No bloquea jurisdicciones OFAC**: el OFAC SDN no es solo por país — es por individuos, entidades y vectores más granulares. La validación de jurisdicción on-chain da una falsa sensación de seguridad sobre compliance OFAC.

### C) Sin validación (agnóstico de contrato)

Documentar que el contrato no valida y confiar 100% en el backend.

**Descartada**: deja gap de documentación — los consumidores del contrato (auditores, reguladores) no sabrían si la validación existe o no. La Opción A es equivalente a C en términos de código on-chain, pero establece la validación formalmente en un artefacto compartido.

---

## Consequences

### Positive

- **Cero gas adicional on-chain**: no se modifica el contrato `IdentityRegistry.sol`.
- **Lista actualizable sin redeploy**: cuando ISO 3166-1 actualiza, se modifica `jurisdiction-codes.ts` y el backend lo toma en el próximo despliegue.
- **Tipo compartido**: el módulo `packages/shared` es importable tanto por `apps/api` (validación server-side) como por `apps/web` (validación UI antes de submit).
- **Testeable de forma aislada**: la función `isValidJurisdiction()` es una función TypeScript pura, testeable con Vitest sin ninguna dependencia de blockchain.
- **Cobertura completa de la lista ISO**: ~250 países/territorios incluidos. On-chain, una whitelist de 250 entradas costaría ~$500+ USD en gas de deployment (en una L1).

### Negative

- **Backend es el único enforcement point**: si el backend tiene un bug y pasa `bytes2(0)` o un código inválido, el estado on-chain quedará con datos sucios.
- **Sin revert on-chain para jurisdicciones inválidas**: el contrato no puede rechazar un `setKYC` con `jurisdiction = "XX"`. Un auditor externo leyendo solo el contrato no verá esta validación.

### Neutral

- **Riesgo residual conocido y mitigado**: el indexer Goldsky detectaría `jurisdiction == bytes2(0)` o códigos desconocidos en el evento `KYCUpdated`. Si se detecta, el `COMPLIANCE_OFFICER_ROLE` puede revocar vía `revokeKYC`. La ventana de exposición es la del tiempo de detección del indexer.
- **Restricted countries (OFAC)**: la lista en `jurisdiction-codes.ts` incluye todos los países ISO. La decisión de bloquear países completos bajo sanciones OFAC/ONU/UE es responsabilidad del módulo `screening/` del backend. `jurisdiction-codes.ts` no enumera qué países están bloqueados — eso está fuera de scope de este artefacto.

---

## Implementation notes

### Artefacto creado

`packages/shared/src/constants/jurisdiction-codes.ts`:

- Exporta `JURISDICTION_CODES: readonly JurisdictionEntry[]` con los países del MVP (LATAM, UE, NA, APAC, y otros relevantes).
- Exporta `isValidJurisdiction(code: string): boolean`: helper de validación que verifica que el código tenga 2 caracteres y exista en la lista.
- Exporta helpers adicionales `isLATAMJurisdiction` e `isEUJurisdiction` para uso analítico.

### Punto de integración en el backend

```typescript
// apps/api/src/modules/kyc/kyc.service.ts (ejemplo)
import { isValidJurisdiction } from '@tokenization/shared/constants/jurisdiction-codes';

if (!isValidJurisdiction(kycDto.jurisdiction)) {
  throw new ValidationError(`Invalid jurisdiction code: ${kycDto.jurisdiction}`);
}
// ... llamar setKYC on-chain
```

### Punto de integración en el frontend

```typescript
// apps/web/src/features/onboarding/jurisdiction-select.tsx (ejemplo)
import { JURISDICTION_CODES } from '@tokenization/shared/constants/jurisdiction-codes';

// Render <select> con JURISDICTION_CODES como opciones
```

### Validación adicional recomendada

El backend debe además validar que el país NO esté en las listas de screening activas antes de aprobar el KYC. Esto es responsabilidad del módulo `screening/` (fuera del scope de este ADR), que consulta OFAC SDN, EU Financial Sanctions, ONU Consolidated List.

### Nota sobre países OFAC-restricted en el código

El módulo `jurisdiction-codes.ts` incluye TODOS los países ISO, incluyendo los bajo sanciones comprensivas (Cuba, Irán, Corea del Norte, Siria, Venezuela). La **exclusión** de compradores de esos países es responsabilidad del backend de screening, no de este artefacto. Incluirlos en la lista ISO es correcto: son países con códigos ISO válidos.

---

## References

- `docs/security-reviews/audit-IdentityRegistry-deep-2026-05-22.md` (finding M-05)
- `packages/shared/src/constants/jurisdiction-codes.ts` (artefacto resultante)
- `packages/contracts/src/IdentityRegistry.sol` (contrato sin cambios para este finding)
- ADR-012 (AccessControlDefaultAdminRules — otro finding de Iteration #3)
- `docs/ITERATION-LOG.md` (Iteration #3)
