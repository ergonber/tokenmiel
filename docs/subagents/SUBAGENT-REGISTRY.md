# Subagent Registry

> Registry maestro de subagentes especializados del proyecto. Cada subagente tiene scope acotado, lee solo la documentación correspondiente, y produce outputs específicos. Este aislamiento reduce riesgo de prompt injection cross-area y errores por contexto incompleto.

---

## Principios de aislamiento

1. **Scope acotado:** cada subagente tiene un conjunto limitado de archivos que puede tocar.
2. **Documentación dirigida:** cada subagente lee solo los archivos relevantes a su área.
3. **Sin contaminación cross-area:** el subagente de contracts NO toca frontend, etc.
4. **Comandos limitados:** cada subagente solo puede ejecutar comandos relacionados con su área.
5. **Output documentado:** cada subagente produce artefactos específicos que se versionan.

---

## Subagentes definidos

### 1. `contracts-engineer`

**Rol:** implementar smart contracts Solidity siguiendo specs.

**Scope:**
- ✅ `packages/contracts/**`
- ✅ `packages/abis/**` (lectura/escritura para codegen)
- ❌ `apps/**`, `packages/ui/**`, `packages/db/**`

**Skills relevantes:**
- `solidity-testing`
- `solidity-security`
- `foundry-solidity`
- `web3-testing`
- `account-abstraction` (si toca Smart Wallets)

**Archivos críticos a leer ANTES:**
1. `/Users/firrton/Desktop/tokenización/CLAUDE.md` (raíz)
2. `/Users/firrton/Desktop/tokenización/packages/contracts/CLAUDE.md`
3. `docs/architecture/CONTRACT-SPECS.md` (source of truth)
4. `docs/architecture/TEST-SPECS.md` (TDD-first)
5. `docs/architecture/ADR-001` a `ADR-005`
6. `docs/architecture/ARQUITECTURA-TECNICA-MVP.md` §6, §7, §7B

**Comandos permitidos:**
- `forge build`, `forge test`, `forge fmt`, `forge coverage`
- `slither .`, `mythril analyze`
- `cast` (interactuar con cadena)
- `forge script` (deployment)

**Comandos prohibidos:**
- `npm`, `npx` (usar `pnpm`)
- `curl | bash`, `wget | sh`
- Cualquier cosa que toque `apps/**` o `packages/ui/**` o `packages/db/**`

**Outputs esperados:**
- `packages/contracts/src/*.sol` (4 contratos + interfaces + libraries)
- `packages/contracts/test/**/*.t.sol` (suite completa de tests)
- `packages/contracts/script/*.s.sol` (deployment scripts)
- Coverage report ≥ 100% líneas/branches
- Slither sin issues high

---

### 2. `tests-engineer`

**Rol:** implementar tests Foundry (unit, fuzz, invariant, integration).

**Scope:**
- ✅ `packages/contracts/test/**`
- ✅ `packages/contracts/src/**` (solo lectura para entender lo que testea)
- ❌ `apps/**`, `packages/ui/**`

**Skills relevantes:**
- `solidity-testing` (auto-invoke)
- `foundry-solidity`
- `web3-testing`

**Archivos críticos a leer ANTES:**
1. `CLAUDE.md` raíz
2. `packages/contracts/CLAUDE.md`
3. `docs/architecture/TEST-SPECS.md`
4. `docs/architecture/CONTRACT-SPECS.md` (para entender lo que testea)

**Comandos permitidos:**
- `forge test`, `forge coverage`, `forge fmt`
- `forge snapshot` (gas snapshots)

**Outputs esperados:**
- `packages/contracts/test/unit/*.t.sol`
- `packages/contracts/test/fuzz/*.fuzz.t.sol`
- `packages/contracts/test/invariant/*.invariant.t.sol`
- `packages/contracts/test/integration/*.t.sol`
- Coverage ≥ 100% líneas/branches
- Fuzz runs ≥ 10,000
- Invariant runs ≥ 50,000, depth 100

---

### 3. `security-auditor`

**Rol:** review de seguridad de smart contracts, identificar vulnerabilidades, proponer mitigaciones.

**Scope:**
- ✅ `packages/contracts/**` (solo lectura, NO modificar código directamente)
- ✅ `docs/security-reviews/` (escribir reportes)

**Skills relevantes:**
- `solidity-security` (auto-invoke)
- `web3-testing`

**Archivos críticos a leer ANTES:**
1. `CLAUDE.md` raíz
2. `packages/contracts/CLAUDE.md`
3. Todos los `packages/contracts/src/*.sol`
4. Todos los tests existentes
5. `docs/architecture/ARQUITECTURA-TECNICA-MVP.md` §17 (capa de seguridad)
6. ADRs: ADR-003, ADR-004, ADR-005

**Comandos permitidos:**
- `slither .` (análisis estático)
- `mythril analyze` (análisis simbólico)
- `forge test --fuzz-runs 100000` (stress testing)
- `forge inspect <contract> storage-layout`

**Comandos prohibidos:**
- Modificar código (solo crear issues / reportes)

**Outputs esperados:**
- `docs/security-reviews/audit-report-YYYY-MM-DD.md` con findings clasificados:
  - **Critical** — explotable, alto impacto, fix urgente
  - **High** — explotable con condiciones, fix antes de mainnet
  - **Medium** — riesgo no inmediato pero a mitigar
  - **Low** — best practice, ideal pero no bloqueante
  - **Informational** — comentarios, mejoras DX

**Categorías de vulnerabilidades a cubrir:**
- Reentrancy (CEI pattern, nonReentrant)
- Integer overflow/underflow (Solidity 0.8+ protege, pero unchecked blocks)
- Access control gaps (missing role checks)
- Signature replay (nonces, EIP-712 domain)
- Oracle manipulation (Chainlink staleness, multi-sig collusion)
- Front-running, MEV (private mempool, commit-reveal)
- Gas griefing (unbounded loops, gas-bombing)
- Logic errors (state machine bugs, off-by-one)
- Storage collisions (no aplica si no hay proxy, pero verificar)
- Compilation warnings (Slither y compiler warnings)

---

### 4. `backend-engineer`

**Rol:** implementar módulos del backend (Bun + Hono + Drizzle).

**Scope:**
- ✅ `apps/api/**`
- ✅ `packages/db/**`, `packages/shared/**` (lectura/escritura para tipos compartidos)
- ❌ `packages/contracts/**`, `apps/web/**`, `packages/ui/**`

**Skills relevantes:**
- (no skills específicas de Bun/Hono en el ecosistema oficial; usar conocimiento general TypeScript)

**Archivos críticos a leer ANTES:**
1. `CLAUDE.md` raíz
2. `apps/api/CLAUDE.md`
3. `docs/architecture/ARQUITECTURA-TECNICA-MVP.md` §13, §22, §23
4. Schemas existentes en `packages/db/src/schema/`
5. Tipos en `packages/shared/src/`
6. ADR-007 (stack backend)

**Comandos permitidos:**
- `bun install`, `bun dev`, `bun test`
- `pnpm db:generate`, `pnpm db:migrate`, `pnpm db:studio`
- `pnpm lint`, `pnpm type-check`

**Outputs esperados:**
- `apps/api/src/modules/<module>/` (estructura hexagonal completa)
- Schemas Drizzle en `packages/db/src/schema/`
- Schemas Zod en `packages/shared/src/schemas/`
- Tests unitarios + integration
- OpenAPI spec actualizado en `docs/api/openapi.yaml`

---

### 5. `frontend-engineer`

**Rol:** implementar UI del frontend (Next.js 15 + wagmi v2 + RainbowKit + shadcn/ui).

**Scope:**
- ✅ `apps/web/**`
- ✅ `packages/ui/**`, `packages/shared/**`
- ❌ `packages/contracts/**`, `apps/api/**`, `packages/db/**`

**Archivos críticos a leer ANTES:**
1. `CLAUDE.md` raíz
2. `apps/web/CLAUDE.md`
3. `docs/architecture/ARQUITECTURA-TECNICA-MVP.md` §14, §22, §23
4. ABIs en `packages/abis/src/`
5. Tipos en `packages/shared/src/`

**Comandos permitidos:**
- `pnpm dev`, `pnpm build`, `pnpm start`
- `pnpm test`, `pnpm test:e2e`, `pnpm test:a11y`
- `pnpm storybook`

**Outputs esperados:**
- Components, pages, hooks en `apps/web/src/`
- Componentes reusables en `packages/ui/src/`
- Tests Vitest + Playwright
- i18n strings en `apps/web/messages/<locale>.json`
- WCAG AA compliance

---

### 6. `docs-curator`

**Rol:** mantener documentación viva, ADRs, runbooks, READMEs.

**Scope:**
- ✅ `docs/**`
- ✅ Cualquier `README.md` de área
- ✅ `CLAUDE.md` por área (en coordinación con otros subagentes)
- ❌ Código de producción (`apps/**/src`, `packages/contracts/src`, etc.)

**Skills relevantes:**
- `cognitive-doc-design`
- `skill-creator` (si crea skills nuevas)

**Archivos críticos a leer ANTES:**
1. `CLAUDE.md` raíz
2. Todos los `CLAUDE.md` de área (para contexto)
3. ADRs existentes en `docs/architecture/`
4. `docs/architecture/ARQUITECTURA-TECNICA-MVP.md`

**Comandos permitidos:**
- Solo lectura de código (`bat`, `rg`, etc.)
- Escritura en `docs/**` y archivos `*.md`

**Outputs esperados:**
- ADRs en `docs/architecture/ADR-XXX.md`
- Runbooks en `docs/runbooks/*.md`
- READMEs por área
- OpenAPI spec
- Onboarding docs (`CONTRIBUTING.md`, `ONBOARDING.md`)
- ITERATION-LOG.md (bitácora del loop iterativo)

---

## Reglas universales para todos los subagentes

1. **Leer SIEMPRE el CLAUDE.md raíz primero**, después el CLAUDE.md de área.
2. **Respetar el scope** — no tocar archivos fuera de su área.
3. **TDD obligatorio** para código (tests antes de implementación).
4. **Loop estricto** build → test → document → review.
5. **Sin instalación de paquetes externos** sin verificación (sin `curl | bash`, sin paquetes no maintainados, sin `npm install`).
6. **Custom errors en Solidity** — no string reverts.
7. **Zod validation** en backend para toda entrada.
8. **WCAG AA** en frontend.
9. **PII nunca en logs** sin sanear.
10. **Documentar en ITERATION-LOG.md** cada cambio significativo.

---

## Workflow inter-subagente

```
                       ┌──────────────────┐
                       │  docs-curator    │ (mantiene docs viva)
                       └──────────────────┘
                                ▲
                                │
       ┌────────────────────────┼────────────────────────┐
       │                        │                        │
       ▼                        ▼                        ▼
┌──────────────┐       ┌──────────────────┐       ┌──────────────┐
│  contracts-  │       │  backend-        │       │  frontend-   │
│  engineer    │       │  engineer        │       │  engineer    │
└──────────────┘       └──────────────────┘       └──────────────┘
       │                        │                        │
       │  (ABIs codegen)        │  (uses ABIs read)      │  (uses ABIs read)
       ▼                        ▼                        ▼
┌──────────────────────────────────────────────────────────────┐
│            packages/abis/  ←  source of truth shared          │
└──────────────────────────────────────────────────────────────┘
       │
       ▼
┌──────────────┐
│  tests-      │  (paralelo a contracts-engineer, TDD)
│  engineer    │
└──────────────┘
       │
       ▼
┌──────────────────┐
│  security-       │  (después de contracts + tests)
│  auditor         │
└──────────────────┘
```

---

## Comandos NUNCA permitidos (todos los subagentes)

- ❌ `npm`, `npx`, `npm install`, `npx ...`
- ❌ `curl <url> | bash`, `wget <url> | sh`
- ❌ `sudo` (no permisos elevados)
- ❌ `rm -rf` con paths absolutos no relacionados al proyecto
- ❌ `git push --force` (a `main`, `develop`)
- ❌ `git commit --no-verify` (saltar hooks)
- ❌ Modificar `~/.zshrc`, `~/.bashrc`, `~/.gitconfig`, otros configs del usuario fuera del proyecto

---

**Última actualización:** 2026-05-19
**Maintainer:** Dany Hidalgo F.
