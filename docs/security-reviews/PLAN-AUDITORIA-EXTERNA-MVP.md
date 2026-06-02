# Plan de Auditoría Externa — MVP (gate final pre-mainnet)

> **Propósito:** documento de coordinación y management para contratar y ejecutar la **auditoría profesional externa** de los 3 contratos del MVP. Es el **gate obligatorio** antes de cualquier deploy a mainnet. No es un documento técnico de implementación: es la guía operativa para que un PM (o el responsable del proyecto) pueda accionar la auditoría de punta a punta.

**Última actualización:** 2026-05-29
**Autor del documento:** Daniel Hidalgo Carrasco + Claude
**Scope del documento:** coordinación de auditoría externa de `packages/contracts/src/*.sol` (MVP de 3 contratos)
**Estado del MVP:** code-frozen, audit-ready interno. **Auditoría externa: NO iniciada.**

---

## 0. TL;DR

1. Los **3 contratos del MVP** (`AssetVault`, `IdentityRegistry`, `RedemptionManager`) están **code-frozen**: 100% branch coverage, Slither 0 findings, 216 tests verdes, fuzz 10k, invariant hasta 200k calls, 3 auditorías internas profundas + ADRs 001-017.
2. El **siguiente y último gate** antes de mainnet es una **auditoría profesional externa** (firma reconocida). No la reemplaza ninguna review interna.
3. **El deploy (testnet y mainnet) está FUERA DEL SCOPE del batch de desarrollo actual** y queda **gateado por esta auditoría externa**. Ningún deploy a mainnet ocurre sin sign-off del auditor + remediación de findings aceptada.
4. **Fase 2 (LabRegistry, QualityAttestation, PlumeArcAdapter, multi-chain Polygon) está EXPLÍCITAMENTE EXCLUIDA** de esta auditoría. Se audita por separado cuando se construya.
5. Candidatos de firma evaluados: **Sherlock**, **Trail of Bits**, **Cantina** (§4). Decisión de firma pendiente.

---

## 1. Objetivo y alcance

### 1.1 Objetivo

Obtener una **validación de seguridad independiente y profesional** de los smart contracts del MVP antes de exponerlos a fondos reales en mainnet (Plume Network). El objetivo NO es encontrar bugs que ya conocemos: es que un tercero adversarial sin sesgo de autor confirme (o refute) que el sistema es seguro para custodiar USDC de compradores europeos y representar miel física tokenizada.

### 1.2 Alcance — IN SCOPE

Los **3 contratos inmutables del MVP** (sin proxy, sin upgradeability — ADR-003) + sus libraries e interfaces:

| Artefacto | Archivo | Rol | LOC efectivas aprox. |
|---|---|---|---|
| **AssetVault** | `src/AssetVault.sol` | ERC-1155 + lifecycle de lote + custodia USDC + reserva técnica + reembolso pro-rata | ~310 |
| **IdentityRegistry** | `src/IdentityRegistry.sol` | Gatekeeper KYC on-chain (`canMint` / `canRedeem`) | ~120 |
| **RedemptionManager** | `src/RedemptionManager.sol` | Flujo de redención física con modelo de lock contable (Opción B) | ~200 |
| **Libraries** | `src/libraries/*.sol` | `ComplianceConstants`, `QualityRules`, `DocumentHashes` (lógica pura/constantes) | — |
| **Interfaces** | `src/interfaces/I*.sol` | `IAssetVault`, `IIdentityRegistry`, `IRedemptionManager` | — |

Adicionalmente se entregan como **material de contexto** (no necesariamente como artefactos a auditar línea por línea, pero sí relevantes para entender el sistema):

- `script/DeployPlume.s.sol` — script de deploy modular + orquestador (resuelve la dependencia cíclica `AssetVault.setRedemptionManager`).
- Suite de tests completa (`test/unit`, `test/integration`, `test/invariant`).

### 1.3 Alcance — OUT OF SCOPE (excluido explícitamente)

Lo siguiente **NO se audita en esta ronda**. Pertenece a Fase 2+ y se auditará por separado cuando exista código real:

| Excluido | Razón |
|---|---|
| **`LabRegistry.sol`** | Reservado en `phase2/` (ADR-005, ADR-010). NO forma parte del MVP de 3 contratos. |
| **`QualityAttestation`** | Eliminado del MVP por simplificación de estados (ADR-010). |
| **`PlumeArcAdapter`** (bridge KYC Plume Arc) | Integración de fase 2; hoy el gating es vía `IdentityRegistry` directo. |
| **Multi-chain Polygon PoS** (mirror via SkyLink/CCIP) | Fase 6+ (ADR-001). El attestation hash aún no incluye `chainid` — fix gateado a pre-multi-chain, no al MVP single-chain. |
| **Backend (Bun + Hono), DB, KYC bridge Sumsub, oráculos off-chain** | Auditorías de aplicación / pentest separados, fuera del scope de smart-contract audit. |

> **Nota de coordinación:** dejar este límite por escrito en el SOW/contrato con la firma evita scope creep y sobrecostos. La firma audita 3 contratos + libs, no la plataforma entera.

---

## 2. Estado de preparación (audit-readiness)

Esto es **lo que se le entrega al auditor** el día 1. El objetivo de tener todo esto listo ANTES de contratar es maximizar la señal de la auditoría externa (que no gaste horas redescubriendo lo que ya cubrimos) y minimizar el costo.

### 2.1 Métricas de calidad (estado verificado del código)

| Dimensión | Estado | Fuente |
|---|---|---|
| **Branch coverage** | **100%** en los 3 contratos | `forge coverage` (sin invariants, ver §6.3 handoff) |
| **Line / function coverage** | **100% / 100%** en los 3 contratos | idem |
| **Slither (análisis estático)** | **0 findings** accionables (falsos positivos silenciados con justificación en NatSpec) | `slither .` v0.11.5 scoped |
| **Tests totales** | **216 / 216 passing** | `forge test` |
| **Fuzz testing** | **10.000 runs** sobre invariantes clave (ej. acumulador de lock no excede balance) | `forge test --fuzz-runs 10000` |
| **Invariant testing** | hasta **200.000 calls**, 0 violaciones, 0 reverts (spec 50k×100 pendiente por OOM — RM-29) | `forge test` invariant suite |
| **Bytecode size** | dentro del límite EVM 24.576 bytes | `forge build` |
| **Compilador** | solc 0.8.24, EVM `paris`, optimizer 200 runs | `foundry.toml` |

Desglose de los 216 tests: AssetVault 45 + 44 (branches) · IdentityRegistry 33 + 13 (branches) · RedemptionManager 71 · DeployPlume 5 · Lifecycle E2E 5.

### 2.2 Trabajo de review interno ya realizado (referencia para el auditor)

El MVP pasó por **un reporte inicial + tres auditorías internas profundas** (metodología de 3 agentes: audit → fix → re-audit adversarial). El auditor externo debe partir de estos documentos para no repetir trabajo:

| Documento | Contrato | Hallazgos | Estado |
|---|---|---|---|
| `audit-report-2026-05-19.md` | 4 contratos (review inicial) | 1 High, 5 Medium, 7 Low, 8 Info | Base histórica; superado por los deep audits |
| `audit-AssetVault-deep-2026-05-19.md` | AssetVault | 0 Critical, 3 High, 8 Medium, 6 Low, 9 Info | Cerrado vía Gap 3 + ADRs |
| `audit-IdentityRegistry-deep-2026-05-22.md` | IdentityRegistry | 0 Critical, 2 High, 8 Medium, 6 Low, 5 Info | Cerrado vía Gap 4 + ADR-013 |
| `audit-RedemptionManager-deep-2026-05-26.md` | RedemptionManager | 5 Critical, 6 High, 5 Medium, 4 Low, 3 Info (23 total) | Cerrado vía Opción B + ADR-015/016/017 |

> Los findings que requirieron decisión arquitectónica (no mecánica) se resolvieron con ADRs formales, no con parches silenciosos. Esto es deliberado: el auditor externo puede leer el ADR y entender el *por qué* de cada decisión, no solo el *qué*.

### 2.3 ADRs (Architecture Decision Records) — decisiones formales

Se entregan los **ADRs 001-017**. Los más relevantes para la auditoría de los 3 contratos:

| ADR | Decisión | Relevancia para el auditor |
|---|---|---|
| ADR-003 | 4 contratos inmutables sin proxy | No hay upgradeability → sin riesgo de storage collision / proxy. |
| ADR-002 | ERC-1155 + bloqueo de P2P (`_update` override) | El token NO es transferible peer-to-peer. Invariante central. |
| ADR-009 | Escrow total post-cosecha | Semántica de custodia de USDC y reserva técnica. |
| ADR-010 | Simplificación de estados (sin QualityAttestation) | Por qué el MVP es de 3 contratos, no 4. |
| ADR-012 | `AccessControlDefaultAdminRules` (delay 3 días para transferir admin) | Mitigación de lockout / captura de admin. |
| ADR-013 | Pause en IdentityRegistry | Respuesta al H-02 del deep audit (emergencia regulatoria). |
| ADR-014 | Tier check en refund | Gating de elegibilidad en el reembolso. |
| ADR-015 | Timeout policy (buyer self-cancel a 60d + co-canceler compliance) | Resuelve RM-06/07 (riesgo de lock eterno). |
| ADR-016 | Pause asymmetry sistémico (pause = Compliance\|Admin; unpause = Admin only) | Modelo de control de emergencia en los 3 contratos. |
| ADR-017 | Spec reconciliation — máquina de estados de exportación (2 funciones, 3 fases) | Resuelve RM-11 (estado muerto `EN_EXPORTACION`). |

### 2.4 Paquete de entrega al auditor (data room)

Lo que se le pasa a la firma el día 1:

- [ ] Código fuente congelado: commit hash exacto + tag (ej. `v0.1.0-audit`).
- [ ] `docs/architecture/CONTRACT-SPECS.md` (reconciliado con el código real — ver Gap 6 del handoff).
- [ ] `docs/architecture/TEST-SPECS.md`.
- [ ] ADRs 001-017.
- [ ] Las 3 auditorías internas profundas + el reporte inicial.
- [ ] Reporte de coverage (lcov export, 100% branches).
- [ ] Reporte de Slither (0 findings + lista de falsos positivos silenciados con justificación).
- [ ] Gas snapshots y análisis de gas existentes.
- [ ] Diagrama de roles/`AccessControl` y de la máquina de estados del lote + de la redención.
- [ ] README con instrucciones de build/test reproducibles (`forge build`, `forge test`, gotchas del entorno).

> **Gate de preparación:** no se contrata firma hasta que este checklist esté completo Y `CONTRACT-SPECS.md` esté reconciliado con el código (hoy parcialmente desactualizado — Gap 6 del handoff). Entregar specs que mientan sobre el código es exactamente la clase de inconsistencia que un auditor escala a finding y que nos costó caro internamente (RM-03/RM-16: claims falsos en NatSpec).

---

## 3. Perfil del codebase (lo que el auditor va a encontrar)

Para que la firma dimensione el esfuerzo correctamente:

- **Estándar de token:** ERC-1155 (multi-token por lote), con `_update()` overrideado para **bloquear toda transferencia P2P** (modelo "solo primario").
- **Control de acceso:** OpenZeppelin `AccessControlDefaultAdminRules` v5, roles granulares (`BACKEND_SIGNER_ROLE`, `ORACLE_ROLE`, `COMPLIANCE_OFFICER_ROLE`, `DEFAULT_ADMIN_ROLE`), pause asimétrico.
- **Custodia de valor:** `AssetVault` custodia USDC (SafeERC20), maneja reserva técnica (15-20%) y reembolso pro-rata en caso de lote fallido.
- **Flujo de redención:** modelo de **lock contable** (Opción B, estilo Compound/Aave: mapping de locked sobre balance real, sin escrow físico). Invariante crítica: `sum(redenciones INICIADAS) <= balanceOf(buyer, loteId)`.
- **Integración con oráculos:** confirmaciones críticas vía **Safe multi-sig 2-de-3** (`ORACLE_ROLE`). Chainlink PoR es fase 2 (no en scope).
- **Seguridad aplicada:** custom errors (no string reverts), CEI estricto + `nonReentrant` en funciones que mueven valor, sin `tx.origin`, sin `block.timestamp` para randomness, sin inline assembly, sin proxy.

Esto encaja con el sweet-spot de cualquiera de las 3 firmas candidatas: codebase chico-mediano (~630 LOC efectivas en 3 contratos), patrón conocido (RWA + ERC-1155 + AccessControl + redemption flow), bien testeado y documentado.

---

## 4. Candidatos de firma de auditoría

> **Nota honesta sobre precios:** NO se fijan montos exactos en este documento porque varían por LOC, duración, demanda de la firma y el momento. Pedir cotización formal (RFP/SOW) a las tres. Lo que sí se documenta abajo es el **modelo**, el **timeline típico** y el **fit** real para ESTE codebase.

### 4.1 Sherlock

- **Modelo:** **contest/competición** (audit contest) con un pool de watsons + pago por severidad de los findings, opcionalmente combinado con un lead auditor y/o cobertura tipo seguro. Hay también modalidad de auditoría privada.
- **Timeline típico:** ventana de contest corta e intensa (del orden de **1-2 semanas** de competición activa) + período de juzgamiento/escalación de findings.
- **Fit para este codebase:** **bueno**. Un codebase chico, bien acotado y bien documentado es ideal para un contest — muchos ojos sobre poca superficie. El modelo competitivo tiende a maximizar la cantidad de findings por dólar en superficies acotadas. Contras: requiere que el código esté EXTREMADAMENTE pulido antes (el ruido de findings duplicados/low se paga en tiempo de juzgamiento) y la coordinación de la escalación de findings exige disponibilidad nuestra durante la ventana.

### 4.2 Trail of Bits

- **Modelo:** **fixed-scope / engagement privado tradicional**. Equipo asignado de auditores senior, scope y duración cerrados por contrato, metodología propia (incluye análisis con herramientas propias tipo Slither — que ellos mantienen — y, según engagement, verificación formal / fuzzing avanzado).
- **Timeline típico:** engagement reservado con anticipación (cola de semanas/meses según disponibilidad); la auditoría en sí suele ser del orden de **2-4 semanas** para un scope de este tamaño, más el reporte.
- **Fit para este codebase:** **muy bueno en rigor, premium en costo y lead time**. ToB es referencia de la industria; su marca da peso regulatorio/legal (relevante para una plataforma RWA con exposición legal en Europa). Mantienen Slither, así que nuestro 0-findings de Slither les resulta familiar de inmediato. Contras: es la opción más cara y con mayor lead time de booking; puede ser overkill para 3 contratos chicos si el presupuesto es ajustado, pero es la que más "blinda" frente a inversores/legal.

### 4.3 Cantina (Spearbit)

- **Modelo:** **híbrido / marketplace de auditores** — permite tanto **competición** (Cantina Competitions) como engagements de **scope fijo** armando un equipo curado de auditores independientes top (red Spearbit). Flexible: se elige el formato según presupuesto y urgencia.
- **Timeline típico:** según formato; un engagement privado de scope fijo para 3 contratos chicos suele ser del orden de **1-3 semanas** de auditoría activa, con booking más ágil que ToB.
- **Fit para este codebase:** **muy bueno y el más flexible**. Permite calibrar formato (competición vs equipo fijo) al presupuesto, y dar con auditores con experiencia específica en RWA / ERC-1155 / flujos de redención. Buen punto medio entre el costo/ruido de un contest puro y el costo/lead-time de ToB. Contras: la calidad depende de qué auditores se asignan (la red es grande y heterogénea); hay que validar el perfil del equipo propuesto antes de firmar.

### 4.4 Recomendación de proceso de selección

No casarse con una antes de cotizar. Proceso sugerido:

1. Enviar el **mismo paquete** (§2.4) y un **RFP idéntico** a las tres.
2. Comparar: costo, lead time real (cuándo PUEDEN empezar), perfil del equipo asignado, formato (contest vs fijo), y qué incluye el sign-off / re-auditoría de remediación.
3. **Sesgo recomendado del Senior Architect:** para una plataforma RWA con exposición legal real, priorizar la firma cuya **marca + reporte** tenga peso ante inversores y reguladores, aunque cueste algo más. Para 3 contratos chicos y bien testeados, **Cantina (scope fijo)** suele ser el mejor balance costo/rigor/lead-time; **Trail of Bits** si el presupuesto permite el premium y se busca máximo blindaje reputacional; **Sherlock (contest)** si se prioriza amplitud de revisores y el código está impecablemente pulido.

---

## 5. Timeline / fases propuestas

Pipeline secuencial. Cada fase tiene un gate de salida que habilita la siguiente. Los rangos de duración son estimaciones de coordinación, no compromisos de la firma.

### Fase 0 — Preparación del paquete (interno)
- **Qué:** completar el data room (§2.4): congelar código (tag `v0.1.0-audit`), reconciliar `CONTRACT-SPECS.md` con el código (Gap 6), exportar coverage + reporte Slither, empaquetar ADRs + auditorías internas, escribir README reproducible.
- **Gate de salida:** checklist §2.4 completo + `CONTRACT-SPECS.md` reconciliado.
- **Duración estimada:** 3-5 días.
- **Responsable:** equipo de contratos.

### Fase 1 — Selección de firma
- **Qué:** RFP a Sherlock / ToB / Cantina, comparar cotizaciones, validar perfil del equipo, firmar SOW con scope IN/OUT explícito (§1).
- **Gate de salida:** contrato firmado + fecha de inicio agendada + commit hash congelado comunicado a la firma.
- **Duración estimada:** 1-3 semanas (dominado por el lead time de booking de la firma).

### Fase 2 — Ventana de auditoría
- **Qué:** la firma audita. Nosotros: ventana de soporte (responder dudas, no tocar el código congelado salvo emergencia comunicada).
- **Gate de salida:** entrega del **draft report** con findings.
- **Duración estimada:** 1-4 semanas según firma/formato (§4).

### Fase 3 — Remediación de findings
- **Qué:** triage de findings por severidad; fix de Critical/High obligatorios; decisión documentada (ADR nuevo) para los que requieran cambio arquitectónico; aceptar/refutar Low/Info con justificación.
- **Gate de salida:** todos los Critical/High **resueltos** o formalmente **aceptados con mitigación documentada y aprobada**.
- **Duración estimada:** 1-2 semanas (depende del volumen de findings).

### Fase 4 — Re-auditoría / sign-off
- **Qué:** la firma re-revisa los fixes (fix review) y emite el **reporte final** + sign-off.
- **Gate de salida:** **reporte final firmado** sin Critical/High abiertos.
- **Duración estimada:** 3-7 días.

### Fase 5 — Luz verde para deploy (FUERA del batch de dev actual)
- **Qué (en orden):**
  1. Deploy a **Plume testnet** (chainid 98867) con el código auditado → validación funcional E2E en red real.
  2. Ventana de observación / smoke tests en testnet.
  3. Deploy a **Plume mainnet** solo tras checklist de despliegue + verificación de contratos + handover de claves a HSM/multi-sig.
- **Gate de entrada (DURO):** reporte final del auditor sin Critical/High abiertos (Fase 4). **Sin esto, NO hay deploy a mainnet.**
- **Responsable:** equipo de contratos + ops (claves en HSM/multi-sig, NUNCA en env vars — regla §9 del CLAUDE.md raíz).

> **Aclaración de scope crítica:** las Fases 0-4 son coordinación + auditoría. La **Fase 5 (deploy testnet/mainnet) NO forma parte del batch de desarrollo actual de smart contracts** y está **gateada** por el sign-off de la Fase 4. El batch de dev terminó en "code-frozen, audit-ready". Todo lo posterior depende de esta auditoría.

---

## 6. Entregables esperados del auditor y criterios de aceptación

### 6.1 Entregables exigidos a la firma (definir en el SOW)

1. **Reporte de auditoría** con findings clasificados por severidad (Critical / High / Medium / Low / Informational), cada uno con: descripción, ubicación (archivo + línea), impacto, escenario de explotación y recomendación de fix.
2. **Fix review / re-auditoría** de las remediaciones (que el reporte final confirme que cada Critical/High quedó cerrado).
3. **Reporte final firmado** (versión pública publicable o privada, según se acuerde) — el artefacto que sirve de sign-off ante inversores/legal.
4. **Resumen ejecutivo** apto para audiencia no técnica (inversores, partner legal).

### 6.2 Criterios de aceptación (gate antes de mainnet)

El gate se considera **superado** si y solo si:

- [ ] **0 findings Critical abiertos** (todos resueltos y re-verificados).
- [ ] **0 findings High abiertos** (resueltos y re-verificados, o aceptados con mitigación documentada en ADR **y aprobada explícitamente** por el responsable del proyecto + partner legal cuando aplique).
- [ ] **Medium:** resueltos o con decisión documentada (ADR) y aceptación formal.
- [ ] **Low / Informational:** triados; los que no se arreglen quedan registrados con justificación.
- [ ] **Reporte final firmado** por la firma, sobre el **commit congelado** (o el commit post-remediación, claramente identificado).
- [ ] El código desplegado a mainnet es **exactamente** el commit auditado/re-auditado (verificación de bytecode on-chain == artefacto auditado).

> **Regla dura:** ningún deploy a mainnet con findings Critical o High abiertos. Sin excepción. Un High "aceptado" requiere ADR + firma del responsable del proyecto + (si tiene implicancia legal, como H-01 del reembolso) firma del partner legal.

---

## 7. Riesgos de coordinación y mitigaciones

| # | Riesgo | Impacto | Mitigación |
|---|---|---|---|
| R1 | **Scope creep:** la firma intenta auditar Fase 2 / backend / oráculos off-chain | Sobrecosto + dilución de foco | Scope IN/OUT explícito en el SOW (§1.3). Excluir LabRegistry / QualityAttestation / PlumeArc / Polygon por escrito. |
| R2 | **Código no congelado:** seguimos tocando contratos durante la ventana | Findings sobre código obsoleto, re-trabajo, costo extra | Tag `v0.1.0-audit` inmutable. Freeze duro: solo se toca el código en remediación (Fase 3), nunca durante Fase 2. |
| R3 | **Specs desincronizadas del código** (Gap 6 del handoff) | El auditor escala inconsistencias spec↔código a findings (ya nos pasó: RM-03/RM-16) | Gate de Fase 0: reconciliar `CONTRACT-SPECS.md` ANTES de entregar. |
| R4 | **Lead time de booking** (sobre todo ToB) | El deploy a mainnet se atrasa semanas/meses | Iniciar la conversación de selección (Fase 1) en paralelo a Fase 0. Reservar slot temprano. |
| R5 | **Findings High con dimensión legal** (ej. H-01: reembolso solo cubre la reserva técnica 15-20%) | No es un bug de código sino una decisión producto+legal; puede bloquear el sign-off | Resolver la política de reembolso (producto + partner legal) **antes** de la auditoría, no durante. Documentar en ADR. |
| R6 | **Disponibilidad nuestra durante la ventana** (sobre todo en formato contest) | Findings sin responder a tiempo → escalan o quedan ambiguos | Asignar un punto de contacto técnico dedicado con SLA de respuesta durante la ventana. |
| R7 | **Remediación introduce regresiones** | Un fix abre un bug nuevo no cubierto por la re-auditoría | Mantener el loop interno (TDD + 100% coverage + Slither + re-run de la suite) sobre cada fix antes de mandarlo a fix review. |
| R8 | **Claves operativas mal manejadas en deploy** (Fase 5) | Compromiso total post-auditoría (auditar y después filtrar la clave) | Claves en HSM (AWS/GCP KMS) o hardware wallet + multi-sig 2-de-3. NUNCA en env vars (regla §9 del CLAUDE.md raíz). Handover de claves es parte del checklist de Fase 5. |
| R9 | **Drift entre commit auditado y commit desplegado** | Se despliega algo distinto a lo auditado | Verificación de bytecode on-chain == artefacto auditado, como ítem obligatorio del gate (§6.2). |
| R10 | **Invariant a escala spec no ejecutado** (RM-29: 50k×100 OOMea en el entorno actual) | El auditor lo nota como gap de cobertura de invariantes | Antes de entregar: optimizar el handler (bounded array) para alcanzar la spec, o documentar formalmente la limitación + el resultado de 200k calls como evidencia. |

---

## 8. Estado actual y próxima acción

- **Estado:** MVP code-frozen, audit-ready interno (216 tests, 100% branches, Slither 0, 3 deep audits, ADRs 001-017). **Auditoría externa NO iniciada.**
- **Deploy:** FUERA del batch de desarrollo actual. Gateado por el sign-off de esta auditoría externa.
- **Próxima acción (Fase 0):** completar el data room (§2.4) y reconciliar `CONTRACT-SPECS.md` con el código real. En paralelo, abrir la conversación de selección con las tres firmas (Fase 1) para no comerse el lead time de booking.

---

## 9. Referencias

### Documentos de review interno (entregables al auditor)
- `docs/security-reviews/audit-report-2026-05-19.md` — reporte inicial (4 contratos)
- `docs/security-reviews/audit-AssetVault-deep-2026-05-19.md`
- `docs/security-reviews/audit-IdentityRegistry-deep-2026-05-22.md`
- `docs/security-reviews/audit-RedemptionManager-deep-2026-05-26.md`

### Arquitectura y decisiones
- `docs/architecture/CONTRACT-SPECS.md` (reconciliar antes de entregar — Gap 6 del handoff)
- `docs/architecture/TEST-SPECS.md`
- `docs/architecture/ADR-001` … `ADR-017`

### Continuidad de la fase de contratos
- `docs/SMART-CONTRACTS-HANDOFF.md` (estado, metodología, gotchas del entorno, gaps medios)

### Código (commit a congelar antes de la auditoría)
- `packages/contracts/src/AssetVault.sol`
- `packages/contracts/src/IdentityRegistry.sol`
- `packages/contracts/src/RedemptionManager.sol`
- `packages/contracts/src/libraries/*.sol`
- `packages/contracts/src/interfaces/I*.sol`
- `packages/contracts/script/DeployPlume.s.sol`

---

**Status del documento:** plan accionable, listo para ejecutar Fase 0.
**Próxima revisión:** al cerrar Fase 0 (data room completo + specs reconciliadas), antes de enviar el RFP.
