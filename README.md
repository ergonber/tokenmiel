# tokenization-platform

> RWA tokenization platform for agricultural commodities — multi-chain (Plume primary, Polygon secondary), on-chain quality attestation via certified labs.

**Status:** active development (MVP).
**Author:** Daniel Hidalgo Carrasco
**License:** TBD.

---

## Documentos arquitectónicos primarios

Estos son los dos documentos rectores. Cualquier decisión técnica debe respetar lo descrito aquí, o producir un ADR justificando la desviación.

- [`docs/architecture/ARQUITECTURA-TECNICA-MVP.md`](./docs/architecture/ARQUITECTURA-TECNICA-MVP.md) — arquitectura técnica completa v2.0 (decisiones, stack, módulos, roadmap)
- [`docs/business/PROPUESTA-TOKENIZACION-MIEL-BOLIVIANA.md`](./docs/business/PROPUESTA-TOKENIZACION-MIEL-BOLIVIANA.md) — propuesta conceptual y legal (responsabilidad del compañero legal)

## Layout del monorepo

```
apps/
  web/                  Next.js 15 — frontend público + admin
  api/                  Bun + Hono — backend API
packages/
  contracts/            Foundry — smart contracts Solidity (4 contratos)
  shared/               Tipos, schemas Zod, constantes
  ui/                   Componentes shadcn/ui compartidos
  config/               eslint, tsconfig, prettier, tailwind
  db/                   Drizzle schemas + migrations
  abis/                 ABIs y types generados (wagmi generate)
tools/
  scripts/              Scripts operacionales
docs/
  architecture/         ADRs (Architecture Decision Records)
  runbooks/             Operational runbooks
  subagents/            CLAUDE.md por subagente especializado
  api/                  OpenAPI specs
```

## Quickstart (para developers)

**Requisitos:**
- Node.js ≥ 20
- pnpm ≥ 9 (NUNCA usar npm/npx — ver `CLAUDE.md`)
- Bun ≥ 1.x (para backend)
- Foundry (forge, cast, anvil) — instalación manual documentada en `docs/runbooks/foundry-install.md`

**Setup local:**
```bash
pnpm install
cp .env.example .env.local  # editar con credenciales reales (NO commitear)
pnpm dev
```

## Stack tecnológico (resumen)

| Capa | Tecnología |
|---|---|
| Blockchain primario | Plume Network (L2 EVM RWA-focused) |
| Blockchain secundario | Polygon PoS (fase 6+) |
| Smart contracts | Solidity 0.8.24+, OpenZeppelin v5, Foundry |
| Backend | Bun + Hono + TypeScript + Drizzle ORM |
| Database | PostgreSQL (Supabase) |
| Frontend | Next.js 15 + TypeScript + wagmi v2 + RainbowKit |
| KYC | Sumsub + Plume Arc |
| Storage | Arweave (permanente) + Cloudflare R2 (operacional) |
| Oráculo de hitos | Safe multi-firma 2-de-3 |
| Oráculo de reservas | Chainlink Proof of Reserve |
| Oráculo de calidad | LabRegistry + QualityAttestation (custom) |
| Monorepo | Turborepo + pnpm workspaces |

## Subagentes y división del trabajo

Este proyecto se desarrolla con un esquema de **subagentes especializados** que operan en áreas acotadas y leen únicamente la documentación correspondiente a su scope. Esto reduce riesgo de:
- Contaminación de contexto entre áreas
- Prompt injection cross-area
- Errores por contexto incompleto

Ver `docs/subagents/` para detalles sobre cada subagente.

## Workflow loop (estricto)

Cada cambio significativo pasa por este loop, en orden:

1. **Build** — implementar el cambio (código, config, doc)
2. **Test** — verificar que tests existentes pasan + nuevos tests cubren el cambio
3. **Document** — actualizar README, ADR si aplica, runbook si aplica
4. **Review** — security review si tocó contratos o secrets

Sin completar los 4 pasos, no se considera "hecho".

## Reglas de seguridad operacional

- **NUNCA** commitear secrets, claves privadas, ni `.env` files reales.
- **NUNCA** instalar paquetes de fuentes no verificadas. Solo paquetes con maintainer conocido.
- **NUNCA** ejecutar `npm` o `npx` — solo `pnpm` y `pnpm dlx` (regla CLAUDE.md global).
- Llaves operativas viven en HSM (AWS KMS, GCP KMS) o hardware wallets (Ledger).
- Multi-sig 2-de-3 obligatorio para operaciones críticas on-chain.

## Contribuciones

Ver `CONTRIBUTING.md` (a crear).

## Soporte

Este proyecto está en desarrollo activo. Para preguntas técnicas: ver la documentación en `docs/`.
