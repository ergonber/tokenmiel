# infra/

Infraestructura como código y configuraciones de despliegue para tokenization-platform.

## Estructura planeada

```
infra/
├── docker/         # Dockerfiles + docker-compose para desarrollo y prod
├── terraform/      # IaC: Plume/Polygon nodes, Supabase, Upstash, KMS
└── kubernetes/     # Manifests (futuro — cuando se escale a multi-instancia)
```

## Status actual

🚧 **En desarrollo.** Las subcarpetas se crearán a medida que se necesiten.

## Reglas

- **NUNCA** commitear secrets, claves privadas, ni `.env` files reales.
- Variables sensibles vivien en HSM (AWS KMS, GCP KMS) o en secrets managers cloud.
- Multi-sig 2-de-3 obligatorio para operaciones críticas on-chain.

## Documentos relacionados

- `docs/architecture/ADR-001-multi-chain-strategy.md` — estrategia de redes
- `docs/architecture/ADR-007-backend-stack.md` — stack del backend (Bun + Hono + Drizzle)
- `docs/runbooks/` — runbooks operacionales (a crear)
