# ADR-025: Finalidad y manejo de reorg en Plume

**Status:** Accepted
**Date:** 2026-06-02
**Author:** Daniel Hidalgo Carrasco
**Tags:** finality, reorg, plume, l2-sequencer, read-model, indexer, viem, blocktag, cctp, idempotencia
**Resuelve:** OS-2.4 (barrera de finalidad N-confirmaciones + mecánica de reorg) y OS-5.5 (ADR de finalidad/reorg en Plume) de ARQUITECTURA-BACKEND-FASE2
**Relacionado:** ADR-024 (RPC Plume + failover), CIS §8 (state machines), CIS §1.2 read path, ARQUITECTURA-BACKEND-FASE2 §1.2 (read path: indexer + read model)
**Supersedes:** N/A
**Superseded by:** N/A

---

## Context

El read path del backend (CIS §1.2, ARQUITECTURA-BACKEND-FASE2 §1.2) convierte el log on-chain en proyecciones servibles (`holding`, `lote_proyeccion`, `redencion_proyeccion`, `kyc_mirror`, escrow espejo). La regla rectora invariante es **"ante divergencia cache vs cadena, gana la cadena"** (CIS §3, Matriz source-of-truth): el backend NUNCA es autoritativo de balances, plata ni transición de estado on-chain. Pero esa regla deja abierta una pregunta operacional que el audit de cobertura de Fase 2 marcó como **bloqueante para mainnet**: ¿qué es exactamente "la cadena"? ¿La cabeza del sequencer, que puede reorganizarse, o un punto más profundo y estable?

La §1.2 ya esboza la respuesta ("el read path NUNCA proyecta en head"; "dos zonas: confirmada y pendiente/optimista") pero deja el valor concreto como **decisión abierta** — literalmente `CONFIRMACIONES_FINALIDAD` "por config — ADR abierto" (§1.2) y "el ADR de finalidad/reorg en Plume (valor de `CONFIRMACIONES_FINALIDAD`)" (OS-5.5). Este ADR cierra ese hueco.

### El hueco que cierra (traído del audit de cobertura)

Plume es un **L2 EVM con sequencer**. Tiene tres "niveles de finalidad" muy distintos que el código de Fase 2 estaba colapsando en un único parámetro ambiguo:

1. **Confirmación soft del sequencer (~250ms):** el sequencer ordena y promete inclusión, pero esto NO es finalidad — es una promesa que el operador del sequencer puede romper (reorg de secuenciado, recovery tras un fallo, o reordenamiento durante un upgrade).
2. **Finalidad práctica de terceros:** Circle (CCTP) trata a Plume como **1 confirmación / ~8s** para sus propósitos. Es un punto de referencia útil de "suficientemente firme para la mayoría de los flujos", pero NO es finalidad absoluta y NO es un número que debamos hardcodear como si fuera ley.
3. **Finalidad absoluta:** el settlement del batch a **L1 (Ethereum)**. Recién ahí el estado es irreversible bajo el modelo de seguridad de la L2.

El error que el audit detectó es el patrón ingenuo de **hardcodear un `N` de confirmaciones** (`headBlock - eventBlock >= N`) y tratar `N` bloques de profundidad como sinónimo de "firme". En una L2 con sequencer eso es **incorrecto por construcción**: la altura de bloque del sequencer no mapea linealmente a riesgo de reorg como sí lo hace (aproximadamente) en una L1 PoW/PoW-histórica. El nodo de Plume YA expone su propia noción de cabeza segura vía los block tags estándar de Ethereum (`safe`, `finalized`); ignorarlos para reinventar un contador propio es duplicar — mal — una lógica que el nodo ya resuelve con información que el backend no tiene (estado del settlement a L1, salud del sequencer).

Sumado a esto, el audit marcó que la **mecánica de reorg estaba descrita pero no especificada**: §1.2 dice "identificar el bloque de bifurcación, recomputar holding/escrow desde transfer_log, re-aplicar máquinas de estado desde el fork-point" — pero sin definir el punto de anclaje de idempotencia ni el procedimiento determinístico de recompute. Esto deja la puerta abierta a un reorg mal aplicado que corrompa una proyección de balances o de estado de redención.

### Restricción heredada

- El read model materializa SOLO a tablas servibles eventos suficientemente firmes (CIS §1.2); lo **crítico** (gates `canMint`/`canRedeem`, balance pre-tx, `paused()`) se lee **siempre LIVE**, nunca de la zona servible ni de la pendiente (CIS §1.2, §4, §9).
- Toda fila de proyección lleva procedencia (`chainId`, `blockNumber`, `logIndex`, `txHash`, `updatedAtBlock`) e idempotencia por `(chainId, txHash, logIndex)` (CIS §1.2).
- Goldsky maneja reorgs nativamente (rollback de entities); el read model Postgres es una **segunda barrera**, no la única (CIS §1.2).

---

## Decision

**La zona "confirmada/servible" del read model se keyea contra el block tag `safe`/`finalized` que reporta el nodo de Plume (viem `blockTag: "safe"` / `blockTag: "finalized"`), NO contra un `N` de confirmaciones hardcodeado.** El nodo es la fuente de verdad de la cabeza segura. La zona "pendiente/optimista" existe para UIs que toleran estado provisional. Lo crítico SIEMPRE se lee LIVE, nunca de la zona pendiente. La finalidad absoluta es el settlement a L1 (Ethereum). Ante reorg: identificar el bloque de bifurcación, recomputar holding/escrow desde `transfer_log` y re-aplicar las máquinas de estado de CIS §8 desde el fork-point, con idempotencia por `(chainId, txHash, logIndex)`.

### Mecánica concreta

**1. Tres zonas de finalidad ancladas en block tags del nodo (no en un contador):**

| Zona | Anclaje | Qué se sirve | Tolerancia a reorg |
|---|---|---|---|
| **Pendiente / optimista** | head (`latest`) del sequencer (~250ms) | UIs que muestran "pendiente" explícito; NUNCA gates ni balance pre-tx | Alta — puede revertirse |
| **Confirmada / servible** | `blockTag: "safe"` (referencia de firmeza ~8s estilo CCTP, pero leída del nodo) | listados, portfolio histórico, timeline, dashboards | Muy baja — el nodo ya la considera segura |
| **Final** | `blockTag: "finalized"` (settlement a L1) | conciliación contable, cierre de auditoría, reportes regulatorios | Nula — irreversible |

El backend NO mantiene un `CONFIRMACIONES_FINALIDAD` numérico como gate de materialización. Materializa a la zona servible los eventos cuyo `blockNumber <= bloque devuelto por el nodo para `blockTag: "safe"`, y marca como `final` los que están `<= finalized`. El número de confirmaciones, si se loguea, es **observabilidad derivada** (`safeBlock - eventBlock`), no la condición de corte.

**2. Lo crítico se lee LIVE — invariante de código (CIS §4/§9):** los gates `canMint`/`canRedeem`, `balanceOf`/`availableBalance`/`tokensLockedFor`, `kgDisponibles(loteId)` y `paused()` de los 3 contratos se leen con `blockTag: "latest"` directo al nodo en el momento de la decisión. NUNCA salen de la zona servible ni de la pendiente. Esta regla ya existe en §1.2 y este ADR la refuerza: la zona servible es para **mostrar**, no para **decidir**.

**3. Detección de reorg.** El ingestor compara, por cada lote de eventos entrante, el `(blockNumber, blockHash)` que reporta el nodo/Goldsky contra el `blockHash` que el read model tiene persistido para ese `blockNumber`. Si difieren por debajo del `safe` actual, hubo reorg en la zona pendiente: se identifica el **fork-point** = el `blockNumber` más alto cuyo `blockHash` persistido sigue coincidiendo con el del nodo.

**4. Recompute determinístico desde el fork-point.** Una vez identificado el fork-point:
1. Se descartan (o invalidan) las filas de proyección con `blockNumber > fork-point` que pertenecían a la rama huérfana.
2. **`holding` y escrow espejo se recomputan desde `transfer_log`** (append-only, fuente cruda de balances): se re-derivan los balances replayando la secuencia de `TransferSingle` válida (mint `from=0`, burn `to=0`) hasta la nueva cabeza.
3. **Las máquinas de estado de CIS §8 se re-aplican desde el fork-point**, validando cada transición: `lote_proyeccion` con §8.1 (PREVENTA → COSECHADO → ALMACENADO → REDENCION_PARCIAL → AGOTADO, o → FALLIDO), `redencion_proyeccion` con §8.3 (INICIADA → EN_EXPORTACION → COMPLETADA/CANCELADA), `kyc_mirror` con §8.2. El handler RECHAZA transiciones inválidas (defensa ante reorg mal aplicado) en vez de aplicarlas a ciegas.
4. La **idempotencia por `(chainId, txHash, logIndex)`** garantiza que re-aplicar un evento que sobrevivió al reorg es un no-op exacto: el recompute es seguro de re-ejecutar y converge al mismo estado que un backfill completo desde `startBlock`.

**5. Goldsky como primera barrera, Postgres como segunda.** Goldsky hace rollback de entities ante reorg nativamente; el read model Postgres añade su propia detección + recompute. Las dos barreras son independientes: si Goldsky no captara un reorg pequeño en la zona pendiente, la comparación de `blockHash` del paso 3 lo detecta igual.

**6. Finalidad absoluta = L1.** La zona `final` (`blockTag: "finalized"`, settlement a Ethereum) es la única que la conciliación contable y la auditoría regulatoria tratan como irreversible. La conciliación de escrow (job de 15 min) y los reportes que cruzan plata contra cadena se anclan a `finalized`, no a `safe`.

---

## Alternatives considered

### A — Hardcodear `CONFIRMACIONES_FINALIDAD = N` (el patrón ingenuo de §1.2 pre-ADR) (rechazada)

Materializar a la zona servible con `headBlock - eventBlock >= N`, con `N` fijo por config.

**Por qué se rechazó:**
- En una L2 con sequencer, la profundidad en bloques **no es proporcional al riesgo de reorg** como (aproximadamente) lo es en L1. Un `N` fijo o sobre-conserva (latencia inútil) o sub-conserva (sirve estado revertible).
- **Ignora información que el nodo SÍ tiene y el backend no**: estado del settlement a L1 y salud del sequencer. El nodo ya resume eso en `safe`/`finalized`; reinventarlo con un contador es duplicar mal.
- Acopla el backend a una suposición frágil sobre el comportamiento del sequencer de Plume que puede cambiar con un upgrade de la red.

### B — Servir desde el head del sequencer (~250ms), sin barrera de finalidad (rechazada)

Aprovechar la confirmación soft de ~250ms y materializar todo en head para latencia mínima.

**Por qué se rechazó:**
- Viola "ante divergencia gana la cadena" en su peor forma: serviría estado que el sequencer puede revertir, contaminando dashboards de balances y de estado de redención.
- El head es exactamente la **zona pendiente**, que este ADR sí conserva — pero etiquetada como provisional y JAMÁS usada para gates/decisiones. Servir todo desde head borra esa distinción.

### C — Tratar "1 confirmación / ~8s estilo CCTP" como constante hardcodeada (rechazada)

Tomar el criterio de Circle (Plume = 1 confirmación / ~8s) y codificarlo como el umbral de finalidad del backend.

**Por qué se rechazó:**
- El ~8s de CCTP es una **referencia de firmeza útil**, no un contrato. Hardcodearlo nos ata a una política de un tercero que puede cambiar sin avisarnos, y vuelve a caer en el anti-patrón de número mágico de la alternativa A.
- El nodo ya expone `safe`, que para propósitos prácticos vive en esa vecindad de firmeza pero se mueve con la red. Usar `blockTag: "safe"` nos da el mismo nivel de garantía SIN hardcodear el número y SIN depender de la política de Circle.

### D — Confiar solo en el rollback nativo de Goldsky (rechazada)

Delegar 100% el manejo de reorg al subgraph de Goldsky y no implementar la segunda barrera en Postgres.

**Por qué se rechazó:**
- Deja al read model Postgres sin defensa propia ante un reorg que Goldsky no propague correctamente o ante un desfase de ingestión.
- CIS §1.2 manda explícitamente la "segunda barrera". El recompute determinístico desde `transfer_log` + idempotencia por `(chainId, txHash, logIndex)` es barato y reconstruible — no hay razón para no tener red de seguridad propia.

---

## Consequences

### Positive

1. **Cero números mágicos de finalidad** — la firmeza la dicta el nodo (`safe`/`finalized`), no un `N` que envejece mal. El backend se adapta automáticamente a cambios de comportamiento del sequencer o del settlement a L1.
2. **Tres zonas explícitas y bien tipadas** — pendiente (mostrar como provisional), confirmada (servir), final (conciliar/auditar). Cada consumidor sabe contra qué zona lee.
3. **Lo crítico nunca depende de la finalidad del read model** — gates y balance pre-tx van LIVE al nodo; un reorg en la zona pendiente NO puede causar un doble-mint ni una redención indebida porque esas decisiones no leen del cache.
4. **Reorg recovery determinístico y reconstruible** — recompute desde `transfer_log` + re-aplicación validada de las máquinas de estado §8 + idempotencia por `(chainId, txHash, logIndex)` convergen al mismo estado que un backfill desde `startBlock`. El recompute es seguro de re-ejecutar.
5. **Defensa en profundidad** — dos barreras independientes (Goldsky nativo + recompute Postgres) cubren el reorg aunque una falle.
6. **Auditoría anclada a finalidad absoluta** — la conciliación contable y los reportes regulatorios se anclan a `finalized` (L1), no a un punto revertible.

### Negative

1. **Latencia de servibilidad atada al `safe` del nodo** — la zona confirmada está ~8s detrás del head en lugar de ~250ms. Mitigado por la zona pendiente para UIs que toleran provisional, y porque lo crítico va LIVE de todos modos.
2. **Dependencia de que el nodo de Plume reporte `safe`/`finalized` correctamente** — si el RPC no soporta o miente sobre esos tags, la barrera se degrada. Mitigado por ADR-024 (RPC + failover `fallback()` de viem) y por el health-check de bootstrap; si un endpoint no devuelve `safe`, se failover-ea.
3. **El recompute desde `transfer_log` tiene costo** — un reorg profundo obliga a replayar una ventana de eventos. Mitigado porque los reorgs por debajo de `safe` son raros y la ventana a recomputar es acotada (del fork-point al head, no desde génesis).

### Neutral

1. **`CONFIRMACIONES_FINALIDAD` deja de ser un gate y pasa a ser observabilidad derivada** — si se loguea `safeBlock - eventBlock`, es métrica, no condición de corte. Cualquier referencia previa a ese parámetro como umbral debe releerse a la luz de este ADR.
2. **Goldsky-en-Plume y push-vs-polling** quedan fuera de scope de este ADR (son el otro half de OS-5.5) — este ADR decide la semántica de finalidad/reorg, no el transporte del indexer.
3. **El job de conciliación contable cambia su ancla** de "saldo actual" a `finalized`; el job de holdings vs `totalSupply(loteId)` puede seguir contra `safe` para detección temprana. Esta asimetría es intencional.

---

## Implementation notes

Se implementa en el submódulo `indexing/` del backend (Bun + Hono, ADR-007), capa hexagonal:

- **`domain`** — `FinalityZone` (`PENDING` | `CONFIRMED` | `FINAL`) y los invariantes de transición de CIS §8 (`lote_proyeccion` §8.1, `redencion_proyeccion` §8.3, `kyc_mirror` §8.2). El validador de transición vive acá y RECHAZA transiciones inválidas (defensa anti-reorg-mal-aplicado).
- **`application`** — `proyectarEvento` (idempotente por `(chainId, txHash, logIndex)`), `detectarReorg` (compara `blockHash` persistido vs nodo, deriva fork-point), `recomputarDesdeForkPoint` (replay de `holding`/escrow desde `transfer_log` + re-aplicación validada de §8), `clasificarFinalidad` (mapea `blockNumber` → zona contra `safe`/`finalized` del nodo).
- **`infrastructure`** — viem `getBlock({ blockTag: "safe" })` y `getBlock({ blockTag: "finalized" })` para resolver los cortes de zona (RPC vía ADR-024, con `fallback()`); cliente GraphQL/webhook Goldsky (primera barrera); repos Drizzle del read model. Los reads LIVE críticos usan `blockTag: "latest"` directo.
- **Drizzle/Postgres** — las tablas de proyección (`holding`, `lote_proyeccion`, `redencion_proyeccion`, `kyc_mirror`, escrow espejo) ganan una columna de zona de finalidad derivada (o se calcula al consultar contra el `safe`/`finalized` cacheado, evitando materializar un flag que se mueve). `transfer_log` (append-only) es la fuente cruda del recompute de balances. La idempotencia se enforcea con UNIQUE `(chainId, txHash, logIndex)`.
- **Backfill** — desde `startBlock` (bloque de deploy, 2026-06-01 en testnet 98867) reconstruye TODAS las zonas; el recompute por reorg es un caso acotado del mismo mecanismo. Único no-reconstruible-por-log: `hashFotosApiario`/`tipoCertificadoOrigen` → resync con `lotes()` live (CIS §1.2, asimetría storage-vs-evento).

**Regla de código no negociable:** ningún gate de decisión (`canMint`/`canRedeem`, balance pre-tx, `paused()`) puede leer de la zona servible ni pendiente. Si un endpoint de decisión lee del read model en vez de LIVE, es un bug de seguridad, no una optimización (CIS §4/§9).

---

## References

- `docs/architecture/ARQUITECTURA-BACKEND-FASE2.md` §1.2 (read path: indexer + read model; párrafo "Reorgs / finalidad"; OS-2.4; OS-5.5)
- `docs/architecture/CIS-v1.md` §1.2 (read path), §3 (Matriz source-of-truth, "ante divergencia gana la cadena"), §4 (read surface, read-vs-live), §8 (state machines: §8.1 lote, §8.2 KYC, §8.3 redención), §9 (authority boundary on-chain vs off-chain)
- ADR-024 (RPC Plume + failover — el transport viem `fallback()` que sostiene la lectura de `safe`/`finalized`)
- ADR-019 (eventos de dominio — `TokensRedimidos`/`RedemptionManagerSet`/`ReembolsoFinalizado` que hacen el read model reconstruible por log, prerequisito del recompute por reorg)
- ADR-001 (Plume Network primaria; Goldsky subgraph como indexer)
- viem `getBlock({ blockTag })` (`"latest"` | `"safe"` | `"finalized"`) — semántica de finalidad del nodo
- Circle CCTP: Plume tratado como 1 confirmación / ~8s (referencia de firmeza, NO constante hardcodeada)
