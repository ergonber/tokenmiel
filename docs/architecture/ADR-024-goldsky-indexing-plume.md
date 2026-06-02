# ADR-024: Indexación con Goldsky subgraph (managed) sobre Plume + ingestión por push-webhook

**Status:** Accepted
**Date:** 2026-06-02
**Author:** Daniel Hidalgo Carrasco
**Tags:** indexing, goldsky, subgraph, plume, read-path, webhook, reorg, finality, backend-fase2, no-custom-indexer
**Resuelve:** OPEN TOPIC "ADR-024 — Goldsky en Plume + ingestión" (ARQUITECTURA-BACKEND-FASE2 §7), OS-5.5
**Relacionado:** ADR-001 (multi-chain: Plume primaria, Goldsky como indexer ya nombrado), ADR-019 (eventos de dominio para observabilidad del indexer), ADR-023 (RPC Plume + failover), ADR-025 (finalidad/reorg en Plume — `CONFIRMACIONES_FINALIDAD`), ARQUITECTURA-BACKEND-FASE2 §15 + §18.1, CIS v1 §5
**Supersedes:** N/A
**Superseded by:** N/A

---

## Context

El read path de la Fase 2 (`ARQUITECTURA-BACKEND-FASE2.md` §1.2) parte de un principio rector heredado de la **CIS v1**: **el read model se reconstruye 100% desde el log on-chain**; ante divergencia cache vs cadena, **gana la cadena**, y el backend nunca es la fuente de verdad de balances, lotes ni redenciones. Para que eso funcione hace falta una pieza que **decodifique los logs de los 3 contratos del MVP** (`AssetVault`, `IdentityRegistry`, `RedemptionManager`), maneje finalidad/reorg, y entregue los eventos del catálogo CIS §5 a la proyección Postgres servible.

Esa pieza ya tiene nombre en los documentos rectores: **Goldsky subgraph (managed)**. ADR-001 §"Implementation notes" lo lista explícitamente (`Indexer: Goldsky subgraph para Plume`), y la tabla de decisiones de `ARQUITECTURA-BACKEND-FASE2` §0 lo fija con procedencia `§15 + §18.1 + ADR-001`. La §18.1 además declara una **prohibición dura**: dentro de las "Contradicciones a evitar (NO hacer)" figura *"indexer custom paralelo a Goldsky"*. O sea: la elección de Goldsky NO se re-decide; lo que quedaba abierto era otra cosa.

### El hueco concreto que cierra este ADR

El audit de cobertura de la Fase 2 (`ARQUITECTURA-BACKEND-FASE2` §7, fila **ADR-024**) dejó dos preguntas SIN cerrar que **bloquean el wiring del read path**:

1. **¿Goldsky soporta Plume?** Los argumentos a favor de Goldsky en §15.3 estaban escritos pensando en **Polygon** (fase 8+), no en Plume (la chain primaria, ADR-001). Si Goldsky NO soportara Plume, todo el read path caería al fallback (The Graph / self-hosted graph-node), y un graph-node self-hosted ES exactamente el *"indexer custom paralelo"* que §18.1 prohíbe sin ADR. La pregunta no era cosmética: definía si la arquitectura de lectura era viable tal como está escrita.

2. **¿Cómo ingiere el backend lo que Goldsky decodifica — push o pull?** La topología §1.2 dice *"Goldsky (GraphQL + push-webhook) → submódulo de ingestión `indexing/` → Postgres read model (Drizzle)"*, pero ofrece **dos transportes**: polling del endpoint GraphQL o suscripción por webhook. La §7 lo plantea como trade-off abierto: *"Push = menor latencia / mejor manejo de reorg; polling = más simple pero más latencia"*. Sin decidirlo, el submódulo `indexing/` no se puede implementar (OS-2.3).

El estado de deploy refuerza la urgencia: los 3 contratos ya están **deployados en Plume testnet (chainId 98867) el 2026-06-01** (CIS v1 §1), y la proyección completa del ciclo de redención `ALMACENADO → REDENCION_PARCIAL → AGOTADO` depende del evento `TokensRedimidos` que ADR-019 agregó pre-deploy (GAP-2). El indexer no puede arrancar hasta resolver sobre qué red corre y cómo recibe los eventos.

---

## Decision

Se confirma **Goldsky subgraph (managed)** como el ÚNICO indexer del MVP, corriendo sobre **Plume** (testnet 98867 ya, mainnet 98866 al deploy), suscrito a los 3 `dataSources` del catálogo CIS §5; y se adopta **ingestión por push-webhook** (Goldsky → submódulo `indexing/`) en lugar de polling GraphQL. NO se construye ningún indexer custom paralelo — la prohibición de §18.1 se respeta al pie.

### 1. Goldsky soporta Plume — confirmado

Goldsky lista **Plume Network** en su catálogo de redes soportadas para subgraphs (`docs.goldsky.com/chains/supported-networks`) y mantiene una landing dedicada `goldsky.com/chains/plume`. La premisa de §15.3 (argumentada sobre Polygon) se extiende a Plume sin cambios: Goldsky es chain-agnóstico para EVM y Plume es una L2 EVM. **No se activa el fallback**, así que NO se dispara la prohibición de indexer paralelo de §18.1.

**PENDIENTE menor (no bloquea esta decisión):** confirmar puntualmente el soporte de **testnet 98867** (la confirmación documentada cubre la familia Plume; falta el datapoint exacto de testnet vs solo mainnet 98866). Si el testnet no estuviera disponible como red managed, el **fallback acotado** es: (a) indexar contra **mainnet** una vez deployado, operando en testnet con reads live `viem` mientras tanto; o (b) **self-hosted graph-node SOLO para testnet** — y esa segunda opción, por ser un indexer fuera de Goldsky, **requeriría un ADR propio** (per §18.1). El happy path es Goldsky managed en ambas redes.

### 2. Topología de ingestión: push-webhook

```
Plume (98867/98866)
   → Goldsky subgraph managed (3 dataSources, decodifica logs + maneja reorg)
      → push-webhook  ──HTTP POST (firmado)──▶  submódulo indexing/ (apps/api)
         → proyectarEvento (valida máquina de estados §8)
            → Postgres read model (Drizzle): holding, lote_proyeccion,
              redencion_proyeccion, kyc_mirror, transfer_log, config_onchain, admin_mirror
```

- El **subgraph** define un `dataSource` por contrato (las 3 addresses de CIS §1, chainId 98867) con `startBlock` = bloque de deploy (2026-06-01). Decodifica **TODO el catálogo de eventos CIS §5** (handlers generados **desde el ABI**, no de la prosa — cubre GAP-5; `AssetVault` 26 eventos, `IdentityRegistry` 17, `RedemptionManager` 15).
- Goldsky **empuja** cada cambio de entity al endpoint webhook del backend. El submódulo `indexing/` lo recibe, valida la transición contra las máquinas de estado §8, y materializa a las tablas Drizzle con idempotencia por `(chainId, txHash, logIndex)`.

### 3. Por qué push y no polling

- **Menor latencia** — el evento llega cuando ocurre, sin el lag del intervalo de poll. Importa para confirmar tx: el write path (§1.3) marca el estado de dominio efectivo **solo cuando ve el evento indexado** (no en el receipt); push acorta esa ventana.
- **Mejor manejo de reorg** — Goldsky empuja rollbacks de entities cuando hay reorg; el push transmite el evento de rollback directamente, en vez de que el backend lo infiera comparando snapshots de polls sucesivos.
- **Sin estado de cursor frágil** — el polling obliga a llevar un cursor (`lastSyncedBlock`) y a paginar; el push delega el seguimiento a Goldsky y deja al backend como receptor idempotente.

El read model Postgres mantiene su **segunda barrera de finalidad** independiente del transporte: solo materializa a las tablas servibles eventos con `headBlock - eventBlock >= CONFIRMACIONES_FINALIDAD` (el valor `N` lo fija **ADR-025**, finalidad/reorg en Plume). Push vs polling NO cambia esta regla — cambia cómo llega el evento, no cuándo se considera servible.

---

## Alternatives considered

### Polling del endpoint GraphQL de Goldsky (rechazada)

El submódulo `indexing/` consulta periódicamente el GraphQL del subgraph (`query { ... where blockNumber_gt: $cursor }`) y proyecta los deltas.

**Por qué se rechazó:**
- ❌ **Más latencia** — el evento se ve recién en el siguiente tick del poll; degrada la confirmación de tx del write path (que depende de ver el evento, no el receipt).
- ❌ **Manejo de reorg más débil** — el backend tendría que detectar el rollback comparando resultados de polls sucesivos, en vez de recibir el evento de rollback que Goldsky empuja.
- ❌ **Cursor frágil** — exige llevar y persistir `lastSyncedBlock`, paginar, y recuperarse de gaps; superficie de bug propia.
- ✅ Único punto a favor: más simple de arrancar (no requiere exponer un endpoint público firmado). Insuficiente frente a la latencia y el reorg.

> Nota: GraphQL **NO desaparece**. Sigue disponible para queries ad-hoc, backfill desde `startBlock` y conciliación. La decisión es sobre el **transporte de ingestión continua** (push), no sobre eliminar el acceso GraphQL.

### Indexer custom / self-hosted graph-node como camino primario (rechazada)

Operar un `graph-node` propio (o un indexer a medida sobre `viem`/`eth_getLogs`) en vez de Goldsky managed.

**Por qué se rechazó:**
- ❌ **Viola §18.1 directamente** — *"indexer custom paralelo a Goldsky"* está en la lista de "NO hacer". Adoptarlo como primario requeriría revertir ADR-001 y §15, no un ADR nuevo de detalle.
- ❌ **Reinventa finalidad/reorg** — Goldsky ya resuelve rollback de entities nativamente; un indexer propio tendría que reimplementar esa lógica (cara y propensa a bugs en una L2 joven).
- ❌ **Carga operacional** — infra de indexación a mantener (sync, RPC, almacenamiento, alta disponibilidad) que Goldsky ofrece managed.
- ✅ Solo se contempla como **fallback acotado a testnet** si Goldsky no soportara 98867 — y en ese caso se formaliza con su propio ADR (ver PENDIENTE menor en Decision §1).

### The Graph descentralizado (rechazada como primario)

Publicar el subgraph en la red descentralizada de The Graph en vez de Goldsky.

**Por qué se rechazó:**
- ❌ **Plume no está garantizado** en la red descentralizada de The Graph; Goldsky sí lo lista. La cobertura de chains es justamente el criterio que motivó este ADR.
- ❌ **Webhooks/mirroring** — el push-webhook a infra propia y el mirroring son features de Goldsky; The Graph descentralizado no los ofrece de la misma forma.
- ✅ Se mantiene como **respaldo documentado** (igual que en §0), no como primario.

---

## Consequences

### Positive

1. **Read path desbloqueado** — con Goldsky-en-Plume confirmado y push-webhook decidido, el submódulo `indexing/` (OS-2.3) y el subgraph (OS-2.1) se pueden implementar sin esperar más decisiones de transporte.
2. **§18.1 respetada** — al confirmarse Goldsky managed, NO se cae al fallback self-hosted; la prohibición de indexer custom paralelo queda intacta y no hace falta justificar una excepción.
3. **Latencia mínima de confirmación** — el push entrega el evento apenas ocurre; el write path confirma el estado de dominio (que depende de ver el evento, no el receipt) con la menor demora posible.
4. **Reorg manejado en la fuente** — Goldsky empuja rollbacks de entities; el backend los recibe en vez de inferirlos, y los compone con su segunda barrera de finalidad (`CONFIRMACIONES_FINALIDAD`, ADR-025).
5. **Cero infra de indexación propia** — sin graph-node que operar; el equipo mantiene el submódulo de ingestión y los handlers, no la capa de sync/RPC/almacenamiento.
6. **Backfill y conciliación intactos** — GraphQL sigue disponible para reconstruir TODO desde `startBlock` y para el job BullMQ de conciliación (`suma de holdings == totalSupply(loteId)`, escrow espejo == on-chain).

### Negative

1. **Endpoint webhook público a asegurar** — el push obliga a exponer un endpoint HTTP receptor. Hay que validar **firma del webhook de Goldsky** ANTES de procesar (mismo patrón HMAC-first que el webhook de Sumsub, §1.4), idempotencia por `(chainId, txHash, logIndex)`, y rechazar payloads no firmados. Es superficie de ataque nueva, mitigada por el patrón ya establecido en el proyecto.
2. **Acoplamiento a Goldsky como vendor managed** — disponibilidad y SLA del read path quedan atados a un proveedor externo. Mitigado: el subgraph es portable (mismo manifiesto corre en The Graph o graph-node self-hosted), y GraphQL permite re-backfill completo desde `startBlock` ante un corte; la migración de vendor no perdería datos porque la fuente de verdad sigue siendo la cadena.
3. **PENDIENTE testnet 98867 sin cerrar** — la confirmación cubre Plume mainnet/familia; falta el datapoint puntual de testnet managed. Si faltara, dispara el fallback acotado (mainnet-only o graph-node testnet con ADR propio). No bloquea la decisión, pero es un check obligatorio antes de wirear el subgraph a 98867.

### Neutral

1. **GraphQL no se elimina** — push es el transporte de ingestión continua; GraphQL queda para backfill, conciliación y queries ad-hoc. Ambos coexisten contra el mismo subgraph.
2. **`startBlock` por red** — el subgraph en testnet usa el bloque de deploy 2026-06-01; al deployar a mainnet (98866) se define un nuevo `startBlock` y se recalcula el pin de bytecode/ABI (CIS §2). El manifiesto del subgraph se versiona por red, no por upgrade (los contratos son inmutables, ADR-003).
3. **Dependencia transversal con ADR-019** — la proyección `REDENCION_PARCIAL → AGOTADO` y el `kgRedimidos` acumulado existen SOLO porque `TokensRedimidos` se agregó pre-deploy (GAP-2). Antes de indexar mainnet hay que verificar que el bytecode desplegado a 98866 incluye ADR-019; si no, el read path tendría el punto ciego que GAP-2 resolvió.

---

## Implementation notes

### Submódulo `indexing/` (apps/api, hexagonal)

Per §1.2 ("Encaje"), el submódulo respeta la estructura por capas del monolito modular:

- **`domain`** — invariantes de transición de las máquinas de estado §8 (valida cada proyección antes de materializar; defensa ante reorg mal aplicado).
- **`application`** — casos de uso `proyectarEvento`, `reconstruirReadModel` (backfill), `conciliarConCadena` (job BullMQ de conciliación).
- **`infrastructure`** — **webhook handler** del push de Goldsky (Hono route con validación de firma HMAC-first), cliente **GraphQL** Goldsky para backfill/queries, **repos Drizzle** de las 7 tablas de proyección, y **`viem`** para los reads live (campos no indexables por log: `hashFotosApiario`, `tipoCertificadoOrigen` → hidratar de `lotes()`).
- **`api`** — endpoints con validación **Zod** (incluido el receptor del webhook).

Reusa `viem` (reads live), `audit/` (hash chain para eventos sensibles) y `notifications/` (alertas de divergencia).

### Webhook handler — orden NO negociable (espejo del patrón Sumsub §1.4)

1. **Validar firma** del webhook de Goldsky sobre el raw body ANTES de parsear (falla → 401, no procesa).
2. **Idempotencia** por `(chainId, txHash, logIndex)` (`INSERT ... ON CONFLICT DO NOTHING`).
3. **Zod** del payload, persistir crudo.
4. **Proyectar** validando la máquina de estados §8; materializar solo eventos con finalidad (`headBlock - eventBlock >= CONFIRMACIONES_FINALIDAD`, ADR-025).
5. Responder **200 rápido**; el trabajo pesado va a cola BullMQ.

NUNCA se firma ni se emite una tx dentro del handler del webhook.

### Subgraph manifest (OS-2.1)

- 3 `dataSources` (una por contrato, addresses de CIS §1), `network: plume` (variante testnet/mainnet por chainId), `startBlock` = bloque de deploy.
- Handlers generados **desde el ABI congelado** (`packages/abis/*.abi.json`), no de la prosa — garantiza cubrir el catálogo §5 completo incluido el evento omitido en la prosa (GAP-5: `DefaultAdminDelayChangeCanceled`).
- Entities espejo de las tablas de proyección Drizzle; idempotencia y procedencia (`chainId`, `blockNumber`, `logIndex`, `txHash`).

### Config

- `GOLDSKY_WEBHOOK_SECRET` (validación de firma del push) — secret, NUNCA en env de prod en claro (per CLAUDE.md §9 / ADR-022).
- `GOLDSKY_GRAPHQL_URL` (backfill/conciliación).
- `CONFIRMACIONES_FINALIDAD` (`N`) — definido por **ADR-025**, no por este ADR.

### Checklist pre-mainnet

- [ ] Confirmar soporte managed de **testnet 98867** en Goldsky (si no → fallback acotado, ver Decision §1).
- [ ] Verificar que el bytecode deployado a 98866 incluye los 3 eventos de ADR-019 (sin esto, GAP-2 reaparece).
- [ ] Recalcular `startBlock` y pin de bytecode/ABI para las addresses de mainnet (CIS §2).

---

## References

- `docs/architecture/ARQUITECTURA-BACKEND-FASE2.md` §0 (tabla de decisiones: Goldsky con procedencia §15 + §18.1 + ADR-001), §1.2 (read path: topología Goldsky → `indexing/` → Postgres; catálogo de eventos a suscribir; reorgs/finalidad), §1.3 (write path: confirmación = ver el evento indexado, no el receipt), §7 (OPEN TOPIC "ADR-024 — Goldsky en Plume + ingestión"; este ADR lo cierra), §18.1 (prohibición de indexer custom paralelo)
- `docs/architecture/CIS-v1.md` §1 (deploy a Plume testnet 98867, 2026-06-01; addresses), §2 (pin de bytecode/ABI), §5 (EVENT CATALOG — la fuente de los handlers del subgraph), §8 (máquinas de estado que `proyectarEvento` valida)
- ADR-001 (multi-chain: Plume primaria; "Indexer: Goldsky subgraph para Plume" en Implementation notes)
- ADR-019 (eventos de dominio para observabilidad del indexer — `RedemptionManagerSet`, `TokensRedimidos`, `ReembolsoFinalizado`; sin ellos el read path tiene el punto ciego GAP-2)
- ADR-023 (RPC Plume + failover — el `viem` transport con `fallback()` que el submódulo usa para reads live)
- ADR-025 (finalidad/reorg en Plume — fija `CONFIRMACIONES_FINALIDAD`, la segunda barrera del read model)
- Goldsky — supported networks (Plume listado): https://docs.goldsky.com/chains/supported-networks
- Goldsky — Plume Network indexing: https://goldsky.com/chains/plume
