# ADR-020: Custodia HOT/COLD del backend — superficie hot mínima de 3 funciones

**Status:** Accepted
**Date:** 2026-06-02
**Author:** Daniel Hidalgo Carrasco
**Tags:** backend, custody, hot-cold, kms, safe, multisig, access-control, relayer, key-management, threat-model
**Resuelve:** OS-5.3 (boundary exacto del backend signer vs Safe) — decisión abierta que bloquea el wiring a mainnet
**Relacionado:** CIS §6.1 (las 8 claves del deploy), ADR-007 (backend stack Bun+Hono+Drizzle+viem), ADR-012 (AccessControlDefaultAdminRules), ADR-016 (asimetría pause/unpause), ADR-022 (custodia KMS concreta — shape de `KmsAccount`)
**Supersedes:** N/A
**Superseded by:** N/A

---

## Context

El backend de Fase 2 (`ARQUITECTURA-BACKEND-FASE2.md` §1.3) es el ÚNICO componente que arma, firma o prepara transacciones on-chain contra los 3 contratos del MVP. La pregunta que quedó abierta como bloqueante de producción (OP-5 → OS-5.3) es **dónde cae exactamente la línea entre lo que el backend firma por sí mismo (HOT) y lo que requiere intervención humana multi-firma (COLD)**.

El sistema define 7 roles on-chain (CIS §6.1), distribuidos en los 3 contratos:

- `DEFAULT_ADMIN_ROLE` — gobernanza (transferencia de rol con delay de 3 días por ADR-012, `unpause` exclusivo por ADR-016, `setRedemptionManager` one-time).
- `ADMIN_ROLE` — `crearLote` en `AssetVault`.
- `BACKEND_SIGNER_ROLE` — `comprar` en `AssetVault`, `setKYC`/`revokeKYC` en `IdentityRegistry`.
- `COMPLIANCE_OFFICER_ROLE` — sanción/freeze en `IdentityRegistry`, `pause` (con admin), `cancelarRedencion` en `RedemptionManager`.
- `ORACLE_ROLE` — hitos físicos en `AssetVault` (`confirmarCosecha`, `confirmarAlmacenamiento`, `marcarFallido`, `reembolsarLoteFallido`, `finalizarReembolso`) y en `RedemptionManager` (`confirmarExportacion`, `completarRedencion`, `cancelarRedencion`).
- `TREASURY_SRL_ROLE` — `liberarReservaTecnica` en `AssetVault`.

### El hueco que cierra

El hueco no es de código de contrato (el access-control on-chain ya está congelado y auditado): es **de custodia operacional del backend**. Sin una regla explícita, un implementador podría razonablemente decidir que el backend signer también opere hitos de oracle "para reducir fricción" (un cofundador no siempre está disponible para firmar en el Safe), o que el backend tenga `ADMIN_ROLE` para crear lotes desde el dashboard. Cada rol que el backend pueda firmar autónomamente es **una clave más cuyo compromiso (vía RCE en el servidor, fuga de credenciales KMS, insider) se traduce en daño on-chain inmediato y sin segundo factor humano**.

La seguridad operacional del proyecto (CLAUDE.md §9, CIS §6.1) ya manda que las llaves críticas vivan en HSM (KMS) o hardware wallets y que las operaciones críticas pasen por Safe 2-de-3. Pero "crítico" sin un boundary explícito es ambiguo. Este ADR fija ese boundary de forma vinculante para `RelayerService` y `PrivilegedEndpointRegistry` (§1.3).

### Restricción heredada — la cadena es la autoridad

Vale recordar (CIS §9, matriz source-of-truth) que tener `BACKEND_SIGNER_ROLE` NO equivale a poder mintear a voluntad: si el destinatario no pasa `canMint`, `comprar` revierte `NotKYCVerified` en `AssetVault._update`. El gate KYC es on-chain. Aun así, una clave hot comprometida puede hacer daño real dentro de su superficie (registrar KYC fraudulento vía `setKYC`, mintear a addresses que el atacante haya pre-aprobado), de modo que minimizar esa superficie sigue siendo la prioridad.

---

## Decision

**`BACKEND_SIGNER_ROLE` es el ÚNICO rol que el backend firma de forma autónoma (HOT, vía GCP KMS), y su superficie hot se limita a exactamente 3 funciones: `comprar`, `setKYC`, `revokeKYC`. TODO lo demás es COLD: el backend únicamente prepara calldata para el Safe 2-de-3 / hardware wallets, y NUNCA firma.**

### Las 3 funciones HOT (Vía A — relayer autónomo, KMS)

| Función | Contrato | Por qué es HOT |
|---|---|---|
| `comprar(loteId, cantidadTokens, comprador, montoUSDCPagado, paymentRefHash)` | `AssetVault` | Se dispara automáticamente tras confirmar el pago off-chain; alto volumen, baja latencia esperada, gateada on-chain por `canMint`. El backend NO transfiere USDC acá (lo hace antes; `comprar` no hace `transferFrom`) |
| `setKYC(user, tier, expiresAt, jurisdiction, sumsubApplicantHash)` | `IdentityRegistry` | Se dispara desde el pipeline KYC (Sumsub → decisión → on-chain) tras un webhook GREEN; alto volumen de onboarding |
| `revokeKYC(user, reason)` | `IdentityRegistry` | Contraparte de `setKYC`; revocación automática ante rechazo/expiración de la decisión |

Estas 3 son operaciones de **alto volumen, disparadas por eventos del sistema (pago confirmado, webhook Sumsub), donde esperar una firma humana mataría la UX** y donde el daño de un compromiso está acotado por el gate on-chain. Firma con un `KmsAccount` custom de viem cuyo `signTransaction`/`sign` delega en GCP KMS vía referencia `BACKEND_SIGNER_KMS_KEY_ID` — la clave privada NUNCA se materializa en el proceso ni en env de prod (CIS §17.2, detalle de implementación en ADR-022).

### Todo lo demás es COLD (Vía B — calldata para el Safe / hardware, el backend NO firma)

El backend arma `SafeTransactionData` (vía `encodeFunctionData` de viem), lo envía al Safe Transaction Service y dispara `signers-notifier`; la transacción queda en estado `PENDING_SAFE` hasta que las firmas humanas la ejecutan. El backend NO posee ninguna de estas claves:

| Rol | Funciones COLD | Custodia |
|---|---|---|
| `ADMIN_ROLE` | `crearLote` | Hardware / Safe |
| `ORACLE_ROLE` | `confirmarCosecha`, `confirmarAlmacenamiento`, `marcarFallido`, `reembolsarLoteFallido`, `finalizarReembolso`, `confirmarExportacion`, `completarRedencion`, `cancelarRedencion` | Safe 2-de-3 |
| `TREASURY_SRL_ROLE` | `liberarReservaTecnica` | Hardware del tesorero |
| `COMPLIANCE_OFFICER_ROLE` | `markSanctioned`, `unmarkSanctioned`, `freezeAddress`, `unfreezeAddress`, `pause`, `cancelarRedencion` (path admin) | Hardware (titular + suplente) |
| `DEFAULT_ADMIN_ROLE` | `unpause` (exclusivo, ADR-016), `setRedemptionManager` (one-time), gestión de roles (delay 3 días, ADR-012) | Safe 2-de-3 |

### Caso especial — sin rol, self-custody

`iniciarRedencion` y `cancelarRedencion` por el path buyer-after-timeout (ADR-015) las firma **el comprador con su propio wallet** (RainbowKit). El backend NO las relaya ni las prepara como calldata para el Safe: solo expone un endpoint de PRE-VALIDACIÓN de lectura (`canRedeem`, `balanceOf`, `availableBalance` vs lock). Caen fuera del eje HOT/COLD porque el backend nunca es signer.

### La regla, en una línea

El backend firma autónomamente **3 funciones y solo 3**. Cualquier intento de mover una función fuera de ese conjunto a HOT requiere un ADR nuevo que supere a este.

---

## Alternatives considered

### Alternativa A — Más roles hot (p.ej. `ORACLE_ROLE` o `ADMIN_ROLE` en el backend signer) (rechazada)

Dar al backend la capacidad de firmar autónomamente hitos de oracle (`confirmarCosecha`, `confirmarExportacion`, `completarRedencion`) y/o `crearLote`, para que el dashboard ejecute sin esperar firmas del Safe.

**Por qué se rechazó:**
- ❌ **Amplía dramáticamente la superficie hot** — cada función adicional firmable por el backend es un vector más de compromiso. Un RCE en el servidor o una fuga de la credencial KMS pasaría de "puede registrar KYC y mintear (gateado)" a "puede confirmar cosechas fantasma, liberar reservas, completar redenciones y quemar tokens". El daño escala de acotado a sistémico.
- ❌ **Rompe el modelo de confianza 2-de-3** — los hitos físicos (cosecha, almacenamiento, export, BL/AWB, DUE) son attestations humanas que verifican documentos del mundo real (CIS §9: "OFF-CHAIN decisión → ON-CHAIN attestation"). Automatizarlas vía backend elimina el control humano multi-firma que justifica el Safe.
- ❌ **Contradice CLAUDE.md §9 y CIS §6.1** — la intención declarada es Safe 2-de-3 para `SAFE_ADMIN` y `ORACLE_SAFE`. Mover esos roles a hot exigiría un ADR que revierta esa postura de seguridad.
- ✅ El único beneficio (menos fricción operacional) no compensa: la fricción de firmar en el Safe es precisamente la garantía de seguridad que se busca para operaciones de valor.

### Alternativa B — Todo cold, incluso `comprar`/`setKYC`/`revokeKYC` (rechazada)

No darle al backend ningún rol firmable; absolutamente todo pasa por el Safe / hardware, incluyendo el minteo de compras y la sincronización de KYC.

**Por qué se rechazó:**
- ❌ **Mata la UX de los flujos de alto volumen** — `setKYC` se dispara por cada onboarding aprobado (alto volumen, rate esperado >100/h según runbook ADR-013) y `comprar` por cada compra confirmada. Exigir firma humana 2-de-3 por cada una es operacionalmente inviable.
- ❌ **Hitos atascados en `PENDING_SAFE`** — sin un signer autónomo, el onboarding y la compra quedarían bloqueados esperando que un cofundador firme, introduciendo minutos u horas de latencia en operaciones que deben ser casi instantáneas.
- ✅ **Es más seguro** — superficie hot cero. Pero la seguridad adicional es marginal: las 3 funciones hot ya están acotadas (gate `canMint` on-chain, `setKYC`/`revokeKYC` solo tocan el registro KYC que de todos modos es metadata gateada), mientras el costo de UX es prohibitivo.

### Alternativa C — Superficie hot intermedia (incluir algún hito de bajo riesgo) (rechazada implícitamente)

Cualquier punto intermedio entre A y la decisión adoptada (p.ej. "solo `confirmarExportacion` hot porque es de bajo valor monetario").

**Por qué se rechazó:** un boundary "intermedio" reintroduce la ambigüedad que este ADR busca eliminar. La línea limpia y defendible es **alto-volumen + gateado-on-chain = hot; todo lo demás = cold**. Las 3 funciones elegidas son exactamente las que cumplen ambos criterios; ninguna otra los cumple. Un boundary difuso invita a la erosión gradual de la superficie de seguridad.

---

## Consequences

### Positive

1. **Superficie de compromiso mínima y explícita** — un atacante que comprometa el backend (RCE, fuga de credencial KMS, insider) solo puede invocar `comprar`, `setKYC` y `revokeKYC`, todas acotadas: `comprar` está gateada por `canMint` on-chain; `setKYC`/`revokeKYC` solo mutan el registro KYC (que también es metadata gateada por el enforcement on-chain). No puede confirmar hitos, liberar fondos, quemar tokens, pausar/despausar, ni tocar roles.
2. **Boundary inequívoco y verificable** — `PrivilegedEndpointRegistry` (§1.3) materializa la regla como tabla declarativa endpoint↔rol↔función↔vía. Es auditable de un vistazo: si una fila marca HOT para algo que no sea las 3 funciones, es un bug.
3. **Consistente con la seguridad operacional ya decidida** — respeta CLAUDE.md §9, CIS §6.1/§17.2, ADR-012 (delay admin) y ADR-016 (asimetría pause). No introduce excepciones a la postura de "Safe 2-de-3 para lo crítico".
4. **UX preservada en los flujos calientes** — onboarding KYC y compra siguen siendo casi instantáneos (firma KMS autónoma), sin depender de la disponibilidad de los cofundadores.
5. **Defensa en profundidad** — incluso dentro de la superficie hot, el daño está doblemente acotado: gate on-chain (`canMint`) + el hecho de que el backend signer es UN solo address con UN stream de nonce (cola `relayer-hot` concurrency=1, §1.3), lo que limita el throughput de un abuso.

### Negative

1. **Fricción operacional en hitos** — cada confirmación de cosecha, almacenamiento, exportación, completar/cancelar redención, reembolso, creación de lote, liberación de reserva, sanción/freeze, pause/unpause y wiring requiere intervención humana en el Safe / hardware. Los hitos quedan en `PENDING_SAFE` hasta que las firmas se junten. Mitigación: `signers-notifier` (Resend + Slack) alerta a los firmantes; el dashboard prepara la calldata para que solo falte firmar.
2. **Disponibilidad de firmantes como dependencia operacional** — si los cofundadores del Safe 2-de-3 no están disponibles, los hitos se atascan. Esto es un costo aceptado y deliberado: la lentitud es el precio del control multi-firma. Mitigación: el path buyer-after-timeout de `cancelarRedencion` (ADR-015) es la escape valve para el caso extremo de que el Safe desaparezca, sin depender del backend.
3. **El backend signer sigue siendo un punto caliente** — aunque mínimo, las 3 funciones hot implican que el backend mantiene una clave operativa (referencia KMS). Mitigación: la clave vive en GCP KMS (nunca en env de prod, ADR-022), con rotación periódica posible vía el delay de roles de ADR-012, y el monitoreo de rate de `KYCUpdated` >100/h dispara el runbook de compromiso (ADR-013).

### Neutral

1. **`cancelarRedencion` aparece en dos vías** — el path admin/compliance es COLD (oracle o compliance officer firman); el path buyer-after-timeout es self-custody (el comprador firma). Ninguno es HOT. Esta dualidad es intencional (ADR-015) y debe mantenerse al editar `PrivilegedEndpointRegistry`.
2. **`iniciarRedencion` no entra en el eje HOT/COLD** — la firma el comprador con su wallet; el backend solo da preview de lectura. No es una excepción a la regla, simplemente no es una operación del backend.
3. **La elección AWS vs GCP KMS es ortogonal a este ADR** — esta decisión fija QUÉ firma el backend autónomamente y por qué; el CÓMO concreto de la custodia de la clave hot (proveedor KMS, shape de `KmsAccount`) se define en ADR-022. Acá se asume GCP KMS según la decisión congelada, pero el boundary HOT/COLD no cambia con el proveedor.

---

## Implementation notes

Se implementa en el **write path** del backend (`ARQUITECTURA-BACKEND-FASE2.md` §1.3, OP-3), stack Bun + Hono + Drizzle + viem (ADR-007):

- **`RelayerService` — dos vías mutuamente excluyentes.** La Vía A (HOT) resuelve un `walletClient` con `KmsAccount` custom de viem que delega `signTransaction`/`sign` en GCP KMS (referencia `BACKEND_SIGNER_KMS_KEY_ID`, nunca la clave en claro); solo acepta `comprar`, `setKYC`, `revokeKYC`. La Vía B (COLD) reusa el patrón existente `oracle/` (tx-builder → safe-adapter → Safe Transaction Service → `signers-notifier`): arma `encodeFunctionData`, NO firma, y deja la tx en `PENDING_SAFE`.
- **`PrivilegedEndpointRegistry` — la regla hecha código.** Tabla declarativa endpoint↔rol↔función↔vía↔Zod con doble gate independiente: Clerk + 2FA (RBAC de aplicación) Y rol on-chain. Solo 3 endpoints son `via: HOT`: `POST /purchases/:loteId/mint` (`comprar`), `POST /identity/kyc` (`setKYC`), `POST /identity/kyc/revoke` (`revokeKYC`). Todos los `POST /admin/*` son `via: COLD`. En la Vía B la clave on-chain está en hardware ajeno al backend, así que el RBAC de Clerk jamás habilita una firma.
- **Pre-flight + simulación.** Ambas vías hacen `simulateContract` antes de proceder (mapea custom errors como `NotKYCVerified`, `LoteNotInPreventa`, `MontoUSDCInsuficiente` a HTTP); la Vía A además hace pre-flight reads (`canMint`, `paused()`, `lotes().estado`, `kgDisponibles` en gramos) — el pre-check NUNCA reemplaza el gate on-chain, solo evita gastar gas/nonce en un revert seguro.
- **Idempotencia + nonce solo aplican a la Vía A.** El `BACKEND_SIGNER_ROLE` es UN address con UN stream → cola BullMQ `relayer-hot` concurrency=1, `next_nonce` en `relayer_nonce` reconciliado contra `getTransactionCount(signer, 'pending')`. Idempotencia en dos capas (`relayer_idempotency` por `paymentRefHash` + verificación de `LoteComprado` en Goldsky) para impedir el doble-mint. La Vía B no maneja nonce (lo maneja el Safe).
- **Ledger + auditoría.** Tabla `relayer_tx` con columna `via [HOT|COLD]` y estados (`QUEUED`/`SIMULATED`/`SENT`/`MINED`/`FAILED`/`PENDING_SAFE`/`EXECUTED_SAFE`) + `audit_log` append-only (hash chain, sin PII). El estado de dominio lo confirma el evento indexado por Goldsky, NO el receipt de la tx.
- **Lo que el write path NO hace** (refuerza el boundary): no firma roles COLD, no mueve USDC (lo hace `payments/escrow`), no reemplaza el gate KYC con su pre-check, no relaya `iniciarRedencion` ni el `cancelarRedencion` buyer-timeout.

---

## References

- `docs/architecture/CIS-v1.md` §6.1 (las 8 claves del deploy: roles, holders lógicos, custodia mainnet intended), §9 (authority boundary on-chain vs off-chain), §17.2 (gestión de llaves: KMS, no clave en env)
- `docs/architecture/ARQUITECTURA-BACKEND-FASE2.md` §1.3 (write path: Vía A HOT relayer / Vía B COLD Safe, `RelayerService`, `PrivilegedEndpointRegistry`), §2.2 (endpoints privilegiados rol+vía), OP-3/OS-5.3 (objetivo que este ADR cierra)
- ADR-007 (backend stack — Bun + Hono + Drizzle + viem; backend signer en KMS, no clave en env)
- ADR-012 (AccessControlDefaultAdminRules — delay de 3 días para transferencia/rotación de roles; relevante para la rotación de la clave hot)
- ADR-015 (Timeout Policy — el path buyer-after-timeout de `cancelarRedencion` es self-custody, escape valve sin backend)
- ADR-016 (asimetría pause/unpause — `unpause` exclusivo de `DEFAULT_ADMIN_ROLE`, COLD)
- ADR-022 (custodia KMS concreta — define el shape de `KmsAccount` y el proveedor; complementa este ADR sin alterar el boundary HOT/COLD)
- CLAUDE.md §9 (seguridad operacional: HSM/hardware, Safe 2-de-3, no secrets en env de prod)
