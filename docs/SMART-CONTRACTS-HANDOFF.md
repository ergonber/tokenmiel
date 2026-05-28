# Smart Contracts — Handoff de sesión

> **Propósito:** documento de continuidad para retomar el trabajo de smart contracts en una nueva sesión de Claude (o por otra persona). Contiene: estado actual, metodología de trabajo, gotchas del entorno, comandos de referencia, y el plan de los próximos pasos con opciones y recomendaciones.

**Última actualización:** 2026-05-27
**Autor de la sesión:** Daniel Hidalgo Carrasco + Claude
**Scope del documento:** `packages/contracts/` (smart contracts Solidity)

---

## 0. TL;DR — cómo arrancar la próxima sesión

1. Leé este documento entero (especialmente §3 Metodología y §4 Entorno/Gotchas).
2. Estado: **RedemptionManager.sol está 100% cerrado** (audit + 3 ADRs + 100% coverage + slither clean). **AssetVault e IdentityRegistry tienen gaps**. Integration tests y deploy scripts NO existen.
3. **Acción inmediata pendiente:** abrir **PR #2** para mergear los 4 commits del feature branch que NO están en main (ver §2).
4. **Próximo trabajo recomendado:** Gap 1 (Integration tests) → ver §6.
5. Prompt sugerido para arrancar la próxima sesión: ver §9.

---

## 1. Estado de la fase smart contracts

### Los 4 contratos del MVP

| Contrato | Audit | Coverage (líneas / branches / funcs) | Slither | Estado |
|---|---|---|---|---|
| **RedemptionManager.sol** | ✅ Ciclo completo (este sprint) | **100% / 100% / 100%** | ✅ 0 findings | ✅ **CERRADO** |
| **AssetVault.sol** | ✅ 2026-05-19 (previo) | 94.24% / **41.67%** / 90.48% | ⚠️ 6 findings INFO | 🟡 Gaps abiertos |
| **IdentityRegistry.sol** | ✅ 2026-05-22 (previo) | 100% / **48.00%** / 100% | ❓ No corrido standalone | 🟡 Gaps abiertos |
| **LabRegistry.sol** | — | — | — | ⏸️ `phase2/` (reservado, ADR-010, NO MVP) |

### Tests totales del proyecto: **149/149 passing**
- AssetVault: 45 · IdentityRegistry: 33 · RedemptionManager: 71

### Findings del audit de RedemptionManager (23 totales): TODOS cerrados o deferidos
- 5 CRITICAL ✅ · 6 HIGH ✅ · 5 MEDIUM ✅ · 4 LOW ✅ · 3 INFO (2 ✅ + 1 refutado)
- Los 3 MEDIUM que requerían decisión arquitectónica se resolvieron con ADR-015, ADR-016, ADR-017.

---

## 2. Estado Git / PR (LEER — hay commits sin mergear)

- **Repo:** https://github.com/Firrton/tokenization-platform (privado)
- **Colaborador:** `ergonber` (write access, invitación enviada)
- **Branch de trabajo:** `feature/redemption-manager-option-b`

### PR #1 — MERGED ✅ (solo los primeros 3 commits llegaron a `main`)

`main` contiene:
```
c598471 Merge pull request #1
0544ee3 test: close RM-25/26/27/28 coverage gaps + AV fix
ed75f34 chore: reorganize root docs + scaffold infra/tools
92fd0e0 feat: Option B lock acumulator
fdc72a2 initial commit
```

### ⚠️ 4 commits PENDIENTES de mergear (en el feature branch, NO en main)

```
f06a30a feat: ADR-017 spec reconciliation — 2-phase export state machine
96d83b5 feat: ADR-016 pause asymmetry — propagate ADR-013 systemically
6d7bc84 feat: ADR-015 timeout policy — close RM-06/07 (HIGH)
3a22706 feat: easy wins RM-15/18/19 + 100% coverage + slither clean
```

**ACCIÓN PENDIENTE:** abrir **PR #2** desde `feature/redemption-manager-option-b` hacia `main` con estos 4 commits. Comando:
```bash
gh pr create --base main --head feature/redemption-manager-option-b \
  --title "feat(contracts): finalize RedemptionManager — easy wins + ADR-015/016/017" \
  --body "..."
```
(O crear un branch nuevo desde estos commits si se prefiere separar.)

---

## 3. Metodología / flujo de trabajo (CÓMO trabajamos)

Esta es la parte más importante para mantener continuidad. El flujo que funcionó:

### 3.1 Ciclo de auditoría por contrato (el patrón "3 agentes")

1. **Agente 1 (auditoría):** lee el contrato + specs + ADRs, identifica findings con IDs (`RM-01`, `AV-XX`, etc.), severidad (CRITICAL/HIGH/MEDIUM/LOW/INFO), categoría, ubicación, impacto, escenario de ataque, recomendación, código de fix sugerido.
2. **Agente 2 (fix):** implementa los fixes siguiendo TDD. Tests primero, después implementación.
3. **Agente 3 (re-auditoría adversarial):** verifica que cada finding quedó resuelto, busca regresiones, corre la verificación pesada (fuzz, invariant, coverage, slither).
4. **Documentación:** se escribe el reporte en `docs/security-reviews/audit-<Contrato>-deep-<fecha>.md`.

Para delegar a agentes, usar el `Agent` tool con `subagent_type: general-purpose`, `model: opus` para auditoría/validación, `model: sonnet` para implementación.

### 3.2 Flujo "easy-wins" (paso a paso, con oversight del usuario)

Para cerrar findings LOW/MEDIUM mecánicos sin requerir ADR. El patrón por cada paso:
1. **Explicar** qué se va a hacer (qué tests/cambios, por qué).
2. **Mostrar** el código antes de aplicarlo (preview).
3. **Aplicar** el cambio.
4. **Verificar** con `forge test`.
5. **Esperar visto bueno** del usuario antes del siguiente paso.

El usuario prefiere este flujo paso-a-paso con revisión entre cada uno. NO hacer todo de una sin mostrar.

### 3.3 Flujo de ADR (decisiones arquitectónicas)

Cuando un finding requiere decisión de diseño (no es mecánico):
1. **Presentar el problema** en detalle (qué dice el audit, impacto, gap operacional real).
2. **Dar 3 opciones** (A/B/C) con pros/cons honestos.
3. **Recomendar una** con razonamiento de Senior Architect.
4. El usuario elige.
5. **Escribir el ADR** en `docs/architecture/ADR-XXX-<nombre>.md` (formato: Status, Context, Decision, Alternatives, Consequences, Implementation, Testing requirements, Migration plan, References).
6. **Implementar** el cambio en el contrato + interface + tests.
7. **Verificar:** forge test + coverage + slither.
8. **Commit + push** con mensaje conventional detallado.

### 3.4 Convenciones de commits
- Conventional commits (`feat:`, `fix:`, `test:`, `chore:`, `docs:`).
- **NUNCA** "Co-Authored-By" ni AI attribution (regla global del usuario).
- Mensajes detallados con secciones (PROBLEM, DECISION, CHANGES, VERIFICATION, CONSEQUENCES).

### 3.5 Idioma
- Respuestas al usuario: castellano rioplatense (voseo), directo, Senior Architect.
- Código, identifiers, NatSpec, commit messages: inglés (excepto identifiers de dominio: `comprar`, `iniciarRedencion`, `confirmarExportacion`, `completarRedencion`, `LoteMiel`, etc.).
- ADRs y docs: castellano (convención del proyecto).

---

## 4. Entorno / Gotchas (CRÍTICO — evita perder tiempo redescubriendo)

### 4.1 Foundry no está en el PATH por defecto
- Binario: `/Users/firrton/.foundry/bin/forge`
- Versión: **`1.5.0-stable-monad`** (fork de Monad Labs — tiene quirks de output)
- Usar el path completo o exportar: `PATH="/Users/firrton/.foundry/bin:$PATH"`

### 4.2 El shell de bash PIERDE el cwd entre llamadas
- Síntoma: `forge` responde "No files changed" o "command not found".
- Fix: prefijar SIEMPRE con `cd /Users/firrton/Desktop/tokenización/packages/contracts && ...`

### 4.3 `forge coverage` MUERE por OOM (exit 137 / SIGKILL)
- **Causa:** corre todos los tests incluyendo invariants. Config `[invariant] runs=50000, depth=100` en `foundry.toml` + handler con `push` unbounded (finding RM-29) = consume toda la RAM.
- **Workaround que funciona:**
  ```bash
  forge coverage --no-match-path "test/invariant/**" --report summary
  ```
- Para lcov: `forge coverage --no-match-path "test/invariant/**" --report lcov --report-file lcov.info`
- **Fix permanente pendiente (RM-29):** optimizar el handler del invariant (bounded circular array en vez de push).

### 4.4 Slither
- Versión: **0.11.5** (instalado vía `brew install slither-analyzer`).
- **Necesita forge en PATH** (usa `forge config --json` internamente). Comando que funciona:
  ```bash
  cd /Users/firrton/Desktop/tokenización/packages/contracts && \
  PATH="/Users/firrton/.foundry/bin:$PATH" slither . --filter-paths "lib|test|phase2|<contratos-a-excluir>|libraries"
  ```
- Para scopear a un contrato, filtrar los OTROS con `--filter-paths`.

### 4.5 Falsos positivos de Slither ya silenciados (con justificación en NatSpec)
1. `naming-convention` en getters de `public constant` (`MAX_DUE_NUMERO_LENGTH`, `REDENCION_TIMEOUT`) — constantes DEBEN ser SCREAMING_SNAKE_CASE.
2. `unimplemented-functions` en `IAssetVault.totalSupply` — falso positivo de diamond inheritance vía `super`. Silenciado en el header del contrato AssetVault.
3. `timestamp` en el check `block.timestamp >= createdAt + REDENCION_TIMEOUT` — manipulación ±15s es 0.000003% de un threshold de 60 días.

### 4.6 6 findings Slither pre-existentes en AssetVault (NO silenciados — deuda técnica real)
- `calls-loop` ×4 en `reembolsarLoteFallido` (mitigado por `BatchTooLarge`)
- `cyclomatic-complexity` 12 en `reembolsarLoteFallido`
- `naming-convention` en parámetro `_redemptionManager`
- Estos se atienden cuando se haga el ciclo de AssetVault (Gap 3).

---

## 5. Comandos de referencia (los que funcionan en este entorno)

```bash
# Siempre desde la carpeta de contratos
cd /Users/firrton/Desktop/tokenización/packages/contracts

# Build
/Users/firrton/.foundry/bin/forge build

# Tests (todos)
/Users/firrton/.foundry/bin/forge test 2>&1 | rg "Suite result|FAIL"

# Tests de un contrato
/Users/firrton/.foundry/bin/forge test --match-contract RedemptionManager

# Test específico verbose
/Users/firrton/.foundry/bin/forge test --match-test "test_nombre" -vv

# Fuzz a 10k
/Users/firrton/.foundry/bin/forge test --fuzz-runs 10000

# Coverage (SIN invariants para evitar OOM)
/Users/firrton/.foundry/bin/forge coverage --no-match-path "test/invariant/**" --report summary

# Coverage lcov para ver branches específicas no cubiertas
/Users/firrton/.foundry/bin/forge coverage --no-match-path "test/invariant/**" --report lcov --report-file lcov.info
# Parsear branches no cubiertas de un contrato:
awk '/^SF:.*<Contrato>\.sol$/,/^end_of_record$/' lcov.info | rg "^BRDA:" | rg ",(-|0)$"

# Slither (scoped)
PATH="/Users/firrton/.foundry/bin:$PATH" slither . --filter-paths "lib|test|phase2|libraries"

# Format
/Users/firrton/.foundry/bin/forge fmt

# Git (NUNCA push directo a main — usar PR con feature branch)
```

**Nota sobre comandos largos:** correrlos en background (`run_in_background`) porque coverage/slither/invariant tardan minutos.

---

## 6. Los 4 GAPS CRÍTICOS — opciones y recomendaciones

### 🔴 Gap 1 — Integration / E2E tests (`test/integration/` VACÍO)

**Problema:** 149 unit tests verdes pero CERO pruebas cross-contract end-to-end.

| Opción | Scope | Veredicto |
|---|---|---|
| A — Solo happy-path lifecycle | 1 flujo compra→redención | Insuficiente |
| **B — Happy + flujos alternativos** ⭐ | Happy + lote fallido/refund + cancelación + cancel desde EN_EXPORTACION | **RECOMENDADA** |
| C — B + escenarios adversariales | + reentrancy cross-contract, role-confusion | Overkill (mejor para auditoría externa) |

**Recomendación: B.** Los flujos alternativos son operaciones reales del negocio. Lo adversarial se delega al auditor externo.

### 🔴 Gap 2 — Deploy scripts (`script/` VACÍO)

**Problema:** sin `DeployPlume.s.sol`. Dependencia cíclica: `AssetVault.setRedemptionManager` necesita la address de RedemptionManager.

| Opción | Approach | Veredicto |
|---|---|---|
| A — Monolítico `DeployAll.s.sol` | Un script todo | Rígido |
| **B — Modular per-contract + orquestador** ⭐ | Scripts separados + `DeployPlume.s.sol` orquestador + config env/JSON | **RECOMENDADA** |
| C — Modular + multi-chain | + capa Plume/Polygon | Prematuro (Polygon = fase 6) |

**Recomendación: B.** Matchea el naming del proyecto, resuelve la dependencia cíclica, testeable con `DeployTest.t.sol`.

### 🔴 Gap 3 — AssetVault coverage 41.67% branches → 100%

**Problema:** mismo gap que RedemptionManager pre-fix + 6 Slither findings. Contrato MÁS crítico (custodia USDC).

| Opción | Scope | Veredicto |
|---|---|---|
| A — Solo coverage a 100% | Tests de branches | Deja Slither sucio |
| **B — Coverage + Slither cleanup** ⭐ | Tests a 100% + atender los 6 findings | **RECOMENDADA** |
| C — Re-auditoría completa fresh | Audit nuevo → fix → ... | Overkill (ya tuvo audit 2026-05-19) |

**Recomendación: B.** Replica el ciclo que funcionó para RedemptionManager. Ojo: el `cyclomatic-complexity 12` de `reembolsarLoteFallido` puede requerir refactor real.

### 🔴 Gap 4 — IdentityRegistry coverage 48% branches → 100%

**Problema:** mismo patrón. **Diferencia:** Slither NO se corrió standalone — estado desconocido.

| Opción | Scope | Veredicto |
|---|---|---|
| A — Solo coverage a 100% | Tests de branches | Slither sigue desconocido |
| **B — Coverage + correr Slither scoped** ⭐ | Tests a 100% + destapar findings ocultos | **RECOMENDADA** |
| C — Re-auditoría completa fresh | Audit nuevo → ... | Overkill (ya tuvo audit 2026-05-22) |

**Recomendación: B.** Énfasis en correr Slither standalone primero — es el único gap con un "unknown".

### Orden recomendado de los 4 gaps
1. **Gap 1 (Integration tests)** — mayor riesgo no cubierto; los E2E destapan bugs de integración antes de invertir en coverage de branches.
2. **Gap 2 (Deploy scripts)** — habilita testnet; los integration tests pueden reusar el wiring.
3. **Gap 3 (AssetVault)** — el más crítico, ciclo conocido.
4. **Gap 4 (IdentityRegistry)** — mismo ciclo, último por ser menos crítico.

---

## 7. Gaps medios / bajos (para después de los críticos)

| # | Gap | Detalle |
|---|---|---|
| 5 | Invariant a escala spec (RM-29) | `50k×100` OOMea. Optimizar handler (bounded array) o documentar limitación formalmente. |
| 6 | CONTRACT-SPECS.md desactualizado | ADR-015/016/017 cambiaron comportamiento. Reconciliar spec source-of-truth. |
| 7 | Gas analysis doc de RedemptionManager | Falta `docs/gas-analysis/RedemptionManager-gas-*.md` (existe para los otros 2). |
| 8 | Audit doc de RedemptionManager es pre-ADR | `audit-RedemptionManager-deep-2026-05-26.md` se escribió ANTES de los ADRs. Agregar addendum con findings cerrados. |

## 8. Fuera del scope MVP

| # | Item | Razón |
|---|---|---|
| 9 | LabRegistry (4to contrato) | `phase2/`, reservado ADR-010 |
| 10 | Auditoría externa profesional (Sherlock/ToB/Cantina) | Milestone separado, gate final pre-mainnet |

---

## 9. Prompt sugerido para arrancar la próxima sesión

> Estamos continuando la fase de smart contracts del proyecto tokenization-platform. Leé `docs/SMART-CONTRACTS-HANDOFF.md` que tiene todo el contexto: estado actual, metodología, gotchas del entorno (forge en `/Users/firrton/.foundry/bin/`, coverage OOM con invariants, slither setup), y los 4 gaps críticos con sus opciones.
>
> RedemptionManager.sol ya está cerrado (100% coverage, slither clean, 3 ADRs). Quiero arrancar con el **Gap 1 (Integration tests, Opción B)**: flujos E2E happy + lote fallido/refund + cancelación. Usá el mismo flujo paso-a-paso: explicá qué vas a hacer, mostrame el código, aplicá, verificá con forge test, esperá mi visto bueno.
>
> Antes de empezar: confirmá el estado git (hay 4 commits en `feature/redemption-manager-option-b` sin mergear a main — habría que abrir PR #2).

---

## 10. Referencias

### ADRs creados este sprint
- `docs/architecture/ADR-015-timeout-policy.md` — buyer self-cancel después de 60d + compliance co-canceler (RM-06/07)
- `docs/architecture/ADR-016-pause-asymmetry-systemic.md` — pause=Compliance|Admin, unpause=Admin only, en los 3 contratos (RM-21)
- `docs/architecture/ADR-017-spec-reconciliation-export-state-machine.md` — 2 funciones, 3 fases (RM-11)

### Audits
- `docs/security-reviews/audit-RedemptionManager-deep-2026-05-26.md` (23 findings, pre-ADR)
- `docs/security-reviews/audit-AssetVault-deep-2026-05-19.md`
- `docs/security-reviews/audit-IdentityRegistry-deep-2026-05-22.md`

### Source files clave
- `packages/contracts/src/RedemptionManager.sol` (CERRADO — referencia de "cómo debe quedar")
- `packages/contracts/src/AssetVault.sol` (Gap 3)
- `packages/contracts/src/IdentityRegistry.sol` (Gap 4)
- `packages/contracts/src/interfaces/I*.sol`
- `packages/contracts/test/unit/*.t.sol` (tests por contrato)
- `packages/contracts/test/invariant/RedemptionManager.invariant.t.sol` (handler con RM-29 pendiente)
- `packages/contracts/test/{integration,fuzz}/` (VACÍOS — Gap 1)
- `packages/contracts/script/` (VACÍO — Gap 2)
- `packages/contracts/foundry.toml` (config: invariant runs=50000 depth=100)

### Reglas del proyecto
- `CLAUDE.md` (raíz) + `packages/contracts/CLAUDE.md` (reglas de área)
- `docs/architecture/CONTRACT-SPECS.md` (source of truth — parcialmente desactualizado, ver Gap 6)
- `docs/architecture/TEST-SPECS.md`
