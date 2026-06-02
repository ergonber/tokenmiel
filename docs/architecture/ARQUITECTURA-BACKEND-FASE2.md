# Arquitectura de Backend — Fase 2

> **Fecha:** 2026-06-01
> **Estado:** derivado de **CIS v1.2** (congelado) + despliegue **Plume testnet 98867**. Documento ejecutable: lo que el equipo va a construir en Fase 2.
> **Principio rector:** el **CIS dicta la FORMA** (qué superficie existe, qué eventos, qué máquinas de estado) — se DERIVA, no se inventa. Los **ADR deciden la IMPLEMENTACIÓN** (stack, custodia, indexer). Nada de este documento vive fuera del CIS o de un ADR. Si algo contradice un documento rector, requiere un ADR nuevo.

---

## §0 — Reconciliación: lo que YA está decidido (no se re-litiga)

Esta tabla existe para cortar la discusión: lo de abajo está cerrado. Cualquier cambio sobre estas filas necesita un ADR nuevo, no una conversación de pasillo.

| Tema | Decisión congelada | Fuente |
|---|---|---|
| Runtime + framework HTTP | **Bun 1.x + Hono 4.x**, TypeScript 5.x. Patrón **Modular Monolith** (NO microservicios para MVP). | ADR-007 + §13.1/§13.2 ARQUITECTURA-TECNICA-MVP |
| ORM + base de datos | **Drizzle ORM** sobre **PostgreSQL 16+ (Supabase)**. ACID indispensable para `audit_log` y compliance. Migraciones con `drizzle-kit`. Schema en `packages/db/src/schema`, migraciones en `packages/db/migrations`. | ADR-007 (tabla stack + notes) |
| Cache + jobs asíncronos | **Redis (Upstash)** para cache; **BullMQ + Redis** para cron/jobs. 6 jobs ya enumerados. | ADR-007 + §13.5 |
| Validación de inputs | **Zod en CADA endpoint** (DTO + Zod). Type-share front/back vía `packages/shared` (Zod schemas), NO tRPC. | ADR-007 + §13.4 + §17.3 |
| Cliente Web3 backend | **viem 2.x** (mismo viem que usa wagmi v2 en el frontend). | ADR-007 + §13.1 |
| Auth admin | **Clerk con 2FA OBLIGATORIO** para todo admin. Se eligió Clerk sobre Supabase Auth por mejor 2FA. | ADR-007 + §17.3 |
| Logging | **pino**. **No PII en logs** (sanear nombre/dirección/doc antes de loggear). | ADR-007 + CLAUDE.md §9 |
| Patrón interno de módulos | **Hexagonal (Ports & Adapters)**: `domain` / `application` / `infrastructure` / `api` por módulo. Repository + Use case + Domain events in-process. Módulos: `assets`, `lots`, `identity`, `payments`, `documents`, `oracle`, `audit`, `notifications`, `shared`. | ADR-007 + §13.3/§13.4 |
| Webhooks de terceros | Patrón obligatorio: (1) **HMAC SHA-256**, (2) **idempotencia**, (3) procesar. Aplica a Sumsub, Stripe, MoonPay, Ramp. | ADR-007 + CLAUDE.md §9 |
| Audit log append-only | Tabla `audit_log` con `REVOKE UPDATE,DELETE`; solo INSERT a `api_user`. **Hash chain**: `prev_hash = sha256(prev_row \|\| current_row)`. | ADR-007 + CLAUDE.md §9 |
| Indexer on-chain | **Goldsky subgraph** (managed) sobre los 3 contratos MVP. GraphQL para backend y frontend. Soporta mirroring a webhooks. The Graph como respaldo. | §15 + §18.1 + ADR-001 |
| Red blockchain primaria | **Plume Network mainnet** primaria (fases 1-7). Polygon PoS secundaria fase 8+ vía **mirror de estado** (NO bridge de tokens), SkyLink primario / CCIP alternativa. USDC nativo por chain. | ADR-001 + §9.1 |
| Oráculo de hitos (humano) | **Safe (Gnosis) 2-de-3** en Plume, 3 cofundadores con hardware wallet. Dashboard admin prepara tx; firma final en Safe Web UI. Módulo `oracle/` (tx-builder, safe-adapter, signers-notifier). | §7.3/§7.4 + §13.3 |
| Oráculo de reservas | **Chainlink Proof of Reserve** (Plume primero, Polygon mirror fase 6+). | §9.1 + ADR-004 |
| Notificaciones | **Resend** (email) + **Slack** alerts. Módulo `notifications/`. | §13.3 |
| Hosting / topología base | Front Next.js en **Vercel**; backend Bun/Hono en **Railway o Fly.io**; Postgres en **Supabase**; Redis en **Upstash**; indexer en **Goldsky cloud**; storage **Arweave + Cloudflare R2**. | §18.1 |
| CI/CD | **GitHub Actions**: en PR build Turborepo + lint + type-check + tests (Vitest, `forge test` + fuzz) + Slither + coverage. En merge a main: preview, E2E Playwright, staging, approval manual, prod. | §18.2 |
| Gestión de llaves | **NO secrets en env de prod**. Backend signer en **AWS KMS o GCP KMS** (referencia KMS, no clave). Treasury SRL + Safe signers en hardware. Backup seeds en escrow notarial. API keys de terceros en secret manager. | §17.2 + CLAUDE.md §9 |
| Hardening backend | Security headers, **rate limiting** (IP + user, Redis-backed), **CORS estricto**, Zod por endpoint, prepared statements (Drizzle), CSP estricto, CSRF SameSite=Strict + double-submit. | §17.3 + CLAUDE.md §9 |

**Contradicciones a evitar (NO hacer):** microservicios; reemplazar Drizzle/Postgres o meter NoSQL; otro ORM/runtime/framework (Prisma, Express, Fastify, tRPC); indexer custom paralelo a Goldsky; secrets/claves en env de prod; que el backend ejecute operaciones críticas on-chain saltándose el Safe 2-de-3; Supabase Auth para admin; asumir Polygon/Alchemy/Infura como RPC primario (la chain primaria es **Plume**); saltarse Zod/HMAC/hash-chain; event bus distribuido (Kafka/SQS) inter-módulos.

---

## §1 — Arquitectura: los 4 layers

El backend de Fase 2 es UN proceso Bun + Hono (modular monolith hexagonal, ADR-007) organizado conceptualmente en cuatro layers que cruzan los módulos existentes. **No son cuatro procesos ni cuatro stacks**: son cuatro responsabilidades que extienden los módulos ya dibujados. La regla de oro: la **cadena es la autoridad** (CIS Matriz source-of-truth, §9); el backend audita, concilia, sincroniza y sirve — nunca decide plata ni estado on-chain por sí mismo.

```
                 ┌──────────────────────────────────────────────────────┐
   Plume          │   Contract interface layer  (packages/abis + chain)  │
  (3 contratos    │   ABIs congelados + addresses + viem clients tipados │
   inmutables)    └───────────────┬─────────────────────┬────────────────┘
        │                         │ reads live           │ writes (HOT/COLD)
        │ logs                    ▼                      ▼
        │            ┌────────────────────┐   ┌──────────────────────────┐
        ▼            │   Read path        │   │   Write path             │
   ┌─────────┐       │  Goldsky → Postgres│   │  Relayer (KMS) + Safe     │
   │ Goldsky │──────▶│  read model        │   │  privileged endpoints     │
   └─────────┘       └──────────┬─────────┘   └─────────────┬────────────┘
                                │                            │
                                ▼                            ▼
                     ┌────────────────────────────────────────────────────┐
                     │  Integration boundary (KYC sync Sumsub→IdentityReg, │
                     │  external deps monitoring, source-of-truth)         │
                     └────────────────────────────────────────────────────┘
```

### §1.1 — Contract interface layer

La **única puerta tipada del backend hacia los 3 contratos del MVP**. NO es un indexer (eso es Goldsky, no se duplica) ni un repo de dominio: es la capa de *adapters de infraestructura* (hexagonal) que (a) carga los ABIs congelados, (b) resuelve `chainId → addresses`, y (c) expone clients viem tipados read/write. Vive como packages compartidos `@tokenization/abis` + `@tokenization/chain`, consumidos por `apps/api/src/modules/*/infrastructure/on-chain/`.

**Componente 1 — ABI registry tipado (`packages/abis`).** El package YA tiene los 3 JSON congelados (`AssetVault.abi.json` 54fn/26ev, `IdentityRegistry.abi.json` 38fn/17ev, `RedemptionManager.abi.json` 36fn/15ev — conteos de CIS §2). Falta el binding TS. Qué se construye:
1. `packages/abis/package.json` (hoy ausente): `name: "@tokenization/abis"`, `type: module`, exports de ABIs + tipos, dependencia `abitype`.
2. `packages/abis/src/index.ts`: importa cada `*.abi.json` y lo re-exporta `as const satisfies Abi` para que viem/abitype infieran tipos estáticos de cada función/evento — autocompletado y type-safety en `readContract`/`writeContract`/`getLogs` SIN escribir tipos a mano.
3. **Regla VERBATIM**: los nombres del binding son los del ABI tal cual (`comprar`, `confirmarCosecha`, `iniciarRedencion`, `LoteComprado`, `TokensRedimidos`, `RedencionIniciada`). No se traducen ni renombran.
4. **Fuente de verdad = ABI, NO la prosa** (GAP-5): el catálogo de eventos/funciones OZ heredados (p.ej. `DefaultAdminDelayChangeCanceled`, `rollbackDefaultAdminDelay`) puede faltar en la prosa del CIS pero SÍ está en el ABI. El binding sale del JSON → cobertura completa.
5. **Pin de integridad (CIS §2)**: `packages/abis/src/integrity.test.ts` verifica que el sha256 del ABI no cambió, y en bootstrap contra red real que el `getBytecode` de cada address matchee el **deployed runtime bytecode sha256** pinneado. Testnet 98867 ya pinneado; mainnet `[PENDIENTE DEPLOY]`.

**Componente 2 — Address registry estático versionado por re-deploy (`packages/chain`).** Como los contratos son **INMUTABLES sin proxy** (CIS §7, ADR-003), el registry es un **mapa estático `chainId → deployment`**. Una address = una versión inmutable de la lógica. `packages/chain/src/deployments.ts` indexa por chainId con `deployVersion` (bump SOLO en re-deploy), `deployedAt`, y por contrato `{ address, runtimeBytecodeSha256, verified }`. Datos reales hardcodeados desde CIS §1/§2:
- `AssetVault`: `0x1E39944BD26485F5946abae706Aa99D729886b47`, sha256 `81743037a5953e315535c524593adcdeb93257749a1d60917dc89ef6c37da6fe`, `verified: false`.
- `IdentityRegistry`: `0x8FBa3ae61B53516a32Ce443E2abb83Edcddfd6Cc`, sha256 `b1cea3c19754a405b453242d8931671423ed12e45b6478e80fc7bd7e3a9dbdf0`, `verified: false`.
- `RedemptionManager`: `0xd6EA5406D7579C1bc5ea935d5ED46675Edf8d062`, sha256 `2eb49f6c939eff643e2ab67b9aa0b5e25a593fb010e4990e02f04414c8fa4d76`, `verified: false`.
- `USDC` (MockUSDC, 6 decimales, SIN mint expuesto): `0xf309e1eB2E3f4Cb169d6C9986A98C3e408C72Fb5`, `kind: 'MockUSDC'`.
- Plume mainnet (98866): addresses y sha256 `[PENDIENTE DEPLOY]` → el backend lo trata como NOT-READY (fail-fast, Componente 5). Anvil local (31337): addresses resueltas en runtime desde el broadcast de `forge script`, no se hardcodean.

`resolveAddress(chainId, contractName, version?)`: función pura que devuelve la address o lanza `UnknownDeployment` / `AddressPending` (custom errors). Es el único camino para obtener una address — **prohibido hardcodear addresses fuera de este package**. Soporta coexistencia `v1`(pausada)+`v2` durante una eventual migración por bug crítico (playbook `pause()`+redeploy, NO proxy). `SUPPORTED_CHAINS` = solo 98867 (testnet) y 98866 (mainnet cuando deploye); Polygon NO entra (fase 8+).

**Componente 3 — viem chain + transport (`packages/chain/src/clients`).** `plumeTestnet` / `plumeMainnet` vía `defineChain` (id, nativeCurrency, rpcUrls inyectados por config/env — ver ADR-RPC abierto). `getPublicClient(chainId)` (read-only, cacheado). `getWalletClient(chainId)`: **NO contiene clave privada** — el signer de `BACKEND_SIGNER_ROLE` es una **referencia KMS** (CIS §6.1/§17.2), construido con un `custom account` de viem cuyo `signTransaction`/`sign` delega a un adapter KMS (AWS/GCP, ADR abierto). Las operaciones críticas de hito NO firman acá: van por `oracle/` al Safe.

**Componente 4 — ContractClients tipados (los 3 wrappers).** Tres clases adapter que combinan ABI (Comp.1) + address (Comp.2) + viem client (Comp.3), exponiendo SOLO la superficie del CIS §3/§4 con tipos derivados del ABI. No agregan lógica de negocio (eso vive en use-cases). Ubicación `apps/api/.../shared/infrastructure/on-chain/`:
- **`AssetVaultClient`** (§3.1/§4.1): reads (`lotes`, `kgDisponibles`, `reservaTecnicaActual`, `totalSupply`, `balanceOf`, `exists`, `paused`, `usdc`, `identityRegistry`, `redemptionManager`, `hasRole`); writes vía KMS gateadas por rol (`comprar` BACKEND_SIGNER — recordando que el backend transfiere USDC ANTES, `comprar` NO hace `transferFrom`); las de ORACLE/TREASURY/admin (`confirmarCosecha`, `liberarReservaTecnica`, `reembolsarLoteFallido`, `setRedemptionManager`, `pause`/`unpause`) se exponen como **builders de calldata** para el Safe; decoders de eventos (`LoteComprado`, `TokensRedimidos`, `ReembolsoEjecutado`, `ReembolsoFinalizado`, `RedemptionManagerSet`, `TransferSingle` con semántica mint `from=0`/burn `to=0`).
- **`IdentityRegistryClient`** (§3.2/§4.2): reads (`getTier`, `isSanctioned`, `isFrozen`, `isExpired`, `canMint`, `canRedeem`, `getJurisdiction`, `getKYCData`, `paused`); writes BACKEND_SIGNER (`setKYC`, `revokeKYC`); las de COMPLIANCE (`markSanctioned`, `freezeAddress`, etc.) van por hardware como calldata builders. El wrapper documenta que `getTier` NO descuenta expiry → para gating se usa `canMint`/`canRedeem`, nunca `getTier` crudo.
- **`RedemptionManagerClient`** (§3.3/§4.3): reads (`getRedencion`, `getNextRedencionId` → el backend itera `[1, getNextRedencionId())`, `availableBalance`, `tokensLockedFor` — el wrapper documenta el gotcha de orden de args: recibe `(buyer, loteId)` pero indexa `[loteId][buyer]`; constantes `REDENCION_TIMEOUT`=60d, `MAX_DUE_NUMERO_LENGTH`=64); writes ORACLE (`confirmarExportacion`, `completarRedencion`, `cancelarRedencion`) como calldata builders; `iniciarRedencion` es del comprador (sin rol) → el wrapper la expone solo para simulación/preview y para el frontend vía `packages/shared`, el backend NO la firma.

**Componente 5 — Bootstrap / health-check de integridad (`shared/`).** Al arrancar, un `ChainBootstrap` por cada contrato del chainId activo: (1) `resolveAddress` → si `[PENDIENTE DEPLOY]` lanza `AddressPending` y **aborta el arranque** (fail-fast); (2) `getBytecode` → sha256 → compara contra `runtimeBytecodeSha256` del registry → mismatch = `BytecodeMismatch` → abort (detecta apuntar a código no auditado, CIS §2); (3) cachea los `ContractClients` y loguea (pino, sin PII) `{chainId, deployVersion, addresses, verified}`.

**Resolución red→addresses y versionado de ABIs:** `CHAIN_ID` (env) → `DEPLOYMENTS[chainId]` → `resolveAddress(name)`. Estático, puro, testeable. El ABI es idéntico entre redes, versionado por hash del JSON + pin de runtime bytecode por address. `deployVersion` bumpea SOLO con re-deploy (bug crítico + ADR). Cuando se verifique en explorer (hoy los 3 `verified:false`) se flipa el flag, sin cambiar address ni bytecode.

**Lo que este layer NO hace:** no indexa históricos (eso es Goldsky); no firma hitos críticos (van al Safe); no guarda clave privada; no valida jurisdicción (off-chain, ADR-011) ni re-implementa el gate KYC (on-chain).

### §1.2 — Read path (indexer + read model)

Convierte el **log on-chain** (autoritativo, §9 + Matriz s-o-t) en **proyecciones consultables** que sirven con baja latencia. No inventa estado: TODO se deriva del catálogo de eventos CIS §5 o se lee live de la read surface §4. **Ante divergencia cache vs cadena, gana la cadena.**

Dos decisiones reconciliadas que NO se re-deciden: indexación = **Goldsky subgraph** (no hay indexer custom paralelo; necesidades nuevas = agregar entity/handler al subgraph existente); read model en **Drizzle + Postgres** (`packages/db/src/schema`, `drizzle-kit`).

Topología: **Goldsky (GraphQL + push-webhook) → submódulo de ingestión `indexing/` en el monolito → Postgres read model (Drizzle)**. El subgraph decodifica logs y maneja finalidad; el read model Postgres es la proyección servible que une on-chain con datos off-chain (Sumsub applicant, shipping, payment refs) que el subgraph NO tiene.

> **DESTACADO transversal:** la proyección completa del ciclo de redención **`ALMACENADO → REDENCION_PARCIAL → AGOTADO` es posible SOLO porque Fase 1 agregó `TokensRedimidos`** (ADR-019, GAP-2). Sin ese evento de dominio, el burn vía `burnForRedemption` solo emitiría `TransferSingle(to=0)` — indistinguible del burn de reembolso `reembolsarLoteFallido` — y habría que correlacionar por tx-hash. Con `TokensRedimidos` (`loteId`, `from`, `cantidad`, `kgRedimidosTotal`, `nuevoEstado`) la transición de estado del lote y el `kgRedimidos` acumulado se proyectan directo del log, sin punto ciego. Lo mismo aplica a `RedemptionManagerSet` (GAP-1) y `ReembolsoFinalizado` (GAP-3/4).

**Qué eventos suscribir (TODO el catálogo §5).** El subgraph define un `dataSource` por contrato (3 addresses §1, chainId 98867) con `startBlock` = bloque de deploy (2026-06-01).
- **AssetVault — 26 eventos (§5.1):** dominio → `LoteCreado` (crea `lote_proyeccion` PREVENTA), `LoteComprado` (upsert holding + escrow espejo; el param se llama `montoUSDC`), `CosechaConfirmada` (PREVENTA→COSECHADO; **asimetría: NO trae `hashFotosApiario` ni `tipoCertificadoOrigen` → hidratar live de `lotes()`**), `MontoNetoLiberado`, `AlmacenamientoConfirmado` (COSECHADO→ALMACENADO; `almacenAutorizado` solo vive en el evento), `LoteFallido` (→FALLIDO), `ReservaTecnicaLiberada`, `ReembolsoEjecutado` (uno por comprador por batch), `RedemptionManagerSet` (GAP-1, wiring one-time), `TokensRedimidos` (**GAP-2, PIEZA CLAVE** → baja holding, setea `kgRedimidos`, aplica `nuevoEstado`), `ReembolsoFinalizado` (GAP-3/4, cierra paginación), `TransferSingle` (**fuente autoritativa de balances**). Gobernanza/operación → `EmergencyPaused`/`EmergencyUnpaused` (mirror + alerta Slack; el `paused` real se sirve LIVE), `Paused`/`Unpaused` OZ (auditoría), `RoleGranted`/`RoleRevoked` (role map), 4× `DefaultAdmin*` (delay 3 días, alerta `pendingDefaultAdmin`).
- **IdentityRegistry — 17 eventos (§5.2):** verdict CIS **CONFIRMED, cero huecos** (toda mutación emite evento → mirror reconstruible 100%). `KYCUpdated` (**alto volumen; rate >100/h dispara runbook ADR-013**), `KYCRevoked`, `Sanctioned`/`Unsanctioned`, `Frozen`/`Unfrozen`, + gobernanza/pausa igual que AssetVault. El `actor` en todos los mutators = `msg.sender` (FIX M-03, forensics) → se persiste.
- **RedemptionManager — 15 eventos (§5.3):** verdict **CONFIRMED, cero huecos materiales**. `RedencionIniciada` (crea `redencion_proyeccion` INICIADA + `tokensLocked`+), `RedencionEnExportacion` (INICIADA→EN_EXPORTACION, guarda `dueNumero`), `RedencionCompletada` (→COMPLETADA terminal; correlaciona con `TokensRedimidos` del mismo tx para enlazar redención↔lote↔kg), `RedencionCancelada` (→CANCELADA terminal, libera lock) + gobernanza. **GAP-5 (LOW):** el catálogo omite `DefaultAdminDelayChangeCanceled` → el handler toma el set del **ABI**, no de la prosa.

**Tablas de proyección (Drizzle/Postgres).** Todas con procedencia (`chainId`, `blockNumber`, `logIndex`, `txHash`, `updatedAtBlock`) e idempotencia por `(chainId, txHash, logIndex)`:
- `holding` — balances ERC-1155 por `(chainId, contractAddr, wallet, loteId)`: `balance` (de la secuencia de `TransferSingle`), `tokensLocked` (movido por `RedencionIniciada`±), `availableBalance` (= `balance - tokensLocked`, 0 si negativo). Para holdings de dashboard se sirve esta tabla; para **balance exacto pre-tx** se lee LIVE.
- `lote_proyeccion` — `(chainId, contractAddr, loteId)`: `estado` (`LoteEstado` PREVENTA=0…FALLIDO=5), `kgEsperados`, `precioPorTokenUSDC`, `productorSRL`, `hashFSA`, `reservaBps`, `kgRealCosechado`, `kgRedimidos`, `motivoFallo`, `reembolsoFinalizado`; hashes de hitos; campos **NO indexables por log** hidratados live de `lotes()` (`hashFotosApiario`, `tipoCertificadoOrigen`); escrow espejo (`reservaTecnicaUSDC`, `montoNetoPendiente`, `reservaTecnicaLiberada`). El handler aplica la **máquina de estados §8.1** y VALIDA cada transición (defensa ante reorg mal aplicado).
- `redencion_proyeccion` — `(chainId, contractAddr, redencionId)`: `comprador`, `loteId`, `cantidadTokens`, `datosEnvioHash`, `estado` (`EstadoRedencion` INICIADA=0…CANCELADA=3), `dueNumero`, `hashBLAWB`, `createdAt`, `completedAt`, `cancelReason`. Reconstruida 100% de los 4 eventos de dominio. Off-chain join: shipping real vive en `documents/` (Arweave); la proyección guarda el puntero, no el contenido.
- `kyc_mirror` — `(chainId, contractAddr, user)`: `tier`, `sanctioned`, `frozen`, `jurisdiction`, `expiresAt`, `updatedAt`, `sumsubApplicantHash`, `lastActor`. **Expiry es derivado** (§8.2: transición implícita sin evento) → se calcula al consultar (`expiresAt <= now`), no se materializa flag. **CRÍTICO:** este mirror es para dashboards/compliance; la PUERTA `canMint`/`canRedeem` se enforcea ON-CHAIN, el backend NUNCA decide minteo/redención leyendo el mirror.
- `transfer_log` — append-only de cada `TransferSingle` (fuente cruda de holdings + detección de la invariante "NUNCA `from!=0 && to!=0`" — P2P bloqueado).
- `config_onchain` (redemptionManagerAddr de `RedemptionManagerSet` + addresses inmutables + pin bytecode/ABI) y `admin_mirror` (role map, `pendingDefaultAdmin`, delays, pausa espejo).

**Read-vs-live (§4).** Regla derivada de §9 + Matriz s-o-t: lo que es **gate/decisión crítica o debe ser exacto a la tx se lee LIVE**; lo histórico/listado/dashboard se sirve del read model.
- *Siempre LIVE:* `paused()` de los 3 contratos (chequeo antes de `comprar`/`iniciarRedencion`; views no se bloquean por pause, ADR-013), `canMint`/`canRedeem` (gate KYC, enforcement on-chain), `balanceOf`/`availableBalance`/`tokensLockedFor` (balance pre-tx), `kgDisponibles(loteId)` (capacidad en gramos, FIX H-02), `lotes(loteId)` (para `hashFotosApiario`/`tipoCertificadoOrigen` y escrow exacto).
- *Siempre read model:* listados de lotes, portfolio histórico, histórico de redenciones/transfers/escrow, mirror KYC para panel compliance (vista, no gate), timeline de auditoría.
- *Híbrido:* detalle de lote (proyección + hidratación live de los campos sin evento); conciliación de escrow (job `payment reconciliation` compara espejo vs `reservaTecnicaActual` live + saldo USDC del contrato).

**Reorgs / finalidad.** El read path NUNCA proyecta en head. Goldsky maneja reorgs nativamente (rollback de entities); el read model Postgres añade una **segunda barrera**: solo materializa a las tablas servibles eventos con `N` confirmaciones (`headBlock - eventBlock >= CONFIRMACIONES_FINALIDAD`, `N` por config — ADR abierto). Dos zonas: **confirmada** (servible) y **pendiente/optimista** (UIs que toleran "pendiente"); lo crítico nunca usa la zona pendiente (usa live). Ante reorg: identificar bloque de bifurcación, recomputar `holding`/escrow desde `transfer_log`, re-aplicar máquinas de estado desde el fork-point validando §8. Idempotencia por `(chainId, txHash, logIndex)`. **Backfill** desde `startBlock` reconstruye TODO (único no-reconstruible-por-log: `hashFotosApiario`/`tipoCertificadoOrigen` → resync con `lotes()`). Job BullMQ de conciliación: `suma de holdings == totalSupply(loteId)`, escrow espejo == on-chain, alerta divergencias.

**Encaje:** submódulo `indexing/` (`domain` con invariantes de transición §8, `application` con `proyectarEvento`/`reconstruirReadModel`/`conciliarConCadena`, `infrastructure` con cliente GraphQL Goldsky + webhook handler + repos Drizzle + viem para reads live, `api` con endpoints Zod). Reusa `viem`, `audit/` (hash chain para eventos sensibles), `notifications/` (alertas).

### §1.3 — Write path (relayer + privileged endpoints)

El **ÚNICO punto del backend que ARMA, FIRMA y EMITE transacciones on-chain** (o prepara calldata para el Safe). Todo lo demás es solo lectura. **Principio:** tener `BACKEND_SIGNER_ROLE` NO significa poder mintear a cualquiera — si el destinatario no pasa `canMint`, `comprar` revierte `NotKYCVerified` en `AssetVault._update`. El layer hace **pre-flight reads** (optimización de gas/nonce) pero NUNCA asume que su pre-check reemplaza el gate on-chain.

**Dos sub-vías por custodia (heredadas del CIS §6.1, mutuamente excluyentes):**
- **Vía A — HOT relayer (firma autónoma, KMS):** único rol que el backend firma por sí mismo = **`BACKEND_SIGNER_ROLE`** (custodia KMS, NO clave en env). Funciones: `AssetVault.comprar(loteId, cantidadTokens, comprador, montoUSDCPagado, paymentRefHash)`, `IdentityRegistry.setKYC(...)`, `IdentityRegistry.revokeKYC(...)`.
- **Vía B — COLD / Safe (el backend SOLO prepara calldata, NO firma):** reusa el patrón existente `oracle/` (tx-builder → safe-adapter → Safe Transaction Service → signers-notifier). Mapeo rol→funciones: **`ORACLE_ROLE`** (Safe 2-de-3) `confirmarCosecha`/`confirmarAlmacenamiento`/`marcarFallido`/`reembolsarLoteFallido`/`finalizarReembolso` + `confirmarExportacion`/`completarRedencion`/`cancelarRedencion`; **`ADMIN_ROLE`** (HW/Safe) `crearLote`; **`TREASURY_SRL_ROLE`** (HW tesorero) `liberarReservaTecnica`; **`COMPLIANCE_OFFICER_ROLE`** (HW titular+suplente) `markSanctioned`/`unmarkSanctioned`/`freezeAddress`/`unfreezeAddress` + `pause` + `cancelarRedencion`; **`DEFAULT_ADMIN_ROLE`** (Safe 2-de-3) `unpause` (exclusivo, asimetría ADR-016), `setRedemptionManager` (one-time), gestión de roles con delay 3 días.
- **Caso especial SIN rol:** `RedemptionManager.iniciarRedencion(...)` la llama el **comprador con su propio wallet** (self-custody RainbowKit). El backend NO la relaya; solo provee un endpoint de PRE-VALIDACIÓN (`canRedeem`, balance, `availableBalance` vs lock). Mismo patrón para `cancelarRedencion` path buyer-post-timeout (ADR-015). Esto destapa el OPEN TOPIC de gas/relayer B2C.

**`RelayerService` (Vía A happy path):** (1) resuelve `walletClient` con `KmsAccount` custom (firma remota vía `BACKEND_SIGNER_KMS_KEY_ID`, nunca materializa la clave); (2) **pre-flight reads** (para `comprar`: `lotes(loteId).estado==PREVENTA`, `kgDisponibles` en gramos cubre, `canMint(comprador)`, `paused()==false`, USDC ya transferido al contrato; para `setKYC`: `tier in 1..3`, `expiresAt>now`, jurisdicción ISO off-chain ADR-011) → falla = 4xx ANTES de tocar nonce/gas; (3) `simulateContract` para capturar el custom error (`NotKYCVerified`, `LoteNotInPreventa`, `MontoUSDCInsuficiente`, etc.) y mapearlo a HTTP; (4) nonce + idempotencia; (5) firma + envío; (6) tracking de `tx_hash` + `waitForTransactionReceipt` — **el estado de dominio lo confirma el evento indexado por Goldsky, no el receipt**. Vía B: pasos 1-3 igual, paso 5 NO firma → arma `SafeTransactionData` (`encodeFunctionData`), lo manda al Safe Transaction Service, dispara `signers-notifier`; estado `PENDING_SAFE` hasta ver el evento del hito.

**`PrivilegedEndpointRegistry`** — tabla declarativa endpoint↔rol↔función↔vía↔Zod. Doble gate independiente: **Clerk + 2FA** (RBAC de aplicación) Y rol on-chain; ambos deben pasar. En Vía B la key on-chain está en hardware ajeno al backend, así que el RBAC de Clerk nunca habilita la firma. Endpoints clave: `POST /purchases/:loteId/mint` (HOT, comprar), `/identity/kyc` y `/identity/kyc/revoke` (HOT), `/admin/lotes` (COLD, crearLote), `/admin/lotes/:id/{cosecha,almacenamiento,fallido,reembolso,reembolso/finalizar,reserva/liberar}` (COLD), `/admin/redenciones/:id/{exportacion,completar,cancelar}` (COLD), `/admin/identity/:user/{sanction,unsanction,freeze,unfreeze}` (COLD), `/admin/contracts/:name/{pause,unpause}` (COLD), `/admin/wiring/redemption-manager` (COLD).

**Idempotencia + nonce (corazón de seguridad, NO doble-mint):**
- *HTTP:* header `Idempotency-Key` (para `comprar` la clave natural es `paymentRefHash`). Tabla `relayer_idempotency(idempotency_key PK, endpoint, request_hash, status, tx_hash, result, created_at)`. `INSERT ... ON CONFLICT DO NOTHING`; si existía → devolver resultado previo, NUNCA re-emitir; misma key con payload distinto → 409.
- *Cadena (defensa en profundidad):* antes de emitir `comprar`, consultar Goldsky si ya hay un `LoteComprado` con ese `paymentRefHash`. Cubre el caso de fila de idempotencia perdida pero tx sí entrada. `setKYC`/`confirmar*` son idempotentes a nivel semántico (el gate de estado §8.1/§8.3 revierte el segundo intento).
- *Nonce:* el `BACKEND_SIGNER_ROLE` es UN address con UN stream → **cola BullMQ `relayer-hot` concurrency=1** (serializa, retry/backoff nativo, encaja con el stack), `next_nonce` en tabla `relayer_nonce` reconciliado contra `getTransactionCount(signer, 'pending')`. Stuck tx → re-broadcast mismo nonce + gas bump (EIP-1559 ×1.25), NUNCA reusar nonce con otro payload. Gap recovery vía el job de reconciliación.

**Ledger + auditoría:** tabla `relayer_tx(id, idempotency_key, endpoint, contract_name, function_name, via [HOT|COLD], signer_or_safe, calldata, nonce, tx_hash, safe_tx_hash, status [QUEUED|SIMULATED|SENT|MINED|FAILED|PENDING_SAFE|EXECUTED_SAFE], revert_error, created_by_admin, created_at, mined_at)` + `audit_log` append-only (hash chain, sin PII, complementa los `actor`-indexed de los eventos). **Error mapping:** `selector (4 bytes) → error de dominio HTTP`, generado desde `packages/abis` (no de la prosa); `EnforcedPause` → 503.

**Lo que este layer NO hace:** no mueve USDC (lo hace payments/escrow; este layer solo verifica saldo en pre-flight); no firma roles COLD; no reemplaza el gate KYC con su pre-check; no usa event bus ni indexer paralelo; no relaya `iniciarRedencion` ni el cancelar buyer-timeout.

### §1.4 — Integration boundary (KYC sync + external deps + source-of-truth)

**Decisión load-bearing (se respeta, no se re-decide):** el sistema tiene UNA puerta de compliance y está **ON-CHAIN** (CIS §9). El backend es **únicamente la fuente del DATO KYC** (evidencia Sumsub) y un **empujador de estado** hacia `IdentityRegistry`. No es autoritativo de plata, balances ni estado de lotes/redenciones. Por eso el boundary es un **pipeline unidireccional con dos flujos separados**: inbound de evidencia (Sumsub → backend → DECISIÓN) y outbound de estado (backend → `setKYC` → CONFIRMA leyendo `KYCUpdated`). Extiende el módulo `identity/` (`kyc-sync`/`screening`/`on-chain-sync`), no crea stack paralelo.

**Pipeline KYC (Sumsub → IdentityRegistry):**
1. **Webhook (`identity/api` `POST /webhooks/sumsub`):** orden NO negociable — (a) HMAC SHA-256 sobre raw body ANTES de parsear (falla → 401, no procesa); (b) idempotencia por `(provider, external_event_id)` UNIQUE en `webhook_events`; (c) Zod del payload Sumsub, persiste crudo, **encola** job BullMQ `kyc-sync`, responde 200 rápido. NUNCA se firma una tx dentro del handler HTTP.
2. **`ResolveKYCDecision` (`application`):** mapea `reviewResult.reviewAnswer` → tier 0/1/2/3 (GREEN básico → tier 1 = `canMint`; GREEN reforzado → tier 2/3 = `canRedeem`; rechazo → no escribe o `revokeKYC` si ya estaba aprobado). **Valida jurisdicción OFF-CHAIN** contra lista ISO 3166-1 alpha-2 (ADR-011; el `jurisdiction: bytes2` on-chain es metadata, no se valida on-chain). Calcula `expiresAt` (política backend, ej. 365d; el contrato solo exige futuro) y `sumsubApplicantHash: bytes32` (hash determinístico, NO el id en claro — no PII on-chain).
3. **`IdentityRegistryWriter` (`infrastructure`, viem):** firma con `BACKEND_SIGNER_ROLE` (KMS). `setKYC(user, tier, expiresAt, jurisdiction, sumsubApplicantHash)` (preconditions: `user!=0`, `tier!=0` — tier 0 va por `revokeKYC` FIX M-04, `tier<=3`, `expiresAt>now`, `whenNotPaused`) o `revokeKYC(user, reason)`. **`setKYC`/`revokeKYC` (+`comprar`) son lo ÚNICO que el backend ejecuta autónomamente.** `markSanctioned`/`freezeAddress` NO los hace el backend — son `COMPLIANCE_OFFICER_ROLE` (hardware); el backend solo PREPARA/ALERTA.
4. **Confirmación = ver el evento, NO la tx minada:** Goldsky capta `KYCUpdated`/`KYCRevoked` y reconcilia el outbox (`onchain_tx`); el KYC se marca efectivo SOLO cuando el evento aparece.
5. **Auditoría:** cada decisión (input Sumsub → tier → tx → evento) al `audit_log` append-only, referenciando `txHash` + `sumsubApplicantHash`, sin PII.

**Screening continuo (`identity/screening`):** job BullMQ **nightly 02:00 UTC** (OFAC SDN). Un match NO sanciona on-chain: genera **propuesta de sanción** → `COMPLIANCE_OFFICER_ROLE` (Resend + Slack). Compliance firma `markSanctioned(user, reason, evidenceHash)` desde hardware (`evidenceHash!=0` mandatorio, FIX M-01); el backend solo aporta el `evidenceHash` (hash de evidencia en Arweave/R2). Job **identity expiry diario:** detecta `expiresAt` por vencer → dispara re-onboarding e invalida cache; la transición a Expirada es **implícita on-chain** (§8.2), NO escribe.

**Monitoreo de external deps (CIS §10) — extiende Goldsky + jobs, NO indexer paralelo:**
- *USDC* (IERC20, 6 decimales, immutable): el backend lee `AssetVault.usdc()` para saber a qué token transferir ANTES de `comprar` (`comprar` NO hace `transferFrom`; RM NO toca USDC). Job **payment reconciliation cada 15 min** concilia saldo USDC on-chain vs contabilidad espejo y alerta liquidez baja (CONFLICT-4).
- *IdentityRegistry:* indexa los 6 mutators; monitorea `paused()` — si está pausado, `setKYC` revierte `EnforcedPause` → **el backend DETIENE la cola `kyc-sync` y alerta**, no martilla la cadena. Vigila `KYCUpdated` rate >100/h (compromiso de signer, runbook ADR-013).
- *RedemptionManager:* indexa `RedemptionManagerSet` (GAP-1) para confirmar el cableado one-time.
- *Plume Arc:* **NO implementado** en el MVP. Se deja un puerto vacío `KycBridgePort` (extensión futura), SIN implementación.
- *LabRegistry / QualityAttestation:* **DEFERIDOS (ADR-010)**, no hay paso `QUALITY_ATTESTED`. Puerto `QualityAttestationPort` vacío, SIN integrar contratos inexistentes.
- *Chainlink PoR:* fase futura, fuera de los 3 contratos MVP — solo se nombra como dep a monitorear.

**Address registry del backend (§7 + §1):** `{chainId → {contractName → address}}`, cada deploy = versión inmutable; addresses testnet ya conocidas, mainnet `[PENDIENTE DEPLOY]`. Pin de runtime bytecode sha256 + ABI por address (`packages/abis`, gana el ABI). No puede generar bindings mainnet finales hasta el deploy real.

---

## §2 — API contract (punto de convergencia)

El API es donde write surface (§3 CIS) y view surface (§4 CIS) convergen en endpoints Hono. Todos: Zod en el DTO, type-share vía `packages/shared`, rate limiting, CORS estricto. Los privilegiados además: Clerk + 2FA + RBAC mapeado a rol on-chain.

### §2.1 — Endpoints de lectura (públicos / autenticados read)

| Endpoint | Fuente | Notas |
|---|---|---|
| `GET /lotes` | read model (`lote_proyeccion`) | catálogo de preventa + estado |
| `GET /lotes/:id` | read model + hidratación **live** `lotes()` | `hashFotosApiario`/`tipoCertificadoOrigen` no tienen evento |
| `GET /lotes/:id/capacidad` | **LIVE** `kgDisponibles(loteId)` | capacidad vendible exacta pre-`comprar` (gramos, FIX H-02) |
| `GET /wallets/:addr/holdings` | read model (`holding`) | portfolio histórico |
| `GET /wallets/:addr/balance/:loteId` | **LIVE** `balanceOf` / `availableBalance` | balance exacto pre-tx |
| `GET /redenciones/:id` | read model (`redencion_proyeccion`) | ciclo INICIADA→…→COMPLETADA/CANCELADA |
| `GET /identity/:addr/status` | read model (`kyc_mirror`) **+ LIVE** `canMint`/`canRedeem` para gate | mirror para UI; gate siempre live |
| `GET /redenciones/preview` | **LIVE** `canRedeem` + balance + lock | pre-validación antes de que el usuario firme `iniciarRedencion` |
| `GET /contracts/:name/status` | **LIVE** `paused()` | nunca del read model |
| `GET /admin/audit/timeline` | read model (eventos + `actor`) | Clerk; auditoría |

### §2.2 — Endpoints privilegiados de escritura (rol + vía)

| Endpoint (Hono) | Rol on-chain | Función | Vía | Dispara |
|---|---|---|---|---|
| `POST /admin/lotes` | ADMIN_ROLE | `crearLote` | COLD (Safe/HW) | operador |
| `POST /purchases/:loteId/mint` | BACKEND_SIGNER_ROLE | `comprar` | HOT (KMS) | backend post-pago |
| `POST /identity/kyc` | BACKEND_SIGNER_ROLE | `setKYC` | HOT (KMS) | backend sync Sumsub |
| `POST /identity/kyc/revoke` | BACKEND_SIGNER_ROLE | `revokeKYC` | HOT (KMS) | backend/compliance |
| `POST /admin/lotes/:id/cosecha` | ORACLE_ROLE | `confirmarCosecha` | COLD (Safe 2/3) | oracle |
| `POST /admin/lotes/:id/almacenamiento` | ORACLE_ROLE | `confirmarAlmacenamiento` | COLD (Safe 2/3) | oracle |
| `POST /admin/lotes/:id/fallido` | ORACLE_ROLE | `marcarFallido` | COLD (Safe 2/3) | oracle |
| `POST /admin/lotes/:id/reembolso` | ORACLE_ROLE | `reembolsarLoteFallido` (batch≤100) | COLD (Safe 2/3) | oracle |
| `POST /admin/lotes/:id/reembolso/finalizar` | ORACLE_ROLE | `finalizarReembolso` | COLD (Safe 2/3) | oracle |
| `POST /admin/lotes/:id/reserva/liberar` | TREASURY_SRL_ROLE | `liberarReservaTecnica` | COLD (HW tesorero) | tesorero |
| `POST /admin/redenciones/:id/exportacion` | ORACLE_ROLE | `confirmarExportacion` | COLD (Safe 2/3) | oracle |
| `POST /admin/redenciones/:id/completar` | ORACLE_ROLE | `completarRedencion` | COLD (Safe 2/3) | oracle |
| `POST /admin/redenciones/:id/cancelar` | ORACLE_ROLE \| COMPLIANCE_OFFICER_ROLE | `cancelarRedencion` (path admin) | COLD | oracle/compliance |
| `POST /admin/identity/:user/{sanction,unsanction,freeze,unfreeze}` | COMPLIANCE_OFFICER_ROLE | `markSanctioned`/… | COLD (HW) | compliance |
| `POST /admin/contracts/:name/pause` | COMPLIANCE_OFFICER_ROLE \| DEFAULT_ADMIN_ROLE | `pause` | COLD | compliance/admin |
| `POST /admin/contracts/:name/unpause` | DEFAULT_ADMIN_ROLE (exclusivo) | `unpause` | COLD (Safe 2/3) | admin |
| `POST /admin/wiring/redemption-manager` | DEFAULT_ADMIN_ROLE | `setRedemptionManager` (one-time) | COLD (Safe 2/3) | admin |

> `iniciarRedencion` y el `cancelarRedencion` buyer-timeout NO tienen endpoint de escritura: los firma el usuario (self-custody). El backend solo expone su preview de lectura.

---

## §3 — Matriz source-of-truth (final)

Regla rectora invariante: **ante divergencia, gana la cadena.** El backend mantiene cache/índice reconstruible y SOLO es origen de UN dato: la evidencia KYC.

| Dato | Autoritativo (on-chain) | Rol del backend | ¿Backend es fuente? |
|---|---|---|---|
| Balances / holdings | AssetVault ERC-1155 (`balanceOf`, `totalSupply`) | Cache reconstruido de `TransferSingle` (mint `from=0`, burn `to=0`) | **NO** — solo índice |
| Allowlist + KYC (enforcement) | IdentityRegistry (`canMint`/`canRedeem`/`getTier`/flags) | Cache + **ORIGEN del dato** (`setKYC`); valida jurisdicción off-chain (ADR-011) | **Origen del DATO, NO del enforcement** |
| Evidencia KYC (Sumsub applicant) | — (on-chain solo `sumsubApplicantHash`) | **FUENTE DE VERDAD ÚNICA.** PII cifrada en DB, hash en cadena | **SÍ — único caso** |
| Registro de lotes / asset | AssetVault (`lotes(loteId)`, `LoteEstado`) | Índice de eventos + lecturas `lotes()` (`hashFotosApiario`/`tipoCertificadoOrigen` no están en eventos) | **NO** |
| Estado de redención | RedemptionManager (`getRedencion`, `tokensLockedFor`) | Índice de los 4 eventos de dominio; shipping/DUE/BL-AWB off-chain (on-chain solo hashes) | **NO** |
| Custodia USDC en escrow | AssetVault (saldo + `reservaTecnicaUSDC`/`montoNetoPendiente`/`reservaTecnicaLiberada`) | Contabilidad espejo + conciliación cada 15 min | **NO** — audita/concilia |

**Filas autoritativas on-chain: 6 (5 originales + evidencia KYC off-chain). El backend es fuente en 1 (evidencia KYC, hasheada).** El backend NUNCA decide balances, plata ni transición de estado on-chain por sí mismo.

---

## §4 — Objetivos principales (Fase 2)

1. **OP-1 — Cablear el backend a los 3 contratos del MVP de forma tipada, íntegra y versionada por re-deploy** (Contract interface layer): bindings desde el ABI congelado, address registry estático con pin de bytecode, bootstrap fail-fast.
2. **OP-2 — Construir el read path: indexar el catálogo completo de eventos vía Goldsky y proyectarlo a un read model Postgres servible, con la regla read-vs-live como invariante de código** y manejo correcto de reorgs/finalidad.
3. **OP-3 — Construir el write path: relayer HOT (KMS) para `BACKEND_SIGNER_ROLE` + preparación de calldata COLD para el Safe 2-de-3, con idempotencia y manejo de nonce que impidan el doble-mint.**
4. **OP-4 — Cerrar el integration boundary: pipeline KYC Sumsub→IdentityRegistry confirmado por evento, screening continuo derivado a compliance, y monitoreo de external deps — respetando que la cadena es la única autoridad de compliance.**
5. **OP-5 — Resolver y formalizar (ADR) las decisiones abiertas que bloquean producción** (RPC Plume, KMS concreto, custodia HOT/COLD, gas/relayer, finalidad/reorg, Goldsky-en-Plume) antes del wiring a mainnet.

---

## §5 — Objetivos secundarios (cada uno cuelga de un objetivo principal)

**De OP-1:**
- OS-1.1 — Publicar `packages/abis` con bindings `as const satisfies Abi` (abitype) de los 3 contratos + test de integridad de hash de ABI.
- OS-1.2 — Publicar `packages/chain` con el mapa estático `DEPLOYMENTS` (datos reales testnet 98867 + placeholders mainnet) y `resolveAddress` puro con custom errors.
- OS-1.3 — Definir `plumeTestnet`/`plumeMainnet` + `getPublicClient`/`getWalletClient` (account KMS sin clave privada).
- OS-1.4 — Implementar los 3 ContractClients tipados (AssetVault/IdentityRegistry/RedemptionManager) con decoders de eventos y los gotchas documentados (`tokensLockedFor` arg order, `getTier` sin expiry).
- OS-1.5 — Implementar `ChainBootstrap` (resolveAddress + match de runtime bytecode + cache de clients + fail-fast en `[PENDIENTE DEPLOY]`/mismatch).

**De OP-2:**
- OS-2.1 — Definir el subgraph Goldsky: 3 dataSources + handlers para TODO el catálogo §5 (handlers generados desde el ABI, no de la prosa — GAP-5).
- OS-2.2 — Crear el schema Drizzle del read model: `holding`, `lote_proyeccion`, `redencion_proyeccion`, `kyc_mirror`, `transfer_log`, `config_onchain`, `admin_mirror` (con columnas de procedencia + idempotencia por `(chainId, txHash, logIndex)`).
- OS-2.3 — Implementar el submódulo `indexing/` (webhook/GraphQL Goldsky + `proyectarEvento` con validación de máquinas de estado §8).
- OS-2.4 — Implementar la barrera de finalidad N-confirmaciones (zona confirmada vs pendiente) y la mecánica de reorg (recompute desde fork-point).
- OS-2.5 — Implementar la regla read-vs-live como invariante de código (gates y balance pre-tx SIEMPRE live) + hidratación live de campos sin evento.
- OS-2.6 — Implementar el job `conciliarConCadena` (holdings==totalSupply, escrow espejo==on-chain) con alertas.

**De OP-3:**
- OS-3.1 — Implementar `RelayerService` con las dos vías (HOT firma KMS / COLD calldata al Safe) y el `KmsAccount` custom de viem.
- OS-3.2 — Implementar `NonceManager` serializado (cola BullMQ `relayer-hot` concurrency=1 + reconciliación contra `getTransactionCount`) + política de re-broadcast/gas-bump.
- OS-3.3 — Implementar idempotencia en dos capas (`relayer_idempotency` por `paymentRefHash` + verificación de `LoteComprado` en Goldsky).
- OS-3.4 — Implementar `PrivilegedEndpointRegistry` (mapa endpoint↔rol↔función↔vía↔Zod) con doble gate Clerk+2FA y RBAC.
- OS-3.5 — Implementar `SolidityErrorDecoder` (selector→error HTTP, generado desde `packages/abis`) + ledger `relayer_tx` + escritura al `audit_log`.
- OS-3.6 — Reusar el patrón `oracle/` (tx-builder/safe-adapter/signers-notifier) para la Vía B y exponer el preview de `iniciarRedencion`.

**De OP-4:**
- OS-4.1 — Implementar `POST /webhooks/sumsub` (HMAC SHA-256 sobre raw body + idempotencia `webhook_events` + Zod + encolar, sin firmar inline).
- OS-4.2 — Implementar `ResolveKYCDecision` (mapeo Sumsub→tier + jurisdicción ISO off-chain + `expiresAt` + `sumsubApplicantHash`).
- OS-4.3 — Implementar `IdentityRegistryWriter` (`setKYC`/`revokeKYC` vía KMS) + reconciliador outbox→evento (`KYCUpdated`/`KYCRevoked`).
- OS-4.4 — Implementar screening nightly 02:00 UTC → propuesta de sanción a COMPLIANCE (NO sanciona on-chain) + job identity-expiry diario (re-onboarding, no escribe).
- OS-4.5 — Implementar el monitoreo de external deps: payment reconciliation cada 15 min (liquidez USDC), watch de `paused()` (detiene `kyc-sync`), alerta rate KYC >100/h, watch `RedemptionManagerSet`.
- OS-4.6 — Dejar los puertos vacíos `KycBridgePort` (Plume Arc) y `QualityAttestationPort` (LabRegistry/QA) documentados como extensión, SIN implementación.

**De OP-5:**
- OS-5.1 — Redactar y aprobar el ADR de RPC Plume + failover (transport viem `fallback()`).
- OS-5.2 — Redactar y aprobar el ADR de KMS concreto (AWS vs GCP) que define el shape de `KmsAccount`.
- OS-5.3 — Redactar y aprobar el ADR de custodia HOT/COLD (boundary exacto del backend signer vs Safe).
- OS-5.4 — Redactar y aprobar el ADR de gas/relayer (quién paga gas, fondeo/rotación de wallet operacional, gas-bump, B2C self-custody).
- OS-5.5 — Redactar y aprobar el ADR de finalidad/reorg en Plume (valor de `CONFIRMACIONES_FINALIDAD`) y el ADR Goldsky-en-Plume + push vs polling.

---

## §6 — Checklist (derivada de los objetivos secundarios — esta se va tildando)

**OP-1 — Contract interface layer**
- [ ] 1. Crear `packages/abis/package.json` (`@tokenization/abis`, `type: module`, dep `abitype`) y `src/index.ts` con bindings `as const satisfies Abi` de los 3 contratos. (OS-1.1)
- [ ] 2. Escribir `packages/abis/src/integrity.test.ts`: hash sha256 de cada ABI JSON pinneado. (OS-1.1)
- [ ] 3. Crear `packages/chain/src/deployments.ts` con `DEPLOYMENTS` (datos reales testnet 98867 + placeholders mainnet 98866 + anvil 31337 runtime). (OS-1.2)
- [ ] 4. Implementar `resolveAddress(chainId, name, version?)` puro con `UnknownDeployment`/`AddressPending`. (OS-1.2)
- [ ] 5. Definir `plumeTestnet`/`plumeMainnet` (`defineChain`) + `getPublicClient(chainId)` cacheado. (OS-1.3)
- [ ] 6. Implementar `getWalletClient(chainId)` con `KmsAccount` (sin clave privada en memoria). (OS-1.3)
- [ ] 7. Implementar `AssetVaultClient` (reads §4.1 + writes KMS `comprar` + calldata builders ORACLE/admin + decoders de eventos). (OS-1.4)
- [ ] 8. Implementar `IdentityRegistryClient` (reads §4.2 + `setKYC`/`revokeKYC` + calldata builders compliance; doc `getTier` sin expiry). (OS-1.4)
- [ ] 9. Implementar `RedemptionManagerClient` (reads §4.3 con doc del arg-order de `tokensLockedFor` + calldata builders ORACLE + preview `iniciarRedencion`). (OS-1.4)
- [ ] 10. Implementar `ChainBootstrap` (resolveAddress + match runtime bytecode sha256 + cache + fail-fast). (OS-1.5)

**OP-2 — Read path**
- [ ] 11. Definir el subgraph Goldsky: 3 dataSources con `startBlock` de deploy + handlers de TODO el catálogo §5, generados desde el ABI. (OS-2.1)
- [ ] 12. Crear schema Drizzle: `holding`, `lote_proyeccion`, `redencion_proyeccion`, `kyc_mirror`, `transfer_log`, `config_onchain`, `admin_mirror` con procedencia + idempotencia `(chainId, txHash, logIndex)`. (OS-2.2)
- [ ] 13. Generar y aplicar migraciones `drizzle-kit` del read model. (OS-2.2)
- [ ] 14. Implementar submódulo `indexing/` (cliente GraphQL + webhook handler Goldsky). (OS-2.3)
- [ ] 15. Implementar `proyectarEvento` con validación de las máquinas de estado §8.1/§8.2/§8.3. (OS-2.3)
- [ ] 16. Implementar la barrera de finalidad N-confirmaciones (zona confirmada vs pendiente). (OS-2.4)
- [ ] 17. Implementar la mecánica de reorg (recompute `holding`/escrow desde `transfer_log`, re-aplicar máquinas de estado desde fork-point). (OS-2.4)
- [ ] 18. Implementar la regla read-vs-live como invariante (gates + balance pre-tx SIEMPRE live) + hidratación live de `hashFotosApiario`/`tipoCertificadoOrigen`. (OS-2.5)
- [ ] 19. Implementar `reconstruirReadModel` (backfill desde `startBlock`). (OS-2.3)
- [ ] 20. Implementar el job BullMQ `conciliarConCadena` (holdings==totalSupply, escrow espejo==on-chain) con alertas a `notifications/`. (OS-2.6)

**OP-3 — Write path**
- [ ] 21. Implementar `RelayerService` (Vía A HOT firma KMS + Vía B COLD calldata al Safe). (OS-3.1)
- [ ] 22. Implementar `KmsAccount` (custom viem account, firma remota vía `BACKEND_SIGNER_KMS_KEY_ID`). (OS-3.1)
- [ ] 23. Implementar `NonceManager` (cola BullMQ `relayer-hot` concurrency=1 + reconcile contra `getTransactionCount('pending')`). (OS-3.2)
- [ ] 24. Implementar política de re-broadcast / gas-bump (EIP-1559 ×1.25, mismo nonce, nunca otro payload) + gap recovery. (OS-3.2)
- [ ] 25. Crear tablas `relayer_idempotency`, `relayer_nonce`, `relayer_tx` (migraciones Drizzle). (OS-3.3/OS-3.5)
- [ ] 26. Implementar idempotencia HTTP por `paymentRefHash` (`ON CONFLICT DO NOTHING`, 409 en payload distinto) + verificación de `LoteComprado` en Goldsky. (OS-3.3)
- [ ] 27. Implementar `PrivilegedEndpointRegistry` (mapa endpoint↔rol↔función↔vía↔Zod) con doble gate Clerk+2FA + RBAC. (OS-3.4)
- [ ] 28. Implementar los endpoints Hono privilegiados (HOT: `/purchases/:loteId/mint`, `/identity/kyc`, `/identity/kyc/revoke`; COLD: todos los `/admin/...`). (OS-3.4)
- [ ] 29. Implementar `SolidityErrorDecoder` (selector→error HTTP desde `packages/abis`; `EnforcedPause`→503). (OS-3.5)
- [ ] 30. Integrar cada escritura privilegiada con el `audit_log` append-only (hash chain, sin PII). (OS-3.5)
- [ ] 31. Reusar `oracle/` (tx-builder/safe-adapter/signers-notifier) para la Vía B + exponer preview de `iniciarRedencion`. (OS-3.6)

**OP-4 — Integration boundary**
- [ ] 32. Implementar `POST /webhooks/sumsub` (HMAC SHA-256 raw body → idempotencia `webhook_events` → Zod → encolar `kyc-sync`, sin firmar inline). (OS-4.1)
- [ ] 33. Crear tablas `webhook_events`, `onchain_tx` (outbox), `kyc_cache`, `applicants` (PII cifrada). (OS-4.1/OS-4.3)
- [ ] 34. Implementar `ResolveKYCDecision` (mapeo Sumsub→tier + jurisdicción ISO off-chain + `expiresAt` + `sumsubApplicantHash`). (OS-4.2)
- [ ] 35. Implementar `IdentityRegistryWriter` (`setKYC`/`revokeKYC` vía KMS, con pre-check de preconditions). (OS-4.3)
- [ ] 36. Implementar el reconciliador outbox→evento (KYC efectivo SOLO al ver `KYCUpdated`/`KYCRevoked`). (OS-4.3)
- [ ] 37. Implementar el job screening nightly 02:00 UTC → propuesta de sanción a COMPLIANCE (NO sanciona on-chain). (OS-4.4)
- [ ] 38. Implementar el job identity-expiry diario (re-onboarding + invalidar cache, NO escribe on-chain). (OS-4.4)
- [ ] 39. Implementar el job payment reconciliation cada 15 min (liquidez USDC AssetVault vs espejo) con alerta. (OS-4.5)
- [ ] 40. Implementar watch de `paused()` de IdentityRegistry (detiene cola `kyc-sync` + alerta) y alerta rate `KYCUpdated` >100/h. (OS-4.5)
- [ ] 41. Dejar puertos vacíos `KycBridgePort` y `QualityAttestationPort` documentados como extensión, SIN implementación. (OS-4.6)

**OP-5 — ADRs bloqueantes**
- [ ] 42. ADR-023 — RPC Plume + política de failover (transport viem `fallback()`). (OS-5.1)
- [ ] 43. ADR-022 — KMS concreto (AWS vs GCP) + shape de `KmsAccount`. (OS-5.2)
- [ ] 44. ADR-020 — Custodia HOT/COLD: boundary exacto del backend signer vs Safe 2-de-3. (OS-5.3)
- [ ] 45. ADR-021 — Modelo de gas/relayer (quién paga, fondeo/rotación de wallet, gas-bump, B2C self-custody). (OS-5.4)
- [ ] 46. ADR de finalidad/reorg en Plume (`CONFIRMACIONES_FINALIDAD`) + ADR-024 Goldsky-en-Plume + push vs polling. (OS-5.5)

---

## §7 — ADRs decididos en Fase 2 (antes "abiertos a decidir")

> Estos eran los huecos que el CIS y los ADR vigentes dejaban SIN cerrar, cada uno bloqueante del wiring a producción (mainnet 98866). **Todos quedaron DECIDIDOS por los ADR-020 a ADR-030 (2026-06-02).** Se conservan acá con su decisión y referencia al ADR que la cierra.

| ADR | Estado | Decisión (resumen) |
|---|---|---|
| **ADR-020 — Custodia HOT/COLD** | ✅ Decidido (ver ADR-020) | `BACKEND_SIGNER_ROLE` es el ÚNICO rol hot vía GCP KMS, con superficie hot de exactamente 3 funciones (`comprar`/`setKYC`/`revokeKYC`); TODO lo demás (ADMIN/ORACLE/TREASURY/COMPLIANCE/DEFAULT_ADMIN) es cold vía Safe 2-de-3 / hardware (el backend arma calldata, NO firma). |
| **ADR-021 — Gas / relayer en Plume** | ✅ Decidido (ver ADR-021) | Vía A: `BACKEND_SIGNER` paga su propio gas con su wallet KMS; nonce serializado por cola BullMQ `relayer-hot` (concurrency=1) + leader-election; re-broadcast mismo-nonce con gas-bump EIP-1559 ×1.25; fondeo por monitoreo + alerta + top-up manual. B2C self-custody (el comprador paga su gas); gasless (ERC-2771/4337) = fast-follow, NO MVP. |
| **ADR-022 — KMS concreto** | ✅ Decidido (ver ADR-022) | GCP Cloud KMS, clave asimétrica `EC_SIGN_SECP256K1_SHA256`. `KmsAccount` custom de viem; la clave NUNCA se materializa. `BACKEND_SIGNER_KMS_KEY_ID` e `IRYS_FUNDING_WALLET_KMS_KEY_ID` pasan de ARN de AWS a nombre de recurso GCP (`projects/.../cryptoKeyVersions/VERSION`). |
| **ADR-023 — RPC Plume + failover** | ✅ Decidido (ver ADR-023) | Transport viem `fallback([oficial, dRPC, thirdweb], { rank: true })`, Plume-only (98866/98867). Env: `PLUME_RPC_URL` + `PLUME_RPC_URL_FALLBACK_DRPC`/`_THIRDWEB` (vacías → se omiten). Alchemy/Infura siguen siendo SOLO Polygon fase 8+. |
| **ADR-024 — Goldsky en Plume + ingestión** | ✅ Decidido (ver ADR-024) | Goldsky managed soporta Plume (no se cae al fallback, §18.1 respetada); ingestión por **push-webhook** firmado (no polling). 3 dataSources (CIS §5). PENDIENTE menor: confirmar testnet 98867 managed antes de wirear. |
| **ADR-025 — Finalidad/reorg en Plume** | ✅ Decidido (ver ADR-025) | La zona servible se keyea contra el block tag `safe`/`finalized` del nodo (viem `blockTag`), **NO** contra un `CONFIRMACIONES_FINALIDAD` hardcodeado. Lo crítico siempre LIVE (`latest`). Reorg: fork-point + recompute determinístico desde `transfer_log`, idempotencia `(chainId, txHash, logIndex)`. |
| **ADR-026 — RLS / seguridad de DB** | ✅ Decidido (ver ADR-026) | `ENABLE` + `FORCE ROW LEVEL SECURITY` sobre las 10 tablas con PII/financiero + roles de mínimo privilegio (`api_user`/`audit_reader`). El `audit_log` mantiene `REVOKE UPDATE,DELETE` + hash chain (NO RLS). Resuelve DB-SEC-01 (no estaba en §7 original; cubre el gap de seguridad de la capa de datos). |
| **ADR-027 — Cifrado de PII at-rest** | ✅ Decidido (ver ADR-027) | `applicants` cifrada con AES-256-GCM + envelope encryption (DEK por registro, KEK en GCP KMS de ADR-022). On-chain sigue yendo solo `sumsubApplicantHash`. Complementa RLS (ADR-026). Cierra el "PII cifrada" antes solo declarado. |
| **ADR-028 — Stack de observabilidad** | ✅ Decidido (ver ADR-028) | pino (sin PII, con `traceId` OTel) + OpenTelemetry (tracing distribuido real) + Sentry + Better Stack + Tenderly. **PagerDuty INCLUIDO** para P0 (resuelve la inconsistencia §16.1 vs §16.3); resto a Slack/Resend. Nuevo env: `PAGERDUTY_INTEGRATION_KEY`. |
| **ADR-029 — Disaster Recovery (RTO/RPO)** | ✅ Decidido (ver ADR-029) | RTO < 1h / RPO ~0. Supabase PITR + read replica cross-region (datos off-chain + `audit_log`); read model reconstruible por backfill desde `startBlock` (`23675712` en testnet 98867); snapshot mensual del `audit_log` a Arweave; clave HOT recuperable por IAM/KMS (NO escrow físico — ese es solo para seeds del Safe). |
| **ADR-030 — Allowlist de jurisdicciones** | ✅ Decidido (ver ADR-030) | `ALLOWED_JURISDICTIONS` + `isAllowedJurisdiction()` en `packages/shared` (admisión, distinta de `isValidJurisdiction` de ADR-011); enforcement en `ResolveKYCDecision` antes de `setKYC`. Lista MVP provisional con **sign-off legal como gate de release bloqueante** a mainnet. Off-chain, `IdentityRegistry` intacto. |
| **Decisiones de infra/negocio (pueden ir en ADRs menores)** | ⏳ Parcial | Política Sumsub→tier y `expiresAt` TTL, Railway vs Fly.io, secret manager concreto, regiones/VPC, estrategia dev/staging/prod SIGUEN abiertas. **Ya cerradas:** jurisdicciones permitidas (ADR-030), observabilidad (ADR-028), custodia B2C self-custody (ADR-020/021). |

**Dependencia crítica recordada:** toda la proyección del ciclo `REDENCION_PARCIAL→AGOTADO` y el `kgRedimidos` acumulado dependen de **`TokensRedimidos` (ADR-019)**. El pin de bytecode de §2 es **testnet**; antes de indexar mainnet hay que verificar que el bytecode desplegado a 98866 incluye ADR-019 — si no, el read path tendría el punto ciego que GAP-2 resolvió.

---

*Documento derivado de CIS v1.2 (congelado) + ADR-001/003/007/010/011/013/014/015/016/017/019. Cualquier desviación requiere ADR nuevo.*
