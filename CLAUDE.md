# CLAUDE.md — tokenization-platform (raíz)

> Reglas obligatorias para cualquier agente de Claude Code que trabaje en este repositorio. Léelas antes de cualquier acción.

---

## 1. Identidad del proyecto

**Nombre:** tokenization-platform
**Tipo:** plataforma RWA (Real World Assets) tokenization con foco en commodities agrícolas. Empresa de tokenización con sede operativa en Bolivia.
**Primer caso de uso:** miel monofloral boliviana para exportación premium.
**Arquetipo:** plataforma genérica extensible a múltiples commodities (café, cacao, quinua, etc.).
**Multi-chain:** Plume Network (primaria) + Polygon PoS (secundaria, fase 6+).

---

## 2. Documentos rectores (fuente de verdad)

**Cualquier cambio que contradiga estos documentos requiere un ADR nuevo.**

- `docs/architecture/ARQUITECTURA-TECNICA-MVP.md` (v2.0) — arquitectura técnica completa
- `docs/business/PROPUESTA-TOKENIZACION-MIEL-BOLIVIANA.md` — propuesta conceptual + legal (responsabilidad del compañero legal, fuera del scope técnico de este repo)
- `docs/architecture/CONTRACT-SPECS.md` — specs detalladas de los 4 smart contracts
- `docs/architecture/TEST-SPECS.md` — specs de tests Foundry (TDD-first)
- `docs/architecture/ADR-*.md` — Architecture Decision Records (decisiones formales)

---

## 3. Stack tecnológico (resumen ejecutivo)

| Capa | Tecnología | Notas |
|---|---|---|
| Blockchain primario | Plume Network | L2 EVM RWA-focused |
| Blockchain secundario | Polygon PoS | fase 6+, mirror via SkyLink/CCIP |
| Smart contracts | Solidity 0.8.24+, OZ v5, Foundry | 4 contratos inmutables sin proxy |
| Backend | Bun + Hono + TypeScript + Drizzle ORM | Modular monolith |
| DB | PostgreSQL (Supabase) | ACID, audit log append-only |
| Frontend | Next.js 15 App Router + wagmi v2 + RainbowKit | Multi-chain |
| KYC | Sumsub + Plume Arc bridge | Tier 1/2/3 |
| Storage | Arweave (permanente) + Cloudflare R2 (operacional) | Triple storage |
| Oracle de hitos | Safe multi-firma 2-de-3 | Hardware wallets |
| Oracle de reservas | Chainlink Proof of Reserve | BUILD program |
| Oracle de calidad | LabRegistry + QualityAttestation | Custom on-chain |
| Monorepo | Turborepo + pnpm workspaces | NUNCA npm/npx |

---

## 4. Reglas obligatorias globales (checklist)

Cualquier agente que toque este repo debe cumplir:

- [ ] **SIEMPRE** usar `pnpm` / `pnpm dlx` — NUNCA `npm` / `npx` (CLAUDE.md global del usuario)
- [ ] **SIEMPRE** seguir el loop estricto: build → test → document → review
- [ ] **SIEMPRE** escribir tests antes de implementación (TDD: red-green-refactor)
- [ ] **SIEMPRE** crear ADR si la decisión arquitectónica se desvía o cambia
- [ ] **SIEMPRE** validar inputs con Zod en backend
- [ ] **SIEMPRE** usar custom errors en Solidity (NO string reverts)
- [ ] **SIEMPRE** NatSpec completo en funciones Solidity públicas
- [ ] **NUNCA** commitear `.env`, `.env.local`, secrets, claves privadas
- [ ] **NUNCA** usar `bash cat/grep/find/sed/ls/echo` — usar `bat/rg/fd/sd/eza` (regla global usuario)
- [ ] **NUNCA** instalar paquetes externos sin verificación de origen
- [ ] **NUNCA** ejecutar `curl | bash` ni scripts remotos no verificados
- [ ] **NUNCA** override decisiones arquitectónicas sin ADR
- [ ] **NUNCA** mintear tokens sin KYC verificado on-chain
- [ ] **NUNCA** permitir transferencias P2P del token (override `_update()` lo bloquea)
- [ ] **NUNCA** exponer endpoints admin sin 2FA (Clerk)
- [ ] **NUNCA** usar `tx.origin` en Solidity (siempre `msg.sender`)
- [ ] **NUNCA** confiar en `block.timestamp` para randomness o decisiones críticas

---

## 5. Workflow loop estricto (build → test → doc → review)

Ningún cambio se considera "hecho" sin pasar por los 4 pasos:

1. **Build** — implementar el cambio (código, config, doc). Comitearlo con mensaje convencional.
2. **Test** — verificar:
   - Tests existentes pasan (`pnpm test`)
   - Tests nuevos cubren el cambio (TDD: deben existir antes que el código)
   - Coverage no baja
3. **Document** — actualizar:
   - README de área si aplica
   - ADR si cambio arquitectónico
   - NatSpec si se modificó signature de contrato
   - `docs/ITERATION-LOG.md` con entrada de la iteración
4. **Review** — si el cambio toca:
   - Smart contracts → invocar `solidity-security` skill + análisis Slither
   - Secrets / KMS / auth → review manual obligatorio
   - Cross-chain logic → review manual obligatorio

---

## 6. Apuntadores a sub-CLAUDE.md por área

Cada subagente especializado debe leer **su CLAUDE.md correspondiente**, NO los demás (aislamiento de contexto):

- `packages/contracts/CLAUDE.md` — para smart contracts Solidity
- `apps/api/CLAUDE.md` — para backend Bun + Hono
- `apps/web/CLAUDE.md` — para frontend Next.js
- `docs/subagents/SUBAGENT-REGISTRY.md` — registry maestro de subagentes

---

## 7. Comandos comunes

**Setup local:**
```bash
pnpm install
cp .env.example .env.local  # editar con credenciales reales (NO commitear)
```

**Smart contracts (en `packages/contracts/`):**
```bash
forge install                                       # instalar dependencias Foundry
forge build                                         # compilar
forge test -vvv                                     # tests verbose
forge test --fuzz-runs 10000                        # fuzz testing
forge test --invariant-runs 50000                   # invariant testing
forge coverage                                      # coverage report
forge fmt                                           # formatear código
slither .                                           # análisis estático seguridad
forge script script/Deploy.s.sol --rpc-url $RPC --broadcast --verify
```

**Backend (en `apps/api/`):**
```bash
bun dev                                             # dev server
bun test                                            # tests unitarios
pnpm db:generate                                    # generar migraciones Drizzle
pnpm db:migrate                                     # aplicar migraciones
```

**Frontend (en `apps/web/`):**
```bash
pnpm dev                                            # dev server Next.js
pnpm build                                          # production build
pnpm test                                           # tests unitarios
pnpm test:e2e                                       # Playwright E2E
```

**Monorepo:**
```bash
pnpm dev                                            # arranca todo (turbo dev)
pnpm build                                          # build de todo
pnpm test                                           # tests de todo
pnpm lint                                           # lint de todo
pnpm type-check                                     # type check de todo
```

---

## 8. Lo que un subagente NO debe hacer (sección crítica)

- ❌ Instalar paquetes de fuentes no verificadas (npm registry sin auditoría, paquetes con baja reputación, paquetes que requieran `--force` o `--legacy-peer-deps`)
- ❌ Ejecutar scripts remotos (`curl | bash`, `wget | sh`) sin verificar checksum manual
- ❌ Override decisiones arquitectónicas sin crear primero un ADR
- ❌ Tocar archivos fuera de su scope acotado (el subagente de contracts NO toca `apps/web`, etc.)
- ❌ Usar `npm` o `npx` en lugar de `pnpm` / `pnpm dlx`
- ❌ Commitear sin que tests pasen
- ❌ Commitear archivos `.env*`, claves privadas, secrets, dumps de DB con PII
- ❌ Modificar archivos críticos sin ADR:
  - `docs/architecture/ARQUITECTURA-TECNICA-MVP.md`
  - `docs/architecture/CONTRACT-SPECS.md`
  - `docs/architecture/TEST-SPECS.md`
  - `docs/architecture/ADR-*.md` ya aprobados
- ❌ Agregar dependencias sin justificación documentada
- ❌ Saltarse pre-commit hooks (`--no-verify`)
- ❌ Force-push a `main` o `develop`

---

## 9. Seguridad operacional (regla crítica)

- **Llaves operativas:** viven en HSM (AWS KMS / GCP KMS) o hardware wallets (Ledger Nano X). NUNCA en env vars de producción.
- **Backend signer wallet:** referencia KMS (`BACKEND_SIGNER_KMS_KEY_ID`), NO la clave privada.
- **Multi-sig 2-de-3 obligatorio** para operaciones críticas on-chain (oracle, treasury, admin).
- **Audit log append-only:** la tabla `audit_log` tiene policy PostgreSQL que revoca UPDATE/DELETE a todos los roles excepto un backup admin específico.
- **Hash chain en audit log:** cada fila contiene hash de la anterior, detecta manipulación retroactiva.
- **Webhooks:** validar firma HMAC SHA-256 antes de procesar (Sumsub, Stripe, MoonPay, Ramp).
- **Rate limiting:** todos los endpoints públicos con rate limit (Redis-backed).
- **CORS estricto:** solo dominios propios.
- **No PII en logs:** sanear nombre, dirección, doc identidad antes de loggear.

---

## 10. Reglas de commits y branches

- **Conventional Commits obligatorio:** `feat:`, `fix:`, `chore:`, `docs:`, `refactor:`, `test:`, `ci:`
- **Branches:** `main` (producción), `develop` (integración), `feature/<nombre>`, `fix/<nombre>`, `hotfix/<nombre>`
- **NUNCA** "Co-Authored-By" o AI attribution en commits (regla global del usuario)
- **Mínimo 1 reviewer** para PRs a `develop`
- **Mínimo 2 reviewers** para PRs a `main`
- **Squash merge** por defecto

---

## 11. Idioma

- **Persona / texto en respuestas al usuario:** español rioplatense (voseo), warm pero directo
- **Código, identifiers, comments, UI strings, docs técnicas:** **inglés** por default (excepto cuando el dominio de negocio usa español rioplatense intencionalmente, como `comprar`, `confirmarCosecha`, `LoteMiel`)
- **Documentación de arquitectura, ADRs, READMEs:** español rioplatense (ya es la convención del proyecto)

---

## 12. Archivos críticos a leer ANTES de cualquier cambio

Cualquier agente que toque este repo, **antes de su primer cambio**, debe leer:

1. **Este archivo** (`CLAUDE.md` raíz)
2. **`/Users/firrton/.claude/CLAUDE.md`** (reglas globales del usuario, aplican siempre)
3. **`docs/architecture/ARQUITECTURA-TECNICA-MVP.md`** (v2.0)
4. **CLAUDE.md de su área** (contracts / api / web)
5. **`docs/subagents/SUBAGENT-REGISTRY.md`** (registry de subagentes)

Cualquier agente que toque smart contracts, **adicionalmente**:
- `docs/architecture/CONTRACT-SPECS.md`
- `docs/architecture/TEST-SPECS.md`
- ADRs relevantes (`ADR-001` a `ADR-005` para smart contracts)

---

**Última actualización:** 2026-05-19
**Versión del proyecto:** 0.1.0 (MVP en desarrollo)
