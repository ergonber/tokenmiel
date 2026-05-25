# ADR-007: Stack backend (Bun + Hono + Drizzle + PostgreSQL)

**Status:** Accepted
**Date:** 2026-05-19
**Author:** Dany Hidalgo F.
**Tags:** backend, bun, hono, drizzle, postgres

---

## Context

El backend procesa flujos críticos: KYC sync, payments, redenciones, oracle dashboard, audit log, integración con APIs externas (Sumsub, Stripe, MoonPay, Ramp, labs). Necesita ser:
- Performante (alta concurrencia con cargas variables)
- Type-safe end-to-end con frontend y contratos
- Modular (escalable a microservicios si volumen lo justifica)
- DX moderno (productividad equipo MVP chico)
- Compatible con PostgreSQL (ACID para audit log y compliance)

---

## Decision

**Stack:**

| Componente | Tecnología | Versión |
|---|---|---|
| Runtime | **Bun** | 1.x |
| Framework HTTP | **Hono** | 4.x |
| Lenguaje | TypeScript | 5.x |
| ORM | **Drizzle** | latest |
| DB | PostgreSQL (Supabase managed) | 16+ |
| Cache | Redis (Upstash) | latest |
| Validación | Zod | latest |
| Cliente Web3 | viem | 2.x |
| Auth | Clerk | latest |
| Logger | pino | latest |
| Jobs | BullMQ | latest |

**Patrón:** Modular Monolith (no microservicios para MVP).

---

## Alternatives considered

### Node.js + Express
- ✅ Maduro, máximo pool de developers
- ❌ Performance inferior a Bun
- ❌ Express estancado, no en development activo
- ❌ Stack no-moderno

### Node.js + Fastify
- ✅ Performante para Node
- ✅ Más moderno que Express
- ❌ Bun + Hono es más performante y más moderno
- ❌ Pool de plugins más chico vs Express

### Deno + Oak
- ✅ Type-safe nativo
- ❌ Ecosistema más chico, menos npm compat
- ❌ Adopción menor que Bun en producción

### Bun + Express
- ❌ Compatibilidad parcial — Express asume Node API
- ❌ No aprovecha edge-readiness de Bun

### Node.js + tRPC
- ✅ Type-safety end-to-end automática
- ❌ Asume cliente TypeScript (excluye integraciones genéricas API)
- ❌ Más complejo para webhooks de terceros

### Prisma ORM (en lugar de Drizzle)
- ✅ Más maduro, mejor ecosistema
- ❌ Schema en `.prisma` separado (DX worse para Drizzle's SQL-like API)
- ❌ Runtime overhead (Drizzle es más ligero)
- ❌ Migraciones menos flexibles

### TypeORM
- ❌ Más complejo, menos type-safe que Drizzle
- ❌ Active Record antipattern en JS/TS

### MongoDB / Firestore
- ❌ Sin ACID — no apto para compliance / audit log
- ❌ Vendor lock-in (Firestore)
- ❌ Sin SQL complejo

---

## Consequences

### Positive (Bun)

- **Performance:** ~3-4x más rápido que Node.js para HTTP requests
- **TypeScript nativo:** sin compile step en dev (tsx integrado)
- **DX moderno:** built-in test runner, watch mode, package manager
- **Bun.serve API** simple y performante
- **Edge-ready:** compatible con Cloudflare Workers (futuro)

### Positive (Hono)

- **Edge-first:** corre en Node, Bun, Deno, Cloudflare Workers, Vercel Edge
- **Type-safe:** route handlers tipados con TypeScript inference
- **Ligero:** <14KB bundle size
- **Hono middleware ecosystem** suficiente para MVP

### Positive (Drizzle)

- **Type-safety end-to-end:** schemas TS, queries tipadas
- **SQL-like API:** más control que Prisma (tradeoff: más verbose)
- **Sin runtime overhead** significativo
- **Migraciones simples** (`drizzle-kit generate`, `migrate`)
- **Edge-compatible**

### Positive (PostgreSQL Supabase)

- **ACID** indispensable para audit_log append-only y compliance
- **Realtime subscriptions** disponibles si necesario
- **Storage** S3-compatible (alternativa a R2)
- **Auth integrado** (no usamos porque preferimos Clerk para 2FA mejor)
- **Backups automáticos**, dashboard

### Negative

- **Bun 1.x todavía tiene paquetes Node.js con compat parcial.** Mitigación: priorizar paquetes Bun-native, usar Node compat solo si necesario.
- **Hono ecosystem más chico** que Express (mitigación: plugins críticos ya cubiertos, custom middleware fácil de escribir).
- **Drizzle DX requires SQL knowledge** (mitigación: equipo conoce SQL).
- **Menor pool de developers Bun** vs Node (mitigación: equipo remoto global, Bun es learning curve <1 día para devs Node).

### Neutral

- **Hosting:** Railway o Fly.io soportan Bun nativo.
- **Type-safety vs cliente:** type-share via `packages/shared` (Zod schemas) en lugar de tRPC.

---

## Implementation notes

### Modular Monolith pattern

```
apps/api/src/modules/<name>/
├── domain/         (entities, value objects)
├── application/    (use cases, services)
├── infrastructure/ (repositories, adapters)
└── api/            (Hono routes, DTOs)
```

**Boundaries claros:** módulos se comunican vía interfaces explícitas, no acceso directo a internals.

**Cross-cutting concerns** en `apps/api/src/shared/`:
- `logger/` (pino instance)
- `errors/` (error classes)
- `middleware/` (Hono middleware)
- `types/` (cross-module types)

### Configuración Bun

`apps/api/package.json`:
```json
{
  "scripts": {
    "dev": "bun --watch src/server.ts",
    "build": "bun build src/server.ts --outdir dist --target bun",
    "start": "bun dist/server.js",
    "test": "bun test"
  }
}
```

### Configuración Drizzle

`apps/api/drizzle.config.ts`:
```typescript
import { defineConfig } from 'drizzle-kit';
export default defineConfig({
  schema: '../../packages/db/src/schema/index.ts',
  out: '../../packages/db/migrations',
  dialect: 'postgresql',
  dbCredentials: { url: process.env.DATABASE_URL! },
});
```

### Webhooks (patrón obligatorio)

```typescript
app.post('/webhooks/sumsub/individual', async (c) => {
  // 1. Validar firma HMAC SHA-256
  const signature = c.req.header('x-payload-digest');
  const body = await c.req.text();
  if (!verifyHmac(body, signature, process.env.SUMSUB_WEBHOOK_SECRET!)) {
    return c.json({ error: 'invalid signature' }, 401);
  }

  // 2. Idempotencia
  const event = JSON.parse(body);
  if (await isAlreadyProcessed(event.applicantId, event.reviewStatus)) {
    return c.json({ ok: true, idempotent: true });
  }

  // 3. Procesar
  await processKycEvent(event);

  return c.json({ ok: true });
});
```

### Audit log append-only

PostgreSQL policy:
```sql
REVOKE UPDATE, DELETE ON audit_log FROM PUBLIC;
GRANT INSERT ON audit_log TO api_user;
GRANT SELECT ON audit_log TO api_user, audit_reader;
```

Cada inserción incluye `prev_hash = sha256(prev_row || current_row)` (hash chain).

---

## References

- ARQUITECTURA-TECNICA-MVP.md §13 (capa backend)
- Bun docs: https://bun.sh/docs
- Hono docs: https://hono.dev/
- Drizzle ORM docs: https://orm.drizzle.team/
- Supabase docs: https://supabase.com/docs
