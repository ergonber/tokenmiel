# CLAUDE.md — apps/api (backend Bun + Hono)

> Reglas obligatorias para cualquier agente que trabaje con el backend. Scope acotado: SOLO archivos en `apps/api/` (excepto lectura de ABIs en `packages/abis/`, schemas en `packages/db/`, tipos en `packages/shared/`).

---

## 1. Scope

**Lo que SÍ podés tocar:**
- `apps/api/src/**` — código backend
- `apps/api/tests/**` — tests backend
- `apps/api/package.json`, `apps/api/tsconfig.json`
- `apps/api/drizzle.config.ts`
- `packages/db/src/**` — schemas Drizzle (compartido con el backend)
- `packages/shared/src/**` — tipos/schemas Zod compartidos

**Lo que NO podés tocar:**
- `packages/contracts/**` — smart contracts (otra área)
- `apps/web/**` — frontend (otra área)
- `packages/ui/**` — componentes UI

**Solo lectura permitida en:**
- `packages/abis/src/**` — ABIs generados por wagmi (NO editar manualmente)

---

## 2. Stack

| Componente | Tecnología | Versión |
|---|---|---|
| Runtime | Bun | 1.x |
| Framework HTTP | Hono | 4.x |
| Lenguaje | TypeScript | 5.x |
| ORM | Drizzle | latest stable |
| DB | PostgreSQL | 16+ (via Supabase managed) |
| Cache / Queues | Redis | latest (via Upstash) |
| Validación | Zod | latest stable |
| Cliente Web3 | viem | 2.x |
| Auth | Clerk | latest |
| Logger | pino | latest |
| Job scheduler | BullMQ | latest |
| Testing | Vitest | latest |
| HTTP test | Hono test client | included |

---

## 3. Arquitectura

**Patrón:** **Modular Monolith** (un proceso, múltiples módulos con boundaries claros).

**Justificación (ver ARQUITECTURA-TECNICA-MVP.md §13.2):** microservicios añaden complejidad operacional (deployment, networking, distributed tracing) que no justifica el equipo MVP. Permite refactorizar a microservicios cuando el volumen lo justifique.

**Módulos definidos** (NO inventar nuevos sin justificación documentada):

| Módulo | Propósito |
|---|---|
| `assets/` | categorías de activos tokenizables (miel, café, cacao...) |
| `lots/` | lotes individuales con ciclo de vida |
| `identity/` | KYC sync con Sumsub + bridge Plume Arc + screening sancionados |
| `quality/` | oráculo de calidad: integración con labs, attestations |
| `payments/` | Stripe + SWIFT + MoonPay + Ramp + reconciliación |
| `documents/` | upload a Arweave + R2, hash SHA-256, catálogo |
| `oracle/` | preparación de tx Safe multi-sig |
| `chainlink/` | integración Proof of Reserve + BUILD program |
| `crosschain/` | mirror Plume↔Polygon (fase 6+) |
| `audit/` | log append-only con hash chain + snapshots mensuales |
| `notifications/` | email transaccional (Resend) + Slack |
| `shared/` | cross-cutting (logger, errors, types, middleware) |

**Patrón interno por módulo (Hexagonal / Ports & Adapters):**

```
modules/<name>/
├── domain/         (entities, value objects, domain logic)
├── application/    (use cases, application services)
├── infrastructure/ (repositories, external integrations)
└── api/            (Hono routes, DTOs Zod, request handlers)
```

---

## 4. Archivos críticos a leer ANTES de cualquier cambio

1. `/Users/firrton/Desktop/tokenización/CLAUDE.md` (raíz, reglas globales del proyecto)
2. **Este archivo** (CLAUDE.md de área)
3. **`ARQUITECTURA-TECNICA-MVP.md`** secciones 13 (capa backend), 22 (módulos), 23 (flujos críticos)
4. **`packages/db/src/schema/*`** para schemas de DB
5. **`packages/shared/src/*`** para tipos compartidos
6. **`packages/abis/src/*`** para ABIs on-chain (lectura)
7. **ADRs relevantes:** ADR-007 (stack backend), ADR-001 (multi-chain), ADR-004 (oracle), ADR-005 (lab registry)

---

## 5. Reglas obligatorias

### 5.1 Validación
- [ ] **TODA** entrada HTTP validada con Zod schema antes de tocar lógica
- [ ] Schemas Zod en `packages/shared/src/schemas/` para reutilización
- [ ] Errors de validación devuelven 400 con detalle estructurado (NO 500)

### 5.2 Errors y logs
- [ ] **NUNCA** `throw "string"` — usar Error class custom
- [ ] **NUNCA** `console.log` — usar pino (logger estructurado)
- [ ] **NUNCA** loggear PII (nombre completo, dirección, doc identidad) — sanear primero
- [ ] Errors estructurados con campo `code` para clasificación (auth_failed, kyc_required, etc.)
- [ ] Logs incluyen `traceId` para trazabilidad

### 5.3 Database
- [ ] Drizzle ORM **siempre** — prohibido SQL raw sin parametrizar
- [ ] Migraciones versionadas en `packages/db/migrations/`
- [ ] Tabla `audit_log` append-only — policy PostgreSQL revoca UPDATE/DELETE
- [ ] Hash chain en audit_log: cada row contiene `prev_hash`
- [ ] **PII cifrada at-rest** donde aplique
- [ ] Conexión via connection pooler (pgbouncer en Supabase)

### 5.4 Auth y autorización
- [ ] Clerk middleware en TODO endpoint que no sea estrictamente público
- [ ] **2FA obligatorio** para usuarios con role admin
- [ ] Role-based access control (RBAC) en cada endpoint
- [ ] Verificación de scope/permission antes de ejecutar lógica

### 5.5 Webhooks
- [ ] **TODA** validación de firma HMAC SHA-256 ANTES de procesar
- [ ] Idempotencia obligatoria (tabla `webhook_log` con event_id único)
- [ ] Rate limiting agresivo
- [ ] Timeout corto (5s) para no bloquear el emisor

### 5.6 Secrets
- [ ] **NUNCA** secrets hardcodeados en código
- [ ] **NUNCA** secrets en logs
- [ ] Secrets desde env vars (en dev), KMS en prod
- [ ] **Backend signer wallet:** referencia KMS (`BACKEND_SIGNER_KMS_KEY_ID`), no clave privada raw
- [ ] `.env.local` en `.gitignore`

### 5.7 Rate limiting
- [ ] Todos los endpoints públicos con rate limit (Redis-backed)
- [ ] Endpoints sensibles (KYC, payments) con rate más estricto
- [ ] Por IP + por user

### 5.8 CORS
- [ ] CORS estricto: solo dominios propios (`web.tokenization-platform.com` u otro)
- [ ] Methods explícitos (GET, POST, PUT, DELETE — no `*`)
- [ ] Credentials solo donde aplique

---

## 6. Comandos comunes

```bash
# Setup
bun install

# Dev
bun dev                                       # arranca server con hot reload
bun run --watch src/server.ts                 # alternativa explícita

# Tests
bun test                                      # tests unitarios
bun test:integration                          # tests integration (requiere DB local)
bun test --coverage                           # con coverage

# DB (Drizzle)
pnpm db:generate                              # generar migraciones desde schema
pnpm db:migrate                               # aplicar migraciones
pnpm db:studio                                # Drizzle Studio (UI)
pnpm db:push                                  # push schema sin migración (dev only)

# Linting / type-check
pnpm lint
pnpm type-check

# Production build
bun build src/server.ts --outdir dist --target bun
```

---

## 7. Lo que NO debe hacer en esta área

- ❌ Usar `console.log` — usar `pino`
- ❌ Usar `npm` / `npx` — usar `pnpm` / `pnpm dlx` (regla global)
- ❌ Hacer `JSON.stringify` de objetos con PII sin sanear
- ❌ Ejecutar SQL raw sin parametrizar (Drizzle previene esto, no rompas esa garantía)
- ❌ Tocar `packages/contracts/` (esa es otra área)
- ❌ Tocar `apps/web/` (esa es otra área)
- ❌ Almacenar claves privadas en DB ni env vars (solo referencias KMS)
- ❌ Procesar webhook sin validar firma HMAC primero
- ❌ Saltarse Zod validation porque "es solo para admin"
- ❌ Permitir UPDATE o DELETE en `audit_log` (la policy DB lo previene, NO crear excepciones)
- ❌ Loggear payloads completos sin sanear PII
- ❌ Usar cliente HTTP custom (usar `fetch` global de Bun o `viem` para Web3)
- ❌ Crear módulo nuevo sin justificación documentada (los módulos están definidos)
- ❌ Saltarse rate limiting porque "es endpoint interno"
- ❌ Devolver stack traces a clientes en respuestas de error

---

## 8. Estructura de un módulo (template)

```
apps/api/src/modules/<name>/
├── domain/
│   ├── entities/
│   │   └── <Entity>.ts
│   ├── value-objects/
│   └── events/
├── application/
│   ├── use-cases/
│   │   └── <UseCase>.ts
│   └── services/
├── infrastructure/
│   ├── repositories/
│   │   └── <Entity>Repository.ts
│   ├── external/
│   │   └── <ExternalAdapter>.ts
│   └── on-chain/
│       └── <ContractClient>.ts
├── api/
│   ├── routes/
│   │   └── <routes>.routes.ts
│   ├── dto/
│   │   └── <Dto>.dto.ts
│   └── handlers/
│       └── <handler>.handler.ts
├── tests/
│   ├── unit/
│   └── integration/
└── README.md                  # descripción del módulo
```

---

## 9. Workflow loop dentro del área

Cada cambio en `apps/api/`:

1. **Build:**
   - Definir Zod schema en `packages/shared/src/schemas/` si es input nuevo
   - Definir Drizzle schema en `packages/db/src/schema/` si es entidad nueva
   - Implementar use case en `application/`
   - Adapter en `infrastructure/`
   - Route handler en `api/`
2. **Test:**
   - `bun test` (unit tests pasan)
   - `bun test:integration` (integration tests pasan)
   - Coverage ≥ 80% (objetivo MVP)
3. **Document:**
   - README del módulo actualizado
   - OpenAPI spec actualizado si es endpoint nuevo (`docs/api/openapi.yaml`)
   - Changelog del módulo
4. **Review:**
   - `pnpm lint` sin errores
   - `pnpm type-check` sin errores
   - Si tocó auth / KMS / secrets / audit log: review manual obligatorio

---

## 10. Integraciones externas (precaución)

### Sumsub (KYC)
- Webhook signature: HMAC SHA-256 con `SUMSUB_WEBHOOK_SECRET`
- Header: `x-payload-digest`
- Idempotencia por `applicantId + reviewStatus`

### Stripe / MoonPay / Ramp (pagos)
- Webhook signature según cada provider
- Validar antes de marcar payment como confirmado
- Reconciliación nightly (job)

### Plume Arc (KYC bridge)
- Lectura del estado KYC nativo de Plume
- Sincronización con `IdentityRegistry.sol` custom
- Fallback si Plume Arc no disponible

### Arweave (vía Bundlr/Irys)
- Funding wallet via KMS (`IRYS_FUNDING_WALLET_KMS_KEY_ID`)
- Verificación post-upload con readback
- Backup paralelo en Cloudflare R2

### Safe multi-sig (oracle)
- `@safe-global/protocol-kit`
- Generar transacción pre-firmada
- Notificar a 3 firmantes via Slack DM + email
- Webhook callback de Safe Transaction Service

---

**Última actualización:** 2026-05-19
**Aplicabilidad:** todos los archivos bajo `apps/api/**`
