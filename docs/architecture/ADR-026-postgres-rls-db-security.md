# ADR-026: Row-Level Security y seguridad de la base de datos

**Status:** Accepted
**Date:** 2026-06-02
**Author:** Daniel Hidalgo Carrasco
**Tags:** backend, postgres, supabase, rls, row-level-security, pii, least-privilege, defense-in-depth, audit-log, drizzle
**Resuelve:** DB-SEC-01 (contención ante credencial de DB filtrada o bypass de la parametrización del ORM en tablas con PII o datos financieros)
**Relacionado:** ADR-007 (stack backend Bun+Hono+Drizzle+Supabase; tabla `audit_log` con `REVOKE UPDATE,DELETE` + hash chain), ADR-027 (cifrado de PII en reposo), CLAUDE.md §9 (seguridad operacional)
**Supersedes:** N/A
**Superseded by:** N/A

---

## Context

El backend de fase 2 (`ARQUITECTURA-BACKEND-FASE2.md`) materializa un read model y un set de tablas operativas que concentran **PII y datos financieros**: `applicants` (evidencia Sumsub, PII cifrada — la única fuente de verdad PII del sistema, per la matriz §10 del backend), `kyc_mirror` (tier/sanción/jurisdicción por wallet), `holding` (balances ERC-1155 por wallet), `lote_proyeccion` / `redencion_proyeccion` (proyecciones financieras y de redención), las tablas del relayer (`relayer_idempotency`, `relayer_nonce`, `relayer_tx`), `webhook_events` y `onchain_tx` (outbox). Todas viven en PostgreSQL gestionado por Supabase (ADR-007).

El único control de acceso a datos diseñado HOY a nivel de DB es el de la tabla `audit_log`: `REVOKE UPDATE,DELETE ON audit_log FROM PUBLIC` + `GRANT INSERT/SELECT` acotado a `api_user`/`audit_reader`, más la hash chain (`prev_hash = sha256(prev_row || current_row)`) que detecta manipulación retroactiva (ADR-007 §Implementation notes, CLAUDE.md §9). Para **todas las demás tablas no hay control a nivel de fila ni de rol**: la conexión del backend abre con un rol que puede leer y escribir cualquier fila de cualquier tabla, y la única barrera entre un atacante y los datos es la **parametrización de queries de Drizzle** (anti SQL-injection en la capa de aplicación).

### El hueco que cierra (traído del audit de cobertura)

El audit de cobertura de seguridad del MVP dejó explícito que **backend, DB y KYC bridge quedan fuera del scope de la auditoría de smart contracts** (`PLAN-AUDITORIA-EXTERNA-MVP.md`: "Auditorías de aplicación / pentest separados, fuera del scope de smart-contract audit"). Eso traslada al equipo la responsabilidad de cerrar los controles de la capa de datos por diseño, antes del pentest de aplicación.

El gap concreto es de **defensa en profundidad**: si una credencial de DB se filtra (env mal manejado, log que la expone, dump comprometido, dependencia maliciosa que la lee del proceso) **o** si aparece un bypass de la parametrización de Drizzle (un `sql.raw` mal usado, una columna interpolada sin sanitizar), el rol de conexión actual **lee y escribe todo**: PII de KYC, balances, idempotencia del relayer, outbox de transacciones. La parametrización del ORM es una **única línea de defensa en la capa de aplicación**; no hay red de contención por debajo. Esto contradice el espíritu de "mínimo privilegio" de CLAUDE.md §9, que hoy solo se aplica al `audit_log`.

Es importante encuadrar el límite de autoridad (CIS §9, matriz source-of-truth): el backend **NO es la puerta** de minteo/redención — eso se enforcea on-chain (`canMint`/`canRedeem`). Por lo tanto un compromiso de la DB **no permite acuñar ni redimir tokens indebidamente**. Pero sí permite **leer PII**, **exfiltrar balances y proyecciones financieras**, y **corromper el read model y las tablas del relayer** (idempotencia, nonce, outbox), lo que habilita denegación de servicio, doble procesamiento o envenenamiento de datos servidos al frontend. Ese es exactamente el blast radius que esta decisión acota.

---

## Decision

Se adopta **Row-Level Security (RLS) de PostgreSQL como control transversal de contención** sobre TODAS las tablas con PII o datos financieros, complementado con **roles de DB de mínimo privilegio**. El `audit_log` mantiene su esquema actual (`REVOKE UPDATE,DELETE` + hash chain), que NO es RLS sino **revocación de privilegios a nivel de tabla** — ambos controles se complementan, no se sustituyen.

### Alcance de tablas (RLS habilitado y forzado)

`ENABLE ROW LEVEL SECURITY` **y** `FORCE ROW LEVEL SECURITY` en:

- `applicants` (PII cifrada — ADR-027)
- `kyc_mirror`
- `holding`
- `lote_proyeccion`
- `redencion_proyeccion`
- `relayer_idempotency`, `relayer_nonce`, `relayer_tx` (las `relayer_*`)
- `webhook_events`
- `onchain_tx`

`FORCE` es deliberado: sin él, el dueño de la tabla (rol de migraciones) bypassa RLS por default; con `FORCE`, las policies aplican también al owner salvo en la ventana de migración controlada.

### Roles de DB (mínimo privilegio)

| Rol | Propósito | Privilegios |
|---|---|---|
| `api_user` | conexión del backend en runtime (Bun+Hono+Drizzle) | solo las operaciones y filas que su rol necesita por tabla; INSERT/SELECT en `audit_log` (ya existente, ADR-007) |
| `audit_reader` | lectura de compliance / read-only | SELECT acotado a las tablas y filas que compliance necesita; SELECT en `audit_log` (ya existente, ADR-007) |
| rol de migraciones (owner) | aplicar DDL y migraciones Drizzle | DDL; opera la ventana de migración; sujeto a `FORCE RLS` salvo en migración controlada |

El `api_user` deja de ser un superusuario de datos: sus permisos se acotan tabla por tabla (qué operaciones) y fila por fila (qué filas vía policies). El `audit_reader` es estrictamente de lectura para compliance, sin acceso de escritura a ninguna tabla.

### Mecánica de las policies

PostgreSQL RLS filtra filas mediante policies por `(rol, comando)`. El backend setea el contexto de identidad por transacción y las policies lo consumen:

```sql
-- 1. Habilitar y forzar RLS por tabla (ejemplo: kyc_mirror)
ALTER TABLE kyc_mirror ENABLE ROW LEVEL SECURITY;
ALTER TABLE kyc_mirror FORCE  ROW LEVEL SECURITY;

-- 2. api_user: solo las operaciones que su rol necesita, sobre las filas que necesita.
--    El backend setea el contexto por transacción (SET LOCAL app.actor = ...);
--    la policy lo lee con current_setting(..., true) (missing_ok = true => no rompe si no está seteado).
CREATE POLICY kyc_mirror_api_rw ON kyc_mirror
  FOR ALL
  TO api_user
  USING (true)               -- USING gobierna lectura/UPDATE/DELETE visibles
  WITH CHECK (true);          -- WITH CHECK gobierna INSERT/UPDATE entrantes

-- 3. audit_reader: solo lectura de compliance.
CREATE POLICY kyc_mirror_compliance_ro ON kyc_mirror
  FOR SELECT
  TO audit_reader
  USING (true);

-- 4. audit_log: NO RLS — control por revocación de privilegios (ADR-007), se mantiene.
--    REVOKE UPDATE, DELETE ON audit_log FROM PUBLIC;  + hash chain.
```

El predicado `USING`/`WITH CHECK` se materializa por tabla según el dato: las tablas operativas del relayer y el outbox usan policies que confinan al `api_user` a su propio contexto de ejecución; las proyecciones servibles confinan la lectura a lo que compliance/runtime necesita. La regla rectora es **deny-by-default**: con RLS habilitado y sin policy que matchee, la fila no es visible ni mutable; cada acceso legítimo se concede explícitamente.

### Relación con `audit_log`

El `audit_log` **no** lleva RLS. Su control es **revocación de privilegios de tabla** (`REVOKE UPDATE,DELETE`) + hash chain. RLS y revocación son ortogonales: RLS filtra *qué filas* ve/muta un rol; la revocación quita *qué comandos* puede ejecutar un rol sobre la tabla entera. El `audit_log` necesita inmutabilidad de filas existentes (append-only), que se logra revocando UPDATE/DELETE; no necesita filtrado por fila. Las demás tablas necesitan filtrado por fila/rol, que es lo que aporta RLS. Se aplican en conjunto, cada una en su tabla.

---

## Alternatives considered

### Alternativa A — Confiar solo en la parametrización de Drizzle (status quo) (rechazada)

Dejar la seguridad de datos enteramente en la capa de aplicación: queries parametrizadas + validación Zod de inputs.

**Por qué se rechazó:**
- ❌ **Única línea de defensa** — sin RLS, una credencial de DB filtrada o un único `sql.raw` mal escrito expone TODA la PII y los datos financieros. No hay contención por debajo del ORM.
- ❌ **Contradice mínimo privilegio (CLAUDE.md §9)** — hoy el control de "mínimo privilegio" solo cubre el `audit_log`; el resto opera con un rol omnipotente de datos.
- ❌ **El pentest de aplicación lo marcaría como hallazgo** — backend/DB están fuera del scope del audit de contratos pero entran al pentest separado (`PLAN-AUDITORIA-EXTERNA-MVP.md`); la ausencia de RLS sobre PII es un finding casi seguro.

### Alternativa B — Cifrado de PII como único control de la capa de datos (rechazada como sustituto)

Apoyarse exclusivamente en el cifrado de columnas PII (ADR-027) y no aplicar RLS.

**Por qué se rechazó como sustituto (se mantiene como complemento):**
- ❌ **El cifrado protege PII, no datos financieros estructurados** — `holding`, `lote_proyeccion`, `redencion_proyeccion`, `relayer_tx` contienen balances, montos y estado del relayer que no se cifran (son indexables/consultables). Un rol comprometido los lee igual.
- ❌ **No acota escritura ni corrupción** — el cifrado no impide que una credencial filtrada **escriba/corrompa** el read model o las tablas del relayer (idempotencia, nonce, outbox).
- ✅ **Complementario, no excluyente** — cifrado (ADR-027) + RLS (esta ADR) son capas distintas: el cifrado reduce el valor de un dump, RLS reduce qué puede tocar una credencial viva. Se adoptan ambos.

### Alternativa C — Filtrado a nivel de aplicación con un rol de DB único (rechazada)

Implementar el "mínimo privilegio" solo en el código del backend (cada repositorio Drizzle filtra por contexto), manteniendo un único rol de DB con permisos totales.

**Por qué se rechazó:**
- ❌ **El control vive en el mismo proceso que el atacante explota** — si la credencial se filtra, el atacante se conecta directo a Postgres y saltea por completo la capa de aplicación y sus filtros.
- ❌ **No es defensa en profundidad** — colapsa la barrera al mismo plano (la aplicación) que ya falló. RLS pone el control en la DB, fuera del alcance de un compromiso de la app.

### Alternativa D — Supabase Auth + policies basadas en `auth.uid()` (rechazada para este backend)

Usar el modelo RLS nativo de Supabase atado a sesiones de Supabase Auth.

**Por qué se rechazó:**
- ❌ **El proyecto usa Clerk para auth, no Supabase Auth** (ADR-007): no hay `auth.uid()` poblado por sesiones de Supabase. El backend se conecta como servicio (`api_user`), no como usuario final.
- ✅ **Se usa RLS de Postgres "crudo"** — `TO <rol>` + `current_setting('app.actor', true)` seteado por transacción desde el backend, sin acoplar a Supabase Auth. RLS es una primitiva de Postgres; no requiere Supabase Auth para funcionar.

---

## Consequences

### Positive

1. **Contención real ante credencial filtrada o bypass del ORM** — con RLS forzado + roles de mínimo privilegio, una credencial comprometida ya no lee/escribe todo: queda confinada a las filas y operaciones que su rol concede. Cierra DB-SEC-01.
2. **Mínimo privilegio extendido a toda la capa de datos** — el principio que hoy solo cubre el `audit_log` (CLAUDE.md §9) pasa a cubrir PII, balances, proyecciones y tablas del relayer.
3. **Defensa en profundidad** — el control vive en PostgreSQL, fuera del proceso de aplicación; un compromiso del backend no lo desactiva (a diferencia de un filtro en el código).
4. **Separación de lectura de compliance** — `audit_reader` da a compliance lectura acotada sin poder de escritura, reduciendo el blast radius de esa credencial.
5. **Complementa el cifrado (ADR-027) y el audit_log inmutable (ADR-007)** — tres capas ortogonales: cifrado en reposo, filtrado por fila/rol, append-only con hash chain.
6. **Adelanta hallazgos del pentest de aplicación** — RLS sobre PII es un control esperado; tenerlo por diseño reduce findings en el pentest separado del MVP.

### Negative

1. **Complejidad de policies y testing** — cada tabla suma policies `(rol, comando, USING, WITH CHECK)` que hay que diseñar, versionar en migraciones Drizzle y testear (incluyendo tests negativos: que `api_user` NO vea lo que no debe, que `audit_reader` no escriba). Mitigación: suite de tests de RLS por rol como parte del CI de DB.
2. **Riesgo de policy mal escrita = denegación de servicio** — una `USING` demasiado restrictiva puede ocultar filas legítimas y romper el read path en runtime. Mitigación: deny-by-default con concesiones explícitas + tests de happy-path por rol antes de merge.
3. **Overhead operacional en migraciones** — `FORCE RLS` sujeta también al owner; las migraciones que tocan datos requieren una ventana controlada o `SET LOCAL` de bypass para el rol de migraciones. Mitigación: documentar el patrón de migración bajo `FORCE RLS` en el runbook de DB.
4. **Pequeño costo de evaluación por query** — los predicados de policy se evalúan en cada acceso. Para las tablas y volúmenes del MVP es despreciable, pero debe vigilarse en `holding`/`transfer_log` de alto volumen.

### Neutral

1. **`audit_log` queda explícitamente fuera de RLS** — sigue gobernado por revocación de privilegios + hash chain (ADR-007). Es intencional y debe mantenerse así al editar el esquema: no migrar el `audit_log` a RLS.
2. **El esquema Drizzle aún no existe** — el read model y las tablas operativas están especificados en `ARQUITECTURA-BACKEND-FASE2.md` (OS-2.2, OS-3.3/3.5, OS-4.1/4.3) pero `packages/db/src/schema` está vacío. Esta ADR es un **control de diseño** que debe aterrizar junto con las primeras migraciones de fase 2, no un retrofit sobre tablas existentes.
3. **`transfer_log` no está en el alcance explícito de esta decisión** — es append-only crudo de `TransferSingle` (datos on-chain públicos, sin PII). Puede incorporarse a RLS por consistencia de roles, pero no es prioridad de contención de PII/financiera.

---

## Implementation notes

### Dónde vive el control

RLS y los roles son **DDL de PostgreSQL**, versionados como migraciones Drizzle en `packages/db/migrations`. Drizzle no modela RLS en su DSL de schema (`packages/db/src/schema`); las policies y los `ALTER TABLE ... ENABLE/FORCE ROW LEVEL SECURITY` se escriben en SQL plano dentro de las migraciones (Drizzle soporta SQL custom en migraciones). El schema TS de Drizzle define las tablas; la migración adjunta habilita RLS y crea las policies y los roles.

### Roles y conexión (Bun + Hono + Drizzle)

- El backend se conecta **siempre** como `api_user` (nunca como owner ni superuser). La cadena de conexión de runtime apunta a ese rol; la `DATABASE_URL` de migraciones apunta al rol de migraciones. Son credenciales distintas, gestionadas como secretos (CLAUDE.md §9: nunca en env de producción en claro; referencia a KMS/secret store).
- Por transacción, el backend setea el contexto de identidad antes de las queries de negocio:

```typescript
// infrastructure: por transacción Drizzle, antes de las queries de dominio
await tx.execute(sql`SET LOCAL app.actor = ${actorContext}`);
// las policies leen current_setting('app.actor', true) (missing_ok => no rompe en jobs sin contexto)
```

- `SET LOCAL` confina el contexto a la transacción (se descarta al COMMIT/ROLLBACK), evitando fugas de contexto entre requests que comparten conexión del pool.

### Roles de jobs y relayer

Los jobs BullMQ (conciliación, `kyc-sync`, relayer hot/cold) corren bajo `api_user` con el mismo contexto. Las policies de `relayer_*` confinan al `api_user` a operar su propio stream (idempotencia/nonce/outbox); no se concede a `audit_reader` ninguna escritura sobre `relayer_*`.

### Orden con viem / on-chain

Esta ADR es puramente de la capa de datos: no toca el authority boundary (CIS §9). El enforcement de `canMint`/`canRedeem` sigue 100% on-chain vía viem; RLS protege el **read model y las tablas operativas**, no las decisiones de minteo/redención. Un compromiso de DB no permite acuñar/redimir (la puerta es on-chain), pero sí leer PII/financiero — y eso es lo que RLS acota.

### Testing del control

- Tests de DB por rol: positivos (cada rol ve/escribe lo que debe) y negativos (cada rol NO ve/escribe lo que no debe), incluyendo el caso de credencial sin contexto (`app.actor` no seteado → deny-by-default).
- Validar que `FORCE RLS` está activo en las 10 tablas del alcance (un test de metadatos sobre `pg_class.relforcerowsecurity`).
- Validar que el `audit_log` **no** tiene RLS y **sí** mantiene `REVOKE UPDATE,DELETE` + integridad de hash chain (regresión sobre ADR-007).

---

## References

- `docs/architecture/ARQUITECTURA-BACKEND-FASE2.md` (read model `holding`/`lote_proyeccion`/`redencion_proyeccion`/`kyc_mirror`; tablas `relayer_idempotency`/`relayer_nonce`/`relayer_tx`; `webhook_events`/`onchain_tx`/`applicants` con PII cifrada; OS-2.2, OS-3.3/3.5, OS-4.1/4.3; matriz source-of-truth §10)
- `docs/architecture/CIS-v1.md` §9 (authority boundary on-chain vs off-chain — por qué un compromiso de DB no permite mint/redención pero sí lectura/corrupción del read model)
- `docs/architecture/ADR-007-backend-stack.md` (stack Bun+Hono+Drizzle+PostgreSQL/Supabase; `audit_log` con `REVOKE UPDATE,DELETE` + hash chain; roles `api_user`/`audit_reader`)
- ADR-027 (cifrado de PII en reposo — control complementario sobre `applicants` y columnas PII de `kyc_mirror`)
- `docs/security-reviews/PLAN-AUDITORIA-EXTERNA-MVP.md` (backend/DB/KYC fuera del scope del audit de smart contracts → entran al pentest de aplicación separado)
- `CLAUDE.md` §9 (seguridad operacional: mínimo privilegio, audit log append-only, no PII en logs)
- PostgreSQL Row Security Policies: https://www.postgresql.org/docs/current/ddl-rowsecurity.html
