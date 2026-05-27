# tools/

Scripts operacionales y utilidades de desarrollo para tokenization-platform.

Esta carpeta está prevista en `docs/architecture/ADR-006-monorepo-turborepo-pnpm.md` como parte de la estructura del monorepo (`apps/` + `packages/` + `tools/` + `docs/`).

## Estructura planeada

```
tools/
├── abi-gen/        # Generación de packages/abis vía wagmi-cli
├── seed-db/        # Seeding de datos de desarrollo
├── ops/            # Scripts operacionales (rotate keys, backfills, etc.)
└── scripts/        # Scripts varios (deploy helpers, etc.)
```

## Status actual

🚧 **En desarrollo.** Las subcarpetas se crearán a medida que se necesiten.

## Reglas

- Todos los scripts deben ser **idempotentes** cuando sea posible.
- Scripts que tocan producción deben tener **dry-run mode** explícito.
- **NUNCA** ejecutar scripts remotos (`curl | bash`, `wget | sh`) sin verificación de checksum.
- Usar `pnpm dlx <pkg>` para herramientas one-shot — NUNCA `npx`.
