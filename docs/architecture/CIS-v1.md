# Contract Interface Specification (CIS) v1 — source-frozen

> **Esta es la descripción CONGELADA de la interfaz de contratos para el backend.**
> El backend (fase 2) genera sus typed bindings a partir de ESTE documento + los ABIs en `packages/abis/`. No debe volver a leer el Solidity para entender la superficie pública: si algo no está acá, falta acá, no se asume del código.

| Campo | Valor |
|---|---|
| **Versión** | v1.2 |
| **Fecha** | 2026-06-01 |
| **Revisión** | v1.2 (2026-06-01) — deployado a Plume testnet (chainid 98867); secciones 1 y 2 completadas con addresses reales + pin de runtime bytecode. · v1.1 — AssetVault ABI 23 → 26 eventos: GAP-1/2/3/4 resueltos pre-deploy por ADR-019 (`RedemptionManagerSet`, `TokensRedimidos`, `ReembolsoFinalizado`). |
| **Estado de deploy** | **Deployado en Plume testnet** (chainid 98867) el 2026-06-01. Verificación en explorer y deploy a mainnet PENDIENTES. |
| **Estado del código** | code-frozen, audit-ready interno. 100% branch/line/function coverage, Slither 0 findings accionables, fuzz 10k, invariant hasta 200k calls, 3 auditorías internas profundas, ADRs 001–019 (ADR-019 agregó 3 eventos de dominio a AssetVault pre-deploy). |
| **Auditoría externa** | **PENDIENTE / NO iniciada** — ver `docs/security-reviews/PLAN-AUDITORIA-EXTERNA-MVP.md`. |
| **Scope** | 3 contratos del MVP (`AssetVault`, `IdentityRegistry`, `RedemptionManager`) + 3 libraries (`ComplianceConstants`, `DocumentHashes`, `QualityRules`). |
| **Stack** | Solidity 0.8.24, OpenZeppelin v5, ERC-1155, contratos INMUTABLES sin proxy (ADR-003), EVM target `paris`. |
| **Red objetivo** | Plume Network (primaria). Polygon PoS es fase 6+. |

> **Nota sobre identificadores:** el dominio de negocio está en español rioplatense A PROPÓSITO (`comprar`, `confirmarCosecha`, `iniciarRedencion`, `LoteMiel`, eventos como `LoteComprado`). Todos los identificadores de este documento son VERBATIM del código. La prosa explicativa está en español rioplatense (convención del proyecto).

> **Aviso source-of-truth de tipos:** los nombres de función, params, eventos, indexed flags y errores son la fuente de verdad del documento, pero el **artefacto vinculante para typed bindings es el ABI JSON** (`packages/abis/*.abi.json`). Si hubiera divergencia entre la prosa de acá y el ABI, gana el ABI — y se abre un GAP (sección final).

---

## Sección 1 — Inventario de contratos y addresses

Las tres son piezas del MVP, **deployadas en Plume testnet (chainid 98867) el 2026-06-01**. La columna mainnet sigue `[PENDIENTE DEPLOY]`. Token de pago en testnet: `MockUSDC` en `0xf309e1eB2E3f4Cb169d6C9986A98C3e408C72Fb5` (mock de 6 decimales SIN mint expuesto — sirve para wirear y deployar; para flujos con fondos hace falta un mock minteable, ver sección 10).

### 1.1 AssetVault

| Atributo | Valor |
|---|---|
| Naturaleza | ERC-1155 RWA token + escrow de USDC + registro de lotes (contrato principal del MVP). Hereda `ERC1155`, `ERC1155Supply`, `ERC1155Pausable`, `AccessControlDefaultAdminRules`, `ReentrancyGuard`, `IAssetVault`. |
| Deployed | **SÍ** — Plume testnet (98867), 2026-06-01 |
| Verified (explorer) | **NO** (pendiente; no se pasó API key en el deploy) |
| Audit | Interno hecho (deep audit `audit-AssetVault-deep-2026-05-19.md`) + Slither 0 findings + 100% coverage. **Auditoría externa PENDIENTE.** |
| Address Plume testnet | `0x1E39944BD26485F5946abae706Aa99D729886b47` |
| Address Plume mainnet | `[PENDIENTE DEPLOY]` |

### 1.2 IdentityRegistry

| Atributo | Valor |
|---|---|
| Naturaleza | Allowlist / registro KYC on-chain. Fuente de verdad de KYC consumida por `AssetVault.canMint` y `RedemptionManager.canRedeem`. Sincronizado desde Sumsub off-chain vía `BACKEND_SIGNER_ROLE`. Hereda `AccessControlDefaultAdminRules`, `Pausable`, `IIdentityRegistry`. |
| Deployed | **SÍ** — Plume testnet (98867), 2026-06-01 |
| Verified (explorer) | **NO** (pendiente; no se pasó API key en el deploy) |
| Audit | Interno hecho (`audit-IdentityRegistry-deep-2026-05-22.md`) + Slither 0 findings + 100% coverage. **Auditoría externa PENDIENTE.** |
| Address Plume testnet | `0x8FBa3ae61B53516a32Ce443E2abb83Edcddfd6Cc` |
| Address Plume mainnet | `[PENDIENTE DEPLOY]` |

### 1.3 RedemptionManager

| Atributo | Valor |
|---|---|
| Naturaleza | Redención física en 2 fases (export). Option B "Lock Accumulator": los tokens NUNCA salen del wallet hasta el burn final. Hereda `AccessControlDefaultAdminRules`, `ReentrancyGuard`, `Pausable`, `IRedemptionManager`. NO mueve USDC. |
| Deployed | **SÍ** — Plume testnet (98867), 2026-06-01 |
| Verified (explorer) | **NO** (pendiente; no se pasó API key en el deploy) |
| Audit | Interno hecho (`audit-RedemptionManager-deep-2026-05-26.md`) + Slither 0 findings + 100% coverage. **Auditoría externa PENDIENTE.** |
| Address Plume testnet | `0xd6EA5406D7579C1bc5ea935d5ED46675Edf8d062` |
| Address Plume mainnet | `[PENDIENTE DEPLOY]` |

### 1.4 Libraries (no se deployan por separado)

`ComplianceConstants`, `DocumentHashes`, `QualityRules` son libraries `internal pure`/`constant`: se **inlinan en compile-time** dentro del bytecode de los contratos consumidores. No tienen address propia ni linkeo externo. Sus valores se documentan en la sección 6.x y la matriz de constantes; el backend los hardcodea o los lee del ABI/bytecode.

---

## Sección 2 — ABI capture

Los ABIs ya fueron capturados de la compilación (`forge inspect <Contract> abi --json`, exit 0, JSON válido). El backend consume estos archivos directamente.

| Contrato | ABI path | fn count | event count | Pin: deployed runtime bytecode sha256 (Plume testnet 98867) |
|---|---|---|---|---|
| AssetVault | `packages/abis/AssetVault.abi.json` | 54 | 26 | `81743037a5953e315535c524593adcdeb93257749a1d60917dc89ef6c37da6fe` |
| IdentityRegistry | `packages/abis/IdentityRegistry.abi.json` | 38 | 17 | `b1cea3c19754a405b453242d8931671423ed12e45b6478e80fc7bd7e3a9dbdf0` |
| RedemptionManager | `packages/abis/RedemptionManager.abi.json` | 36 | 15 | `2eb49f6c939eff643e2ab67b9aa0b5e25a593fb010e4990e02f04414c8fa4d76` |

**Nota de pin:** el pin canónico es el **deployed runtime bytecode sha256** de arriba (`cast code <addr> | shasum -a 256`, Plume testnet 98867, 2026-06-01). El ABI es idéntico entre redes; al deployar a mainnet se recalcula el pin para esas addresses. **Verificación en el explorer: PENDIENTE** (no se pasó API key en el deploy) — al verificar, el explorer expone el ABI públicamente y se flipa `Verified=SÍ` en la sección 1.

Referencia de creation-bytecode (compilación, NO usar como pin):
- AssetVault: `a3f19941b61ecb3e78a8ebb02fae6dd30d5836d173f77367033999d94463fa94`
- IdentityRegistry: `df651d0dc358214b686b56c185a76dcc3952000c9d3cff0574b352ca490f9a58`
- RedemptionManager: `10e73ae29ed6d081382a7997776fbc382e03bba4ac02f3c2d3203bb35f517882`

---

## Sección 3 — Write surface

### 3.1 AssetVault — write surface

| Función | Quién puede llamar | Preconditions | Side effects | Eventos | Errores |
|---|---|---|---|---|---|
| `setRedemptionManager(address newRedemptionManager)` | `DEFAULT_ADMIN_ROLE` | `newRedemptionManager != 0`; `redemptionManager == 0` (one-time) | Setea `redemptionManager` (una sola vez; resuelve dependencia circular con RM) | `RedemptionManagerSet` (ADR-019, GAP-1 resuelto) | `ZeroAddress`, `RedemptionManagerAlreadySet` |
| `crearLote(uint256 loteId, uint256 kgEsperados, uint256 precioPorTokenUSDC, uint64 fechaCosechaEstimada, bytes2 origenGeografico, address productorSRL, bytes32 hashFSA, uint16 reservaBps, uint8 variedadMonofloral)` | `ADMIN_ROLE` | lote no existe; `kgEsperados!=0`; `precioPorTokenUSDC!=0`; `productorSRL!=0`; `hashFSA` válido; `1500<=reservaBps<=2000` | Crea `_lotes[loteId]`, estado `PREVENTA`. `loteId` lo elige el caller off-chain (D1: no hay counter interno) | `LoteCreado` | `LoteAlreadyExists`, `InvalidKgEsperados`, `InvalidPrecio`, `ZeroAddress`, `InvalidHash`, `ReservaBpsOutOfRange` |
| `comprar(uint256 loteId, uint256 cantidadTokens, address comprador, uint256 montoUSDCPagado, bytes32 paymentRefHash)` | `BACKEND_SIGNER_ROLE` + `nonReentrant` + `whenNotPaused` | lote existe; estado `PREVENTA`; `cantidadTokens!=0`; `paymentRefHash!=0`; capacidad en GRAMOS (FIX H-02); `montoUSDCPagado >= cantidadTokens*precioPorTokenUSDC`; KYC `canMint` (validado en `_update`). **OFF-CHAIN: el backend DEBE transferir el USDC al contrato ANTES de llamar; `comprar` NO hace `transferFrom`** | Escrow total (FIX H-01 Opción A): acumula `reservaTecnicaUSDC` y `montoNetoPendiente`; `_mint`. NO transfiere al productor acá | `LoteComprado`, `TransferSingle(from=0)` | `LoteNotExists`, `LoteNotInPreventa`, `CantidadTokensCero`, `InvalidHash`, `KgSolicitadosExcedenSupply`, `MontoUSDCInsuficiente`, `NotKYCVerified`, `EnforcedPause` |
| `confirmarCosecha(uint256 loteId, uint256 kgRealCosechado, bytes32 hashSenasag, bytes32 hashAnalisisLab, bytes32 hashActaCosecha, bytes32 hashFotosApiario, bytes32 hashCertificadoOrigen, TipoCertificadoOrigen tipoCertificado)` | `ORACLE_ROLE` + `nonReentrant` | lote existe; estado `PREVENTA`; `kgRealCosechado!=0`; 5 hashes válidos | `PREVENTA → COSECHADO`. Libera `montoNetoPendiente` al `productorSRL` (si >0). Reserva técnica NO se libera acá | `CosechaConfirmada`, `MontoNetoLiberado` (si monto>0) | `LoteNotExists`, `LoteNotInPreventa`, `InvalidKgEsperados`, `InvalidHash` |
| `confirmarAlmacenamiento(uint256 loteId, bytes32 hashContratoDeposito, address almacenAutorizado)` | `ORACLE_ROLE` | lote existe; estado `COSECHADO`; `hashContratoDeposito` válido; `almacenAutorizado!=0` | `COSECHADO → ALMACENADO`. `almacenAutorizado` solo se emite en evento (NO se persiste) | `AlmacenamientoConfirmado` | `LoteNotExists`, `LoteNotInCosechado`, `InvalidHash`, `ZeroAddress` |
| `marcarFallido(uint256 loteId, string calldata motivo)` | `ORACLE_ROLE` | lote existe; estado `PREVENTA` o `COSECHADO` (FIX M-05: NO post-ALMACENADO); `motivo` no vacío | `PREVENTA\|COSECHADO → FALLIDO` (terminal). Setea `motivoFallo` | `LoteFallido` | `LoteNotExists`, `CannotFailLoteInThisState`, `EmptyMotivo` |
| `reembolsarLoteFallido(uint256 loteId, address[] calldata compradores)` | `ORACLE_ROLE` + `nonReentrant` | lote existe; estado `FALLIDO`; `!_reembolsado`; `0 < compradores.length <= 100`; por comprador: balance>0 (sino skip), `!isSanctioned`, `!isFrozen`, `getTier!=0` | Paginable (Opt-B2). Burn pro-rata + `safeTransfer` USDC a compradores válidos. Si `totalSupply==0`: marca `_reembolsado=true` y retorna (caso degenerado, ADR-019, GAP-3 resuelto) | `ReembolsoEjecutado` (por comprador con balance>0), `TransferSingle(to=0)`; `ReembolsoFinalizado` (branch `totalSupply==0`, ADR-019) | `LoteNotExists`, `LoteNotInFallido`, `ReembolsoYaEjecutado`, `EmptyBuyers`, `BatchTooLarge`, `CannotRefundBlockedAddress`, `CannotRefundRevokedAddress` |
| `finalizarReembolso(uint256 loteId)` | `ORACLE_ROLE` | lote existe; estado `FALLIDO`; `!_reembolsado` | `_reembolsado[loteId]=true` (cierra la paginación). NO mueve fondos ni cambia `LoteEstado` (ADR-019, GAP-4 resuelto) | `ReembolsoFinalizado` (ADR-019, GAP-4 resuelto) | `LoteNotExists`, `LoteNotInFallido`, `ReembolsoYaEjecutado` |
| `liberarReservaTecnica(uint256 loteId)` | `TREASURY_SRL_ROLE` + `nonReentrant` | lote existe; estado en `{COSECHADO, ALMACENADO, REDENCION_PARCIAL, AGOTADO}` (NO `PREVENTA` ni `FALLIDO`); reserva disponible >0 | Marca reserva liberada + `safeTransfer` al `productorSRL`. NO cambia `LoteEstado`. CONFLICT-1 Opción A: permitido desde `COSECHADO` (no requiere QUALITY_ATTESTED) | `ReservaTecnicaLiberada` | `LoteNotExists`, `LoteNotInCosechado`, `ReservaAlreadyReleased` |
| `burnForRedemption(address from, uint256 loteId, uint256 cantidad)` | público pero gateado: `msg.sender == redemptionManager` | `redemptionManager != 0` (FIX Bug-B1, chequeado PRIMERO); `msg.sender == redemptionManager`; `cantidad!=0`; `from` con balance suficiente | Acumula `kgRedimidos`. `ALMACENADO → REDENCION_PARCIAL`. `_burn`. Si `totalSupply==0 && REDENCION_PARCIAL → AGOTADO` (terminal) | `TokensRedimidos` (ADR-019, GAP-2 resuelto), `TransferSingle(to=0)` | `RedemptionManagerNotSet`, `OnlyRedemptionCanBurn`, `CantidadTokensCero`, `ERC1155InsufficientBalance` |
| `pause()` | inline: `COMPLIANCE_OFFICER_ROLE` **OR** `DEFAULT_ADMIN_ROLE` (ADR-016) + `whenNotPaused` | no pausado; caller con uno de esos roles | `_pause()` global (bloquea `comprar` y transfers no-mint/no-burn) | `EmergencyPaused`, `Paused` | `UnauthorizedPauseActor`, `EnforcedPause` |
| `unpause()` | `DEFAULT_ADMIN_ROLE` (asimetría ADR-016: NO compliance officer) | pausado; caller `DEFAULT_ADMIN_ROLE` | `_unpause()` global | `EmergencyUnpaused`, `Unpaused` | `ExpectedPause`, `AccessControlUnauthorizedAccount` |
| `setApprovalForAll(address, bool)` | público — **SIEMPRE revierte** | N/A | Ninguno (override que revierte). El backend NUNCA puede usar approvals/operator transfers | — | `TransferP2PNoPermitido` |
| `safeTransferFrom(...)` / `safeBatchTransferFrom(...)` | público — revierte vía `_update` | cualquier transfer `from!=0 && to!=0` revierte | Bloqueado de facto (solo primario, sin P2P) | — | `TransferP2PNoPermitido` |

**Heredadas de `AccessControlDefaultAdminRules` / `AccessControl` (gestión de roles, todas con `DEFAULT_ADMIN_ROLE` salvo nota):** `beginDefaultAdminTransfer`, `acceptDefaultAdminTransfer` (solo pendingDefaultAdmin tras 3 días), `cancelDefaultAdminTransfer`, `changeDefaultAdminDelay`, `rollbackDefaultAdminDelay`, `grantRole`, `revokeRole`, `renounceRole`. Notas clave: `grantRole`/`revokeRole` de `DEFAULT_ADMIN_ROLE` directo están PROHIBIDOS (revierte `AccessControlEnforcedDefaultAdminRules`; hay que usar `begin/accept` con delay de 3 días, FIX M-08).

### 3.2 IdentityRegistry — write surface

| Función | Quién puede llamar | Preconditions | Side effects | Eventos | Errores |
|---|---|---|---|---|---|
| `setKYC(address user, uint8 tier, uint64 expiresAt, bytes2 jurisdiction, bytes32 sumsubApplicantHash)` | `BACKEND_SIGNER_ROLE` + `whenNotPaused` | `user!=0`; `tier!=0` (FIX M-04: tier=0 va por `revokeKYC`); `tier<=3`; `expiresAt > block.timestamp`. **`jurisdiction` NO se valida on-chain (ADR-011)** | Setea `tier`, `expiresAt`, `updatedAt`, `jurisdiction`, `sumsubApplicantHash`. NO toca `sanctioned`/`frozen` | `KYCUpdated` | `ZeroAddressUser`, `TierZeroNotAllowed`, `InvalidTier`, `ExpiryInPast`, `EnforcedPause`, `AccessControlUnauthorizedAccount` |
| `revokeKYC(address user, string calldata reason)` | `BACKEND_SIGNER_ROLE` + `whenNotPaused` | `user!=0`; `reason` no vacío; `tier!=0` | `tier=0` (revocación), `updatedAt`. Separa "nunca verificado" de "verificado y revocado" (FIX M-04) | `KYCRevoked` | `ZeroAddressUser`, `EmptyReason`, `AlreadyRevoked`, `EnforcedPause`, `AccessControlUnauthorizedAccount` |
| `markSanctioned(address user, string calldata reason, bytes32 evidenceHash)` | `COMPLIANCE_OFFICER_ROLE` + `whenNotPaused` | `user!=0`; `reason` no vacío; `evidenceHash!=0` (FIX M-01); `!sanctioned` | `sanctioned=true`, `updatedAt` | `Sanctioned` | `ZeroAddressUser`, `EmptyReason`, `InvalidEvidenceHash`, `AlreadySanctioned`, `EnforcedPause`, `AccessControlUnauthorizedAccount` |
| `unmarkSanctioned(address user, string calldata reason)` | `COMPLIANCE_OFFICER_ROLE` + `whenNotPaused` | `user!=0`; `reason` no vacío; `sanctioned==true` | `sanctioned=false`, `updatedAt` | `Unsanctioned` | `ZeroAddressUser`, `EmptyReason`, `NotSanctioned`, `EnforcedPause`, `AccessControlUnauthorizedAccount` |
| `freezeAddress(address user, string calldata regulatoryOrder, bytes32 orderHash)` | `COMPLIANCE_OFFICER_ROLE` + `whenNotPaused` | `user!=0`; `regulatoryOrder` no vacío (reusa `EmptyReason`); `orderHash!=0` (FIX M-01b); `!frozen` | `frozen=true`, `updatedAt` | `Frozen` | `ZeroAddressUser`, `EmptyReason`, `InvalidOrderHash`, `AlreadyFrozen`, `EnforcedPause`, `AccessControlUnauthorizedAccount` |
| `unfreezeAddress(address user, string calldata reason)` | `COMPLIANCE_OFFICER_ROLE` + `whenNotPaused` | `user!=0`; `reason` no vacío; `frozen==true` | `frozen=false`, `updatedAt` | `Unfrozen` | `ZeroAddressUser`, `EmptyReason`, `NotFrozen`, `EnforcedPause`, `AccessControlUnauthorizedAccount` |
| `pause()` | inline: `COMPLIANCE_OFFICER_ROLE` **OR** `DEFAULT_ADMIN_ROLE` (ADR-013/ADR-016) + `whenNotPaused` | no pausado; caller con uno de esos roles | `_pause()`: bloquea los 6 mutators KYC/compliance. **Las views NO se bloquean** (clave del scope-limited pause de ADR-013) | `EmergencyPaused`, `Paused` | `EnforcedPause`, `UnauthorizedPauseActor` |
| `unpause()` | `DEFAULT_ADMIN_ROLE` (asimetría ADR-013/ADR-016) | pausado; caller `DEFAULT_ADMIN_ROLE` | `_unpause()`: reactiva los 6 mutators | `EmergencyUnpaused`, `Unpaused` | `AccessControlUnauthorizedAccount`, `ExpectedPause` |

**Heredadas (gestión de roles):** mismas que AssetVault — `beginDefaultAdminTransfer`, `acceptDefaultAdminTransfer`, `cancelDefaultAdminTransfer`, `changeDefaultAdminDelay`, `rollbackDefaultAdminDelay`, `grantRole`, `revokeRole`, `renounceRole`. Admin de `BACKEND_SIGNER_ROLE` y `COMPLIANCE_OFFICER_ROLE` es `DEFAULT_ADMIN_ROLE`.

### 3.3 RedemptionManager — write surface

| Función | Quién puede llamar | Preconditions | Side effects | Eventos | Errores |
|---|---|---|---|---|---|
| `iniciarRedencion(uint256 loteId, uint256 cantidadTokens, bytes32 datosEnvioHash) returns (uint256 redencionId)` | público — sin rol; lo llama el comprador (`msg.sender`). `nonReentrant` + `whenNotPaused` | `canRedeem(msg.sender)` (tier>=2, no sancionado/congelado/expirado); `cantidadTokens>0`; `datosEnvioHash!=0`; lote existe; estado `ALMACENADO\|REDENCION_PARCIAL`; `cantidadTokens<=totalSupply(loteId)` (RM-19); `alreadyLocked + cantidadTokens <= balanceOf` (RM-01/02) | Incrementa `_tokensLockedFor[loteId][msg.sender]` (lock contable, Option B — NO transfiere/mintea/quema). `redencionId = _nextRedencionId++`. Crea `_redenciones[redencionId]` estado `INICIADA` | `RedencionIniciada` | `CannotRedeem`, `CantidadCero`, `InvalidHash`, `LoteNotFound`, `LoteNotInAlmacenado`, `CantidadExcedeSupply`, `BalanceInsuficiente`, `EnforcedPause`, `ReentrancyGuardReentrantCall` |
| `confirmarExportacion(uint256 redencionId, string calldata dueNumero)` | `ORACLE_ROLE`. **NO `whenNotPaused`** (§6.13.8). Sin `nonReentrant` | redención existe; estado `INICIADA`; `dueNumero` length 1..64 | `INICIADA → EN_EXPORTACION`. Almacena `dueNumero`. NO decrementa lock, NO quema | `RedencionEnExportacion` | `AccessControlUnauthorizedAccount`, `RedencionNotIniciada`, `RedencionAlreadyFinalized`, `EmptyDUE`, `DUENumeroTooLong` |
| `completarRedencion(uint256 redencionId, bytes32 hashBLAWB)` | `ORACLE_ROLE` + `nonReentrant`. **NO `whenNotPaused`** (§6.13.8) | redención existe; estado `EN_EXPORTACION`; `hashBLAWB!=0`; `balanceOf(comprador) >= cantidadTokens` (RM-04 fail-fast) | Decrementa lock (CEI estricto, ANTES del burn). `EN_EXPORTACION → COMPLETADA` (terminal). BURN vía `assetVault.burnForRedemption` (única vía de burn) | `RedencionCompletada` | `AccessControlUnauthorizedAccount`, `RedencionNotIniciada`, `NotInExportacion`, `InvalidHash`, `BalanceInsuficiente`, `ReentrancyGuardReentrantCall`, (propagados de `burnForRedemption`) |
| `cancelarRedencion(uint256 redencionId, bytes32 reason)` | inline 3-path (ADR-015): `ORACLE_ROLE` **OR** `COMPLIANCE_OFFICER_ROLE` **OR** (`msg.sender==comprador` && `block.timestamp >= createdAt + REDENCION_TIMEOUT` [60 días]). `nonReentrant`. **NO `whenNotPaused`** | redención existe; estado `INICIADA\|EN_EXPORTACION` (ADR-017); `reason!=0`; caller autorizado | Libera lock. `INICIADA\|EN_EXPORTACION → CANCELADA` (terminal). NO quema, NO mueve USDC | `RedencionCancelada` | `RedencionNotIniciada`, `RedencionAlreadyFinalized`, `EmptyReason`, `OnlyAuthorizedCanceler`, `ReentrancyGuardReentrantCall` |
| `pause()` | inline: `COMPLIANCE_OFFICER_ROLE` **OR** `DEFAULT_ADMIN_ROLE` (ADR-016) + `whenNotPaused` | no pausado; caller con uno de esos roles | `_pause()`: bloquea SOLO `iniciarRedencion` (las demás mutators no usan `whenNotPaused`) | `EmergencyPaused`, `Paused` | `EnforcedPause`, `UnauthorizedPauseActor` |
| `unpause()` | `DEFAULT_ADMIN_ROLE` (asimetría ADR-016) | pausado; caller `DEFAULT_ADMIN_ROLE` | `_unpause()` | `EmergencyUnpaused`, `Unpaused` | `AccessControlUnauthorizedAccount`, `ExpectedPause` |

**Heredadas (gestión de roles):** `beginDefaultAdminTransfer`, `acceptDefaultAdminTransfer`, `cancelDefaultAdminTransfer`, `grantRole`, `revokeRole`, `renounceRole`. Admin de `ORACLE_ROLE` y `COMPLIANCE_OFFICER_ROLE` es `DEFAULT_ADMIN_ROLE`. (Las heredadas `changeDefaultAdminDelay`/`rollbackDefaultAdminDelay` existen en el bytecode OZ aunque no estén catalogadas explícitamente en la interfaz — ver GAP-5.)

---

## Sección 4 — Read surface

### 4.1 AssetVault — read surface

| Función | Devuelve | Notas |
|---|---|---|
| `usdc() → IERC20` | address del USDC (immutable) | El backend lo usa para saber a qué USDC transferir antes de `comprar` |
| `identityRegistry() → IIdentityRegistry` | address del IdentityRegistry (immutable) | — |
| `redemptionManager() → address` | address del RM (0 si no seteado) | 0 hasta `setRedemptionManager` |
| `lotes(uint256 loteId) → LoteMiel` | struct completo del lote | Getter explícito sobre `_lotes` privado. Lote inexistente → struct en cero (`productorSRL==0`). Expone TODOS los campos, incluidos `hashFotosApiario` y `tipoCertificadoOrigen` que NO aparecen en evento (ver Sección 5, nota de asimetría) |
| `kgDisponibles(uint256 loteId) → uint256` | kg aún vendibles (redondeo abajo) | FIX H-02: calcula en gramos. 0 si lote no existe o agotado |
| `reservaTecnicaActual(uint256 loteId) → uint256` | reserva técnica USDC no liberada | `reservaTecnicaUSDC - reservaTecnicaLiberada`. No valida existencia (0 para inexistente) |
| `totalSupply(uint256 id) → uint256` | supply del lote `id` | RM-19: override que resuelve diamond inheritance. Consumido por RM vía IAssetVault |
| `totalSupply() → uint256` | supply global (todos los lotes) | Overload sin args de ERC1155Supply |
| `balanceOf(address, uint256) → uint256` | balance de tokens del lote | Estándar ERC-1155. Holdings por wallet |
| `balanceOfBatch(address[], uint256[]) → uint256[]` | balances en batch | Estándar ERC-1155 |
| `exists(uint256 id) → bool` | `totalSupply(id) > 0` | OJO: refleja supply, NO existencia en `_lotes`. Lote creado sin compras → `false` |
| `isApprovedForAll(address, address) → bool` | siempre `false` | `setApprovalForAll` revierte |
| `uri(uint256) → string` | URI base de metadata | Seteada en constructor |
| `paused() → bool` | estado de pausa global | El backend debe chequear antes de `comprar` |
| `hasRole(bytes32, address) → bool` | si tiene rol | Validación off-chain de permisos |
| `getRoleAdmin(bytes32) → bytes32` | rol admin del rol | `DEFAULT_ADMIN_ROLE` para roles del dominio |
| Constantes de rol | `ADMIN_ROLE`, `BACKEND_SIGNER_ROLE`, `COMPLIANCE_OFFICER_ROLE`, `ORACLE_ROLE`, `TREASURY_SRL_ROLE` (bytes32), `DEFAULT_ADMIN_ROLE` (0x00) | Getters auto-generados |
| `MAX_REFUND_BATCH() → uint256` | 100 | Para paginar reembolsos |
| `ADMIN_TRANSFER_DELAY() → uint48` | 3 days (259200) | FIX M-08 |
| `defaultAdmin()`, `pendingDefaultAdmin()`, `defaultAdminDelay()`, `pendingDefaultAdminDelay()`, `defaultAdminDelayIncreaseWait()`, `owner()` | gobernanza admin | `owner()` == `defaultAdmin` (alias IERC5313). Backend monitorea `pendingDefaultAdmin` |
| `supportsInterface(bytes4) → bool` | ERC1155 + ERC165 + AccessControl | FIX M-08 combina ambas cadenas |

### 4.2 IdentityRegistry — read surface

| Función | Devuelve | Notas |
|---|---|---|
| `getTier(address user) → uint8` | tier crudo (0=nunca/revocado, 1-3) | **NO descuenta expiry** — devuelve crudo aunque esté expirado. View NO pausada |
| `isSanctioned(address user) → bool` | flag `sanctioned` | View NO pausada |
| `isFrozen(address user) → bool` | flag `frozen` | View NO pausada |
| `isExpired(address user) → bool` | `expiresAt <= block.timestamp` | Incluye nunca-verificado (`expiresAt=0`). View NO pausada |
| `canMint(address user) → bool` | `tier>=1 && !sanctioned && !frozen && expiresAt > now` | Consumida por `AssetVault._update`. View NO pausada (clave de ADR-013) |
| `canRedeem(address user) → bool` | `tier>=2 && !sanctioned && !frozen && expiresAt > now` | Consumida por `RedemptionManager.iniciarRedencion`. View NO pausada |
| `getJurisdiction(address user) → bytes2` | código ISO 3166-1 alpha-2 | No validado on-chain (ADR-011) |
| `getKYCData(address user) → KYCData` | struct completo `{tier, sanctioned, frozen, jurisdiction, expiresAt, updatedAt, sumsubApplicantHash}` | Único getter que expone `sumsubApplicantHash` y `updatedAt`. View NO pausada |
| Constantes | `BACKEND_SIGNER_ROLE`, `COMPLIANCE_OFFICER_ROLE` (bytes32), `ADMIN_TRANSFER_DELAY` (3 days), `DEFAULT_ADMIN_ROLE` (0x00) | Getters auto-generados |
| `hasRole`, `getRoleAdmin`, `paused`, `defaultAdmin`, `pendingDefaultAdmin`, `defaultAdminDelay`, `pendingDefaultAdminDelay`, `defaultAdminDelayIncreaseWait`, `owner`, `supportsInterface` | gobernanza / estado | Heredadas. Backend monitorea `paused` para alertas |

### 4.3 RedemptionManager — read surface

| Función | Devuelve | Notas |
|---|---|---|
| `getRedencion(uint256 redencionId) → Redencion` | struct `{comprador, loteId, cantidadTokens, datosEnvioHash, estado, dueNumero, hashBLAWB, createdAt, completedAt, cancelReason}` | Inexistente → struct zeroed (`comprador==0`). `estado`: 0=INICIADA,1=EN_EXPORTACION,2=COMPLETADA,3=CANCELADA |
| `getNextRedencionId() → uint256` | próximo `redencionId` | Empieza en 1. Redenciones creadas = `getNextRedencionId()-1`. Backend itera rango `[1, getNextRedencionId())` |
| `availableBalance(address buyer, uint256 loteId) → uint256` | `balanceOf - locked` (0 si locked>balance) | External call (read) a `balanceOf` |
| `tokensLockedFor(address buyer, uint256 loteId) → uint256` | tokens lockeados en redenciones activas | **OJO al orden**: recibe `(buyer, loteId)` pero indexa `_tokensLockedFor[loteId][buyer]`. >0 mientras haya INICIADA/EN_EXPORTACION |
| `assetVault() → IAssetVault` | address AssetVault (immutable) | — |
| `identityRegistry() → IIdentityRegistry` | address IdentityRegistry (immutable) | — |
| Constantes | `ORACLE_ROLE`, `COMPLIANCE_OFFICER_ROLE` (bytes32), `ADMIN_TRANSFER_DELAY` (3 days), `MAX_DUE_NUMERO_LENGTH` (64), `REDENCION_TIMEOUT` (60 days = 5184000), `DEFAULT_ADMIN_ROLE` (0x00) | Getters auto-generados. `ORACLE_ROLE` = `0x68e79a7bf1e0bc45d0a330c573bc367f9cf464fd326078812f301165fbda4ef1` |
| `hasRole`, `getRoleAdmin`, `defaultAdmin`, `pendingDefaultAdmin`, `defaultAdminDelay`, `paused`, `supportsInterface` | gobernanza / estado | Heredadas |

---

## Sección 5 — EVENT CATALOG (sección más importante para el indexer)

> Esta es la base del indexer del backend. Cada evento: params (con indexed flags), transición de estado que señala, frecuencia, función emisora. **Atención a la sección final (GAPS): hay mutaciones de estado que NO emiten evento de dominio — esos son los huecos del indexer.**

### 5.1 AssetVault — eventos

| Evento | Params (indexed = ◆) | Transición / significado | Frecuencia | Emisor |
|---|---|---|---|---|
| `LoteCreado` | `loteId ◆`, `kgEsperados`, `precioPorTokenUSDC`, `productorSRL ◆`, `hashFSA`, `reservaBps` | (inexistente) → PREVENTA | per-lote | `crearLote` |
| `LoteComprado` | `loteId ◆`, `comprador ◆`, `cantidadTokens`, `montoUSDC`, `reservaRetenida`, `paymentRefHash` | PREVENTA (sin cambio de estado; mint + acumula escrow). **El param se llama `montoUSDC`** (recibe `montoUSDCPagado`) | per-compra | `comprar` |
| `CosechaConfirmada` | `loteId ◆`, `kgRealCosechado`, `hashSenasag`, `hashAnalisisLab`, `hashActaCosecha`, `hashCertificadoOrigen` | PREVENTA → COSECHADO. **Asimetría:** `confirmarCosecha` escribe a storage `hashFotosApiario` y `tipoCertificadoOrigen` que NO están en este evento — solo se leen vía `lotes()` | per-lote | `confirmarCosecha` |
| `MontoNetoLiberado` | `loteId ◆`, `monto`, `destinatario ◆` | Acompaña COSECHADO: libera `montoNetoPendiente` al productor (solo si monto>0) | per-lote (condicional) | `confirmarCosecha` |
| `AlmacenamientoConfirmado` | `loteId ◆`, `hashContratoDeposito`, `almacenAutorizado ◆` | COSECHADO → ALMACENADO | per-lote | `confirmarAlmacenamiento` |
| `LoteFallido` | `loteId ◆`, `motivo` | PREVENTA\|COSECHADO → FALLIDO | per-lote (raro) | `marcarFallido` |
| `ReservaTecnicaLiberada` | `loteId ◆`, `monto`, `destinatario ◆` | Sin cambio de LoteEstado; libera reserva al productor (desde COSECHADO+) | per-lote | `liberarReservaTecnica` |
| `ReembolsoEjecutado` | `loteId ◆`, `comprador ◆`, `tokensQuemados`, `usdcDevuelto` | Estado FALLIDO; burn pro-rata + safeTransfer USDC al comprador | per-reembolso (uno por comprador por batch) | `reembolsarLoteFallido` (vía `_refundBuyer`) |
| `EmergencyPaused` | `officer ◆`, `timestamp` | no-pausado → pausado (global) | admin-rare | `pause` |
| `EmergencyUnpaused` | `officer ◆`, `timestamp` | pausado → no-pausado (global) | admin-rare | `unpause` |
| `RedemptionManagerSet` | `redemptionManager ◆` | Cableado one-time del RM (resuelve dependencia circular). Config crítica ahora indexable por logs (ADR-019, resuelve GAP-1) | one-time (al wiring) | `setRedemptionManager` |
| `TokensRedimidos` | `loteId ◆`, `from ◆`, `cantidad`, `kgRedimidosTotal`, `nuevoEstado` | **Señala las transiciones `ALMACENADO → REDENCION_PARCIAL` y `→ AGOTADO`** del lote, expone `kgRedimidos` acumulado, y distingue redención de reembolso. `nuevoEstado` = `LoteEstado` resultante (`REDENCION_PARCIAL`=3 o `AGOTADO`=4). Acompaña al `TransferSingle(to=0)` del burn (ADR-019, resuelve GAP-2) | per-redención | `burnForRedemption` |
| `ReembolsoFinalizado` | `loteId ◆` | Cierre de la paginación del reembolso (`_reembolsado=true`, transición terminal). Emitido en AMBOS paths: `finalizarReembolso` y el branch degenerado `totalSupply==0` de `reembolsarLoteFallido` (ADR-019, resuelve GAP-3 + GAP-4) | per-lote fallido (a lo sumo una) | `finalizarReembolso`, `reembolsarLoteFallido` (branch `totalSupply==0`) |
| `TransferSingle` | `operator ◆`, `from ◆`, `to ◆`, `id`, `value` | ERC-1155. mint: `from=0` (`comprar`). burn: `to=0` (`burnForRedemption`, `reembolsarLoteFallido`). NUNCA `from!=0 && to!=0` (P2P bloqueado). Desde ADR-019, redención y reembolso se distinguen por evento de dominio (`TokensRedimidos` vs `ReembolsoEjecutado`); ya NO hace falta correlacionar por tx (GAP-2 resuelto) | per-compra/redención/reembolso | `comprar`, `burnForRedemption`, `reembolsarLoteFallido` |
| `Paused` / `Unpaused` | `account` | Heredado OZ Pausable. Acompañan EmergencyPaused/Unpaused | admin-rare | `pause` / `unpause` |
| `RoleGranted` / `RoleRevoked` | `role ◆`, `account ◆`, `sender ◆` | Heredado AccessControl. Otorga/revoca rol operacional | admin-rare | `grantRole`/`revokeRole`/`renounceRole`/`acceptDefaultAdminTransfer`/`constructor` |
| `DefaultAdminTransferScheduled` | `newAdmin ◆`, `acceptSchedule` | Inicia transferencia de `DEFAULT_ADMIN_ROLE` con delay 3 días | admin-rare | `beginDefaultAdminTransfer` |
| `DefaultAdminTransferCanceled` | (sin params) | Cancela transferencia pendiente | admin-rare | `cancelDefaultAdminTransfer` |
| `DefaultAdminDelayChangeScheduled` | `newDelay`, `effectSchedule` | Programa cambio del delay | admin-rare | `changeDefaultAdminDelay` |
| `DefaultAdminDelayChangeCanceled` | (sin params) | Cancela cambio de delay pendiente | admin-rare | `rollbackDefaultAdminDelay` |

### 5.2 IdentityRegistry — eventos

| Evento | Params (indexed = ◆) | Transición / significado | Frecuencia | Emisor |
|---|---|---|---|---|
| `KYCUpdated` | `user ◆`, `actor ◆`, `tier`, `expiresAt`, `jurisdiction` | no-registrada → registrada, o re-aprobación. `actor=msg.sender` (FIX M-03, forensics) | per-onboarding (alto volumen; rate >100/h = señal de compromiso, runbook ADR-013) | `setKYC` |
| `KYCRevoked` | `user ◆`, `actor ◆`, `reason` | registrada → revocada (tier=0) | raro | `revokeKYC` |
| `Sanctioned` | `user ◆`, `actor ◆`, `reason`, `evidenceHash`, `timestamp` | (cualquiera) → sancionada. `evidenceHash` mandatorio (FIX M-01) | admin-rare (OFAC SDN match) | `markSanctioned` |
| `Unsanctioned` | `user ◆`, `actor ◆`, `reason` | sancionada → no-sancionada | admin-rare | `unmarkSanctioned` |
| `Frozen` | `user ◆`, `actor ◆`, `regulatoryOrder`, `orderHash` | (cualquiera) → congelada. `orderHash` mandatorio (FIX M-01b) | admin-rare | `freezeAddress` |
| `Unfrozen` | `user ◆`, `actor ◆`, `reason` | congelada → descongelada | admin-rare | `unfreezeAddress` |
| `EmergencyPaused` | `actor ◆`, `timestamp` | no-pausado → pausado (mutators bloqueados; views siguen) | admin-rare / incidente | `pause` |
| `EmergencyUnpaused` | `actor ◆`, `timestamp` | pausado → no-pausado (solo DEFAULT_ADMIN) | admin-rare / post-incidente | `unpause` |
| `Paused` / `Unpaused` | `account` | Heredado OZ Pausable | admin-rare | `pause` / `unpause` |
| `RoleGranted` / `RoleRevoked` | `role ◆`, `account ◆`, `sender ◆` | Heredado AccessControl | admin-rare | `constructor`/`grantRole`/`revokeRole`/`renounceRole`/`acceptDefaultAdminTransfer` |
| `DefaultAdminTransferScheduled` | `newAdmin ◆`, `acceptSchedule` | transferencia admin con delay 3 días (FIX M-08) | admin-rare | `beginDefaultAdminTransfer` |
| `DefaultAdminTransferCanceled` | (sin params) | cancela transferencia pendiente | admin-rare / incidente | `cancelDefaultAdminTransfer` |
| `DefaultAdminDelayChangeScheduled` | `newDelay`, `effectSchedule` | programa cambio de delay | admin-rare | `changeDefaultAdminDelay` |
| `DefaultAdminDelayChangeCanceled` | (sin params) | cancela cambio de delay pendiente | admin-rare | `rollbackDefaultAdminDelay` |

### 5.3 RedemptionManager — eventos

| Evento | Params (indexed = ◆) | Transición / significado | Frecuencia | Emisor |
|---|---|---|---|---|
| `RedencionIniciada` | `redencionId ◆`, `comprador ◆`, `loteId ◆`, `cantidadTokens`, `datosEnvioHash` | (nueva) → INICIADA: crea redención + lock contable | per-redención | `iniciarRedencion` |
| `RedencionEnExportacion` | `redencionId ◆`, `actor ◆`, `dueNumero` | INICIADA → EN_EXPORTACION (DUE registrado, sin burn). `actor`=Safe signer ORACLE (RM-18) | per-redención | `confirmarExportacion` |
| `RedencionCompletada` | `redencionId ◆`, `actor ◆`, `hashBLAWB` | EN_EXPORTACION → COMPLETADA (terminal). Tokens quemados vía `burnForRedemption`. `actor`=Safe signer ORACLE (RM-18) | per-redención | `completarRedencion` |
| `RedencionCancelada` | `redencionId ◆`, `actor ◆`, `reason` | INICIADA\|EN_EXPORTACION → CANCELADA (terminal). Lock liberado, sin burn. `actor`=Oracle/Compliance/buyer-post-timeout | per-redención (a lo sumo una) | `cancelarRedencion` |
| `EmergencyPaused` | `actor ◆`, `timestamp` | pausa el contrato; bloquea solo `iniciarRedencion`. RM-15: custom event ADEMÁS del `Paused` de OZ | admin-rare | `pause` |
| `EmergencyUnpaused` | `actor ◆`, `timestamp` | despausa. Solo DEFAULT_ADMIN | admin-rare | `unpause` |
| `Paused` / `Unpaused` | `account` | Heredado OZ Pausable | admin-rare | `pause` / `unpause` |
| `RoleGranted` / `RoleRevoked` | `role ◆`, `account ◆`, `sender ◆` | Heredado AccessControl. Constructor: ORACLE_ROLE, COMPLIANCE_OFFICER_ROLE x2, DEFAULT_ADMIN_ROLE | admin-rare | `constructor`/`grantRole`/`revokeRole`/`renounceRole`/`acceptDefaultAdminTransfer` |
| `DefaultAdminTransferScheduled` | `newAdmin ◆`, `acceptSchedule` | transferencia admin con delay 3 días | admin-rare | `beginDefaultAdminTransfer` |
| `DefaultAdminTransferCanceled` | (sin params) | cancela transferencia pendiente | admin-rare | `cancelDefaultAdminTransfer` |
| `DefaultAdminDelayChangeScheduled` | `newDelay`, `effectSchedule` | programa cambio de delay | admin-rare | `changeDefaultAdminDelay` |

> El catálogo de eventos heredados OZ de RedemptionManager omite `DefaultAdminDelayChangeCanceled` (emitido por `rollbackDefaultAdminDelay`). Es estándar OZ, no de dominio — ver GAP-5.

---

## Sección 6 — Access-control & roles map + custody

### 6.1 Las 8 claves del deploy (7 roles + deployer)

Derivado de `packages/contracts/script/DeployPlume.s.sol`. En no-local (Plume testnet/mainnet) cada holder se lee de env var; un valor 0 revierte `MissingConfig(<env_var>)`.

| Rol on-chain | Holder lógico | Contratos donde aplica | Env var (deploy) | Custodia mainnet intended | Notas |
|---|---|---|---|---|---|
| `DEFAULT_ADMIN_ROLE` (0x00) | SAFE_ADMIN | AssetVault, IdentityRegistry, RedemptionManager (los 3) | `SAFE_ADMIN_ADDR` | **Safe 2-de-3** (Wyoming) | Delay 3 días para transferencias del propio rol (ADR-012). `unpause` exclusivo (asimetría ADR-016). Setea `setRedemptionManager` (one-time) |
| `ADMIN_ROLE` | SAFE_OPERATOR | AssetVault | `SAFE_OPERATOR_ADDR` | Hardware/Safe | Controla `crearLote` |
| `BACKEND_SIGNER_ROLE` | KMS backend | AssetVault, IdentityRegistry | `BACKEND_SIGNER_ADDR` | **KMS** (AWS/GCP), NO clave privada en env de prod | `comprar` (mint), `setKYC`/`revokeKYC` |
| `COMPLIANCE_OFFICER_ROLE` (titular) | COMPLIANCE | AssetVault, IdentityRegistry, RedemptionManager (los 3) | `COMPLIANCE_ADDR` | Hardware wallet | `pause` (con admin); IdentityRegistry: sanción/freeze; RM: `cancelarRedencion`. NO `unpause` |
| `COMPLIANCE_OFFICER_ROLE` (suplente) | COMPLIANCE_SUPLENTE | los 3 | `COMPLIANCE_SUPLENTE_ADDR` | Hardware wallet | Mismo rol que el titular (dos holders del mismo rol) |
| `ORACLE_ROLE` | ORACLE_SAFE | AssetVault, RedemptionManager | `ORACLE_SAFE_ADDR` | **Safe 2-de-3** | Vault: cosecha/almacenamiento/fallo/reembolsos. RM: confirmar/completar/cancelar redención. NO bloqueado por pause |
| `TREASURY_SRL_ROLE` | TREASURY_SRL | AssetVault | `TREASURY_SRL_ADDR` | Hardware wallet del tesorero | `liberarReservaTecnica` |
| _(deployer / broadcaster)_ | la cuenta que corre `forge script` | — (no es un rol persistente) | clave de deploy | Operacional, efímera | `run()` ejecuta `setRedemptionManager` SOLO si el broadcaster tiene `DEFAULT_ADMIN_ROLE`; si no, queda PENDIENTE de wiring por el Safe |

> **Testnet:** `DeployPlume` permite **EOAs** como holders (perfil local usa addresses fijas `0xA001`…; perfil Plume lee env vars y acepta EOAs). En **mainnet** la intención es Safe 2-de-3 para `SAFE_ADMIN` y `ORACLE_SAFE`, KMS para `BACKEND_SIGNER`, y hardware wallet/Safe para el resto.

> **`RedemptionManager` como "address gateado" (no rol):** `AssetVault.burnForRedemption` solo lo puede llamar `msg.sender == redemptionManager`. No es un rol de AccessControl: es un gate por address, cableado one-time vía `setRedemptionManager`. Es el ÚNICO punto de burn vía RM (Option B).

### 6.2 Asimetría de pause (ADR-016, sistémica en los 3 contratos)

`pause` lo puede disparar `COMPLIANCE_OFFICER_ROLE` **o** `DEFAULT_ADMIN_ROLE` (reacción rápida ante incidente). `unpause` lo puede disparar **solo** `DEFAULT_ADMIN_ROLE` (Safe 2-de-3). Razón: un compliance officer comprometido puede pausar (fail-safe) pero NO puede deshacer una pausa de emergencia.

---

## Sección 7 — Upgradeability

**Los 3 contratos son INMUTABLES, sin proxy (ADR-003).** No hay UUPS/Transparent/Diamond, ni storage gap, ni initializer: usan constructor clásico. Las dependencias (`usdc`, `identityRegistry`, `assetVault`) son `immutable`. El único punto mutable post-deploy es la transferencia de `DEFAULT_ADMIN_ROLE` con delay de 3 días, más el `setRedemptionManager` one-time en AssetVault.

**Implicancia para el address registry del backend:** una address estable = lógica fija. El registry de addresses del backend **NO necesita versionado por upgrade** (no hay upgrades). Solo necesita **versionado por re-deploy**: si se descubre un bug crítico, el playbook es `pause()` + migración a una v2 redeployada (con nuevo ADR), no un proxy upgrade. El backend debe:
- Mapear `{chainId → {contractName → address}}` y tratar cada deploy como una versión inmutable.
- Pinear el deployed runtime bytecode + ABI por address (hoy `[PENDIENTE DEPLOY]`).
- Soportar coexistencia temporal de v1 (pausada) y v2 durante una eventual migración.

---

## Sección 8 — State machines

### 8.1 LoteMiel (`enum LoteEstado`: PREVENTA=0, COSECHADO=1, ALMACENADO=2, REDENCION_PARCIAL=3, AGOTADO=4, FALLIDO=5)

| Desde | Hacia | Trigger | Evento señal |
|---|---|---|---|
| (inexistente) | PREVENTA | `crearLote` | `LoteCreado` |
| PREVENTA | PREVENTA | `comprar` (mint + escrow, sin cambio de estado) | `LoteComprado` (+ `TransferSingle` mint) |
| PREVENTA | COSECHADO | `confirmarCosecha` | `CosechaConfirmada` (+ `MontoNetoLiberado` si monto>0) |
| COSECHADO | ALMACENADO | `confirmarAlmacenamiento` | `AlmacenamientoConfirmado` |
| ALMACENADO | REDENCION_PARCIAL | `burnForRedemption` (1ra redención) | `TokensRedimidos` (`nuevoEstado=REDENCION_PARCIAL`) + `TransferSingle` (burn) — ADR-019, GAP-2 resuelto |
| REDENCION_PARCIAL | REDENCION_PARCIAL | `burnForRedemption` (subsiguientes) | `TokensRedimidos` (`nuevoEstado=REDENCION_PARCIAL`) + `TransferSingle` — ADR-019 |
| REDENCION_PARCIAL | AGOTADO | `burnForRedemption` (`totalSupply==0`) | `TokensRedimidos` (`nuevoEstado=AGOTADO`) + `TransferSingle` — ADR-019 |
| PREVENTA\|COSECHADO | FALLIDO | `marcarFallido` (FIX M-05: NO desde ALMACENADO+) | `LoteFallido` |
| FALLIDO | FALLIDO | `reembolsarLoteFallido` (paginado) + `finalizarReembolso` | `ReembolsoEjecutado` (+ `TransferSingle` burn) / `ReembolsoFinalizado` al cerrar (ADR-019, GAP-4 resuelto; también en branch `totalSupply==0`, GAP-3) |
| COSECHADO\|ALMACENADO\|REDENCION_PARCIAL\|AGOTADO | (sin cambio) | `liberarReservaTecnica` | `ReservaTecnicaLiberada` |

### 8.2 Identidad KYC (`KYCData` en `_kyc[address]`)

| Desde | Hacia | Trigger | Evento señal |
|---|---|---|---|
| NoRegistrada | Registrada | `setKYC` | `KYCUpdated` |
| Registrada | Registrada | `setKYC` (re-aprobación / extensión / cambio tier; preserva sanctioned/frozen) | `KYCUpdated` |
| Registrada | Expirada | paso del tiempo (`block.timestamp >= expiresAt`) | **ninguno — transición implícita** (detectada por `isExpired`/`canMint`/`canRedeem`; NO es mutación, no hay tx → correctamente sin evento) |
| Registrada | Revocada (tier=0) | `revokeKYC` | `KYCRevoked` |
| Revocada\|Expirada | Registrada | `setKYC` (re-onboarding) | `KYCUpdated` |
| (cualquiera) | Sancionada | `markSanctioned` | `Sanctioned` |
| Sancionada | (estado previo sin sanción) | `unmarkSanctioned` | `Unsanctioned` |
| (cualquiera) | Congelada | `freezeAddress` | `Frozen` |
| Congelada | (estado previo sin freeze) | `unfreezeAddress` | `Unfrozen` |
| contrato activo | contrato Pausado | `pause` | `EmergencyPaused` + `Paused` |
| contrato Pausado | contrato activo | `unpause` | `EmergencyUnpaused` + `Unpaused` |

> `sanctioned` y `frozen` son flags ORTOGONALES al tier. Una identidad puede ser Registrada+Sancionada+Congelada a la vez; cualquier flag por sí solo invalida `canMint`/`canRedeem`.

### 8.3 Redención (`EstadoRedencion`: INICIADA=0, EN_EXPORTACION=1, COMPLETADA=2, CANCELADA=3)

| Desde | Hacia | Trigger | Evento señal |
|---|---|---|---|
| (inexistente) | INICIADA | `iniciarRedencion` | `RedencionIniciada` |
| INICIADA | EN_EXPORTACION | `confirmarExportacion` | `RedencionEnExportacion` |
| EN_EXPORTACION | COMPLETADA | `completarRedencion` (decrementa lock + burn vía `burnForRedemption`) | `RedencionCompletada` |
| INICIADA\|EN_EXPORTACION | CANCELADA | `cancelarRedencion` (libera lock, sin burn; ADR-017 permite desde EN_EXPORTACION) | `RedencionCancelada` |
| COMPLETADA / CANCELADA | (terminal) | cualquier trigger revierte | — |

---

## Sección 9 — Authority boundary (on-chain vs off-chain)

Por comportamiento, qué lado es autoritativo:

| Comportamiento | Autoridad | Detalle |
|---|---|---|
| **Allowlist de inversores / enforcement KYC** | **ON-CHAIN** | El allowlist se enforcea on-chain por `IdentityRegistry` + el check de KYC en `comprar`/mint (`AssetVault._update` llama `canMint`), y en redención (`iniciarRedencion` llama `canRedeem`). **NO lo enforcea el backend en tiempo de transferencia.** Aunque el backend tenga `BACKEND_SIGNER_ROLE`, si el destinatario no pasa `canMint`, el mint revierte `NotKYCVerified` en `_update`. El backend es la fuente de los datos KYC (sincroniza desde Sumsub), pero la PUERTA es on-chain |
| **Validación de jurisdicción (ISO 3166-1)** | **OFF-CHAIN** | ADR-011: el campo `jurisdiction: bytes2` se acepta sin validar contra ISO on-chain. El backend valida la jurisdicción ANTES de llamar `setKYC` (lista ISO en código del backend). On-chain `jurisdiction` es metadata para dashboards/compliance, NO un gate |
| **Decisión de reembolso a address con KYC revocado** | **ON-CHAIN (gate) + OFF-CHAIN (recuperación)** | ADR-014: `reembolsarLoteFallido` chequea `getTier(buyer) > 0` además de `!isSanctioned`/`!isFrozen`. Si `tier==0` (revocado), el reembolso on-chain se BLOQUEA (`CannotRefundRevokedAddress`); la recuperación procede off-chain con supervisión de compliance. Evita un breach AML automático |
| **Pago de USDC (recepción)** | **OFF-CHAIN antes, ON-CHAIN custodia después** | El backend transfiere el USDC al contrato ANTES de `comprar`; `comprar` NO hace `transferFrom`. Una vez recibido, el escrow vive on-chain en AssetVault |
| **Confirmación de hitos físicos (cosecha, almacenamiento, export, BL/AWB, DUE)** | **OFF-CHAIN (decisión) → ON-CHAIN (attestation)** | El `ORACLE_ROLE` (Safe 2-de-3) verifica documentos off-chain y attesta on-chain con hashes. El contrato NO valida la veracidad del documento, solo que el hash no sea cero (`DocumentHashes.isValid`) |
| **Autocancelación de redención por timeout** | **ON-CHAIN** | ADR-015: el comprador puede self-cancelar tras `REDENCION_TIMEOUT` (60 días) sin intervención del oracle (escape valve si el Safe desaparece) |

---

## Sección 10 — External dependencies

| Dependencia | Tipo | Estado | Notas |
|---|---|---|---|
| **USDC** (`IERC20`, Circle, 6 decimales) | ERC-20 externo, `immutable` en AssetVault | address por red `[PENDIENTE DEPLOY]` (env `USDC_ADDR`; en Anvil se deploya `MockUSDC`) | Escrow total. AssetVault recibe USDC del backend ANTES de `comprar` (NO `transferFrom`). Salidas `safeTransfer`: `confirmarCosecha` (neto al productor), `liberarReservaTecnica` (reserva al productor), `reembolsarLoteFallido` (pro-rata). El contrato debe tener liquidez USDC suficiente (CONFLICT-4). **RedemptionManager NO toca USDC** |
| **IdentityRegistry** (inter-contrato) | contrato propio del MVP, `immutable` referencia en AssetVault y RedemptionManager | code-frozen, NO deployado | Relación unidireccional vault/redemption → registry. AssetVault llama `canMint`, `isSanctioned`, `isFrozen`, `getTier`. RedemptionManager llama `canRedeem`. IdentityRegistry NO importa a los consumidores |
| **RedemptionManager** (inter-contrato) | contrato propio del MVP, address `mutable one-time` en AssetVault | code-frozen, NO deployado | Dependencia circular resuelta por orden de deploy + `setRedemptionManager` post-deploy (D3, Opción B). Único autorizado a `burnForRedemption` |
| **Plume Network** | red de deploy (L2 EVM RWA) | testnet chainId `98867`, mainnet chainId `98866` (Anvil `31337`) | Red primaria. **El adapter `Plume Arc` (KYC bridge nativo) NO está implementado aún** — el MVP usa el `IdentityRegistry` custom como fuente de verdad KYC |
| **OpenZeppelin v5** | librería base | — | ERC1155(+Supply+Pausable), AccessControlDefaultAdminRules, ReentrancyGuard, Pausable, SafeERC20 |
| **Libraries internas** (`ComplianceConstants`, `DocumentHashes`, `QualityRules`) | libraries `internal pure`/`constant` | inlinadas en compile-time | Sin address propia. `QualityRules.isMonofloralCertified` y las constantes de polen/labs son código preparado pero NO usado en MVP |
| **LabRegistry / QualityAttestation** | contratos de calidad | **DEFERIDOS a fase 2 (ADR-010)** | NO existen en el MVP. NO hay paso `QUALITY_ATTESTED` en el lifecycle. Constantes `MIN_POLLEN_PERCENTAGE_MONOFLORAL`, `MIN_LABS_PARA_ATTESTATION` reservadas |
| **Chainlink PoR** | oracle de reservas | **fase futura** | No integrado en estos 3 contratos del MVP |

---

## Matriz source-of-truth

Para cada dato del sistema: lado autoritativo (on-chain) vs qué guarda el backend.

| Dato | Lado autoritativo (on-chain) | Qué guarda el backend |
|---|---|---|
| **Balances / holdings de tokens** | AssetVault ERC-1155 (`balanceOf`, `totalSupply`) | Índice/cache de holdings por wallet, reconstruido desde `TransferSingle` (mint `from=0`, burn `to=0`). El backend NUNCA es la fuente: ante divergencia, gana la cadena |
| **Allowlist + KYC** | IdentityRegistry (`canMint`, `canRedeem`, `getTier`, flags). Enforcement en mint/redención | Cache del estado KYC + el dato fuente off-chain (Sumsub applicant). El backend ES el origen del dato (sincroniza vía `setKYC`), pero el ENFORCEMENT es on-chain. La jurisdicción la valida el backend (ADR-011) |
| **Registro de lotes / asset** | AssetVault (`lotes(loteId)`, `LoteEstado`) | Índice de lotes reconstruido desde `LoteCreado`/`CosechaConfirmada`/`AlmacenamientoConfirmado`/`LoteFallido` + lecturas de `lotes()`. **OJO:** `hashFotosApiario` y `tipoCertificadoOrigen` NO están en eventos → requieren leer `lotes()` (no se pueden indexar solo por logs) |
| **Estado de redención** | RedemptionManager (`getRedencion`, `EstadoRedencion`, `tokensLockedFor`) | Índice reconstruido desde `RedencionIniciada`/`RedencionEnExportacion`/`RedencionCompletada`/`RedencionCancelada`. Evidencia de envío (datos de shipping, DUE, BL/AWB) off-chain; on-chain solo los hashes |
| **Custodia de USDC en escrow** | AssetVault (saldo USDC del contrato + `reservaTecnicaUSDC`/`montoNetoPendiente`/`reservaTecnicaLiberada` por lote) | Contabilidad espejo reconstruida desde `LoteComprado` (`reservaRetenida`, `montoUSDC`), `MontoNetoLiberado`, `ReservaTecnicaLiberada`, `ReembolsoEjecutado`. La custodia real es on-chain; el backend audita/concilia |

**Filas de source-of-truth: 5.**

---

## Sección final — GAPS & PREGUNTAS ABIERTAS

> Consolidación de TODOS los `missingEvents` y correcciones reportados por la verificación adversarial. **IdentityRegistry y RedemptionManager: verdict CONFIRMED (cero huecos materiales). AssetVault: los 4 gaps de indexabilidad (GAP-1/2/3/4) quedaron RESUELTOS pre-deploy por ADR-019** (3 eventos de dominio agregados; ABI 23 → 26 eventos). Libraries: confirmed (sin eventos por naturaleza). Quedan pendientes sólo correcciones menores no bloqueantes.

### GAPS de indexabilidad — RESUELTOS (ADR-019)

> Los 4 gaps de mutaciones de estado sin evento de dominio en `AssetVault` se resolvieron ANTES del deploy (aprovechando que el contrato aún no es inmutable-en-producción) agregando 3 eventos. Ver `docs/architecture/ADR-019-domain-events-observability.md`.

- **GAP-1 (HIGH) — `AssetVault.setRedemptionManager` no emitía evento.** ✅ RESUELTO con `RedemptionManagerSet(address indexed redemptionManager)`. El cableado one-time del RM ahora es indexable por logs.
- **GAP-2 (HIGH) — `AssetVault.burnForRedemption` no emitía evento de dominio.** ✅ RESUELTO con `TokensRedimidos(loteId◆, from◆, cantidad, kgRedimidosTotal, nuevoEstado)`. Señala las transiciones `ALMACENADO → REDENCION_PARCIAL → AGOTADO`, expone `kgRedimidos` acumulado, y distingue redención de reembolso. El indexer ya NO necesita correlacionar `TransferSingle(to=0)` por tx contra `RedencionCompletada`/`ReembolsoEjecutado`.
- **GAP-3 (MEDIUM) — `reembolsarLoteFallido` caso `totalSupply==0` sin evento.** ✅ RESUELTO con `ReembolsoFinalizado(uint256 indexed loteId)` emitido en el branch degenerado. La mutación terminal ya no es silenciosa.
- **GAP-4 (MEDIUM) — `finalizarReembolso` no emitía evento.** ✅ RESUELTO con `ReembolsoFinalizado(uint256 indexed loteId)`. El cierre de la paginación del reembolso ahora es visible por logs (mismo evento que GAP-3, emitido desde ambos paths).

### Correcciones / matices de superficie (PENDIENTES — no bloqueantes)

- **GAP-5 (LOW) — catálogo de eventos heredados OZ incompleto en RedemptionManager.** La interfaz lista `DefaultAdminDelayChangeScheduled` pero OMITE `DefaultAdminDelayChangeCanceled`; faltan también `changeDefaultAdminDelay()`/`rollbackDefaultAdminDelay()` en el writeSurface catalogado. Son funciones/eventos estándar OZ que SÍ están en el bytecode y en el ABI — no afectan el flujo de negocio ni la indexación de redenciones, pero el backend debe tomarlos del ABI, no de la prosa. _Severidad: low._
- **Asimetría storage-vs-evento en `CosechaConfirmada` (informativo, NO defecto).** `confirmarCosecha` escribe `hashFotosApiario` y `tipoCertificadoOrigen` a storage, pero esos dos campos NO están en el evento. No se pueden indexar por logs; hay que leerlos vía `lotes()`. Ya reflejado en la matriz source-of-truth.
- **Discrepancia de NatSpec en `IRedemptionManager` (informativo, NO afecta ABI).** El NatSpec del param `actor` de `RedencionCancelada`/`EmergencyPaused`/`EmergencyUnpaused` describe los actores de forma imprecisa (dice solo ORACLE/COMPLIANCE cuando puede ser buyer-post-timeout o solo DEFAULT_ADMIN). Este documento describe los actores CORRECTAMENTE. Bug de doc en el código fuente, no del ABI ni de los indexed flags.

### Confirmaciones explícitas (donde verify NO encontró huecos)

- **IdentityRegistry: CONFIRMED, cero huecos.** Toda mutación de storage emite evento (verificado función por función). Indexed flags exactos. Access control correcto. Superficie completa. El backend puede reconstruir TODO el estado KYC desde eventos.
- **RedemptionManager: CONFIRMED, cero huecos materiales.** Toda mutación emite evento. El backend puede reconstruir el estado completo de cada `Redencion` desde los 4 eventos de dominio. Único matiz: GAP-5 (eventos/funciones OZ heredados, no de dominio).
- **Libraries: CONFIRMED.** Son `internal pure`/`constant`, sin estado: cero eventos por naturaleza, no es un hueco.

### Preguntas abiertas

1. **GAP-2 / decisión de indexer:** ✅ RESUELTA por ADR-019 — se agregó el evento de dominio `TokensRedimidos` a `burnForRedemption` ANTES del deploy (no fue redeploy: el contrato aún no estaba deployado). El indexer ya NO necesita correlacionar por tx-hash.
2. **GAP-1:** ✅ RESUELTA por ADR-019 — `setRedemptionManager` ahora emite `RedemptionManagerSet`; el wiring del RM es indexable por logs (sin perjuicio de capturarlo también en el artefacto de deploy).
3. **GAP-3/GAP-4:** ✅ RESUELTA por ADR-019 — ambas mutaciones terminales emiten `ReembolsoFinalizado`; no hay que compensar con lecturas de estado periódicas.
4. **Fecha de release** de esta CIS v1 quedó `undefined`: ¿se sella al congelar el deploy (tag `v0.1.0-audit`) o antes?
5. **Pin de bytecode + addresses:** todos `[PENDIENTE DEPLOY]`. El backend NO puede generar bindings finales pinneados hasta tener el deploy real en Plume.
