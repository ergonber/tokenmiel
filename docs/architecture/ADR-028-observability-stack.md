# ADR-028: Stack de observabilidad (logging, tracing, errores, métricas y alertas)

**Status:** Accepted
**Date:** 2026-06-02
**Author:** Daniel Hidalgo Carrasco
**Tags:** observability, logging, tracing, opentelemetry, sentry, better-stack, tenderly, pagerduty, slack, metrics, backend, no-pii
**Resuelve:** OBS-01 (logging estructurado sin PII con contexto de traza), OBS-02 (tracing distribuido real end-to-end), OBS-03 (inconsistencia de PagerDuty entre el stack §16.1 y la tabla de alertas §16.3)
**Relacionado:** ARQUITECTURA §16 (capa de monitoreo y observabilidad), ADR-007 (stack backend Bun + Hono + Drizzle + viem), ARQUITECTURA-BACKEND-FASE2 §1.1 (bootstrap logging, fila "Logging" y "Notificaciones")
**Supersedes:** N/A
**Superseded by:** N/A

---

## Context

La capa de observabilidad del MVP estaba **enunciada pero no cerrada**. El audit de cobertura sobre `ARQUITECTURA §16` dejó tres huecos concretos que impedían tratar la observabilidad como una decisión ejecutable:

1. **Logging sin contrato de instrumentación.** ADR-007 fija `pino` como logger y ARQUITECTURA-BACKEND-FASE2 §1.1 exige "no PII en logs", pero no se define CÓMO se correlaciona un log con el resto del recorrido de una request. El §16 dice "cada acción produce logs estructurados, métricas y trazas… diagnóstico en producción debe ser posible sin acceso a la máquina", pero el bootstrap de §1.1 solo loguea `{chainId, deployVersion, addresses, verified}` y el resto de los módulos no tiene un identificador de correlación común.

2. **Tracing solo nominal.** El §16.1 menciona "trazas" sin backend de tracing. Lo que existía de facto era, a lo sumo, un `traceId` de request (un id que vive y muere dentro del handler HTTP). Eso NO es tracing distribuido: no propaga contexto a través de la cadena `HTTP → use-case → infrastructure → on-chain (viem) / DB (Drizzle)`. Cuando una `comprar` o una `iniciarRedencion` falla a mitad de camino — por ejemplo entre el mint on-chain y el `INSERT` en `audit_log` — no había forma de seguir el span padre desde el RPC de Plume hasta la query de Drizzle bajo un mismo trace.

3. **PagerDuty inconsistente.** La tabla de stack `§16.1` NO lista PagerDuty, pero la tabla de alertas `§16.3` lo usa como canal de "Backend down", "Smart contract pause activated" y similares (Critical). Es decir: el documento rector depende de una herramienta que el propio stack no declara, y el `.env` no tiene la integration key. Cualquier deploy honesto del MVP no podría disparar esas alertas P0.

Además, el MVP es una plataforma RWA con obligaciones de compliance (KYC/sanciones, `audit_log` append-only con hash chain). La observabilidad no es solo SRE: necesita un **carril de compliance e incidentes** separado y métricas de negocio/compliance auditables, no solo latencia y errores.

El objetivo de este ADR es **formalizar el stack completo de observabilidad**, cerrar los tres huecos y dejar el `.env` y la mecánica de instrumentación explícitos para la Fase 2.

---

## Decision

Se adopta el siguiente stack de observabilidad para backend y frontend del MVP, con los huecos del audit cerrados:

### Logging — `pino` (estructurado, sin PII, con `traceId`)

`pino` sigue siendo el logger (ADR-007). Se formaliza el contrato:

- **Estructurado** (JSON), un solo `logger` raíz en `shared/` con child loggers por módulo (`logger.child({ module })`).
- **Sin PII**: nombre, dirección, documento de identidad y `sumsubApplicantHash` se sanean ANTES de loggear (CLAUDE.md §9, §1.1). Se loguean direcciones on-chain, `loteId`, `redencionId`, hashes de documento y `chainId` — nunca el dato personal.
- **Con `traceId`**: cada log lleva el `traceId` y el `spanId` del contexto OpenTelemetry activo, inyectados por un hook de `pino` (`mixin`) que lee el span actual. Esto reemplaza el `traceId` de request aislado que existía: el `traceId` ahora es el **mismo** que el del trace distribuido, no un id paralelo.

### Tracing — OpenTelemetry (distribuido, real, end-to-end)

Se adopta **OpenTelemetry** como tracing distribuido real, NO un `traceId` de request. El SDK de OTel para Node/Bun se inicializa en el arranque (antes de `Hono`), y propaga el contexto de traza a través de toda la cadena:

```
HTTP (Hono middleware: extrae/crea span raíz)
  → application (use-case: span hijo por caso de uso)
    → infrastructure
        → on-chain (viem: span por RPC call a Plume)
        → DB (Drizzle/pg: span por query)
```

- **Instrumentación HTTP**: middleware de Hono que abre el span raíz por request, propaga `traceparent` (W3C Trace Context) entrante si existe, y cierra el span con el status code.
- **Instrumentación use-cases**: cada use-case abre un span hijo nombrado por la operación de dominio (`comprar`, `iniciarRedencion`, `confirmarCosecha`, `setKYC`), de modo que un trace cuenta la historia de negocio, no solo la HTTP.
- **Instrumentación infra**: auto-instrumentación de `pg` (Drizzle corre sobre `pg`) para spans de query, y spans manuales alrededor de cada llamada `viem` (los `publicClient`/`walletClient` no tienen auto-instrumentación, así que se envuelven en `shared/`). Esto cierra el hueco crítico: un fallo entre el mint y el `INSERT` en `audit_log` queda bajo un único trace navegable.
- El exporter de OTel manda spans Y métricas (ver Métricas).

### Error tracking — Sentry (backend + frontend)

**Sentry** para captura de excepciones y errores no manejados, en backend (Bun + Hono) y frontend (Next.js). Se integra con OTel de modo que cada evento de Sentry lleve el `traceId`, permitiendo saltar de un error a su trace completo. PII sanitizada antes de enviar (`beforeSend`).

### Uptime + log aggregation — Better Stack

**Better Stack** para uptime monitoring (health-checks de backend, frontend e indexer Goldsky) y agregación de los logs `pino`. Los logs estructurados se envían a Better Stack para búsqueda/retención centralizada; el `traceId` permite correlacionar log ↔ trace ↔ error.

### Alertas on-chain — Tenderly

**Tenderly** para alertas y debugging on-chain (ya listado en §16.1 y ARQUITECTURA §11): dispara sobre eventos críticos de los 3 contratos del MVP — `EmergencyPaused` (pause de cualquier contrato), `Sanctioned`, `RedencionCancelada` por compliance, y reverts inesperados de `comprar`/`burnForRedemption`. Tenderly es el sensor on-chain; el ruteo a P0/operativo se decide en el backend.

### Alertas — ruteo por severidad

- **Alertas P0 → PagerDuty.** Se INCLUYE **PagerDuty** (resuelve OBS-03). Disparan paging P0: **backend down**, **smart-contract pause** (`EmergencyPaused` en cualquiera de los 3 contratos vía Tenderly), y **multi-sig pending > 24h** (transacción del Safe 2-de-3 sin firmar). Se agrega `PAGERDUTY_INTEGRATION_KEY` al `.env` y al stack declarado en §16.1.
- **Alertas operativas y de compliance → Slack.** El resto de alertas va por **Slack** (módulo `notifications/`, ADR-007 / §1.1): canal `#compliance` (sanctions match, KYC desync, ROS/UIF pendientes) y canal `#incidents` (error rate, p95 alto, document verification failed). 
- **Email → Resend.** Notificaciones por email (resumen de incidentes, alertas a Compliance Officer) vía **Resend** (ya en §1.1, fila "Notificaciones").

La regla de ruteo: **P0 paga (PagerDuty); todo lo demás avisa (Slack/Resend)**. PagerDuty NO recibe el firehose; solo las tres clases P0 definidas.

### Métricas — exporter OTel → Better Stack / Grafana

Las métricas salen por el **exporter de OpenTelemetry** hacia Better Stack (y/o Grafana Cloud, ya opcional en §16.1). Se exportan:

- **Sistema**: latencia p50/p95/p99 por endpoint, tasa 4xx/5xx, uptime, conexiones DB activas, **cache hit rate** de Redis (Upstash).
- **Negocio**: compras/hora, tokens emitidos por lote, redenciones iniciadas vs completadas, tasa/tiempo de KYC, eventos on-chain por tipo.
- **Compliance**: KYC desync count (off-chain vs on-chain), documentos Arweave pendientes, reportes UIF/ROS pendientes, multi-sig pending transactions.

Las métricas comparten el pipeline de OTel con los traces, de modo que una métrica anómala (p95 alto) es navegable hasta sus traces ejemplares (exemplars).

---

## Alternatives considered

### A. Mantener solo `traceId` de request (sin OpenTelemetry) — rechazada

Seguir con un id de correlación generado en el middleware HTTP y propagado a mano por los logs.

- ❌ **No es tracing distribuido**: muere en el borde del proceso y no cruza a las llamadas `viem` ni a las queries Drizzle/`pg`. El hueco crítico (fallo entre mint on-chain e `INSERT` en `audit_log`) sigue sin diagnóstico.
- ❌ Propagación manual del id en cada capa: frágil, se olvida, no estándar.
- ❌ No interopera con W3C Trace Context ni con un futuro mirror Polygon (fase 8+).

### B. Datadog APM (suite todo-en-uno) — rechazada

Un solo vendor para logs, traces, métricas, alertas y on-chain.

- ❌ **Costo**: el modelo per-host/per-GB de Datadog no encaja con el tier MVP (el §16 fija free tier en Sentry/Better Stack/Tenderly).
- ❌ **Vendor lock-in** de la instrumentación. OpenTelemetry es vendor-neutral: si mañana cambiamos de backend de tracing, el código instrumentado no cambia.
- ❌ Sin cobertura on-chain nativa: igual haría falta Tenderly.

### C. PagerDuty para todas las alertas — rechazada

Rutear todo (error rate, p95, document verification) a PagerDuty.

- ❌ **Fatiga de alerta**: PagerDuty paga a una persona. Saturarlo con medium/high degrada la respuesta a los P0 reales. El ruteo por severidad (P0 → PagerDuty, resto → Slack/Resend) preserva la señal.
- ❌ Costo por evento innecesario para alertas que no requieren paging.

### D. No incluir PagerDuty y resolver la inconsistencia por defecto a Slack — rechazada

Borrar PagerDuty de §16.3 y mandar también los P0 a Slack.

- ❌ Slack no garantiza escalado ni acknowledgment de un P0 fuera de horario. "Backend down" o "smart-contract pause" requieren paging con escalado, no un mensaje que puede pasar inadvertido. El §16.3 ya clasificaba esas alertas como Critical: la decisión correcta es honrar esa criticidad con PagerDuty, no degradarla.

### E. Sentry como backend de tracing y métricas (en vez de OTel) — rechazada

Sentry tiene performance/tracing propio.

- ❌ Acopla tracing al SDK de Sentry; perdemos la neutralidad de OTel y la auto-instrumentación de `pg`. Sentry se mantiene como **error tracking** y consume el `traceId` de OTel, que es su rol natural.

---

## Consequences

### Positive

1. **Diagnóstico end-to-end real**: un fallo a mitad de `comprar`/`iniciarRedencion` (entre on-chain y DB) es navegable bajo un único `traceId` que une log (pino) ↔ trace (OTel) ↔ error (Sentry).
2. **`traceId` único y coherente**: se elimina la duplicidad entre el "traceId de request" y el trace real; ahora son el mismo identificador en todo el stack.
3. **Alertas P0 ejecutables**: la inconsistencia de §16.3 queda resuelta — PagerDuty existe en el stack y en el `.env`, y las tres clases P0 (backend down, contract pause, multi-sig > 24h) pueden disparar paging.
4. **Señal preservada**: el ruteo por severidad evita la fatiga de alerta; PagerDuty solo recibe P0.
5. **Vendor-neutral**: OpenTelemetry desacopla la instrumentación del backend de observabilidad; cambiar de Better Stack/Grafana no toca el código de los use-cases.
6. **Compliance observable**: métricas de KYC desync, ROS/UIF pendientes y multi-sig pending quedan en el pipeline, no como afterthought.
7. **No PII garantizado**: el contrato de saneo de pino se formaliza y se aplica también en `beforeSend` de Sentry y en los atributos de span de OTel.

### Negative

1. **Overhead de instrumentación**: envolver `viem` y los use-cases en spans agrega trabajo de desarrollo y un pequeño costo de runtime por span. Mitigado con sampling configurable por env (`OTEL_TRACES_SAMPLER`).
2. **Más superficie de configuración / secrets**: se suman `PAGERDUTY_INTEGRATION_KEY`, `SENTRY_DSN`, `OTEL_EXPORTER_OTLP_ENDPOINT`, `BETTERSTACK_SOURCE_TOKEN` al `.env`. Todos van por secret manager (§17.2 / CLAUDE.md §9), nunca en env de prod en claro.
3. **Bun + OTel madurez**: la auto-instrumentación de OTel está pensada para Node; sobre Bun puede requerir shims o instrumentación manual donde la auto no enganche (especialmente `pg`). Mitigado: spans manuales en `shared/` para los puntos que la auto no cubra.
4. **Riesgo de PII en atributos de span**: un span mal instrumentado podría filtrar PII. Mitigado con el mismo saneo central que pino y revisión en code review.

### Neutral

1. **Grafana Cloud sigue opcional**: el exporter OTel puede ir a Better Stack y/o Grafana; la elección entre ambos no cambia el código instrumentado.
2. **Tenderly ya estaba en §16.1/§11**: este ADR no lo agrega, solo formaliza qué eventos on-chain dispara y cómo se rutean (P0 vs operativo).
3. **Frontend (Next.js) usa el mismo Sentry**: la propagación de `traceparent` desde el browser al backend es deseable pero queda como mejora incremental, no bloqueante para el MVP.

---

## Implementation notes

Backend Bun + Hono + Drizzle + viem (ADR-007, ARQUITECTURA-BACKEND-FASE2):

- **Bootstrap (§1.1)**: el SDK de OpenTelemetry se inicializa en `shared/` ANTES de instanciar `Hono` (los instrumentation hooks deben registrarse antes de cargar los módulos instrumentados). El `ChainBootstrap` que hoy loguea `{chainId, deployVersion, addresses, verified}` (§1.1) pasa a emitir ese log bajo el `traceId` del span de arranque.
- **Logger pino**: un único logger raíz en `shared/logger/` con `mixin` que inyecta `traceId`/`spanId` del span OTel activo, y un serializer/redactor central (`pino` `redact`) para PII. Child loggers por módulo (`assets`, `lots`, `identity`, `payments`, `documents`, `oracle`, `audit`, `notifications`).
- **Middleware Hono**: `shared/middleware/` abre el span raíz por request, extrae `traceparent` entrante, y cierra el span con el status. Reemplaza cualquier generación de `traceId` ad-hoc previa.
- **Use-cases**: cada caso de uso en `application/` abre un span hijo nombrado por la operación de dominio. Span name en inglés (`comprar`, `iniciarRedencion` se mantienen verbatim por ser dominio).
- **viem**: los `publicClient`/`walletClient` se envuelven en `shared/` para abrir un span por RPC call a Plume (chainid 98867 testnet / mainnet `[PENDIENTE DEPLOY]`), con atributos `chainId`, método RPC y dirección de contrato — nunca PII.
- **Drizzle/pg**: auto-instrumentación de `pg` para spans de query; los `INSERT` a `audit_log` (append-only + hash chain, ADR-007) quedan dentro del trace de la operación que los originó.
- **Sentry**: init en backend y en frontend Next.js; `beforeSend` aplica el mismo redactor de PII; `tracesSampler` alineado con `OTEL_TRACES_SAMPLER`.
- **Tenderly**: alertas configuradas sobre los eventos de dominio del CIS — `EmergencyPaused` (los 3 contratos), `Sanctioned`, `Frozen`, `RedencionCancelada` (path compliance), reverts de `comprar`/`burnForRedemption`. El webhook de Tenderly entra al módulo `notifications/`, que decide PagerDuty (P0) vs Slack (operativo).
- **Alertas / `notifications/`**: el módulo `notifications/` (ya existente, §1.1) gana un router de severidad: `P0 → PagerDuty (PAGERDUTY_INTEGRATION_KEY)`, `compliance → Slack #compliance`, `incidents → Slack #incidents`, `email → Resend`.
- **Nuevos env vars** (al `.env` y `.env.example`, por secret manager en prod): `PAGERDUTY_INTEGRATION_KEY`, `SENTRY_DSN`, `OTEL_EXPORTER_OTLP_ENDPOINT`, `OTEL_TRACES_SAMPLER`, `BETTERSTACK_SOURCE_TOKEN`, `SLACK_WEBHOOK_COMPLIANCE`, `SLACK_WEBHOOK_INCIDENTS`, `RESEND_API_KEY`.
- **Tabla §16 a reconciliar**: agregar PagerDuty a la fila de stack `§16.1` y a la columna de canal de `§16.3` (ya estaba en §16.3 pero ausente de §16.1: esta es la inconsistencia que el ADR cierra).

---

## References

- ARQUITECTURA-TECNICA-MVP.md §16 (capa de monitoreo y observabilidad: §16.1 stack, §16.2 métricas, §16.3 alertas) — fuente del gap y de la inconsistencia de PagerDuty
- ARQUITECTURA-TECNICA-MVP.md §11 (Tenderly como tooling on-chain), §17.2 (gestión de llaves: secrets por secret manager)
- ADR-007 (stack backend: `pino` como logger, viem 2.x, Drizzle/PostgreSQL, módulo `notifications/` con Slack + Resend)
- ARQUITECTURA-BACKEND-FASE2.md §1.1 (fila "Logging": pino sin PII; fila "Notificaciones": Resend + Slack; bootstrap `ChainBootstrap` que loguea `{chainId, deployVersion, addresses, verified}`)
- CIS-v1.md §5 (event catalog: `EmergencyPaused`, `Sanctioned`, `Frozen`, `RedencionCancelada` — los eventos que disparan alertas on-chain vía Tenderly)
- CLAUDE.md §9 (seguridad operacional: no PII en logs, no secrets en env de prod)
- W3C Trace Context (`traceparent`): https://www.w3.org/TR/trace-context/
- OpenTelemetry JS: https://opentelemetry.io/docs/languages/js/
