# ADR-029: Disaster Recovery — objetivos RTO < 1h / RPO ~0 y recuperabilidad del backend

**Status:** Accepted
**Date:** 2026-06-02
**Author:** Daniel Hidalgo Carrasco
**Tags:** disaster-recovery, rto, rpo, backfill, indexer, supabase, pitr, read-replica, audit-log, arweave, kms, runbooks, backend-fase2
**Resuelve:** DR-01 (sin objetivos RTO/RPO definidos), DR-02 (sin procedimiento de recuperación de DB / read model / clave del signer), DR-03 (incident response §17.6 sin recuperabilidad)
**Relacionado:** ADR-024 (Goldsky-en-Plume + ingestión — el backfill depende del indexer), ADR-022 (recuperación de la clave del `BACKEND_SIGNER` vía GCP Cloud KMS), ADR-025 (finalidad/reorg — el recompute converge al mismo estado que el backfill desde `startBlock`), ADR-020 (custodia HOT/COLD — qué claves hay que recuperar), CIS §5 (event catalog exhaustivo = base del backfill), ARQUITECTURA-TECNICA-MVP §17.6 (incident response plan), ARQUITECTURA-BACKEND-FASE2 §1.2 (read path: indexer + read model)
**Supersedes:** N/A
**Superseded by:** N/A

---

## Context

El plan de respuesta a incidentes existente (ARQUITECTURA-TECNICA-MVP §17.6) enumera **procedimientos de contención** —`pause()` ante emergencia, rotación de claves comprometidas, `swapOwner` en el Safe ante pérdida de hardware wallet, comunicación a usuarios— pero **no define objetivos de recuperabilidad ni un procedimiento de restauración**. El audit de cobertura de Fase 2 marcó este hueco: el sistema sabe cómo **detener el daño**, pero no tiene una respuesta documentada y medible a la pregunta operacional básica de disaster recovery: **¿cuánto tarda en volver a operar (RTO) y cuántos datos puede perder (RPO) tras una pérdida total de la capa de backend?**

Una afirmación de control sin objetivos medibles ni runbook que la respalde no es un control. El §17.6 dice "documentar y ensayar trimestralmente" pero no nombra qué se restaura ni con qué garantía.

### El hueco que cierra (traído del audit de cobertura)

La capa de backend de Fase 2 tiene cuatro activos de estado, con propiedades de recuperabilidad **muy distintas** que el §17.6 nunca distinguió:

1. **Read model Postgres** (`holding`, `lote_proyeccion`, `redencion_proyeccion`, `kyc_mirror`, escrow espejo — ARQUITECTURA-BACKEND-FASE2 §1.2). Proyección servible derivada del log on-chain.
2. **Datos off-chain operacionales** (referencias Sumsub, shipping, payment refs) que el subgraph NO tiene y que NO viven on-chain.
3. **`audit_log`** append-only con hash chain (CLAUDE.md §9; ARQUITECTURA §"audit/").
4. **La clave del `BACKEND_SIGNER`** (el único rol HOT, ADR-020) y las seeds del Safe 2-de-3.

La fortaleza estructural que el §17.6 no aprovechaba: **el read model es 100% reconstruible desde la cadena**. El CIS §5 cataloga de forma exhaustiva cada evento de dominio de los 3 contratos, y la regla rectora del read path es "ante divergencia cache vs cadena, gana la cadena" (CIS §3). Eso convierte al read model en **desechable y reconstruible**: no es un activo a respaldar, es una proyección a recomputar. El audit de cobertura pedía formalizar exactamente esto — declararlo como propiedad de DR, no como accidente afortunado.

---

## Decision

Se adoptan **objetivos agresivos de disaster recovery para la capa de backend: RTO < 1 hora y RPO ~0** (pérdida de datos prácticamente nula). Estos objetivos se sostienen sobre cinco mecanismos, uno por activo de estado más los runbooks que los operan.

### 1. DB operacional — Supabase PITR + read replica cross-region

La parte NO reconstruible-por-log de la DB (datos off-chain del punto 2, más el `audit_log`) se protege con **Point-in-Time-Recovery (PITR)** de Supabase y una **read replica cross-region**:

- **PITR** da RPO ~0 para la DB operacional: permite restaurar a cualquier instante (granularidad de segundos) hasta el punto del incidente, sin depender de snapshots discretos.
- La **read replica cross-region** da disponibilidad y failover rápido: si la región primaria cae, se promociona la réplica, manteniendo el RTO por debajo de 1h sin esperar una restauración completa desde backup.

### 2. Read model — reconstruible 100% por backfill desde `startBlock`

El read model **NO se restaura desde backup: se recomputa desde la cadena**. El backfill arranca en el `startBlock` del deploy —**`23675712` en Plume testnet (chainId `98867`)**— y reproyecta TODO el catálogo de eventos del CIS §5 sobre Postgres, con idempotencia por `(chainId, txHash, logIndex)` (la misma propiedad que hace seguro el recompute por reorg de ADR-025).

**Única excepción NO reconstruible-por-log:** `hashFotosApiario` y `tipoCertificadoOrigen`. Son storage que `confirmarCosecha` escribe pero NO emite en `CosechaConfirmada` (asimetría storage-vs-evento documentada en CIS §5.1). Se resincronizan llamando `lotes()` **live** sobre el contrato durante el backfill — un read puntual por lote, no un log a reproyectar.

Esta es la fortaleza estructural de DR: **el backend es desechable**. Perder el read model entero no es un incidente de datos, es un job de reproyección.

### 3. `audit_log` — hash chain + snapshot mensual a Arweave

El `audit_log` es append-only con **hash chain** (cada fila contiene el hash de la anterior → detecta manipulación retroactiva, CLAUDE.md §9). Para DR se le suma un **snapshot mensual a Arweave** (almacenamiento permanente, inmutable, descentralizado — el job `audit-snapshot.ts`, ARQUITECTURA §"Audit snapshot, Día 1 mensual"). El snapshot a Arweave es la copia anti-manipulación de último recurso: aunque se comprometa la DB y la réplica, el audit trail tiene un ancla inmutable fuera de nuestra infra.

### 4. Recuperación de la clave del `BACKEND_SIGNER` — GCP Cloud KMS, NO escrow físico

La clave del único rol HOT (`BACKEND_SIGNER`, ADR-020) vive en **GCP Cloud KMS** (ADR-022) y NUNCA se materializa. Su recuperabilidad se apoya en la infra nativa de Cloud KMS: **versiones de clave (`cryptoKeyVersions`), políticas IAM y backup de la configuración** (keyring, cryptoKey, bindings IAM como infraestructura versionada). No hay "restaurar la clave" en el sentido tradicional: la clave nunca sale de KMS, así que la recuperación es restaurar el **acceso** (IAM + referencia a la versión correcta en `BACKEND_SIGNER_KMS_KEY_ID`), no el material criptográfico.

**El escrow físico NO aplica a esta clave.** El escrow notarial físico está reservado **únicamente para las seeds del Safe 2-de-3** (ARQUITECTURA §17.2, "Backup seeds del Safe → escrow notarial físico, solo en caso de pérdida"). Confundir ambos mecanismos sería un error: la clave HOT se recupera por IAM/KMS; las seeds COLD del Safe por escrow físico.

### 5. Runbooks en `docs/runbooks/` + ensayo trimestral

Los procedimientos del §17.6 se materializan como runbooks ejecutables en `docs/runbooks/`, cubriendo como mínimo: `pause()` de emergencia, rotación de claves comprometidas, `swapOwner` del Safe, y **restore de DB** (PITR + promoción de réplica + lanzamiento del backfill). Se **ensayan trimestralmente** (el §17.6 ya manda el ensayo; este ADR fija qué se ensaya y contra qué objetivo: medir RTO real < 1h y verificar RPO ~0 en el simulacro).

---

## Alternatives considered

### A — Snapshots discretos de DB (diarios) sin PITR ni read replica (rechazada)

El patrón clásico: backup completo nocturno, restaurar el último snapshot ante incidente.

**Por qué se rechazó:**
- ❌ **RPO inaceptable** — un snapshot diario implica perder hasta 24h de datos off-chain (Sumsub refs, shipping, payment refs) ante un incidente justo antes del próximo backup. Contradice el objetivo RPO ~0.
- ❌ **RTO alto** — restaurar un dump completo + replay no cabe holgadamente en < 1h a medida que crece el volumen.
- ⚠️ Se conserva como **defensa adicional** (los snapshots de Supabase siguen existiendo por debajo de PITR), pero NO como mecanismo primario.

### B — Respaldar el read model como dato crítico (backups dedicados del Postgres servible) (rechazada)

Tratar `holding`/`lote_proyeccion`/etc. como activo a respaldar con su propia política de backup.

**Por qué se rechazó:**
- ❌ **Malgasta esfuerzo en un activo desechable** — el read model es derivable al 100% desde el log on-chain (CIS §5 + backfill). Respaldarlo es redundante: la fuente de verdad es la cadena, no el backup.
- ❌ **Riesgo de divergencia** — restaurar un read model viejo desde backup viola "gana la cadena" (CIS §3): podría servir un estado stale que contradice on-chain. El backfill, en cambio, converge SIEMPRE al estado canónico.
- ✅ La alternativa correcta es el mecanismo 2: NO respaldar, reproyectar.

### C — Escrow físico de la clave del `BACKEND_SIGNER` (rechazada)

Aplicar el mismo escrow notarial físico de las seeds del Safe a la clave del signer HOT.

**Por qué se rechazó:**
- ❌ **Contradice ADR-022 y CLAUDE.md §9** — la clave del signer vive en GCP Cloud KMS y NUNCA se materializa fuera de él. Sacarla para meterla en un escrow físico la materializaría, anulando la garantía central de ADR-022.
- ❌ **Confunde dos modelos de custodia distintos** — el escrow físico es para seeds COLD (Safe 2-de-3), donde el material SÍ es exportable y la recuperación humana multi-firma es el diseño. Para la clave HOT en KMS, la recuperación correcta es IAM + versiones de clave.

### D — Multi-region activo-activo de toda la infra (rechazada para el MVP)

Replicar backend + DB + indexer en dos regiones activas simultáneamente.

**Por qué se rechazó:**
- ❌ **Sobredimensionado para el MVP** — el RTO < 1h se alcanza con PITR + read replica + backfill, sin el costo y la complejidad operacional de activo-activo (coordinación de nonce del relayer HOT entre regiones, doble ingestión).
- ⚠️ Evaluable en una fase posterior si el SLA de negocio lo exige; queda fuera del alcance de este ADR.

---

## Consequences

### Positive

1. **Objetivos de DR medibles y agresivos** — RTO < 1h y RPO ~0 dejan de ser aspiración: cada activo tiene un mecanismo concreto que los sostiene, y el ensayo trimestral los verifica empíricamente.
2. **El backend es desechable y reconstruible** — la propiedad estructural más fuerte del DR: perder el read model entero es un job de backfill desde `startBlock`, no un incidente de pérdida de datos. La cadena ES el backup del estado derivable.
3. **RPO ~0 real para lo NO reconstruible** — PITR (granularidad de segundos) protege los datos off-chain que NO viven on-chain; no hay ventana de pérdida de 24h como con snapshots discretos.
4. **Audit trail con ancla inmutable externa** — el snapshot mensual a Arweave + hash chain garantizan que el `audit_log` sobrevive y es verificable aunque se comprometa toda la infra propia.
5. **Recuperación de clave alineada con la postura de seguridad** — la clave HOT se recupera por IAM/KMS sin materializarse nunca (ADR-022); las seeds COLD por escrow físico. Cada modelo de custodia mantiene su mecanismo de recuperación coherente.
6. **Runbooks ejecutables, no prosa** — los procedimientos del §17.6 pasan de enumeración a runbooks versionados en `docs/runbooks/`, ensayados contra objetivos numéricos.

### Negative

1. **Costo/infra sube — confirmar presupuesto** — RTO < 1h / RPO ~0 exige PITR (retención + storage) y read replica cross-region (cómputo + egress entre regiones) de Supabase. Es el tradeoff explícito de objetivos agresivos. **Pendiente: confirmación de presupuesto** antes de habilitar PITR + cross-region en producción.
2. **El backfill depende de Goldsky/indexer (ADR-024)** — la reconstrucción del read model asume que el indexer está disponible y soporta Plume. Si Goldsky cae junto con el incidente, el backfill se degrada al fallback de ADR-024 (The Graph / self-hosted), lo que puede empujar el RTO por encima de 1h. Esta dependencia debe monitorearse como parte del DR.
3. **El backfill no es instantáneo** — reproyectar TODO el catálogo §5 desde `startBlock` toma tiempo proporcional al volumen on-chain. Para el MVP cabe en el RTO; a medida que crece el historial, hay que vigilar que el backfill completo siga entrando en < 1h (mitigación futura posible: checkpoints/snapshots periódicos del read model como punto de partida del backfill, sin contradecir "gana la cadena").
4. **Resync de `hashFotosApiario`/`tipoCertificadoOrigen` por reads live** — la única excepción NO reconstruible-por-log obliga a un `lotes()` live por lote durante el backfill, que depende del RPC de Plume (ADR-023). Es acotado (un read por lote) pero suma a la ruta crítica del restore.

### Neutral

1. **No cambia el authority boundary** — el DR restaura disponibilidad y datos derivados; NO altera qué es autoritativo. La cadena sigue siendo la fuente de verdad de balances/estado on-chain (CIS §9); el read model recuperado es proyección, no autoridad.
2. **Los snapshots de Supabase coexisten con PITR** — PITR es el mecanismo primario; los snapshots por debajo quedan como defensa adicional, no como contradicción.
3. **El ensayo trimestral ya estaba mandado por §17.6** — este ADR no agrega una cadencia nueva, fija el **contenido** del ensayo (medir RTO/RPO reales) sobre la cadencia existente.

---

## Implementation notes

Capa de backend Bun + Hono + Drizzle + viem (ARQUITECTURA-BACKEND-FASE2):

- **PITR + read replica (Supabase):** configuración de plataforma, no código de aplicación. Se habilita PITR sobre el proyecto Supabase y se provisiona la read replica cross-region. El backend NO necesita cambios de código para PITR; sí para failover de réplica (la cadena de conexión Drizzle debe poder repuntar a la réplica promovida — config de `DATABASE_URL` / pooler, sin lógica de dominio).
- **Backfill (`reconstruirReadModel`, OS-2.3):** ya existe como objetivo en ARQUITECTURA-BACKEND-FASE2 (checklist ítem 19). Arranca en `startBlock = 23675712` (testnet 98867), consume el catálogo §5 vía el cliente GraphQL/webhook de Goldsky (ADR-024) y reproyecta con idempotencia `(chainId, txHash, logIndex)`. Vive en el submódulo `indexing/` (`application` → `reconstruirReadModel`). El resync de `hashFotosApiario`/`tipoCertificadoOrigen` se hace con `lotes()` live (viem, `blockTag: "latest"`, RPC vía ADR-023) por cada `loteId` proyectado.
- **`audit_log` snapshot a Arweave:** job mensual `audit-snapshot.ts` (ARQUITECTURA §"scripts"), firma el fondeo del upload con `IRYS_FUNDING_WALLET_KMS_KEY_ID` (misma custodia KMS de ADR-022). El snapshot incluye el último hash de la cadena para poder verificar continuidad al restaurar. La policy Postgres append-only (REVOKE UPDATE/DELETE, CLAUDE.md §9) se preserva tras cualquier restore.
- **Recuperación de la clave HOT:** runbook de IAM/KMS — restaurar bindings IAM sobre el keyring/cryptoKey del `BACKEND_SIGNER`, verificar que `BACKEND_SIGNER_KMS_KEY_ID` apunta a la `cryptoKeyVersion` correcta, y confirmar en el bootstrap fail-fast que la address derivada (`GetPublicKey` → `keccak256(pubkey)[12:]`) coincide con `BACKEND_SIGNER_ADDR` (ADR-022). La config de KMS (keyring/key/IAM) se versiona como infraestructura.
- **Runbooks (`docs/runbooks/`):** crear el directorio (hoy inexistente) con, como mínimo: `pause-emergencia.md`, `rotacion-claves.md`, `swap-owner-safe.md`, `restore-db.md` (PITR + promoción de réplica + lanzamiento de backfill + verificación de conciliación `suma(holdings)==totalSupply`). Cada runbook declara el objetivo medible (RTO < 1h, RPO ~0) y el criterio de éxito del ensayo trimestral.
- **Validación post-restore:** reusar el job BullMQ de conciliación de §1.2 (`suma de holdings == totalSupply(loteId)`, escrow espejo == on-chain) como gate de "restore completo": el read model recuperado solo se declara servible cuando concilia con la cadena.

---

## References

- `docs/architecture/ARQUITECTURA-TECNICA-MVP.md` §17.6 (incident response plan — `pause()`, rotación de claves, `swapOwner`, comunicación; este ADR le agrega recuperabilidad y objetivos)
- `docs/architecture/ARQUITECTURA-TECNICA-MVP.md` §17.2 (gestión de secretos — "Backup seeds del Safe → escrow notarial físico"; DB en Supabase + secret manager)
- `docs/architecture/ARQUITECTURA-BACKEND-FASE2.md` §1.2 (read path: indexer + read model; backfill desde `startBlock`; conciliación; `reconstruirReadModel` OS-2.3)
- `docs/architecture/CIS-v1.md` §5 (event catalog exhaustivo — base del backfill; asimetría `hashFotosApiario`/`tipoCertificadoOrigen` storage-vs-evento, §5.1)
- `docs/architecture/CIS-v1.md` §3 / §9 (regla "gana la cadena"; authority boundary — el read model es proyección, no autoridad)
- ADR-024 (Goldsky-en-Plume + ingestión — el backfill depende del indexer; fallback si Goldsky no soporta Plume)
- ADR-025 (finalidad/reorg — el recompute por reorg converge al mismo estado que el backfill desde `startBlock`; idempotencia `(chainId, txHash, logIndex)`)
- ADR-023 (RPC Plume + failover — los reads live de `lotes()` durante el resync dependen del transport viem)
- ADR-022 (GCP Cloud KMS — recuperación de la clave del `BACKEND_SIGNER` por IAM + versiones, NO escrow; `IRYS_FUNDING_WALLET_KMS_KEY_ID` para el snapshot a Arweave)
- ADR-020 (custodia HOT/COLD — `BACKEND_SIGNER` es la única clave HOT a recuperar; las seeds del Safe 2-de-3 son COLD)
- CLAUDE.md §9 (seguridad operacional — `audit_log` append-only con hash chain, snapshot mensual a Arweave, llaves en HSM/KMS)
