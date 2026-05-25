# ADR-006: Monorepo Turborepo + pnpm workspaces

**Status:** Accepted
**Date:** 2026-05-19
**Author:** Dany Hidalgo F.
**Tags:** repo-structure, monorepo, turborepo, pnpm

---

## Context

El proyecto incluye múltiples artefactos:
- Smart contracts Solidity (Foundry)
- Backend Bun + Hono + Drizzle
- Frontend Next.js 15
- Tipos compartidos, schemas Zod, ABIs generados
- Configs compartidos (eslint, tsconfig, tailwind, prettier)
- Componentes UI compartidos (shadcn/ui)
- Tools y scripts operacionales

La organización del código (monorepo vs polirepo) impacta DX, tipo-safety end-to-end, CI/CD, gestión de dependencias, refactoring, y onboarding de developers.

---

## Decision

**Monorepo único con:**
- **Gestión de paquetes:** pnpm con workspaces (`pnpm-workspace.yaml`)
- **Orquestación de builds:** Turborepo (cache local + remote en Vercel)
- **Estructura:** `apps/` (apps deployables) + `packages/` (libs compartidas) + `tools/` (scripts) + `docs/`

**Prohibido:** `npm` y `npx` (regla global del usuario en `~/.claude/CLAUDE.md` por riesgo de supply-chain attacks en npm registry).

---

## Alternatives considered

### Polirepo (3 repos: contracts, api, web)
- ✅ Separación física estricta, deployments independientes
- ❌ Tipos sincronizados via npm packages publicados (lento, requiere version bumps)
- ❌ 3 PRs para un feature cross-stack
- ❌ Overhead alto para equipo chico (2-4 personas MVP)
- ❌ Refactoring cross-package costoso

### Monorepo con pnpm workspaces (sin Turborepo)
- ✅ Misma estructura, más simple
- ❌ Builds sin caching incremental
- ❌ CI más lento a medida que crece el repo

### Monorepo con Nx
- ✅ Más features que Turborepo
- ❌ Mayor overhead de configuración
- ❌ Steeper learning curve
- ❌ Más opinated, menos flexibilidad

### Monorepo con Rush
- ❌ Microsoft-focused, menos adopción en ecosistema JS moderno

### Monorepo con yarn workspaces
- ❌ Usuario tiene regla estricta contra `npm`/`npx`; yarn classic ya deprecated
- ❌ pnpm tiene mejor performance + symlinks correctos

---

## Consequences

### Positive

- **Tipos compartidos en tiempo real:** cambio en `LoteMiel` struct → `forge build` regenera ABI → `wagmi generate` regenera tipos TS → backend y frontend ven el cambio inmediatamente. Sin sincronización manual.
- **Refactoring atómico cross-package** (cambiar schema + uso en backend + uso en frontend en un solo commit).
- **CI/CD único** con builds incrementales (Turborepo detecta qué packages cambiaron).
- **Onboarding simplificado** para nuevos developers (un solo repo a clonar).
- **Convenciones unificadas:** un solo `.eslintrc`, `tsconfig`, `prettierrc` base.
- **DX moderno** estándar de industria (Vercel, Linear, Cal.com, todos en Turborepo).
- **Remote cache** en Vercel (gratis hasta cierto uso) acelera CI a segundos.

### Negative

- **Repo grande** cuando crece (mitigado: Turborepo cache + `.gitignore` agresivo).
- **CI más complejo de configurar** que polirepo single-package.
- **Riesgo de tight coupling** entre packages (mitigado: reglas claras de dependencias).

### Neutral

- **pnpm tiene curve menor** que yarn pero más que npm (mitigado: docs clara en README).

---

## Implementation notes

### Estructura
```
tokenization-platform/
├── apps/
│   ├── web/                       # Next.js 15
│   └── api/                       # Bun + Hono
├── packages/
│   ├── contracts/                 # Foundry
│   ├── shared/                    # tipos, schemas Zod
│   ├── ui/                        # shadcn/ui compartidos
│   ├── config/                    # eslint, tsconfig, prettier
│   ├── db/                        # Drizzle schemas + migrations
│   └── abis/                      # ABIs y types generados
├── tools/
│   └── scripts/                   # scripts operacionales
├── docs/
│   ├── architecture/              # ADRs
│   ├── runbooks/
│   ├── subagents/                 # CLAUDE.md por subagente
│   └── api/
├── .github/workflows/
├── turbo.json
├── pnpm-workspace.yaml
└── package.json
```

### Reglas de dependencias entre packages

```
apps/web      → packages/{ui, shared, abis, config}
apps/api      → packages/{db, shared, abis, config}
packages/db   → packages/{shared, config}
packages/ui   → packages/{shared, config}
packages/abis → packages/contracts (codegen, no runtime dep)
```

**Regla estricta:** `packages/contracts` (Solidity) es la **fuente de verdad** de los tipos del dominio on-chain. Cualquier cambio en structs/eventos genera (via `wagmi generate`) tipos TypeScript en `packages/abis`, que propagan a apps.

### Versionado interno

- Workspace packages usan `workspace:*` en `package.json` dependencies
- pnpm resuelve a las versiones locales automáticamente
- Sin npm publish (excepto si decidimos publicar algún package en el futuro)

### Comandos comunes

```bash
pnpm install                       # instala TODO el monorepo
pnpm dev                            # turbo dev (paralelo)
pnpm build                          # turbo build (con caching)
pnpm test                           # turbo test (paralelo)
pnpm lint                           # turbo lint (paralelo)
pnpm type-check                     # turbo type-check

# Scoped (solo un package)
pnpm --filter @miel/web dev
pnpm --filter @miel/contracts test
```

### Anti-patterns prohibidos

- ❌ `npm install` en cualquier package (rompe pnpm workspaces)
- ❌ `npx <comando>` (usar `pnpm dlx <comando>` solo si paquete verificado)
- ❌ Dependencias circulares entre packages
- ❌ `package.json` sin `"private": true` en workspace packages (riesgo de publish accidental)
- ❌ Duplicar dependencias entre packages (consolidar en root o en config compartido)

---

## References

- ARQUITECTURA-TECNICA-MVP.md §19 (estructura del monorepo)
- Turborepo docs: https://turbo.build/repo/docs
- pnpm workspaces: https://pnpm.io/workspaces
- CLAUDE.md global del usuario (~/.claude/CLAUDE.md) — regla "Never use npm or npx"
