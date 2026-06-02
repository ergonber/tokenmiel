# Arquitectura Técnica — Plataforma de Tokenización de Activos Reales

## Documento de diseño técnico para MVP

---

**Autor:** Daniel Hidalgo Carrasco
**Fecha:** 29 de mayo de 2026
**Versión:** 2.1
**Estado:** Documento de arquitectura para revisión técnica y presentación institucional

**Cambios v1.0 → v2.0:**
- Red blockchain: cambio de Polygon PoS único a **multi-chain Plume Network (primaria) + Polygon PoS (secundaria)**
- Decisión sobre Chainlink: **revertida**. Incorporamos Chainlink Proof of Reserve + aplicación al BUILD program
- Nuevo pilar arquitectónico: **oráculo de calidad (palinología + NMR + LabRegistry)** como diferenciador del producto — **reservado para FASE 2 (ADR-010)**
- 3 contratos MVP (AssetVault + IdentityRegistry + RedemptionManager). `LabRegistry.sol` es FASE 2 (ADR-010).
- Nuevo módulo backend: `quality/` para integración con laboratorios certificados — **FASE 2**

**Cambios v2.0 → v2.1 (reconciliación con código real — 2026-05-29):**
- MVP confirmado en **3 contratos**, no 4. `LabRegistry` / `QualityAttestation` / estado `QUALITY_ATTESTED` son FASE 2 (ADR-010).
- Redención: máquina de estados 2 fases ADR-017 (`iniciarRedencion` → `confirmarExportacion` → `completarRedencion`); Modelo Option B — lock acumulator contable, sin escrow de tokens; `cancelarRedencion` desde INICIADA o EN_EXPORTACION (ADR-015, 60 días buyer self-cancel).
- Asimetría de pause ADR-016: `pause()` = Compliance|Admin, `unpause()` = solo Admin; aplica a los 3 contratos incluido IdentityRegistry (FIX H-02 / ADR-013).
- Los 3 contratos usan `AccessControlDefaultAdminRules` con delay de 3 días (ADR-012 / FIX M-08), no `AccessControl` plano.
- Escrow total post-cosecha (ADR-009 / FIX H-01); tier-check en reembolso (ADR-014 / FIX H-01).

**Alcance:** este documento define **exclusivamente** la arquitectura tecnológica del MVP. La gestión legal, regulatoria y de relacionamiento institucional queda fuera del alcance y es responsabilidad de la contraparte legal del proyecto.

**Audiencia:** equipo técnico, autoridades técnicas, auditores de smart contracts, ingenieros revisores, potenciales socios técnicos.

---

## Tabla de contenidos

**PARTE I — VISIÓN Y PRINCIPIOS**
1. [Resumen ejecutivo técnico](#1-resumen-ejecutivo-técnico)
2. [Principios arquitectónicos](#2-principios-arquitectónicos)
3. [Visión general del sistema](#3-visión-general-del-sistema)

**PARTE II — DECISIONES FUNDAMENTALES**
4. [Decisión técnica #1: red blockchain](#4-decisión-técnica-1-red-blockchain)
5. [Decisión técnica #2: estándar de token](#5-decisión-técnica-2-estándar-de-token)
6. [Decisión técnica #3: arquitectura de contratos](#6-decisión-técnica-3-arquitectura-de-contratos)
7. [Decisión técnica #4: oráculos y Chainlink](#7-decisión-técnica-4-oráculos-y-chainlink)
8. [Decisión técnica #5: protocolos auxiliares](#8-decisión-técnica-5-protocolos-auxiliares)

**PARTE III — STACK TECNOLÓGICO POR CAPA**
9. [Capa blockchain](#9-capa-blockchain)
10. [Capa de identidad y verificación](#10-capa-de-identidad-y-verificación)
11. [Capa de pagos](#11-capa-de-pagos)
12. [Capa de almacenamiento](#12-capa-de-almacenamiento)
13. [Capa de backend](#13-capa-de-backend)
14. [Capa de frontend](#14-capa-de-frontend)
15. [Capa de indexación](#15-capa-de-indexación)
16. [Capa de monitoreo y observabilidad](#16-capa-de-monitoreo-y-observabilidad)
17. [Capa de seguridad](#17-capa-de-seguridad)
18. [Capa DevOps y CI/CD](#18-capa-devops-y-cicd)

**PARTE IV — ESTRUCTURA DEL CÓDIGO**
19. [Estructura del monorepo](#19-estructura-del-monorepo)
20. [Convenciones de código](#20-convenciones-de-código)
21. [Estrategia de testing](#21-estrategia-de-testing)

**PARTE V — ARQUITECTURA MODULAR**
22. [Módulos del sistema](#22-módulos-del-sistema)
23. [Flujos críticos](#23-flujos-críticos)

**PARTE VI — PLAN DE IMPLEMENTACIÓN**
24. [Roadmap MVP](#24-roadmap-mvp)
25. [Tecnologías evaluadas y descartadas](#25-tecnologías-evaluadas-y-descartadas)

**ANEXOS**
26. [Glosario técnico](#26-glosario-técnico)
27. [Referencias técnicas](#27-referencias-técnicas)

---

# PARTE I — VISIÓN Y PRINCIPIOS

## 1. Resumen ejecutivo técnico

La plataforma es una **infraestructura de tokenización de activos reales (Real World Assets, RWA)** diseñada como **base genérica** para soportar múltiples tipos de activos físicos tokenizables. El primer caso de uso es **miel monofloral** boliviana, pero la arquitectura está pensada para extenderse a otros commodities agrícolas (café, cacao, quinua, frutas amazónicas) y eventualmente a otros tipos de activos físicos tokenizables.

### 1.1 Arquetipo arquitectónico

**Arquetipo:** plataforma **híbrida on-chain / off-chain** con tres pilares:

1. **Capa on-chain (Polygon PoS):** estándares públicos y verificables. Contratos inteligentes para custodia, emisión, redención y compliance hooks.
2. **Capa off-chain (Bun + Hono + PostgreSQL):** lógica de negocio, integraciones con sistemas tradicionales (KYC, pagos fiat, almacenamiento documental), workflows administrativos.
3. **Capa de preservación legal (Arweave):** almacenamiento permanente e inmutable de documentos de respaldo, con hashes verificables on-chain.

### 1.2 Decisiones técnicas centrales

| Decisión | Resolución | Justificación clave |
|---|---|---|
| Red blockchain primaria | **Plume Network** | L2 EVM diseñada 100% para RWA, primitives built-in (Arc, Nexus, SkyLink), grants milestone-based |
| Red blockchain secundaria | **Polygon PoS** (fase 6+) | Track record RWA agrícola LATAM, máximo pool de auditores, redundancia institucional |
| Estrategia de deployment | **Multi-chain progresivo** | Plume MVP fases 1-5, Polygon agregado en fase 6 con replicación de estado vía SkyLink/CCIP |
| Estándar de token | **ERC-1155** | Multi-asset eficiente, batch operations, soporte universal |
| Lenguaje contratos | **Solidity 0.8.24+** | Estándar de industria, pool de auditores máximo |
| Framework de tests | **Foundry** | Fuzzing nativo, invariant testing, performance |
| Arquitectura contratos | **3 contratos inmutables sin proxy (MVP)** | AssetVault + IdentityRegistry + RedemptionManager. `LabRegistry` es FASE 2 (ADR-010). |
| Oráculo de hitos productivos | **Safe multi-firma 2-de-3 (humano)** | Decisiones humanas firmadas para cosecha, almacenamiento, exportación |
| Oráculo de reservas físicas | **Chainlink Proof of Reserve** | Verificación cryptográfica pública de kg en almacén. Aplicación a Chainlink BUILD program |
| Oráculo de calidad | **LabRegistry + QualityAttestation (FASE 2 — ADR-010)** | Pilar del moat: palinología + NMR firmados por labs certificados (IBNORCA, Eurofins, Intertek, SGS) on-chain. No forma parte del MVP. |
| KYC integrado | **Plume Arc** (nativo de Plume) | Reemplaza parte de IdentityRegistry.sol custom; sincronización híbrida con Sumsub |
| Cross-chain (multi-chain) | **Plume SkyLink + Chainlink CCIP (eval)** | Para mirror de estado Plume↔Polygon |
| Runtime backend | **Bun** | Performance, TypeScript nativo, DX moderno |
| Framework API | **Hono** | Edge-ready, ligero, type-safe |
| Frontend | **Next.js 15 App Router** | SSR/SSG, ecosistema maduro |
| ORM | **Drizzle** | Type-safety end-to-end, control SQL |
| Base de datos | **PostgreSQL (Supabase)** | ACID, JSON, extensiones, gestionada |
| KYC provider external | **Sumsub** | Cobertura LATAM + EU, webhooks, tiers; integrado con Plume Arc |
| Almacenamiento permanente | **Arweave vía Bundlr/Irys** | Pago único, permanencia perpetua |
| Almacenamiento operacional | **Cloudflare R2** | S3-compatible, costo bajo |
| Wallet operativa | **Safe (Gnosis Safe) 2-de-3** | Multi-firma con hardware wallets |
| Estructura repo | **Monorepo Turborepo + pnpm** | Tipos compartidos, builds incrementales |
| Market making secundario (fase 2) | **Cicada Partners** (vía Plume) | Liquidez del mercado secundario si se habilita |

### 1.3 Métricas objetivo del MVP

- **Capacidad:** soportar al menos 5,000 usuarios verificados, 100 lotes activos, 50,000 transacciones on-chain en el primer año
- **Latencia API:** p95 menor a 200ms en endpoints críticos
- **Disponibilidad:** 99.9% de uptime para el frontend, 99.95% para el backend de compliance
- **Coverage de tests:** 100% líneas en smart contracts, 80%+ en backend
- **Tiempo de auditoría:** smart contracts auditables externamente en 2-3 semanas
- **Costo operacional infraestructura:** menor a USD 500/mes en operación inicial

---

## 2. Principios arquitectónicos

Estos principios guían cada decisión técnica del proyecto. Cualquier decisión que los contradiga requiere justificación explícita y documentada.

### 2.1 Simplicidad sobre completitud

Cada componente debe hacer **una cosa bien**. Se prefiere un sistema con menos features pero más confiables, sobre uno con muchas features parcialmente implementadas. El MVP es deliberadamente acotado.

### 2.2 On-chain mínimo, off-chain robusto

La blockchain almacena **únicamente lo que necesita ser inmutable y verificable públicamente**: estado de tokens, hashes de documentos, transiciones críticas. Toda la lógica que puede vivir off-chain, vive off-chain. Esto reduce gas, reduce superficie de ataque y aumenta agilidad.

### 2.3 Inmutabilidad por defecto

Los contratos del MVP son **inmutables post-deploy** (sin proxy upgradeable). Esto:
- Maximiza la confianza del usuario (nadie puede cambiar las reglas)
- Simplifica drásticamente la auditoría
- Elimina riesgos de governance malicioso
- Si aparece un bug crítico, se mitiga con `pause()` + migración a v2 con re-mint pro-rata

### 2.4 Type-safety end-to-end

Desde el smart contract hasta el componente de frontend, el sistema mantiene **tipos consistentes**. Cambios en el contrato propagan inmediatamente a backend y frontend via codegen (wagmi generate). Imposibilita drift de tipos.

### 2.5 Type-driven design

Definir los tipos primero, implementar después. Los schemas Zod, los structs Solidity y los tipos TypeScript son la **fuente de verdad** del dominio. La implementación se deriva de los tipos.

### 2.6 Determinismo y reproducibilidad

Builds reproducibles. Tests deterministas. Deployments parametrizados via scripts versionados. Cualquier integrante del equipo debe poder reproducir el sistema completo desde cero en menos de una hora.

### 2.7 Observabilidad como ciudadano de primera

Cada acción del sistema produce logs estructurados, métricas y trazas. No se entrega ningún módulo sin instrumentación. Diagnóstico de un problema en producción debe ser posible sin acceso a la máquina.

### 2.8 Seguridad por construcción

- Llaves privadas nunca residen en variables de entorno; viven en HSM (AWS KMS, GCP KMS) o hardware wallets
- Toda input es validada con Zod antes de tocar lógica de negocio
- Todo endpoint admin requiere multi-factor authentication
- Tabla de auditoría es append-only con hash chain
- Penetration testing obligatorio antes de mainnet

### 2.9 Vendor-agnostic donde sea razonable

Las dependencias con vendors externos están encapsuladas en módulos adapter. Cambiar de Sumsub a Persona, de MoonPay a Transak, de Supabase a Neon, no requiere cambios fuera del adapter correspondiente.

### 2.10 Documentación como código

Todo módulo crítico tiene su propio README con propósito, contratos de interfaz, ejemplos de uso y troubleshooting. Decisiones arquitectónicas se documentan como ADRs (Architecture Decision Records) versionados en el repo.

---

## 3. Visión general del sistema

### 3.1 Diagrama de capas

```
┌─────────────────────────────────────────────────────────────────────────┐
│  USUARIOS                                                                │
│  • Comprador retail B2C (web)                                            │
│  • Comprador empresarial B2B (web + API)                                 │
│  • Operador admin (web admin panel)                                      │
│  • Firmantes del oráculo (Safe Web UI + hardware wallet)                 │
└─────────────────────────────────────────────────────────────────────────┘
                              ▲ ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  CAPA DE PRESENTACIÓN                                                    │
│  Next.js 15 App Router / TypeScript / TailwindCSS / shadcn/ui            │
│  Web3: wagmi v2 + viem + RainbowKit                                      │
│  • Catálogo público                                                      │
│  • Flujos de compra y redención                                          │
│  • Dashboard de usuario                                                  │
│  • Panel administrativo                                                  │
└─────────────────────────────────────────────────────────────────────────┘
                              ▲ ▼  (HTTPS + tRPC / REST)
┌─────────────────────────────────────────────────────────────────────────┐
│  CAPA DE APLICACIÓN                                                      │
│  Bun runtime + Hono framework + TypeScript + Drizzle ORM                 │
│  Módulos:                                                                │
│  • assets/    (gestión de activos tokenizables)                          │
│  • lots/      (lotes individuales, ciclo de vida)                        │
│  • identity/  (KYC sync, screening)                                      │
│  • payments/  (Stripe, SWIFT, MoonPay, Ramp)                             │
│  • documents/ (Arweave uploader, hash calculator)                        │
│  • oracle/    (preparación de tx Safe multi-firma)                       │
│  • audit/     (append-only log con hash chain)                           │
│  • notifications/ (Resend email, Slack)                                  │
└─────────────────────────────────────────────────────────────────────────┘
                              ▲ ▼
┌──────────────────────────────┐  ┌──────────────────────────────────────┐
│  CAPA DE DATOS               │  │  CAPA DE BLOCKCHAIN                  │
│  PostgreSQL (Supabase)       │  │  Polygon PoS Mainnet                 │
│  Redis (Upstash)             │  │  Smart Contracts (Solidity 0.8.24+):│
│  Cloudflare R2 (ops)         │  │  • AssetVault.sol (ERC-1155)         │
│  Arweave (legal permanence)  │  │  • IdentityRegistry.sol              │
└──────────────────────────────┘  │  • RedemptionManager.sol             │
                                   │  Indexer: Goldsky subgraph           │
                                   │  Oracle: Safe 2-de-3 multi-firma     │
                                   └──────────────────────────────────────┘
                                              ▲ ▼
                                   ┌──────────────────────────────────────┐
                                   │  INTEGRACIONES EXTERNAS              │
                                   │  • Sumsub (KYC)                      │
                                   │  • Stripe (pagos B2B card)           │
                                   │  • MoonPay (B2C card → USDC)         │
                                   │  • Ramp Network (SEPA UE)            │
                                   │  • Chainalysis (screening, opcional) │
                                   │  • Resend (email transaccional)      │
                                   │  • Sentry + Better Stack (monitoring)│
                                   └──────────────────────────────────────┘
```

### 3.2 Modelo conceptual de dominio

El sistema maneja seis entidades principales que se relacionan así:

```
        ┌──────────┐
        │  Asset   │ (categoría: miel, café, etc.)
        └────┬─────┘
             │ 1..N
             ▼
        ┌──────────┐
        │   Lot    │ (instancia específica: "100kg miel romero Valle Alto Q2-2026")
        └────┬─────┘
             │ 1..N
             ▼
        ┌──────────┐
        │  Token   │ (representación on-chain: ERC-1155 con loteId como token ID)
        └────┬─────┘
             │ N..1
             ▼
        ┌──────────┐
        │  Buyer   │ (verificado vía Identity)
        └────┬─────┘
             │ 1..N
             ▼
        ┌──────────┐
        │Redemption│ (proceso de retiro físico)
        └────┬─────┘
             │
             ▼
        ┌──────────┐
        │ Document │ (evidencia en Arweave + hash on-chain)
        └──────────┘
```

---

# PARTE II — DECISIONES FUNDAMENTALES

## 4. Decisión técnica #1: red blockchain (multi-chain)

Esta decisión es la más impactante del proyecto porque determina el lenguaje de contratos, el pool de talento dev, los auditores disponibles, los oráculos compatibles y el ecosistema de herramientas.

**Decisión final: estrategia multi-chain progresiva.**

- **Chain primaria (fase 1-5 del MVP):** Plume Network
- **Chain secundaria (fase 6+):** Polygon PoS, con mirror de estado vía Plume SkyLink o Chainlink CCIP

**Por qué multi-chain y no single-chain:** redundancia institucional, máxima cobertura de compradores (algunos prefieren Polygon por su madurez RWA, otros prefieren Plume por sus primitives nativos), y opcionalidad ante riesgos específicos de chain.

**Por qué Plume primero y no Polygon primero:** las primitives de Plume (Arc para KYC, Nexus para datos, SkyLink para cross-chain) reducen significativamente código custom. Es la única chain del mercado diseñada específicamente para tokenización de activos del mundo real.

### 4.1 Criterios de evaluación (con pesos)

| Criterio | Peso | Justificación |
|---|---|---|
| Madurez y track record en RWA agrícola | Alto | Reduce riesgo de pioneering en producción |
| Disponibilidad de auditores experimentados | Alto | Auditoría externa es bloqueante para mainnet |
| EVM compatibility (talento dev) | Alto | Pool global de Solidity devs es máximo |
| Fiat on/off ramps integrados | Alto | UX crítico para B2C |
| Tooling de desarrollo (Foundry, etc.) | Medio-alto | Productividad del equipo |
| Costo de gas predecible | Medio | <USD 0.10/tx aceptable |
| Compliance features built-in | Medio | Reduce código custom |
| Curva de aprendizaje del equipo | Medio | Tiempo a producción |
| Programas de grants | Medio | Reduce burn rate |
| Bridges hacia Ethereum L1 | Bajo | Importante a futuro, no MVP |
| Velocidad de finalidad | Bajo | <30s aceptable |
| TPS (throughput) | Bajo | <100 TPS suficiente MVP |

### 4.2 Análisis comparativo de las candidatas

Cinco candidatas evaluadas: Plume Network, Polygon PoS, Arbitrum One, Algorand, Stellar.

#### 4.2.0 Plume Network (chain primaria adoptada)

**Qué es:** L2 modular EVM-compatible **diseñada 100% para tokenización de RWA**. Mainnet activa desde 2024. Backed por Galaxy Digital, Haun Ventures, Brevan Howard, A16z y otros.

**Primitives nativas para RWA (lo que hace única a Plume):**

| Primitive | Función | Reemplaza |
|---|---|---|
| **Plume Arc** | KYC y compliance integrados a nivel chain | Parte de `IdentityRegistry.sol` custom |
| **Plume Nexus** | Oracle network específico para datos RWA | Custom oracle integrations |
| **Plume SkyLink** | Cross-chain settlement entre Plume y otras chains | Bridges externos |
| **Smart Wallets** | Account abstraction nativa para UX no-crypto | Coinbase Smart Wallets / custom |

**Fortalezas:**
- **EVM compatible**: Solidity, OpenZeppelin v5, Foundry, **todo el stack diseñado funciona idéntico**
- **Diseñada para nuestro caso de uso exacto**: tokenización de RWA con compliance integrado
- **Plume Foundation Grants**: milestone-based, alineables con hitos del proyecto (MVP, primera transacción internacional, lanzamiento forward token, primer exportador recurrente)
- **Partnerships pre-existentes**: Cicada Partners hace market making en tokens RWA en Plume (relevante si activamos mercado secundario en fase 2)
- **Compliance hooks built-in**: KYC enforcement a nivel chain, no a nivel contrato custom
- **USDC nativo + Goldsky soporta Plume**

**Debilidades reales:**
- **Maturity baja**: mainnet desde 2024. Pool de auditores con experiencia específica Plume es menor que Polygon. Las firmas como Trail of Bits y OpenZeppelin tienen expertise EVM genérico pero pocas auditorías Plume-specific hasta ahora.
- **Riesgo de pioneering**: si Plume tiene un incidente de seguridad del sequencer, afecta a toda la operación. Mitigado con multi-chain (Polygon como fallback).
- **Sequencer centralizado** (idéntico a la mayoría de L2 hoy, pero menos battle-tested).
- **Menos liquidez de USDC** que Polygon (suficiente para MVP).
- **Documentación y comunidad dev** más chica que Polygon.

**Costo de gas estimado en Plume:**
- Comparable o menor a Polygon
- Deploy de 3 contratos MVP: ~USD 1-2
- Mint por compra: ~USD 0.005-0.02
- Operaciones del oráculo: ~USD 0.05

#### 4.2.1 Polygon PoS

**Fortalezas:**
- **Líder regional en tokenización agrícola LATAM**. AgroToken (Argentina) tokeniza soja, maíz, trigo. Mercado Bitcoin (Brasil) tokeniza commodities agrícolas y créditos de carbono. Ambos sobre Polygon. Precedente directo y documentado.
- **EVM compatible**. Solidity, OpenZeppelin v5, Foundry, Hardhat. Máximo pool de talento dev. Máxima cobertura de auditores (Trail of Bits, OpenZeppelin, Quantstamp, Sherlock, Cyfrin, Macro).
- **USDC nativo de Circle** (no bridged), CCTP integrado.
- **Indexers maduros**: Goldsky, The Graph, Alchemy, Covalent.
- **AggLayer**: permite migrar a Polygon zkEVM u otras L2 conectadas sin redeployar contratos.
- **Bridges maduros hacia Ethereum L1** (LXLY Bridge, Polygon Portal).
- **Polygon Labs LATAM** tiene presencia regional con soporte técnico hispanohablante.
- **Reconocimiento institucional**: BlackRock BUIDL (BlackRock USD Institutional Digital Liquidity Fund) opera en Polygon, junto con Hamilton Lane, WisdomTree y Société Générale FORGE.

**Debilidades:**
- Gas algo más caro que Algorand y Stellar (pero <USD 0.05 en MVP, no crítico)
- Grants menos generosos que Stellar Foundation (aunque Polygon Village existe)
- Sequencer parcialmente centralizado (idéntico a la mayoría de L2)

**Costo de gas estimado:**
- Deploy de los 3 contratos: ~0.5-1 MATIC (USD 0.50-1)
- Mint por compra: ~0.005-0.01 MATIC (USD 0.005-0.01)
- Burn por redención: similar
- Operaciones del oráculo (multi-sig 2-de-3): ~0.03-0.05 MATIC por tx (USD 0.03-0.05)
- Operación mensual estimada para 500 tx: <USD 10

#### 4.2.2 Arbitrum One

**Fortalezas:**
- L2 Ethereum más adoptada por DeFi institucional
- Mejor seguridad rollup (fraud proofs)
- EVM compatible, mismo stack que Polygon
- USDC Circle nativo

**Debilidades:**
- **Foco principal es DeFi, no RWA agrícola**. Menos precedentes regionales en commodities.
- Gas más caro que Polygon (USD 0.05-0.10 por tx)
- Menos reconocimiento institucional en RWA agrícola LATAM
- Grants menos generosos que Polygon Village
- Onramp fiat menos integrado

**Veredicto:** descartado para MVP. Excelente red, pero no es la mejor opción para el caso de uso.

#### 4.2.3 Algorand

**Fortalezas:**
- **ASA (Algorand Standard Asset)** nativo: la creación de assets es una operación primitiva del protocolo, no requiere smart contract custom. Asset freeze, clawback, optin obligatorio y manager addresses son features built-in.
- **Compliance features built-in**: el creador del asset puede definir freeze address (para congelar tokens en cualquier wallet), clawback address (para revertir transferencias por orden regulatoria), y manager para reasignar permisos.
- **Finalidad instantánea (~4.5 segundos)**, no probabilística
- **Gas ultra-bajo** (~USD 0.0001 por tx)
- **Atomic transfers**: hasta 16 transferencias en una sola transacción atómica (todas o ninguna)
- **Algorand Foundation Grants** generosos, programa específico para RWA
- **Stateful smart contracts** con PyTeal o TEAL

**Debilidades:**
- **No EVM**. PyTeal (Python-like) o TEAL (assembly-like). Curva de aprendizaje 2-4 semanas para devs Solidity.
- **Pool de auditores significativamente menor**. Auditar contratos PyTeal cuesta más y lleva más tiempo.
- **Ecosistema más pequeño** comparado con Polygon. Menos herramientas, menos tutoriales.
- **Indexers menos maduros**: Algorand Indexer es decente pero menos rico que Goldsky/Subgraph.
- **Menos integraciones de wallets** que MetaMask/Coinbase. Pera (Algorand wallet) es nicho.
- **Onramp fiat más limitado**.

**Veredicto:** **alternativa seria**. Si las compliance features built-in son críticas y el equipo acepta el costo de aprendizaje de PyTeal, Algorand puede competir con Polygon. La decisión depende de qué pesa más: built-in compliance vs. madurez ecosistémica.

#### 4.2.4 Stellar

**Fortalezas:**
- **Diseñado desde su origen para tokenización de activos**. Native asset issuance: emitís un asset directamente en la cuenta del emisor sin smart contract.
- **Anchors**: red global de instituciones que actúan como bridges fiat ↔ token. Existen anchors en USD, EUR y otras monedas. Para LATAM, hay anchors interesantes.
- **Authorization flags nativos**: el emisor puede requerir authorization explícita para que un account pueda recibir su asset (modelo permissioned natural).
- **Casos institucionales históricos**: Banco Mundial emitió bonos en Stellar, MoneyGram opera USDC en Stellar, IBM World Wire.
- **Soroban (smart contracts en Rust)**: lanzado en 2024, permite contratos turing-completos.
- **Stellar Development Foundation (SDF) Grants**: el programa más generoso del ecosistema cripto para RWA. Grants típicos USD 50,000 a USD 500,000.
- **Gas ultra-bajo** (~USD 0.00001 por tx)

**Debilidades:**
- **Soroban es joven**: lanzado en producción en 2024. Pool de auditores pequeño. Tooling en desarrollo.
- **Stack completamente distinto**: Rust en lugar de Solidity. Soroban CLI en lugar de Foundry. Aprendizaje 4-8 semanas para devs EVM.
- **Ecosistema dev más chico** que Polygon. Menos contribuidores, menos librerías.
- **Si se usa Stellar Classic (asset nativo sin Soroban)**, se pierden algunas features de lógica condicional avanzada.
- **Menos integraciones de wallets generalistas** (no MetaMask). Stellar tiene Freighter, Lobstr, Xbull.
- **Bridges desde Ethereum** existen pero son menos maduros (Allbridge, otros).

**Veredicto:** **alternativa premium-grants**. Si los SDF Grants son críticos para financiar el MVP (USD 100k+) y el equipo está dispuesto a aprender Rust + Soroban, Stellar es viable. Pero el costo de re-stack es real.

### 4.3 Matriz de decisión actualizada

| Criterio (peso) | **Plume** | Polygon | Arbitrum | Algorand | Stellar |
|---|---|---|---|---|---|
| EVM compatible (mantiene stack) (10) | 10 | 10 | 10 | 0 | 0 |
| Primitives RWA built-in (9) | 10 | 4 | 4 | 7 | 7 |
| Grants ecosystem (8) | 9 | 6 | 5 | 8 | 9 |
| Maturity y track record (8) | 5 | 10 | 9 | 8 | 8 |
| Pool de auditores (7) | 6 | 10 | 9 | 5 | 5 |
| Talent dev disponible (7) | 8 | 10 | 10 | 5 | 3 |
| KYC integrado a nivel chain (6) | 10 | 0 | 0 | 7 | 7 |
| Mercado secundario/market making (6) | 10 | 5 | 5 | 5 | 6 |
| Fiat on/off ramps (6) | 7 | 9 | 7 | 6 | 10 |
| Curva aprendizaje (5) | 9 | 10 | 10 | 6 | 3 |
| **Score ponderado** | **65.1** | **62.4** | **57.6** | **49.8** | **47.8** |

### 4.4 Recomendación adoptada: multi-chain Plume + Polygon

**Chain primaria: Plume Network.** Score más alto en matriz, EVM-compatible, primitives RWA built-in, grants milestone-based, partnerships pre-existentes (Cicada market making).

**Chain secundaria (fase 6+): Polygon PoS.** Redundancia institucional, máximo pool de auditores, track record AgroToken/Mercado Bitcoin para credibilidad con compradores LATAM tradicionales.

**Por qué multi-chain progresivo y no simultáneo desde día 1:**
- **Velocidad**: ir a Plume primero permite lanzar el MVP con menos complejidad operacional
- **Costo**: una auditoría inicial (Plume) en lugar de dos
- **Aprendizaje**: validar primero en Plume aprovechando sus primitives, después portar a Polygon
- **Riesgo controlado**: si Plume falla por inmadurez, Polygon queda disponible como Plan B sin haber gastado auditoría doble

**Sincronización cross-chain entre Plume y Polygon (a partir de fase 6):**
- **Opción A (recomendada): Plume SkyLink** — primitive nativo de Plume para cross-chain settlement
- **Opción B (alternativa): Chainlink CCIP** — protocolo cross-chain genérico, ya que vamos a integrar Chainlink para PoR de todas formas
- **Modelo de mirror, no de bridge**: el token "vive" en Plume. En Polygon hay un mirror del estado del lote (mismo loteId, mismos kg disponibles, mismos hashes) que permite consulta y verificación pero no transferencia. Esto evita la complejidad de bridge bidireccional y los riesgos asociados.

### 4.5 Descartadas para MVP

- **Arbitrum One**: foco principal DeFi, menos primitives RWA. Score 57.6.
- **Algorand**: requiere PyTeal (no-EVM), pool de auditores reducido. Score 49.8.
- **Stellar**: requiere re-stack completo Rust/Soroban (4-8 semanas), pool de auditores Soroban muy chico. Score 47.8. Solo se evalúa si SDF Grants se vuelve crítico para financiamiento.

### 4.6 Decisiones derivadas

**Plume Network (chain primaria):**
- USDC nativo en Plume
- RPC: Plume RPC oficial + provider redundante
- Indexer: Goldsky subgraph para Plume
- Explorer: Plume Explorer
- Multi-sig wallet: Safe (Gnosis Safe) en Plume
- KYC layer: Plume Arc + Sumsub bridge

**Polygon PoS (chain secundaria, fase 6+):**
- USDC nativo Circle en Polygon: contract `0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359`
- RPC: Alchemy (primario) + Infura (fallback)
- Indexer: Goldsky subgraph para Polygon
- Explorer: PolygonScan
- Multi-sig wallet: Safe (Gnosis Safe) en Polygon (3 firmantes mismos que Plume)

### 4.7 Plan de grants asociado a la decisión de chains

| Programa | Chain | Timing | Target | Probabilidad |
|---|---|---|---|---|
| **Plume Foundation Grants** | Plume | Mes 1-2 | Milestone-based: MVP, primera tx internacional, forward token, primer exportador recurrente | Alta (proyecto encaja exactamente con su tesis RWA) |
| **Stellar Community Fund Build Award** | (paralelo, no excluyente) | Mes 1-2 | USD 150K | Media-alta dado precedentes LATAM (Amber, Bank2Bit, Emigro) |
| **Cicada Partners early-stage** | Plume | Mes 2-3 | USD 50-100K + market making support | Alta si Plume Foundation aprueba |
| **Chainlink BUILD program** | Multi-chain | Continuo (apenas testnet) | Acceso gratis a servicios Chainlink + co-marketing | Media-alta (caso de uso PoR + RWA encaja) |
| **Stellar Matching Fund** | Stellar | Mes 6-12 (post-tracción) | Hasta USD 500K matched 1:1 con lead investor | Condicional a lead investor |

---

## 5. Decisión técnica #2: estándar de token

### 5.1 Opciones evaluadas

#### 5.1.1 ERC-20

Cada lote sería un contrato ERC-20 separado. Familiar, máxima compatibilidad de wallets.

**Contra:** proliferación masiva de contratos (un deploy por lote). Costo de deployment alto. Indexer complejo. Gestión administrativa engorrosa. **Descartado.**

#### 5.1.2 ERC-1155 (Multi-Token Standard)

Un solo contrato gestiona múltiples tokens (token IDs distintos). Cada lote es un token ID. Soporta batch operations.

**Pro:**
- Un solo contrato para todos los lotes (deployment eficiente)
- Batch operations (mint múltiple, transfer múltiple en una tx)
- Soporte universal en wallets (MetaMask, Coinbase, Rainbow, Rabby)
- Maduro, ampliamente auditado
- Hook `_update` para custom logic en transfers

**Contra:** no tiene compliance features built-in (debemos implementarlos)

#### 5.1.3 ERC-3643 (T-REX Standard)

Estándar específicamente diseñado para tokenización de RWA con compliance integrado. Implementa identity registry, modular compliance, freeze/burn por regulador.

**Pro:**
- Compliance-first by design
- Identity y compliance modular
- Adoptado por instituciones (Société Générale FORGE)

**Contra:**
- **Diseñado para tokens transferibles entre verified holders (mercado secundario)**. Nuestro modelo es solo primario.
- Mucha complejidad innecesaria para nuestro caso de uso.
- Costo de auditoría significativamente mayor.
- ERC-20 base, requiere un contrato por variedad de asset (no multi-asset eficiente).

#### 5.1.4 Otros estándares

- **ERC-721 (NFT):** no aplica, los lotes son fungibles dentro del lote (1 kg es intercambiable con 1 kg del mismo lote).
- **ERC-6960 (Dual Layer Token):** experimental, baja adopción.

### 5.2 Recomendación: ERC-1155

**Decisión: ERC-1155 con compliance hooks custom embebidos.**

Razón: balance óptimo entre **eficiencia de gas y deployment** (un solo contrato para todos los lotes), **compatibilidad universal de wallets**, **batch operations** y **soporte de hooks** para implementar compliance custom acotado al caso (solo bloqueo de P2P y validación KYC en mint).

ERC-3643 fue descartado porque su valor agregado (transferencias P2P entre verified holders) no aplica a un modelo solo primario. Implementaría máquinas de compliance que nunca se usarían.

### 5.3 Implementación específica

- **OpenZeppelin Contracts v5**: usar `ERC1155` + `ERC1155Supply` + `ERC1155Pausable` + `AccessControlDefaultAdminRules` (delay 3 días, ADR-012) + `ReentrancyGuard`
- **Convención de granularidad:** 1 token = 0.5 kg para miel (configurable por categoría de asset)
- **Sin decimals nativos**: balance es entero. La conversión a unidades físicas se hace en la capa de presentación con constantes documentadas.

---

## 6. Decisión técnica #3: arquitectura de contratos

### 6.1 Opciones evaluadas

| Opción | Contratos | Pro | Contra |
|---|---|---|---|
| Monolítico | 1 contrato | Máxima simplicidad | Acopla todas las responsabilidades |
| 3 contratos (recomendada) | AssetVault + IdentityRegistry + RedemptionManager | Separation of concerns clara | Auditoría de 3 contratos vs 1 |
| 5 contratos | Como arriba + ReserveVault + ComplianceHook | Máxima separación | Over-engineering para MVP |
| Diamond Pattern (EIP-2535) | 1 proxy + N facetas | Upgradeability granular | Auditoría compleja, magic |

### 6.2 Recomendación: 3 contratos inmutables (MVP)

**Decisión: tres contratos inmutables sin proxy para el MVP (ADR-010).**

```
AssetVault.sol         (ERC-1155 + ciclo de vida de lotes + reserva embebida + compliance hook embebido)
IdentityRegistry.sol   (whitelist on-chain, tiers, sanciones, congelamiento — bridge con Plume Arc)
RedemptionManager.sol  (máquina de estados 2 fases + lock acumulator Option B — ADR-017)
```

> **FASE 2 — ADR-010:** `LabRegistry.sol` (whitelist de laboratorios certificados + verificación de `QualityAttestation`) está reservado para FASE 2 y **no se deploya con el MVP**. Ver Sección 7B para el diseño de referencia. El estado `QUALITY_ATTESTED` y la función `confirmarCalidad` en `AssetVault` tampoco existen en el MVP; `COSECHADO` transiciona directamente a `ALMACENADO`.

### 6.3 Por qué inmutable (no upgradeable)

- **Confianza máxima del usuario:** nadie puede cambiar las reglas después del deploy
- **Auditoría simplificada:** sin proxy patterns, sin storage slots colisionando
- **Menos superficie de ataque:** sin admin functions de upgrade
- **Mitigación de bugs:** función `pause()` ejecutable por `COMPLIANCE_OFFICER_ROLE` OR `DEFAULT_ADMIN_ROLE` (ADR-016). `unpause()` solo por `DEFAULT_ADMIN_ROLE` (asimetría deliberada). Si bug crítico aparece, pausamos y migramos a v2 con re-mint pro-rata. Costoso operacionalmente pero infrecuente.

### 6.4 Por qué 3 y no 5 contratos

- **`ReserveVault` separado**: over-engineering. La reserva técnica es una `state variable` interna de `AssetVault`. No requiere contrato propio.
- **`ComplianceHook` separado**: over-engineering. El hook on-chain vive como override de `_update()` en `AssetVault`. Encapsulación natural.
- **`IdentityRegistry` separado**: sí amerita porque es consultado por múltiples contratos potencialmente (`AssetVault` y `RedemptionManager` actuales, otros contratos futuros).
- **`RedemptionManager` separado**: sí amerita porque encapsula un flujo complejo con su propio estado.

### 6.5 Estimaciones actualizadas

| Métrica | Valor |
|---|---|
| Líneas de código Solidity total (3 contratos MVP) | ~1,000-1,400 LOC |
| Tiempo de implementación | 3-4 semanas (con tests Foundry) |
| Coverage objetivo | 100% líneas, branches |
| Fuzz runs | ≥ 10,000 |
| Invariant runs | ≥ 50,000 |
| Costo auditoría externa Plume (única chain inicial) | USD 6,000-18,000 |
| Costo auditoría adicional Polygon (fase 6+) | USD 4,000-10,000 (auditoría de cambios mínimos para deployment Polygon) |
| Tiempo de auditoría | 3-4 semanas |

---

## 7. Decisión técnica #4: oráculos y Chainlink

### 7.1 Funciones de oráculo requeridas en el sistema

El sistema requiere "oráculos" en sentido amplio para varias funciones:

1. **Confirmación de eventos físicos** (cosecha realizada, lote almacenado, exportación confirmada): decisiones humanas basadas en documentos físicos.
2. **Precios**: no requeridos (el precio se fija al mint en USDC).
3. **Datos externos (clima, listas de sanciones)**: utilizados off-chain por el backend, no necesitan llegar a la blockchain.
4. **Aleatoriedad**: no requerida.
5. **Cross-chain messaging**: no requerido en MVP single-chain.
6. **Proof of Reserve**: opcional, podría aportar transparencia.

### 7.2 Opciones evaluadas

#### 7.2.1 Chainlink Price Feeds

Servicio descentralizado de precios on-chain.

**Aplicabilidad al caso:** **NO necesario**. El precio del token es prepago en USDC, fijado off-chain por el operador al crear el lote. No hay precio dinámico.

#### 7.2.2 Chainlink VRF (Verifiable Random Function)

Aleatoriedad criptográfica.

**Aplicabilidad:** **no aplica**.

#### 7.2.3 Chainlink Automation (Keepers)

Ejecución automática de funciones on-chain por tiempo o condición.

**Aplicabilidad:** podríamos usarlo para liberar reserva técnica automáticamente tras confirmación de cosecha, pero:
- La operación ya está cubierta por un cron job en el backend que monitorea eventos
- Backend cron es más simple y más barato
- Sin valor agregado por Chainlink Automation en MVP

#### 7.2.4 Chainlink Functions

Llamar APIs Web2 desde smart contracts.

**Aplicabilidad:** podríamos usarlo para sincronizar Sumsub → IdentityRegistry, pero:
- Webhook directo de Sumsub al backend, y backend llamando al contrato, es más simple
- Chainlink Functions añade gas, latencia y dependencia
- Sin valor agregado en MVP

#### 7.2.5 Chainlink CCIP (Cross-Chain Interoperability Protocol)

Mensajería cross-chain.

**Aplicabilidad:** **no aplica en MVP** (single-chain).

#### 7.2.6 Chainlink Proof of Reserve

Verificación on-chain de reservas off-chain.

**Aplicabilidad:** **interesante a futuro**. Permite verificar públicamente que existen los kg de miel reportados como almacenados. Pero requiere oráculos que verifiquen reportes del almacén, lo que en práctica reemplaza nuestro flujo de Safe multi-firma con documentos hasheados a Arweave. **No necesario en MVP, evaluable en fase 2 si el volumen lo justifica.**

#### 7.2.7 Safe (Gnosis Safe) multi-firma 2-de-3 (oráculo humano)

Multi-firma con 3 firmantes (cofundadores con hardware wallets), threshold 2-de-3. Cualquier confirmación on-chain (cosecha, almacenamiento, exportación, fallo) requiere 2 firmas humanas.

**Pro:**
- **Decisión humana auditable**: cada confirmación tiene firmantes identificables
- **Defensible legalmente**: representantes legales de la entidad emisora firmando
- **Sin dependencias externas**
- **Gas barato**
- **Documentos en Arweave** proveen evidencia inmutable de qué se firmó

**Contra:**
- Requiere disponibilidad de 2 de 3 firmantes para cada confirmación
- Si se pierden 2 hardware wallets, sistema bloqueado (mitigado con escrow notarial de seeds + drill trimestral)

### 7.3 Recomendación: combinar Safe multi-firma + Chainlink Proof of Reserve (revisión v2.0)

**Cambio respecto a v1.0:** la versión 1.0 descartaba Chainlink completamente para MVP. **Esta decisión se revierte parcialmente en v2.0** porque Chainlink Proof of Reserve aporta valor diferencial para credibilidad institucional con compradores premium europeos, y el Chainlink BUILD program (gratis si aceptados) elimina el argumento de costo.

**Decisión v2.0:**

| Función | Solución | Justificación |
|---|---|---|
| Confirmación de hitos productivos (cosecha, almacenamiento, exportación, fallo) | **Safe multi-firma 2-de-3** | Decisiones humanas con responsabilidad identificable |
| **Verificación pública de reservas físicas (kg en almacén)** | **Chainlink Proof of Reserve** | Credibilidad institucional cryptográficamente verificable |
| Confirmación de calidad (palinología, NMR) | **LabRegistry + QualityAttestation (FASE 2 — ADR-010)** | Ver Sección 7B — no incluido en MVP. |
| Cross-chain Plume↔Polygon (fase 6+) | **Plume SkyLink** (primario) o **Chainlink CCIP** (alternativa) | Mirror de estado, no bridge de tokens |
| Price feeds, VRF, Automation, Functions | **No usar en MVP** | Innecesarios para el caso de uso |

**Por qué Chainlink Proof of Reserve sí aporta valor:**

El sistema dice "el lote #5 tiene 100 kg almacenados en el almacén Y". Sin PoR, este dato depende de la firma del oráculo humano (cofundadores). Para un comprador retail europeo, esta firma es suficiente. **Para un comprador institucional B2B premium (importador alemán, hotel 5*, distribuidor de specialty food), no es suficiente.** Quieren verificación independiente.

Chainlink PoR resuelve esto:
1. Nodos Chainlink descentralizados consultan el balance físico (vía API del almacén certificado o reporte firmado)
2. Publican el resultado on-chain de forma firmada y verificable por cualquiera
3. El comprador institucional puede verificar en PolygonScan/PlumeExplorer que los kg reportados existen

**Chainlink BUILD program (clave para el costo):**

- Aplicación abierta para proyectos crypto en early-stage
- Provee acceso gratis a servicios Chainlink + soporte técnico + co-marketing
- Caso de uso (RWA tokenización + PoR) encaja con el target del programa
- **Aplicar apenas tengamos testnet funcionando** (fase 1-2)

**Si no entramos al BUILD program:** PoR sigue siendo viable, costo estimado USD 50-200/mes en LINK tokens (proporcional a frecuencia de updates).

**Plan de escalamiento posterior a MVP:**
- **Chainlink Automation**: si el volumen de operaciones automáticas crece significativamente, evaluar
- **Chainlink Functions**: si necesitamos llamar APIs Web2 desde contratos de forma trusted
- **Chainlink CCIP**: si decidimos mirror de estado a más chains que Polygon (Arbitrum, Avalanche, etc.)

### 7.4 Implementación del Safe multi-firma

- **Firmantes (3):** tres cofundadores con direcciones documentadas y declaradas
- **Hardware wallets:** cada firmante usa Ledger Nano X o Trezor Model T
- **Threshold:** 2-de-3
- **Dashboard custom en panel admin** para preparar transacciones:
  - Upload de documentos
  - Cálculo automático de hash SHA-256
  - Generación de calldata Solidity
  - Envío al Safe Transaction Service
  - Notificación a firmantes vía email + Slack DM
- **Cada firma se ejecuta en Safe Web UI** (interfaz oficial) con el hardware wallet conectado
- **Audit trail completo** en PostgreSQL: tx hash Safe, firmantes, documentos relacionados, timestamp

---

## 7B. [FASE 2 — ADR-010] Decisión técnica #4B: oráculo de calidad (palinología + NMR + LabRegistry)

> **Esta sección describe una decisión arquitectónica FASE 2, no parte del MVP.**
> `LabRegistry.sol`, `QualityAttestation`, la función `confirmarCalidad` y el estado `QUALITY_ATTESTED`
> están reservados para activación posterior (ADR-010). El MVP deployará 3 contratos solamente.
> Esta sección se mantiene como referencia de diseño para cuando se active.

**Esta sección fue incorporada en v2.0 y representa el pilar diferencial del producto para FASE 2.**

### 7B.1 El problema técnico-comercial

La industria mielera global enfrenta un problema masivo de adulteración. China exporta volumen significativo de "miel" mezclada con jarabes (HFCS, jarabe de arroz, jarabe de remolacha) etiquetada falsamente como monofloral premium. Tests rutinarios de aduana no detectan adulteración sofisticada. Como resultado, compradores europeos que pagan premium por miel monofloral certificada reciben mezclas, y la confianza estructural del mercado de mieles especiales está dañada.

**Sin un oráculo de calidad verificable, nuestro token compite contra commodity genérico y pierde el premium price.**

**Con un oráculo de calidad verificable on-chain, nuestro token es la única certificación cryptográfica de monofloralidad disponible en el mercado.** Esto es el moat real del producto.

### 7B.2 Tests científicos relevantes

| Test | Qué detecta | Donde se realiza | Estándar |
|---|---|---|---|
| **Palinología (pollen analysis)** | Porcentaje de polen de la especie monofloral declarada | Lab especializado con microscopio + conteo manual de granos | ≥45% polen dominante = "monofloral" según estándar UE |
| **NMR Spectroscopy** | Adulteración con jarabes (perfil isotópico característico) | Eurofins, Intertek, SGS, TÜV | Pass/Fail binario |
| **C4 Sugar Analysis (AOAC 998.12)** | Adulteración con jarabe de caña o maíz (isótopos C4) | Labs especializados de control alimentario | δ¹³C ratio dentro de rango natural |
| **Pesticidas y antibióticos** | Residuos químicos | Labs de control alimentario | Cumplimiento límites EU MRL |
| **HMF, diastasa, humedad** | Frescura y procesamiento | Lab estándar | Estándares Codex Alimentarius |

### 7B.3 Labs certificados candidatos para LabRegistry

| Lab | Jurisdicción | Especialización | Reconocimiento |
|---|---|---|---|
| **IBNORCA** | Bolivia | Laboratorio nacional acreditado | Reconocido en Bolivia y MERCOSUR |
| **Eurofins** | Alemania / global | NMR spectroscopy para alimentos, palinología | Líder mundial en testing de alimentos |
| **Intertek** | UK / global | Multi-test (palinología + NMR + C4) | Acreditado globalmente |
| **SGS** | Suiza / global | Multi-test, fuerte presencia LATAM | Acreditado globalmente |
| **TÜV** | Alemania | Multi-test, foco mercado europeo | Acreditado en UE |

**Política de LabRegistry:** mínimo 2 labs en whitelist desde el lanzamiento. Recomendado: 1 lab boliviano (IBNORCA) + 1 lab europeo (Eurofins o Intertek) para cada lote, con tests independientes que se contrastan.

### 7B.4 Arquitectura del oráculo de calidad

```
┌─────────────────────────────────────────────────────────┐
│ 1. Operador SRL recoge muestras representativas del lote │
│    y las envía a dos labs certificados independientes    │
│    (IBNORCA + Eurofins, por ejemplo)                     │
└────────────────────┬────────────────────────────────────┘
                     ▼
┌─────────────────────────────────────────────────────────┐
│ 2. Cada lab realiza tests (palinología + NMR + C4 + ...)│
│    y emite certificado digital firmado con su clave     │
│    privada registrada en LabRegistry on-chain           │
└────────────────────┬────────────────────────────────────┘
                     ▼
┌─────────────────────────────────────────────────────────┐
│ 3. Backend valida firma del lab + sube certificados a   │
│    Arweave + extrae resultados estructurados            │
└────────────────────┬────────────────────────────────────┘
                     ▼
┌─────────────────────────────────────────────────────────┐
│ 4. Backend prepara transacción Safe multi-sig:          │
│    confirmarCalidad(loteId, attestation, signatures)     │
└────────────────────┬────────────────────────────────────┘
                     ▼
┌─────────────────────────────────────────────────────────┐
│ 5. Safe multi-sig 2-de-3 firma → tx ejecutada           │
└────────────────────┬────────────────────────────────────┘
                     ▼
┌─────────────────────────────────────────────────────────┐
│ 6. AssetVault.LoteMiel.qualityAttestation populated:    │
│    - labAddresses[]                                      │
│    - pollenSpecies: bytes2 (código ISO botánico)         │
│    - pollenPercentage: uint8 (0-100, real)               │
│    - nmrPassed: bool                                     │
│    - c4Passed: bool                                      │
│    - residuesPassed: bool                                │
│    - fullReportHashes: bytes32[]                         │
│    - testedAt: uint64                                    │
└─────────────────────────────────────────────────────────┘
```

### 7B.5 `LabRegistry.sol` — diseño funcional

**Propósito:** mantener la whitelist on-chain de laboratorios certificados autorizados para emitir attestations de calidad.

**Struct `Lab`:**

```
struct Lab {
    address    signerAddress;       // clave pública del lab
    bytes32    nameHash;            // hash del nombre legal del lab
    bytes2     jurisdiction;        // ISO 3166-1 alpha-2
    uint8[]    specializations;     // enum: PALINOLOGIA, NMR, C4, PESTICIDES, etc.
    bytes32    accreditationHash;   // hash de credenciales de acreditación
    bool       active;
    uint64     addedAt;
    uint64     deactivatedAt;
}

mapping(address => Lab) public labs;
```

**Funciones:**

- `addLab(...)` (only `ADMIN_ROLE`): agrega nuevo lab certificado a la whitelist
- `deactivateLab(...)` (only `COMPLIANCE_OFFICER_ROLE`): desactiva lab por cualquier motivo
- `verifyAttestationSignature(lab, attestationHash, signature) view returns (bool)`: verifica firma del lab off-chain
- `isLabCertifiedFor(lab, specialization) view returns (bool)`: chequea si el lab está autorizado para un test específico

**Eventos:**

- `LabAdded(address indexed lab, bytes2 jurisdiction, uint8[] specializations)`
- `LabDeactivated(address indexed lab, string reason)`

### 7B.6 `QualityAttestation` en `LoteMiel`

Se agrega al struct `LoteMiel` en `AssetVault.sol`:

```
struct QualityAttestation {
    address[]  labAddresses;          // labs que firmaron la attestation
    bytes2     pollenSpecies;          // código de especie monofloral
    uint8      pollenPercentage;       // % real, 0-100
    bool       nmrPassed;
    bool       c4Passed;
    bool       residuesPassed;
    bytes32[]  fullReportHashes;       // un hash por reporte completo
    uint64     testedAt;
    bool       isMonofloralCertified;  // computed: pollenPct >= 45 && nmrPassed && c4Passed && residuesPassed
}

LoteMiel.qualityAttestation; // populated tras confirmarCalidad
```

**Función nueva en `AssetVault.sol`:**

```
function confirmarCalidad(
    uint256 loteId,
    QualityAttestation calldata attestation,
    bytes[] calldata labSignatures  // firmas de cada lab sobre el hash de su reporte
) external onlyRole(ORACLE_ROLE);
```

Esta función:
1. Valida que `attestation.labAddresses[]` contenga al menos 2 labs (uno boliviano + uno internacional)
2. Para cada lab, valida via `LabRegistry.verifyAttestationSignature()` que la firma sea válida
3. Verifica que los labs estén autorizados para los tests correspondientes
4. Computa `isMonofloralCertified` según reglas predefinidas
5. Guarda la attestation en el lote
6. Emite evento `CalidadConfirmada`

### 7B.7 Por qué este diseño es defendible

1. **Transparencia total**: cualquier comprador puede verificar on-chain qué labs analizaron el lote, qué % de polen tiene, si pasó NMR y C4
2. **Doble verificación**: requerir 2 labs independientes (uno boliviano para validez local, uno europeo para validez mercado destino) reduce riesgo de colusión
3. **Cryptográficamente verificable**: cada lab firma con su clave privada registrada on-chain. Manipular el reporte requiere comprometer la clave del lab.
4. **Cadena de custodia documental**: los reportes completos en Arweave permiten auditoría detallada por terceros (compradores institucionales, reguladores, periodistas, ONGs).
5. **Estándar UE adoptado**: la regla `pollenPct >= 45% && nmrPassed && c4Passed` es consistente con la regulación europea de miel monofloral (Directiva 2014/63/UE). No inventamos estándar propio.

### 7B.8 Impacto sobre el resto del sistema

**Nuevo módulo backend:** `apps/api/src/modules/quality/`
- `lab-integration/` — adaptadores para APIs de cada lab certificado
- `attestation-builder/` — construye `QualityAttestation` a partir de reportes individuales
- `signature-verifier/` — verifica firmas de labs antes de enviar a oracle
- `lab-onboarding/` — workflow para incorporar nuevo lab al LabRegistry

**Nuevos flujos operacionales:**
- Onboarding de un lab nuevo (alta en LabRegistry on-chain + setup técnico de integración)
- Confirmación de calidad de un lote (recoge muestras → envía a labs → recibe reportes → builds attestation → submit al oracle)
- Manejo de discrepancias entre labs (si los dos labs reportan resultados muy distintos)

**Timeline operativo del lote:**
- **MVP:** PREVENTA → COSECHADO → ALMACENADO → REDENCION_PARCIAL → AGOTADO (o FALLIDO desde PREVENTA/COSECHADO)
- **FASE 2 (con LabRegistry):** PREVENTA → COSECHADO → **QUALITY_ATTESTED** → ALMACENADO → REDENCION_PARCIAL → AGOTADO

**Tiempo y costo adicional por lote:**
- Tiempo entre cosecha y attestation: 2-4 semanas (envío de muestras, análisis, recepción de reportes)
- Costo por lote: USD 200-600 (depende de labs y tests; suele ser una sola vez al inicio del lote, no por kg)
- Este costo es proporcional al diferencial de precio del producto premium (miel monofloral comanda USD 35-60/kg adicional vs commodity; el costo de certificación se recupera con los primeros 10-15 kg vendidos)

---

## 8. Decisión técnica #5: protocolos auxiliares

### 8.1 Protocolos evaluados

| Protocolo | Función | Decisión MVP v2.0 | Razón |
|---|---|---|---|
| **Plume Arc** | KYC integrado a nivel chain | ✅ Usar (Plume primaria) | Built-in en Plume, reduce código custom de IdentityRegistry |
| **Plume Nexus** | Oracle data layer de Plume | ⚠️ Evaluar fase 1-2 | Para datos RWA específicos; revisar vs Chainlink Functions |
| **Plume SkyLink** | Cross-chain settlement Plume↔otras | ✅ Usar (fase 6+) | Para mirror estado Plume→Polygon |
| **OpenZeppelin Contracts v5** | Librería estándar de contratos seguros | ✅ Usar | Estándar de industria, máxima cobertura de auditoría |
| **Foundry (Forge, Cast, Anvil)** | Framework de tests y deployment | ✅ Usar | Fuzz + invariant testing nativo, performance superior a Hardhat |
| **Hardhat** | Framework alternativo | ❌ No | Foundry cubre el caso, evita duplicación |
| **Safe (Gnosis Safe)** | Multi-firma | ✅ Usar | Deploy en Plume + Polygon, mismos 3 firmantes |
| **wagmi v2 + viem** | Cliente Web3 frontend | ✅ Usar | Multi-chain nativo, type-safe |
| **RainbowKit** | UI de conexión wallet | ✅ Usar | UX limpia, soporte Plume + Polygon |
| **Bundlr / Irys** | Upload a Arweave | ✅ Usar | Pago en muchas monedas, integración EVM |
| **Arweave** | Almacenamiento permanente | ✅ Usar | Permanencia perpetua, ideal para evidencia |
| **IPFS + Pinata** | Almacenamiento alternativo | ❌ No | IPFS no garantiza permanencia, Arweave sí |
| **The Graph** | Indexador descentralizado | ❌ No primario | Goldsky es más rápido y soporta Plume + Polygon |
| **Goldsky** | Indexador centralizado managed | ✅ Usar primario | Performance superior, SLAs profesionales |
| **WalletConnect v2** | Protocolo de wallet | ✅ Usar | Estándar, integrado con RainbowKit |
| **Chainlink Proof of Reserve** | Verificación pública de reservas físicas | ✅ Usar desde MVP | Credibilidad institucional con compradores B2B premium |
| **Chainlink BUILD program** | Acceso gratis a servicios Chainlink + soporte | ✅ Aplicar fase 1 | Si aprobado, costo PoR = cero |
| **Chainlink CCIP** | Cross-chain messaging genérico | ⚠️ Alternativa a SkyLink (fase 6+) | Evaluar vs Plume SkyLink |
| **Chainlink Functions** | Llamar APIs Web2 desde contratos | ⚠️ Evaluar fase 2 | Posible para integración directa con APIs de labs |
| **Chainlink Price Feeds / VRF / Automation** | Precios, randomness, ejecución | ❌ No MVP | No aplicables al caso |
| **Push Protocol** | Notificaciones on-chain | ❌ No MVP | Email + push web es suficiente |
| **EAS (Ethereum Attestation Service)** | Attestaciones on-chain | ❌ No MVP | Reemplazado por LabRegistry + QualityAttestation custom |
| **Pyth Network** | Oracle de precios alternativo | ❌ No | No requerimos price feeds |
| **LayerZero** | Mensajería cross-chain | ❌ No MVP | Plume SkyLink + Chainlink CCIP cubren cross-chain |
| **Wormhole** | Bridge cross-chain | ❌ No MVP | Idem |
| **Lit Protocol** | Threshold cryptography | ❌ No | Safe cubre el caso |
| **Tenderly** | Debugging y simulación | ✅ Usar | Pre-deploy testing en Plume y Polygon |
| **Foundry Cast** | CLI para interactuar con cadena | ✅ Usar | Incluido en Foundry |

### 8.2 Stack de protocolos confirmado v2.0

**On-chain (Plume primaria, Polygon fase 6+):**
- ERC-1155 + `AccessControlDefaultAdminRules` (delay 3 días, ADR-012) + ReentrancyGuard + Pausable (OpenZeppelin v5)
- Asimetría de pause ADR-016: `pause()` = Compliance|Admin; `unpause()` = solo Admin (aplica a los 3 contratos)
- Safe multi-firma 2-de-3 (deploy en Plume + Polygon)
- Plume Arc para KYC integrado a nivel chain
- Chainlink Proof of Reserve para verificación de reservas físicas
- **FASE 2 — ADR-010:** LabRegistry custom para attestations de calidad

**Tooling Solidity:**
- Foundry (forge, cast, anvil)
- OpenZeppelin Contracts v5
- Tenderly para pre-deploy simulation (Plume y Polygon)
- Slither + Mythril para análisis estático

**Frontend Web3:**
- wagmi v2 + viem (multi-chain)
- RainbowKit + WalletConnect v2

**Indexación:**
- Goldsky subgraph (Plume primario, Polygon fase 6+)

**Cross-chain (fase 6+):**
- Plume SkyLink (primaria)
- Chainlink CCIP (alternativa evaluable)

**Almacenamiento:**
- Arweave vía Bundlr/Irys
- Cloudflare R2 (operacional)

---

# PARTE III — STACK TECNOLÓGICO POR CAPA

## 9. Capa blockchain

### 9.1 Componentes (multi-chain v2.0)

| Componente | Tecnología | Versión | Notas |
|---|---|---|---|
| Red primaria | **Plume Network Mainnet** | — | Testnet: Plume Testnet |
| Red secundaria (fase 6+) | Polygon PoS Mainnet | — | Testnet: Polygon Amoy |
| Lenguaje | Solidity | 0.8.24+ | Latest stable, sin features experimentales |
| Compilador | solc | 0.8.24 | Optimizer enabled, runs=200 |
| Estándar de token | ERC-1155 | — | Multi-token semi-fungible |
| Librería base | OpenZeppelin Contracts | 5.x | Última estable |
| Framework de tests | Foundry | latest | forge, cast, anvil |
| Análisis estático | Slither | latest | Pre-commit hook |
| RPC primario Plume | Plume RPC oficial | — | + provider redundante |
| RPC primario Polygon (fase 6+) | Alchemy | — | Polygon endpoint |
| RPC fallback Polygon | Infura | — | Polygon endpoint |
| Explorer Plume | Plume Explorer | — | Para verificación |
| Explorer Polygon | PolygonScan | — | Para verificación |
| Multi-sig | Safe (Gnosis) | latest UI | Deploy en Plume + Polygon, mismos firmantes |
| KYC layer | Plume Arc + Sumsub bridge | — | Plume primaria; bridge a IdentityRegistry custom |
| Proof of Reserve | Chainlink PoR | — | Plume primero, Polygon mirror fase 6+ |
| Stable coin (Plume) | USDC nativo | — | Plume USDC contract address |
| Stable coin (Polygon) | USDC nativo Circle | — | `0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359` |

### 9.2 Contratos del MVP (v2.1 — 3 contratos, ADR-010)

| Contrato | Propósito | Líneas estimadas |
|---|---|---|
| `AssetVault.sol` | ERC-1155 + lifecycle + escrow total + compliance hook. Sin `QualityAttestation` (FASE 2). | ~500-700 |
| `IdentityRegistry.sol` | Whitelist on-chain, tiers, sanciones, congelamiento. Pausable (ADR-013, FIX H-02). | ~200-300 |
| `RedemptionManager.sol` | Máquina de estados 2 fases (ADR-017) + lock acumulator Option B. | ~200-300 |
| `interfaces/I*.sol` | Interfaces (3 contratos MVP) | ~120 total |
| `libraries/ComplianceConstants.sol` | Constantes (granularidad, reserva, tiers) | ~50 |
| `libraries/DocumentHashes.sol` | Helpers SHA-256 | ~50 |
| **Total estimado MVP** | | **~1,070-1,470 LOC** |
| *(FASE 2) `phase2/LabRegistry.sol`* | *Whitelist labs certificados + verificación firmas (ADR-010)* | *~150-250* |
| *(FASE 2) `libraries/QualityRules.sol`* | *Reglas de calidad monofloral (ADR-010)* | *~50* |

### 9.3 Configuración del proyecto Foundry

```
foundry.toml (estructura clave):
- src/
- test/
- script/
- lib/
solc = "0.8.24"
optimizer = true
optimizer_runs = 200
via_ir = true (opcional)
fuzz.runs = 10000
invariant.runs = 50000
invariant.depth = 100
verbosity = 2
```

### 9.4 Estrategia de deployment

- **Testnet (Plume Testnet):** primer deploy de los 3 contratos MVP + ejecución de 7 escenarios end-to-end de validación
- **Pre-mainnet:** auditoría externa (Trail of Bits, Sherlock contest, o OpenZeppelin) — auditoría de 3 contratos
- **Mainnet (Plume Mainnet, fases 1-5):** deploy verificado en Plume Explorer + configuración de roles del Safe
- **Mainnet (Polygon PoS, fase 6+):** deploy incremental con auditoría de cambios mínimos
- **Scripts de deployment:** Foundry scripts en `script/Deploy.s.sol` con parámetros versionados

---

## 10. Capa de identidad y verificación

### 10.1 KYC: Sumsub

| Componente | Detalle |
|---|---|
| Proveedor | Sumsub |
| Tipos de aplicación | Individual + Business |
| Niveles soportados | Tier 1 (básico), Tier 2 (estándar), Tier 3 (reforzado / EDD) |
| Verificación incluida | Documento de identidad, selfie con liveness, comprobante de domicilio, EDD para Tier 3 |
| Integración | Webhook al backend (firmado HMAC SHA-256) |
| Sincronización on-chain | Backend → `IdentityRegistry.setKYC()` |

### 10.2 IdentityRegistry on-chain

```solidity
// CONTRACT-SPECS §5 — struct renombrado KYCData (antes IdentityData)
struct KYCData {
    uint8   tier;                  // 0=none/revocado, 1=básico, 2=estándar, 3=reforzado EDD
    bool    sanctioned;
    bool    frozen;
    bytes2  jurisdiction;          // ISO 3166-1 alpha-2 (e.g. "BO", "DE", "US")
    uint64  expiresAt;             // unix timestamp de expiración KYC
    uint64  updatedAt;             // unix timestamp del último cambio
    bytes32 sumsubApplicantHash;   // hash del applicantId Sumsub (audit trail off-chain, no PII)
}

// El contrato no almacena PII. sumsubApplicantHash es un commitment criptográfico unidireccional.
mapping(address => KYCData) private _kyc;
```

> **ADR-012 / FIX M-08:** `IdentityRegistry` usa `AccessControlDefaultAdminRules` (delay 3 días para transferencias de `DEFAULT_ADMIN_ROLE`).
> **ADR-016 / FIX H-02:** `IdentityRegistry` implementa `Pausable`. Asimetría: `pause()` = COMPLIANCE_OFFICER_ROLE OR DEFAULT_ADMIN_ROLE; `unpause()` = solo DEFAULT_ADMIN_ROLE. Las views (`canMint`, `canRedeem`, `isSanctioned`) **no se bloquean** durante el pause, para que AssetVault y RedemptionManager sigan validando.

### 10.3 Screening de sancionados

| Lista | Fuente | Frecuencia |
|---|---|---|
| OFAC SDN | Treasury.gov XML | Diaria |
| UN Consolidated | scsanctions.un.org | Diaria |
| EU Consolidated | EU sanctions service | Diaria |
| Chainalysis API (opcional) | Chainalysis | Real-time on transaction |

Backend cron nightly recorre la lista de direcciones registradas y aplica matching fuzzy contra las listas oficiales. Hits gatillan `IdentityRegistry.markSanctioned()` automáticamente.

---

## 11. Capa de pagos

### 11.1 Pagos B2B (importadores empresariales)

| Método | Provider | Flujo |
|---|---|---|
| Tarjeta corporativa | Stripe | Pago en USD → conversion USDC → mint |
| Wire SWIFT | Banco Wyoming | Comprador envía wire → reconciliación manual → mint |

### 11.2 Pagos B2C (consumidores retail europeos)

| Método | Provider | Notas |
|---|---|---|
| Tarjeta de crédito → USDC | MoonPay | Mejor cobertura UE |
| SEPA → USDC | Ramp Network | Excelente para EU |
| Tarjeta alternativa | Transak | Backup |
| Wallet con USDC existente | Direct transfer | Para crypto-natives |

### 11.3 Flujo unificado de pagos

```
[Cliente] → [Provider de pago / Wallet] → [USDC en wallet operativa Safe Wyoming]
                                          ↓
                                     [Backend confirma recepción]
                                          ↓
                                     [Backend ejecuta AssetVault.comprar()]
                                          ↓
                                     [Mint de tokens al wallet del comprador]
```

Para B2C UE: el flujo incluye un período de retención de 14 días (window de retracto MiCA) antes del mint on-chain (el "token" vive como crédito off-chain durante ese período).

---

## 12. Capa de almacenamiento

### 12.1 Estrategia de tres niveles

| Nivel | Tecnología | Propósito | Retención |
|---|---|---|---|
| Operacional | PostgreSQL (Supabase) | Datos vivos del sistema | Permanente con backups diarios |
| Backup rápido | Cloudflare R2 | Documentos accesibles rápidamente | Permanente |
| Permanencia legal | Arweave (vía Bundlr/Irys) | Evidencia inmutable e indelible | Perpetuo (pago único) |

### 12.2 Flujo de upload de documentos

```
Operator uploads PDF
        ↓
Backend calculates SHA-256 hash (local)
        ↓
Backend stores in DB: { sha256, status: 'pending' }
        ↓
Backend uploads to Cloudflare R2 (fast access)
        ↓
Backend uploads to Arweave via Bundlr (permanent)
        ↓
Backend downloads from Arweave gateway, re-hashes, verifies match
        ↓
DB updated: { sha256, r2_uri, arweave_uri, status: 'verified' }
        ↓
Hash on-chain via oracle multi-sig firma + tx in MielVault
```

### 12.3 Tipos de documentos almacenados

- Forward Sale Agreement por lote
- Certificados sanitarios (SENASAG u homólogos)
- Análisis físico-químicos de laboratorio
- Actas de cosecha firmadas
- Fotografías georeferenciadas del apiario
- Certificados de origen (Formulario A, EUR.1)
- Contratos de depósito con almacén
- DUE (Declaración Única de Exportación)
- BL/AWB (transporte internacional)
- Términos y Condiciones del servicio (versionado)
- Manuales internos (compliance, operaciones)

---

## 13. Capa de backend

### 13.1 Stack

| Componente | Tecnología | Versión |
|---|---|---|
| Runtime | Bun | 1.x |
| Framework HTTP | Hono | 4.x |
| Lenguaje | TypeScript | 5.x |
| ORM | Drizzle | latest |
| Base de datos | PostgreSQL | 16+ (Supabase) |
| Cache | Redis | latest (Upstash) |
| Validación | Zod | latest |
| Cliente Web3 | viem | 2.x |
| Auth admin | Clerk | latest |
| Logging | pino | latest |
| Cron jobs | BullMQ + Redis | latest |

### 13.2 Arquitectura del backend

**Patrón:** **Modular Monolith** (no microservicios para MVP). Un solo proceso, múltiples módulos con boundaries claros.

**Justificación:** microservicios añaden complejidad operacional (deployment, networking, distributed tracing) que no se justifica con un equipo de 2-4 personas y volumen MVP. Modular monolith permite refactorizar a microservicios cuando el volumen lo justifique.

### 13.3 Módulos del backend

```
apps/api/src/modules/
├── assets/              (categorías de activos tokenizables)
│   ├── domain/         (entidades, value objects)
│   ├── application/    (use cases, application services)
│   ├── infrastructure/ (repositories, external integrations)
│   └── api/            (Hono routes, DTOs Zod)
├── lots/                (lotes individuales, ciclo de vida)
├── identity/            (KYC sync, screening, registry sync)
│   ├── kyc-sync/
│   ├── screening/
│   └── on-chain-sync/
├── payments/            (Stripe, SWIFT, MoonPay, Ramp)
│   ├── stripe-adapter/
│   ├── moonpay-adapter/
│   ├── ramp-adapter/
│   ├── swift-reconciliation/
│   └── unified-purchase/
├── documents/           (Arweave uploader, hash calc, catalog)
├── oracle/              (preparación de tx Safe multi-sig)
│   ├── tx-builder/
│   ├── safe-adapter/
│   └── signers-notifier/
├── audit/               (append-only log, hash chain, snapshots)
├── notifications/       (Resend email, Slack alerts)
└── shared/              (cross-cutting: logger, errors, types)
```

### 13.4 Patrones internos

- **Hexagonal architecture (Ports & Adapters):** cada módulo tiene un core de dominio y adapters para infraestructura externa
- **Repository pattern** para acceso a datos
- **Use case pattern** para application logic
- **DTO + Zod validation** en cada API route
- **Domain events** para comunicación inter-módulos (in-process event bus)

### 13.5 Stack de jobs asíncronos

| Job | Schedule | Función |
|---|---|---|
| Screening nightly | 02:00 UTC | Comparar registrados vs listas de sancionados |
| Document verify | Continuous | Verificar readback de Arweave |
| Audit snapshot | Día 1 mensual | Snapshot del audit log a Arweave |
| Identity expiry | Diaria | Marcar KYC expirados |
| Payment reconciliation | Cada 15 min | Reconciliar wires SWIFT pendientes |
| Withdrawal hold expiry | Cada hora | Procesar mints diferidos (MiCA 14d) |

---

## 14. Capa de frontend

### 14.1 Stack

| Componente | Tecnología |
|---|---|
| Framework | Next.js 15 (App Router) |
| Lenguaje | TypeScript 5.x |
| Estilos | TailwindCSS 4.x |
| Componentes UI | shadcn/ui (basado en Radix) |
| Cliente Web3 | wagmi v2 + viem |
| Wallet UI | RainbowKit |
| Forms | React Hook Form + Zod resolver |
| State management | Zustand (cuando necesario) |
| Data fetching | TanStack Query (integrado con wagmi) |
| i18n | next-intl |
| Animations | Framer Motion |
| Charts | Recharts (si necesarios) |

### 14.2 Estructura de áreas del frontend

```
apps/web/src/app/
├── (marketing)/         (landing público, FAQ, terms)
├── (catalog)/           (catálogo de lotes públicos)
├── (auth)/              (login, registro, recovery)
├── (account)/           (panel del usuario, KYC, compras, redenciones)
├── (admin)/             (panel administrativo)
│   ├── lots/
│   ├── identity/
│   ├── oracle/
│   ├── documents/
│   └── audit/
└── api/                 (route handlers Next.js para edge functions)
```

### 14.3 Wallets soportadas

- MetaMask
- Coinbase Wallet
- WalletConnect v2 (cubre Rainbow, Trust, Rabby, otras)
- Safe Wallet (para compradores B2B con multi-sig propio)
- Ledger directo (vía RainbowKit)
- Trezor directo

### 14.4 Internacionalización

- **Idiomas MVP:** español (es), inglés (en)
- **Roadmap:** alemán (de), italiano (it), francés (fr) en fase 2

---

## 15. Capa de indexación

### 15.1 Goldsky subgraph

**Función:** indexa los eventos on-chain de los 3 contratos y los expone vía API GraphQL para que el backend y el frontend consulten datos históricos con baja latencia.

**Eventos indexados:**
- `AssetVault`: `LoteCreado`, `LoteComprado`, `CosechaConfirmada`, `AlmacenamientoConfirmado`, `LoteFallido`, `ReservaTecnicaLiberada`, `ReembolsoEjecutado`
- `IdentityRegistry`: `KYCUpdated`, `Sanctioned`, `Unsanctioned`, `Frozen`, `Unfrozen`, `KYCRevoked`
- `RedemptionManager`: `RedencionIniciada`, `RedencionEnExportacion`, `RedencionCompletada`, `RedencionCancelada`

### 15.2 Schema del subgraph

```graphql
type Lot @entity {
  id: ID!  # loteId
  asset: Asset!
  state: LotState!
  kgEsperados: BigInt!
  kgCosechadosReal: BigInt
  kgRedimidos: BigInt!
  hashFSA: Bytes!
  hashSenasag: Bytes
  hashAnalisisLab: Bytes
  hashContratoDeposito: Bytes
  productor: Bytes!
  reservaTecnicaUSDC: BigInt!
  purchases: [Purchase!]! @derivedFrom(field: "lot")
  redemptions: [Redemption!]! @derivedFrom(field: "lot")
  createdAt: BigInt!
  updatedAt: BigInt!
}

type Purchase @entity {
  id: ID!
  lot: Lot!
  buyer: Bytes!
  amountTokens: BigInt!
  amountUSDC: BigInt!
  paymentRefHash: Bytes!
  timestamp: BigInt!
  txHash: Bytes!
}

type Redemption @entity { ... }
type Identity @entity { ... }
```

### 15.3 Por qué Goldsky y no The Graph

- **Performance superior** en Polygon mainnet
- **SLAs profesionales** disponibles
- **Mirroring a webhooks**: Goldsky puede empujar eventos a un endpoint webhook, alternativa al polling
- **Dashboard de monitoreo** integrado

The Graph queda como **opción de respaldo** si Goldsky falla o pricing cambia.

---

## 16. Capa de monitoreo y observabilidad

### 16.1 Stack de observabilidad

| Tool | Función | Tier MVP |
|---|---|---|
| Sentry | Error tracking (backend + frontend) | Free tier (sufficient para MVP) |
| Better Stack | Uptime monitoring + log aggregation | Free tier |
| Grafana Cloud (opcional) | Métricas custom | Free tier |
| Plausible Analytics | Web analytics privacy-first | Self-hosted o cloud |
| PolygonScan | Explorador on-chain | Free |
| Tenderly | Alertas on-chain, debugging | Free tier |

### 16.2 Métricas críticas a monitorear

**Sistema:**
- Latencia p50, p95, p99 por endpoint
- Tasa de error 4xx, 5xx
- Uptime backend, frontend, indexer
- Conexiones DB activas
- Cache hit rate Redis

**Negocio:**
- Compras por hora/día
- Tokens emitidos por lote
- Redenciones iniciadas vs completadas
- KYC: tasa de aprobación, tiempo promedio
- Pagos fallidos por método
- Eventos on-chain por tipo

**Compliance / Operacional:**
- KYC desync count (off-chain vs on-chain)
- Documentos pendientes de verificación Arweave
- Reportes UIF pendientes de envío
- ROS queue length
- Multi-sig pending transactions

### 16.3 Alertas

| Alerta | Canal | Severidad |
|---|---|---|
| Error rate >1% | Slack + email | High |
| Latencia p95 >500ms | Slack | Medium |
| Backend down | PagerDuty + Slack | Critical |
| Smart contract pause activated | PagerDuty + Slack + SMS | Critical |
| Sanctions match detected | Slack + email Compliance Officer | High |
| Document verification failed | Slack | Medium |
| Multi-sig transaction pending >24h | Slack | Medium |

---

## 17. Capa de seguridad

### 17.1 Principios de seguridad

1. **Least privilege:** cada componente accede solo a lo que necesita
2. **Defense in depth:** múltiples capas de validación
3. **Zero trust:** cada request es validado, sin asumir confianza
4. **Auditabilidad total:** cada acción es loggeable e investigable
5. **No secrets in env vars:** llaves críticas en HSM o hardware wallets

### 17.2 Gestión de llaves

| Llave | Storage | Acceso |
|---|---|---|
| Backend signer (BACKEND_SIGNER_ROLE) | AWS KMS o GCP KMS | Backend production only |
| Treasury SRL signing | Hardware wallet (Ledger) | Tesorero designado |
| Safe multi-sig signers (3) | Hardware wallets (Ledger Nano X) | 3 cofundadores |
| Backup seeds del Safe | Escrow notarial físico | Solo en caso de pérdida |
| Database credentials | Supabase + secret manager | Backend solo |
| Sumsub API keys | Secret manager (Doppler o similar) | Backend solo |
| Stripe API keys | Secret manager | Backend solo |
| Arweave/Bundlr funding wallet | HSM | Backend con quota |

### 17.3 Hardening del backend

- Helmet.js o equivalente (security headers)
- Rate limiting por IP y por user (con Redis)
- CORS estricto (solo dominios propios)
- Input validation con Zod en cada endpoint
- SQL injection: imposible por uso de Drizzle ORM con prepared statements
- XSS: imposible por React + Content Security Policy estricto
- CSRF: protección por SameSite=Strict cookies + double-submit token
- 2FA obligatorio para todos los admin users (Clerk)

### 17.4 Auditoría de smart contracts

**Pre-auditoría interna:**
- Slither (análisis estático)
- Mythril (análisis simbólico)
- Foundry forge test + invariants
- Code review interno entre devs senior

**Auditoría externa (obligatoria pre-mainnet):**
- **Opción A:** auditor solo (Trail of Bits, OpenZeppelin, Consensys Diligence, Cyfrin, Macro)
- **Opción B:** Sherlock contest (pago contingente a findings)
- **Recomendación:** combinar Sherlock contest + revisión interna de hallazgos

**Bug bounty post-mainnet:**
- Plataforma: Immunefi
- Pool inicial: USD 10,000-50,000
- Severity tiers documentados

### 17.5 Penetration testing

Pre-mainnet, contratar penetration testing externo del backend y frontend (no smart contracts, eso lo cubre la auditoría). Foco en:
- Auth flows
- Permission boundaries (admin vs user)
- Webhook validation (Sumsub, Stripe)
- API rate limiting
- Document upload pipeline
- Multi-sig dashboard

### 17.6 Incident response plan

Documentar y ensayar trimestralmente:
- Procedimiento de `pause()` en smart contract ante emergencia
- Procedimiento de rotación de claves comprometidas
- Procedimiento de `swapOwner` en Safe ante pérdida de hardware wallet
- Procedimiento de comunicación a usuarios afectados (cumpliendo no-aviso en casos de ROS)

---

## 18. Capa DevOps y CI/CD

### 18.1 Hosting

| Servicio | Hosting | Justificación |
|---|---|---|
| Frontend Next.js | Vercel | Optimización nativa, edge functions, ISR |
| Backend Bun/Hono | Railway o Fly.io | Soporte Bun, deployment simple |
| PostgreSQL | Supabase | Managed Postgres + Realtime + Storage |
| Redis | Upstash | Edge-friendly, REST + Redis API |
| Indexer subgraph | Goldsky cloud | Managed |
| Storage permanente | Arweave (descentralizado) | Pago único |
| Storage operacional | Cloudflare R2 | S3-compatible, bajo costo |

### 18.2 CI/CD con GitHub Actions

**Pipeline:**

```
On Pull Request:
  → Install dependencies (pnpm install, cached)
  → Build with Turborepo (cache hit makes it seconds)
  → Lint (ESLint, Solhint, Prettier check)
  → Type-check (tsc --noEmit)
  → Tests unitarios (Vitest backend + frontend)
  → Tests Foundry (forge test + fuzz)
  → Análisis estático Slither sobre contratos
  → Coverage report
  → Comment results on PR

On merge to main:
  → All checks pass
  → Deploy preview to Vercel + Railway preview env
  → Run E2E tests (Playwright)
  → If all green, deploy to staging
  → Manual approval for production deploy
  → Deploy to production
```

### 18.3 Branching strategy

- `main`: producción
- `develop`: integración continua
- `feature/*`: features individuales
- `hotfix/*`: fixes urgentes a producción

Conventional Commits obligatorio (`feat:`, `fix:`, `chore:`, etc.) para changelog automático.

### 18.4 Versionado

- Semantic versioning para el package raíz
- Changelog automático con Changesets o release-please
- Tags Git para cada release a producción
- Smart contracts: versión codificada en `version()` view function

---

# PARTE IV — ESTRUCTURA DEL CÓDIGO

## 19. Estructura del monorepo

### 19.1 Layout completo

```
tokenization-platform/
├── apps/
│   ├── web/                       # Frontend Next.js 15
│   │   ├── src/
│   │   │   ├── app/              # App Router (route groups)
│   │   │   │   ├── (marketing)/
│   │   │   │   ├── (catalog)/
│   │   │   │   ├── (auth)/
│   │   │   │   ├── (account)/
│   │   │   │   └── (admin)/
│   │   │   ├── components/       # Componentes específicos de la app
│   │   │   ├── hooks/            # Hooks custom
│   │   │   ├── lib/              # Utilidades específicas web
│   │   │   ├── styles/           # Globals CSS
│   │   │   └── middleware.ts     # Auth, i18n
│   │   ├── public/
│   │   ├── tests/
│   │   │   ├── unit/             # Vitest
│   │   │   └── e2e/              # Playwright
│   │   ├── package.json
│   │   ├── next.config.ts
│   │   ├── tailwind.config.ts
│   │   └── tsconfig.json
│   │
│   └── api/                       # Backend Bun + Hono
│       ├── src/
│       │   ├── modules/          # Modular monolith
│       │   │   ├── assets/
│       │   │   ├── lots/
│       │   │   ├── identity/    # KYC sync + Plume Arc bridge
│       │   │   ├── quality/     # NUEVO v2.0 — labs, attestations, signature verification
│       │   │   ├── payments/
│       │   │   ├── documents/
│       │   │   ├── oracle/
│       │   │   ├── chainlink/   # NUEVO v2.0 — PoR integration, BUILD program apps
│       │   │   ├── crosschain/  # NUEVO v2.0 — Plume SkyLink + Chainlink CCIP mirror
│       │   │   ├── audit/
│       │   │   └── notifications/
│       │   ├── shared/           # Cross-cutting concerns
│       │   │   ├── logger/
│       │   │   ├── errors/
│       │   │   ├── middleware/
│       │   │   └── types/
│       │   ├── jobs/             # BullMQ workers
│       │   ├── webhooks/         # Webhook endpoints (Sumsub, Stripe)
│       │   ├── server.ts         # Hono app
│       │   └── worker.ts         # Jobs worker
│       ├── tests/
│       │   ├── unit/
│       │   ├── integration/
│       │   └── e2e/
│       ├── package.json
│       ├── tsconfig.json
│       └── drizzle.config.ts
│
├── packages/
│   ├── contracts/                 # Smart contracts Solidity (Foundry)
│   │   ├── src/
│   │   │   ├── AssetVault.sol             # MVP
│   │   │   ├── IdentityRegistry.sol       # MVP
│   │   │   ├── RedemptionManager.sol      # MVP
│   │   │   ├── phase2/                    # FASE 2 — no deployado en MVP (ADR-010)
│   │   │   │   └── LabRegistry.sol        # FASE 2 — oráculo de calidad
│   │   │   ├── interfaces/
│   │   │   │   ├── IAssetVault.sol
│   │   │   │   ├── IIdentityRegistry.sol
│   │   │   │   ├── IRedemptionManager.sol
│   │   │   │   └── ILabRegistry.sol       # FASE 2 (ADR-010)
│   │   │   ├── libraries/
│   │   │   │   ├── ComplianceConstants.sol
│   │   │   │   ├── DocumentHashes.sol
│   │   │   │   └── QualityRules.sol       # FASE 2 (ADR-010)
│   │   │   └── adapters/                  # chain adapters
│   │   │       ├── PlumeArcAdapter.sol    # bridge IdentityRegistry ↔ Plume Arc
│   │   │       └── ChainlinkPoRAdapter.sol # integración con Chainlink PoR feeds
│   │   ├── test/
│   │   │   ├── unit/
│   │   │   │   ├── AssetVault.t.sol
│   │   │   │   ├── IdentityRegistry.t.sol
│   │   │   │   ├── RedemptionManager.t.sol
│   │   │   │   └── phase2/LabRegistry.t.sol   # FASE 2 (ADR-010)
│   │   │   ├── fuzz/
│   │   │   │   └── AssetVault.fuzz.t.sol
│   │   │   ├── invariant/
│   │   │   │   └── AssetVault.invariant.t.sol
│   │   │   └── integration/
│   │   │       ├── PurchaseFlow.t.sol
│   │   │       ├── RedemptionFlow.t.sol
│   │   │       ├── OracleFlow.t.sol
│   │   │       ├── ComplianceScenarios.t.sol
│   │   │       └── phase2/QualityAttestationFlow.t.sol  # FASE 2 (ADR-010)
│   │   ├── script/
│   │   │   ├── Deploy.s.sol               # Multi-chain (Plume + Polygon)
│   │   │   ├── DeployPlume.s.sol          # Plume testnet + mainnet
│   │   │   ├── DeployPolygon.s.sol        # fase 6+
│   │   │   ├── ConfigureRoles.s.sol
│   │   │   └── VerifyContracts.s.sol
│   │   ├── foundry.toml
│   │   ├── remappings.txt
│   │   └── package.json
│   │
│   ├── shared/                    # Tipos, schemas, constantes compartidas
│   │   ├── src/
│   │   │   ├── constants/
│   │   │   │   ├── compliance.ts  # mirror de ComplianceConstants.sol
│   │   │   │   ├── tiers.ts
│   │   │   │   ├── jurisdictions.ts # ISO 3166-1 alpha-2
│   │   │   │   └── document-types.ts
│   │   │   ├── schemas/           # Zod schemas
│   │   │   │   ├── identity.ts
│   │   │   │   ├── lot.ts
│   │   │   │   ├── purchase.ts
│   │   │   │   └── redemption.ts
│   │   │   ├── types/             # TypeScript types
│   │   │   └── utils/             # Funciones puras
│   │   ├── package.json
│   │   └── tsconfig.json
│   │
│   ├── ui/                        # Componentes shadcn/ui compartidos
│   │   ├── src/
│   │   │   ├── components/
│   │   │   │   ├── button.tsx
│   │   │   │   ├── card.tsx
│   │   │   │   ├── dialog.tsx
│   │   │   │   ├── form.tsx
│   │   │   │   └── ...
│   │   │   ├── hooks/
│   │   │   └── lib/
│   │   ├── package.json
│   │   └── tailwind.config.ts
│   │
│   ├── config/                    # Configs compartidos
│   │   ├── eslint/
│   │   │   ├── base.js
│   │   │   ├── next.js
│   │   │   ├── api.js
│   │   │   └── solidity.js
│   │   ├── tsconfig/
│   │   │   ├── base.json
│   │   │   ├── next.json
│   │   │   ├── api.json
│   │   │   └── package.json
│   │   ├── prettier/
│   │   │   └── index.js
│   │   └── tailwind/
│   │       └── base.ts
│   │
│   ├── db/                        # Drizzle schemas + migrations
│   │   ├── src/
│   │   │   ├── schema/
│   │   │   │   ├── identity.ts
│   │   │   │   ├── lots.ts
│   │   │   │   ├── purchases.ts
│   │   │   │   ├── redemptions.ts
│   │   │   │   ├── documents.ts
│   │   │   │   ├── audit-log.ts
│   │   │   │   ├── safe-transactions.ts
│   │   │   │   └── index.ts
│   │   │   ├── migrations/
│   │   │   └── client.ts
│   │   ├── drizzle.config.ts
│   │   └── package.json
│   │
│   └── abis/                      # ABIs y types generados (wagmi generate)
│       ├── src/
│       │   ├── AssetVault.ts
│       │   ├── IdentityRegistry.ts
│       │   ├── RedemptionManager.ts
│       │   └── index.ts
│       ├── wagmi.config.ts
│       └── package.json
│
├── tools/
│   ├── scripts/                   # Scripts operacionales
│   │   ├── deploy-testnet.ts
│   │   ├── deploy-mainnet.ts
│   │   ├── kyc-reconcile.ts       # Reconciliación Sumsub vs IdentityRegistry
│   │   ├── audit-snapshot.ts      # Monthly Arweave snapshots
│   │   └── seed-data.ts           # Seed dev/staging
│   └── docker/
│       └── docker-compose.yml     # Postgres + Redis local
│
├── docs/
│   ├── architecture/              # ADRs (Architecture Decision Records)
│   │   ├── 001-blockchain-network.md
│   │   ├── 002-token-standard.md
│   │   ├── 003-contracts-architecture.md
│   │   ├── 004-oracle-design.md
│   │   ├── 005-no-chainlink.md
│   │   ├── 006-monorepo-structure.md
│   │   └── README.md
│   ├── runbooks/                  # Operational runbooks
│   │   ├── deploy.md
│   │   ├── incident-response.md
│   │   ├── key-rotation.md
│   │   └── safe-recovery.md
│   ├── api/                       # API documentation
│   │   └── openapi.yaml
│   └── ROADMAP.md
│
├── .github/
│   └── workflows/
│       ├── ci.yml                 # CI principal
│       ├── deploy-staging.yml
│       ├── deploy-production.yml
│       └── slither.yml            # Análisis estático automático
│
├── .changeset/                    # Changesets para versionado
├── turbo.json                     # Configuración Turborepo
├── pnpm-workspace.yaml            # pnpm workspaces
├── package.json                   # Root package.json
├── tsconfig.json                  # Root TS config
├── .gitignore
├── .env.example
└── README.md
```

### 19.2 Por qué este layout

- **apps/** contiene aplicaciones desplegables (web + api)
- **packages/** contiene librerías reutilizables (contracts, shared, ui, config, db, abis)
- **tools/** contiene scripts operacionales que no son apps ni librerías
- **docs/** contiene documentación versionada (ADRs, runbooks, API)
- **.github/** contiene CI/CD definitions

### 19.3 Reglas de dependencias entre packages

```
apps/web      → packages/{ui, shared, abis, config}
apps/api      → packages/{db, shared, abis, config}
packages/db   → packages/{shared, config}
packages/ui   → packages/{shared, config}
packages/abis → packages/contracts (codegen)
```

**Regla:** `packages/contracts` (Solidity) es la **fuente de verdad** de los tipos del dominio on-chain. Cualquier cambio en structs/eventos genera (via `wagmi generate`) tipos TypeScript en `packages/abis`, que propagan a apps.

---

## 20. Convenciones de código

### 20.1 Naming

| Elemento | Convención | Ejemplo |
|---|---|---|
| Archivos TS | kebab-case | `purchase-flow.handler.ts` |
| Archivos Solidity | PascalCase | `AssetVault.sol` |
| Variables / funciones JS/TS | camelCase | `getUserById` |
| Componentes React | PascalCase | `BuyTokenDialog` |
| Tipos / Interfaces TS | PascalCase | `PurchaseIntent` |
| Constantes globales | UPPER_SNAKE_CASE | `MAX_TIER_VALUE` |
| Constantes Solidity | UPPER_SNAKE_CASE | `GRAMOS_POR_TOKEN` |
| Funciones Solidity | camelCase | `comprarLote()` |
| Estructuras Solidity | PascalCase | `LoteMiel` |
| Eventos Solidity | PascalCase | `LoteComprado` |

### 20.2 Formatting

- **Prettier** para TypeScript / JavaScript / JSON / Markdown
- **Forge fmt** para Solidity (estándar Foundry)
- **Pre-commit hook** con Husky + lint-staged

### 20.3 Linting

- **ESLint** con presets `@typescript-eslint/recommended` + custom rules
- **Solhint** con preset `solhint:recommended` + custom
- **Tipo de unused vars:** error (no warning)

### 20.4 Imports

- **Imports absolutos** vía TS paths (`@miel/shared`, `@miel/db`)
- **Imports relativos solo dentro del mismo módulo**
- **Orden:** externos → internos abolutos → relativos → estilos

### 20.5 Git conventions

- **Conventional Commits obligatorio:** `feat:`, `fix:`, `chore:`, `docs:`, `refactor:`, `test:`, `ci:`
- **Branches:** `feature/<nombre>`, `fix/<nombre>`, `hotfix/<nombre>`
- **PR title** sigue Conventional Commits
- **PR description** debe incluir: contexto, cambios, cómo probar, riesgos

### 20.6 Code review

- **Mínimo 1 reviewer** para PRs a `develop`
- **Mínimo 2 reviewers** para PRs a `main`
- **Smart contract changes:** revisor obligatorio con experiencia Solidity
- **Squash merge** por defecto (mantiene historia limpia)

---

## 21. Estrategia de testing

### 21.1 Tests de smart contracts

| Tipo | Framework | Coverage objetivo | Cuándo |
|---|---|---|---|
| Unit | Foundry forge test | 100% líneas/branches | Pre-merge |
| Fuzz | Foundry fuzz | ≥10,000 runs por test | Pre-merge |
| Invariant | Foundry invariant | ≥50,000 runs, depth 100 | Pre-merge |
| Integration | Foundry forge test | Casos E2E críticos | Pre-merge |
| Análisis estático | Slither | Cero issues high | CI obligatorio |
| Simbólico | Mythril (opcional) | Casos críticos | Pre-auditoría |

### 21.2 Tests de backend

| Tipo | Framework | Coverage objetivo | Cuándo |
|---|---|---|---|
| Unit | Vitest | ≥80% | Pre-merge |
| Integration | Vitest + Testcontainers | Críticos | Pre-merge |
| E2E API | Vitest + Hono test client | Endpoints críticos | Pre-merge |
| Load testing | k6 (opcional) | Pre-launch | Manual |

### 21.3 Tests de frontend

| Tipo | Framework | Coverage objetivo | Cuándo |
|---|---|---|---|
| Unit | Vitest + Testing Library | ≥70% | Pre-merge |
| Component | Vitest + Storybook | Componentes complejos | Pre-merge |
| E2E | Playwright | Flujos críticos | Pre-merge |
| Accessibility | axe-core + Playwright | WCAG AA | Pre-merge |
| Visual regression | Chromatic o Percy | Componentes críticos | Pre-merge |

### 21.4 Tests E2E críticos

1. Usuario crea cuenta → completa KYC → recibe tier on-chain
2. Usuario compra tokens con MoonPay → recibe tokens en wallet
3. Operador crea lote → admin confirma cosecha con Safe → reserve liberada
4. Usuario inicia redención → exportación confirmada → tokens quemados
5. Address sancionada → bloqueo on-chain → revert en compra
6. Lote fallido → reembolso pro-rata ejecutado correctamente
7. KYC desync detection → reconciliación correcta

---

# PARTE V — ARQUITECTURA MODULAR

## 22. Módulos del sistema

Cada módulo tiene un propósito acotado, una API clara y una documentación propia.

### 22.1 `assets/` (categorías de activos)

**Propósito:** gestionar tipos de activos tokenizables (miel, café, cacao, etc.). Cada `Asset` define las características generales: nombre, granularidad del token, especificaciones de calidad, regulaciones aplicables.

**Endpoints clave:**
- `GET /assets` (público) — listado de assets disponibles
- `POST /admin/assets` — crear nuevo asset
- `PATCH /admin/assets/:id` — actualizar especificaciones

### 22.2 `lots/` (lotes individuales)

**Propósito:** ciclo de vida de cada lote: creación, pre-venta, cosecha, almacenamiento, redención.

**Endpoints clave:**
- `GET /lots` (público) — listado de lotes disponibles para compra
- `GET /lots/:id` (público) — detalle del lote
- `POST /admin/lots` — crear lote
- `PATCH /admin/lots/:id/state` — cambiar estado (preparado para Safe tx)

### 22.3 `identity/` (KYC y verificación)

**Propósito:** integración con Sumsub, sincronización con `IdentityRegistry` on-chain (Plume) y bridge con Plume Arc (KYC nativo de la chain), screening de sancionados.

**Endpoints clave:**
- `POST /identity/kyc-init` — iniciar flujo KYC (devuelve URL Sumsub + creación opcional en Plume Arc)
- `GET /identity/me` — estado del KYC del usuario
- `POST /webhooks/sumsub/individual` — webhook KYC individual
- `POST /webhooks/sumsub/business` — webhook KYC business
- `GET /admin/identity/queue` — cola de revisión manual

### 22.3B `quality/` (oráculo de calidad — FASE 2, ADR-010)

> **Este módulo no se implementa en el MVP.** Requiere `LabRegistry.sol` (FASE 2). Se documenta aquí como referencia de diseño para la activación posterior.

**Propósito (FASE 2):** integración con laboratorios certificados (IBNORCA, Eurofins, Intertek, SGS), construcción y verificación de QualityAttestation, sincronización on-chain con LabRegistry.

**Endpoints clave:**
- `POST /admin/quality/labs` — agregar lab a whitelist (LabRegistry on-chain)
- `PATCH /admin/quality/labs/:id/deactivate` — desactivar lab
- `POST /admin/quality/attestation/build` — construir QualityAttestation a partir de reportes
- `GET /admin/quality/attestation/:lotId` — estado de attestation de un lote
- `POST /webhooks/labs/:labId` — webhook genérico para recepción de reportes firmados
- `GET /quality/lot/:lotId` (público) — datos de calidad verificables del lote (% polen, NMR, etc.)

**Submódulos internos:**
- `lab-integration/` — adaptadores para APIs de cada lab certificado
- `attestation-builder/` — construye QualityAttestation a partir de reportes individuales
- `signature-verifier/` — verifica firmas de labs antes de enviar a oracle
- `lab-onboarding/` — workflow para incorporar nuevo lab al LabRegistry
- `discrepancy-handler/` — manejo de discrepancias entre labs (si reportan resultados muy distintos)

### 22.3C `chainlink/` (Proof of Reserve — NUEVO v2.0)

**Propósito:** integración con Chainlink Proof of Reserve para verificación pública de reservas físicas (kg en almacén). Gestión de la aplicación al BUILD program.

**Endpoints clave:**
- `GET /chainlink/por/:lotId` (público) — último update de PoR para un lote
- `POST /admin/chainlink/por/trigger` — disparar update manual de PoR
- `GET /admin/chainlink/build-program/status` — estado de la aplicación al BUILD program

### 22.3D `crosschain/` (multi-chain — NUEVO v2.0, fase 6+)

**Propósito:** mirror de estado entre Plume y Polygon vía Plume SkyLink o Chainlink CCIP. Reconciliación periódica.

**Endpoints clave:**
- `GET /admin/crosschain/sync/status` — estado de sincronización entre chains
- `POST /admin/crosschain/sync/trigger` — disparar mirror manual
- `GET /admin/crosschain/discrepancies` — alertas de inconsistencia entre chains

### 22.4 `payments/` (pagos fiat y cripto)

**Propósito:** procesar pagos por todos los métodos, confirmar recepción y disparar mint on-chain.

**Endpoints clave:**
- `POST /payments/intent` — crear intención de compra (devuelve método)
- `POST /webhooks/stripe` — confirmación Stripe
- `POST /webhooks/moonpay` — confirmación MoonPay
- `POST /webhooks/ramp` — confirmación Ramp
- `GET /admin/payments/swift/pending` — wires pendientes de reconciliación

### 22.5 `documents/` (Arweave + Cloudflare R2)

**Propósito:** upload de documentos legales con hashing + permanencia.

**Endpoints clave:**
- `POST /admin/documents/upload` (multipart) — subir documento
- `GET /admin/documents/:id` — obtener metadata + URIs
- `GET /admin/documents/orphan` — documentos sin hash on-chain (alerta)

### 22.6 `oracle/` (preparación de transacciones Safe)

**Propósito:** preparar transacciones para el Safe multi-sig (confirmaciones de cosecha, almacenamiento, exportación, fallo).

**Endpoints clave:**
- `POST /admin/oracle/prepare-cosecha` — prepara tx con documentos
- `POST /admin/oracle/prepare-almacenamiento`
- `POST /admin/oracle/prepare-exportacion`
- `POST /admin/oracle/prepare-fallido`
- `POST /webhooks/safe-tx-executed` — callback Safe

### 22.7 `audit/` (audit log)

**Propósito:** mantener registro append-only de toda acción, con hash chain y snapshots mensuales a Arweave.

**Endpoints clave:**
- `GET /admin/audit/recent` — eventos recientes
- `GET /admin/audit/snapshot/:month` — snapshot mensual

### 22.8 `notifications/`

**Propósito:** envío de notificaciones a usuarios (email transaccional) y operadores (Slack).

**Endpoints clave:** (internos, no expone API HTTP)
- `send-email(template, recipient, data)`
- `notify-slack(channel, message)`
- `notify-pagerduty(severity, message)`

---

## 23. Flujos críticos

### 23.1 Flujo: registro y KYC de usuario

```
1. Usuario crea cuenta (Clerk auth)
2. Backend crea row en users con clerk_user_id
3. Usuario visita /onboarding/kyc
4. Backend genera applicantId Sumsub → URL signed
5. Usuario completa KYC en Sumsub
6. Sumsub envía webhook → backend valida firma
7. Backend mapea decisión → tier
8. Backend ejecuta IdentityRegistry.setKYC() (signed tx)
9. Backend espera confirmación → actualiza estado local
10. Usuario ve "KYC aprobado" en su panel
```

### 23.2 Flujo: compra B2C con tarjeta

```
1. Usuario navega a /catalog/:lotId
2. Selecciona cantidad de tokens → /checkout
3. Frontend llama POST /payments/intent { lotId, amount, method: 'moonpay' }
4. Backend valida:
   - KYC tier ≥ 1
   - Lote en PREVENTA
   - Stock disponible
   - No sancionado
5. Backend crea payment_intent en DB con status 'pending'
6. Backend genera URL MoonPay con webhook secret
7. Frontend abre widget MoonPay
8. Usuario completa pago
9. MoonPay envía webhook → backend valida firma
10. Backend marca payment_intent como 'confirmed'
11. [B2C UE] Backend crea withdrawal_hold por 14 días
    [No UE o B2B] Backend ejecuta AssetVault.comprar() inmediatamente
12. Tokens minteados al wallet del usuario
13. Frontend actualiza con TanStack Query / wagmi
```

### 23.3 Flujo: confirmación de cosecha por oráculo

```
1. Operador (panel admin) selecciona lote en estado PREVENTA
2. Sube documentos: certificado SENASAG, análisis lab, acta cosecha, fotos, certificado origen
3. Backend (módulo documents/) calcula hashes SHA-256 locales
4. Backend sube cada documento a Cloudflare R2 (paralelo) y Arweave (paralelo)
5. Backend verifica readback de Arweave (descarga + re-hash + compara)
6. Backend (módulo oracle/) prepara tx:
   - calldata: confirmarCosecha(loteId, kgReal, hashes...)
   - Crea Safe transaction proposal vía Safe SDK
7. Backend notifica a los 3 firmantes (Slack DM + email)
8. Firmante 1 abre Safe Web UI → revisa documentos → conecta Ledger → firma
9. Firmante 2 (lo mismo)
10. Al alcanzar 2 firmas, Safe ejecuta automáticamente la tx on-chain
11. AssetVault.confirmarCosecha() actualiza estado del lote a COSECHADO
12. Goldsky indexa el evento
13. Backend (event listener) detecta CosechaConfirmada → trigger reserve.release-handler
14. Backend prepara tx liberarReservaTecnica() desde wallet TREASURY_SRL_ROLE
15. Tx ejecutada → USDC transferido al productor SRL
```

### 23.4 Flujo: redención y exportación (ADR-017 — 2 fases, Option B)

> **Modelo Option B — lock acumulator:** los tokens permanecen en el wallet del comprador todo el tiempo. El lock es contable (`_tokensLockedFor`). El burn ocurre solo al completar la redención vía `burnForRedemption`.

```
1. Usuario (tier ≥ 2) navega a /account/lots/:lotId
2. Click "Redimir" → completa formulario datos de envío
3. Usuario firma la tx directamente (iniciarRedencion no requiere BACKEND_SIGNER_ROLE)
4. RedemptionManager.iniciarRedencion(loteId, cantidadTokens, datosEnvioHash) ejecutado
   - Lock contable registrado en _tokensLockedFor (tokens siguen en wallet del comprador)
   - Estado: INICIADA
5. Usuario ve "Redención iniciada, esperando confirmación de exportación"
6. Operador SRL recibe notificación → coordina con almacén → tramita DUE en aduana
7. Operador obtiene número DUE
8. Backend prepara tx Safe: confirmarExportacion(redencionId, dueNumero)
9. Safe firma (ORACLE_ROLE) → tx ejecutada
   - Estado: EN_EXPORTACION. Tokens aún en wallet del comprador.
10. Operador contrata courier → recibe BL/AWB
11. Operador sube BL/AWB → backend hashea
12. Backend prepara tx Safe: completarRedencion(redencionId, hashBLAWB)
13. Safe firma → tx ejecutada:
    - Estado: COMPLETADA
    - burnForRedemption() quema tokens del comprador
14. Backend notifica al usuario con tracking del envío
15. Audit log actualizado con tx hashes y URIs Arweave

Cancelación (ADR-015):
- Oracle o Compliance pueden cancelar desde INICIADA o EN_EXPORTACION (reason obligatorio)
- El comprador puede auto-cancelar tras REDENCION_TIMEOUT = 60 días si el Oracle no avanza
```

### 23.5 Flujo: lote fallido y reembolso

```
1. Operador SRL detecta falla (clima, robo, contaminación)
2. Operador documenta motivo + evidencia
3. Sube documentos a document-vault
4. Backend prepara tx marcarFallido(lotId, motivo)
5. Safe multi-sig firma
6. AssetVault.marcarFallido() cambia estado a FALLIDO
7. Backend (event listener) detecta LoteFallido
8. Backend query lista de compradores del lote (desde Goldsky)
9. Backend prepara tx reembolsarLoteFallido(lotId, compradores[])
10. Safe firma
11. AssetVault ejecuta batch:
    - quema tokens de cada comprador
    - transfiere USDC pro-rata a cada wallet
12. Backend notifica a cada comprador del reembolso
13. Audit log actualizado
```

---

# PARTE VI — PLAN DE IMPLEMENTACIÓN

## 24. Roadmap MVP

### 24.1 Fase 0 — Setup y preparación (semana 1-2)

**Outputs:**
- Repo inicializado con estructura monorepo
- CI/CD básico funcionando
- Cuentas creadas: Vercel, Railway, Supabase, Upstash, Sumsub (sandbox), **Plume Testnet faucet**
- Wallets Safe testnet en Plume configuradas con 3 firmantes
- Documentación inicial (README, CONTRIBUTING, ADRs)
- Variables de entorno templated
- **Aplicaciones de grants enviadas: Plume Foundation, Chainlink BUILD program, Stellar Community Fund (paralelo)**

**Tareas técnicas:**
- [ ] Inicializar monorepo Turborepo + pnpm
- [ ] Configurar Foundry en `packages/contracts`
- [ ] Configurar Next.js 15 en `apps/web`
- [ ] Configurar Bun + Hono en `apps/api`
- [ ] Configurar Drizzle en `packages/db`
- [ ] Configurar ESLint + Prettier + Solhint
- [ ] Configurar Husky pre-commit hooks
- [ ] Configurar GitHub Actions CI
- [ ] Setup Vercel deployment preview
- [ ] Setup Railway/Fly.io backend
- [ ] Documentar ADRs base: 001 chain (multi-chain Plume+Polygon), 002 token, 003 contracts (3 MVP + FASE 2 LabRegistry — ADR-010), 004 oracle, 005 Chainlink PoR, 006 oráculo de calidad (FASE 2), 007 grants strategy
- [ ] Aplicar a Plume Foundation Grants
- [ ] Aplicar a Chainlink BUILD program
- [ ] Aplicar a Stellar Community Fund (paralelo, mantiene opcionalidad)
- [ ] Contactar IBNORCA y Eurofins para acuerdos preliminares de testing

### 24.2 Fase 1 — Smart contracts (semana 3-6)

**Outputs:**
- **3 contratos MVP** implementados, tested, deployados en **Plume Testnet**
- ABIs y types generados a `packages/abis`
- Cobertura 100% en líneas y branches
- Análisis estático Slither sin issues high
- Integración inicial con Chainlink PoR feeds (testnet)

**Tareas técnicas:**
- [ ] `ComplianceConstants.sol` + `DocumentHashes.sol`
- [ ] `IdentityRegistry.sol` (AccessControlDefaultAdminRules + Pausable, ADR-012/ADR-016) + bridge con Plume Arc + tests unit
- [ ] `AssetVault.sol` (sin QualityAttestation — FASE 2) + tests unit
- [ ] `RedemptionManager.sol` (Option B lock acumulator, 2-phase ADR-017) + tests unit
- [ ] `ChainlinkPoRAdapter.sol` (integración PoR feeds)
- [ ] Fuzz tests AssetVault + RedemptionManager
- [ ] Invariant tests
- [ ] Integration tests (PurchaseFlow, RedemptionFlow, OracleFlow, ComplianceScenarios)
- [ ] Deploy scripts (`DeployPlume.s.sol`, `ConfigureRoles.s.sol`)
- [ ] Deploy a Plume Testnet
- [ ] Verificación en Plume Explorer testnet
- [ ] Configuración de roles + Safe testnet en Plume

### 24.3 Fase 2 — Backend core (semana 6-8)

**Outputs:**
- Auth funcionando con Clerk
- Schemas DB definidos y migrados
- Módulo identity/ con Sumsub sandbox
- Módulo documents/ con Arweave testnet (devnet)
- Módulo audit/ con hash chain

**Tareas técnicas:**
- [ ] Schemas Drizzle para todas las tablas
- [ ] Migraciones iniciales
- [ ] Setup Clerk + middleware Hono
- [ ] Módulo identity/kyc-sync (webhook + sync on-chain)
- [ ] Módulo identity/screening (job nightly)
- [ ] Módulo documents/ (upload pipeline R2 + Arweave)
- [ ] Módulo audit/ (append-only + hash chain)
- [ ] Logger pino + Sentry integration
- [ ] Tests unit + integration

### 24.4 Fase 3 — Backend operacional (semana 9-11)
<!-- Nota: el módulo quality/ es FASE 2 (ADR-010) y no se implementa en Fase 3 del MVP -->

**Outputs:**
- Flujo de compra completo end-to-end en testnet
- Flujo de redención completo
- Oracle dashboard funcional
- Withdrawal hold MiCA 14d implementado

**Tareas técnicas:**
- [ ] Módulo assets/
- [ ] Módulo lots/ (CRUD + state machine)
- [ ] Módulo payments/ (Stripe + MoonPay + Ramp + SWIFT reconciliation)
- [ ] Módulo oracle/ (Safe SDK integration + prepare tx)
- [ ] Módulo notifications/ (Resend + Slack)
- [ ] Withdrawal hold logic (14 días)
- [ ] Tests integration

### 24.5 Fase 4 — Frontend (semana 12-14)

**Outputs:**
- Catálogo público funcional
- Flujo de compra B2C navegable
- Panel de usuario con tokens y redenciones
- Panel admin con todas las áreas (lots, identity, oracle, audit)

**Tareas técnicas:**
- [ ] Setup Next.js 15 + RainbowKit + wagmi
- [ ] Landing público + catálogo
- [ ] Auth flows (Clerk)
- [ ] KYC onboarding (embed Sumsub)
- [ ] Compra flow B2C
- [ ] Compra flow B2B (con formulario corporativo)
- [ ] Panel usuario (mis lotes, mis redenciones)
- [ ] Panel admin
- [ ] i18n es/en
- [ ] Tests E2E Playwright

### 24.6 Fase 5 — Integración E2E (semana 15-16)

**Outputs:**
- 7 escenarios E2E ejecutados en Amoy
- Bugs identificados y corregidos
- Performance validado (latencia, throughput)
- Documentación de usuario inicial

**Tareas técnicas:**
- [ ] Ejecutar los 7 escenarios E2E críticos
- [ ] Load testing básico (k6)
- [ ] Performance tuning
- [ ] Documentación de usuario
- [ ] Documentación operacional (runbooks)

### 24.7 Fase 6 — Auditoría, hardening y mainnet Plume (semana 17-20)

**Outputs:**
- Reporte de auditoría externa de los 3 contratos MVP
- Findings resueltos
- Penetration testing del backend completado
- Contratos deployados en **Plume Mainnet**
- Bug bounty program publicado

**Tareas técnicas:**
- [ ] Contratar auditor externo con experiencia EVM + RWA (Trail of Bits, Sherlock contest, OpenZeppelin, Quantstamp, Cyfrin) — auditoría de 3 contratos MVP
- [ ] Resolver findings high/medium
- [ ] Penetration testing externo backend/frontend
- [ ] Deploy 3 contratos a Plume Mainnet
- [ ] Verificación en Plume Explorer
- [ ] Configurar Safe Plume mainnet (3 firmantes con hardware wallets Ledger)
- [ ] Configurar Chainlink PoR feeds en mainnet
- [ ] Publicar bug bounty en Immunefi
- [ ] Final review interno

### 24.8 Fase 7 — Soft launch y validación (semana 21-23)

**Outputs:**
- Frontend en producción
- Primer lote piloto creado en Plume mainnet
- 5-10 compradores beta invitados
- Primera redención real ejecutada end-to-end (2 fases: confirmarExportacion → completarRedencion)

**Tareas técnicas:**
- [ ] Deploy frontend a producción Vercel
- [ ] Deploy backend a producción Railway
- [ ] Crear primer lote piloto (50-100 kg, una variedad, monofloral romero o banda)
- [ ] Onboarding de 5-10 compradores beta (mix B2B + B2C)
- [ ] Primera compra real → primera redención real → validación end-to-end
- [ ] Monitoreo intensivo primeras 4 semanas
- [ ] Iteración basada en feedback
- [ ] Coordinar primeros acuerdos con IBNORCA + Eurofins (para activación de LabRegistry en FASE 2)

### 24.9 Fase 8 — Expansión a Polygon (semana 24-27, post soft-launch exitoso)

**Outputs:**
- Contratos deployados también en **Polygon mainnet**
- Mirror de estado vía Plume SkyLink o Chainlink CCIP funcionando
- Frontend soporta wallet en cualquiera de las dos chains
- Compradores pueden elegir chain (Plume o Polygon)

**Tareas técnicas:**
- [ ] Auditoría incremental de cambios para deployment Polygon
- [ ] Deploy contratos a Polygon mainnet
- [ ] Configurar Safe Polygon mainnet (mismos 3 firmantes)
- [ ] Seedear LabRegistry en Polygon (mirror del de Plume)
- [ ] Implementar `crosschain/` module en backend
- [ ] Implementar mirror de estado bidireccional con Plume SkyLink (o Chainlink CCIP)
- [ ] Actualizar frontend para soportar chain switcher en RainbowKit
- [ ] Tests de integridad cross-chain
- [ ] Monitoreo de sincronización entre chains

### 24.10 Resumen de cronograma actualizado (v2.0)

| Fase | Duración | Output principal |
|---|---|---|
| 0. Setup + grants | 2 semanas | Monorepo + CI/CD + aplicaciones grants |
| 1. Contratos (3 MVP) | 4 semanas | 3 contratos + Chainlink PoR + tests 100% |
| 2. Backend core | 3 semanas | KYC + docs + audit + Plume Arc bridge |
| 3. Backend operacional | 3 semanas | Flujos compra + redención (2 fases ADR-017) |
| 4. Frontend | 3 semanas | UX completa con multi-chain ready |
| 5. Integración E2E | 2 semanas | 7+ escenarios validados |
| 6. Auditoría + mainnet Plume | 4 semanas | Findings resueltos, deploy Plume mainnet (3 contratos) |
| 7. Soft launch | 3 semanas | Primer lote + primera redención real end-to-end |
| 8. Expansión Polygon | 4 semanas | Multi-chain operativo |
| *(FASE 2) LabRegistry* | *+3-4 semanas* | *LabRegistry + QualityAttestation + módulo quality/ (ADR-010)* |

**Total fase 1-7 (Plume): 25 semanas (≈ 6 meses)** hasta primer comprador real.
**Total fase 1-8 (multi-chain): 29 semanas (≈ 7 meses)** hasta operación completa Plume + Polygon.

---

## 25. Tecnologías evaluadas y descartadas

Documentación explícita de tecnologías que fueron consideradas pero descartadas, con razón.

**Cambios respecto a v1.0:**
- **Chainlink ya no está descartado completamente.** Proof of Reserve se incorpora desde MVP. Otros productos de Chainlink (Price Feeds, VRF, Automation) siguen descartados.
- **Plume Network reemplaza a Polygon como chain primaria.** Polygon pasa a ser chain secundaria en fase 8.
- **Arbitrum, Algorand, Stellar siguen descartados** para MVP, con razones documentadas en sección 4.2 actualizada.

**Cambios respecto a v2.0 (reconciliación v2.1):**
- **LabRegistry / QualityAttestation: FASE 2 (ADR-010).** El MVP deploya 3 contratos, no 4. EAS sigue descartado; LabRegistry custom es la solución — pero reservada para FASE 2.

| Tecnología | Categoría | Razón de descarte |
|---|---|---|
| Base L2 (Coinbase) | Blockchain | Menor track record en RWA agrícola que Polygon/Plume |
| Arbitrum One | Blockchain | Foco DeFi, menos primitives RWA específicas |
| Algorand | Blockchain | Requiere PyTeal (no-EVM), pool de auditores reducido |
| Stellar | Blockchain | Re-stack completo Rust/Soroban; reservado solo si grants críticos |
| Ethereum Mainnet | Blockchain | Gas prohibitivo para volumen MVP |
| Solana | Blockchain | No-EVM, requiere Rust + Anchor |
| Polygon zkEVM | Blockchain | Más nuevo; Polygon PoS suficiente como chain secundaria |
| ERC-20 por variedad | Token estándar | Proliferación de contratos |
| ERC-3643 (T-REX) | Token estándar | Overkill para solo primario |
| Hardhat | Framework Solidity | Foundry cubre el caso con mejor DX |
| Node.js + Express | Backend | Bun + Hono es más moderno y performante |
| Node.js + Fastify | Backend | Bun + Hono más alineado con TypeScript end-to-end |
| Prisma ORM | ORM | Drizzle ofrece mejor type-safety + control SQL |
| TypeORM | ORM | Más complejo, menos type-safe |
| MongoDB | Database | Sin ACID, no apto para compliance |
| Firestore | Database | Vendor lock-in, sin SQL complejo |
| Chainlink Price Feeds | Oráculo | No requerimos price dinámico (precio prepago fijo) |
| Chainlink VRF | Oráculo | No hay randomness en el caso |
| Chainlink Automation | Oráculo | Backend cron cubre el caso |
| Chainlink Functions | Oráculo | Evaluable fase 2 para APIs de labs |
| Pyth Network | Price oracle | No requerimos price feeds |
| IPFS + Pinata | Storage | Sin garantía de permanencia |
| Filecoin | Storage | Más complejo que Arweave para nuestro caso |
| The Graph (hosted) | Indexer | Goldsky es más rápido y soporta multi-chain |
| Custom indexer | Indexer | Reinventar la rueda, mantenimiento alto |
| Wallets propias custodiales | Wallets | Custodia no-custodial es estándar |
| Metamask Snaps | Wallet | Innecesario para MVP |
| ENS | Naming | Innecesario para MVP |
| Lens Protocol | Social | No aplica al caso |
| Worldcoin / Proof of Personhood | Identity | KYC tradicional + Plume Arc cubre el caso |
| EAS Attestations | Identity | LabRegistry custom es más específico para nuestro caso |
| LayerZero | Cross-chain | Plume SkyLink y Chainlink CCIP cubren cross-chain |
| Wormhole | Cross-chain | Idem |
| Aztec / privacy-focused | Privacy | No requerido (cumplimiento exige transparencia) |

---

## 26. Glosario técnico

**Algorand:** blockchain layer-1 con Pure Proof of Stake, finalidad instantánea y ASA built-in.

**Arweave:** red de almacenamiento descentralizado con pago único para permanencia perpetua.

**ASA:** Algorand Standard Asset, primitiva nativa de Algorand para emitir tokens con compliance built-in.

**Bun:** runtime JavaScript moderno con soporte nativo TypeScript, alternativa a Node.js.

**Chainlink:** red descentralizada de oráculos para conectar blockchains con datos externos.

**Codegen:** generación automática de código (en este proyecto: tipos TypeScript a partir de ABIs Solidity).

**Drizzle:** ORM TypeScript-first con énfasis en type-safety y control SQL.

**EIP-1155 / ERC-1155:** estándar de Ethereum para tokens multi-fungibles (un contrato, múltiples token IDs).

**EIP-3643 / ERC-3643:** estándar de Ethereum para tokenización de activos del mundo real con compliance integrado (T-REX).

**Foundry:** suite de herramientas Solidity (forge, cast, anvil) con énfasis en performance y fuzzing.

**Hono:** framework HTTP edge-first para JavaScript/TypeScript, alternativa a Express.

**HSM:** Hardware Security Module, módulo de seguridad para almacenar claves criptográficas (AWS KMS, GCP KMS).

**Invariant testing:** técnica de testing que verifica propiedades del sistema que deben mantenerse siempre, incluso bajo ejecución aleatoria de funciones.

**Modular monolith:** patrón arquitectónico donde una sola aplicación se organiza en módulos con boundaries claros, sin separación en microservicios.

**OpenZeppelin Contracts:** librería estándar de smart contracts Solidity auditados.

**Polygon AggLayer:** capa de agregación de Polygon que permite interoperabilidad entre chains conectadas (Polygon PoS, zkEVM, etc.).

**Polygon PoS:** sidechain de Ethereum compatible con EVM, con gas predecible y bajo.

**Safe (Gnosis Safe):** wallet multi-firma estándar de industria.

**Smart contract:** programa que se ejecuta en una blockchain con reglas predefinidas, sin posibilidad de manipulación arbitraria post-deploy.

**Soroban:** plataforma de smart contracts de Stellar, basada en Rust.

**Stellar:** blockchain layer-1 diseñada para tokenización de activos y pagos transfronterizos.

**Turborepo:** herramienta de build para monorepos con caching incremental.

**USDC:** stablecoin emitida por Circle, respaldada 1:1 por dólares estadounidenses.

**wagmi:** colección de React hooks para construir aplicaciones Web3 type-safe.

**viem:** cliente Ethereum TypeScript-first, alternativa a ethers.js.

---

## 27. Referencias técnicas

### 27.1 Estándares

- EIP-1155: https://eips.ethereum.org/EIPS/eip-1155
- EIP-3643 (T-REX): https://eips.ethereum.org/EIPS/eip-3643
- EIP-2535 (Diamond): https://eips.ethereum.org/EIPS/eip-2535
- EIP-712 (Typed Data): https://eips.ethereum.org/EIPS/eip-712

### 27.2 Documentación de herramientas

- Polygon Developer Docs: https://docs.polygon.technology/
- Foundry Book: https://book.getfoundry.sh/
- OpenZeppelin Contracts v5: https://docs.openzeppelin.com/contracts/5.x/
- Bun Docs: https://bun.sh/docs
- Hono Docs: https://hono.dev/
- Drizzle ORM Docs: https://orm.drizzle.team/docs/overview
- wagmi v2 Docs: https://wagmi.sh/
- viem Docs: https://viem.sh/
- RainbowKit Docs: https://www.rainbowkit.com/
- Safe Docs: https://docs.safe.global/
- Sumsub API Docs: https://developers.sumsub.com/
- Arweave Docs: https://docs.arweave.org/
- Bundlr Docs: https://docs.bundlr.network/
- Goldsky Docs: https://docs.goldsky.com/
- Turborepo Docs: https://turbo.build/repo/docs

### 27.3 Casos de referencia en RWA agrícola

- AgroToken (Argentina): https://agrotoken.io/
- Mercado Bitcoin Tokens Agrícolas (Brasil): https://www.mercadobitcoin.com.br/
- Centrifuge: https://centrifuge.io/

### 27.4 Herramientas de auditoría y seguridad

- Slither: https://github.com/crytic/slither
- Mythril: https://github.com/Consensys/mythril
- Trail of Bits: https://www.trailofbits.com/
- OpenZeppelin Audits: https://openzeppelin.com/security-audits/
- Sherlock: https://sherlock.xyz/
- Immunefi (bug bounty): https://immunefi.com/

### 27.5 Comunidades técnicas

- Polygon Developer Discord
- OpenZeppelin Community Forum
- Foundry Telegram
- ETH Research

---

**Fin del documento.**

**Versión 2.0 — 19 de mayo de 2026** (multi-chain Plume + Polygon, oráculo de calidad)
**Versión 2.1 — 29 de mayo de 2026** (reconciliación con código real: 3 contratos MVP, ADR-010/012/013/015/016/017)
**Autor: Dany Hidalgo F.**

Este documento es un artefacto técnico de diseño. Está sujeto a actualizaciones según evolucione el estado del arte y las decisiones del equipo. Cualquier desviación significativa respecto a lo aquí descrito debe documentarse como un nuevo ADR (Architecture Decision Record) en `docs/architecture/`.

Para consultas técnicas: contactar al autor o al equipo de arquitectura.
