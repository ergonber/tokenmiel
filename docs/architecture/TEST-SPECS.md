# Test Specifications (Foundry) — Smart Contracts

> Specs exhaustivas de tests Foundry siguiendo TDD (Red-Green-Refactor). Refleja la suite **real** al
> 2026-05-29 y sirve como referencia para nuevos contratos o refactors.
>
> **v2.1 — reconciliación con código real (2026-05-29):**
> - Suite real: **216 tests** (sin invariants) = 100% branch coverage en los 3 contratos MVP.
> - LabRegistry y QualityAttestation marcados como **FASE 2** (ADR-010).
> - Refleja ADR-017 (3-state export machine), ADR-016 (pause asymmetry), ADR-015 (cancellation timeout),
>   FIX M-08 (AccessControlDefaultAdminRules), FIX H-01 (escrow total), Opción B (lock accumulator).
> - Invariant suite existe pero se excluye de runs de coverage (OOM; RM-29 pendiente).

---

## 1. Convenciones globales

### 1.1 Coverage no negociable

- **Líneas:** 100%
- **Branches:** 100%
- **Funciones:** 100%
- **Fuzz runs:** ≥ 10,000 por test fuzz
- **Invariant runs:** ≥ 50,000, depth 100 (suite existe pero se excluye del CI de coverage por OOM — RM-29 pendiente)

### 1.2 Naming

```
test_<context>_<scenario>_<expectedOutcome>()
testFuzz_<context>_<property>(<params>)
invariant_<property>()
test_RevertWhen_<context>_<scenario>()
```

### 1.3 Estructura básica (Arrange-Act-Assert)

```solidity
function test_<context>_<scenario>_<outcome>() public {
    // Arrange
    _setupSomething();

    // Act
    vm.prank(actor);
    contractInstance.someFunction(args);

    // Assert
    assertEq(state, expectedValue);
    // ... más assertions
}
```

### 1.4 Setup helpers compartidos

**`BaseTest.t.sol`** — setup compartido para los **3 contratos MVP**. Despliega sin LabRegistry (FASE 2).

Incluye:
- Deploy de `IdentityRegistry`, `AssetVault`, `RedemptionManager` y `MockUSDC` (6 decimales)
- `setRedemptionManager()` post-deploy para romper el ciclo de dependencias
- Funciones helper:
  - `_setupKYC(address user, uint8 tier)` / `_setupKYC(address user, uint8 tier, bytes2 jurisdiction)`
  - `_createLoteDefault()` — crea lote con parámetros estándar
  - `_comprarTokens(address buyer, uint8 tier, uint256 cantidadTokens)` — mintea USDC, compra
  - `_confirmarCosechaDefault()` — oracle confirma cosecha
  - `_confirmarAlmacenamientoDefault()` — oracle confirma almacenamiento
  - `_advanceToAlmacenado()` — avanza lote hasta `ALMACENADO` (sin paso de QualityAttestation)

> **Nota MVP:** `_seedLabs()` y `_buildQualityAttestation()` son helpers de FASE 2 (no existen en BaseTest actual).

### 1.5 Direcciones de actores estándar

```solidity
address constant ADMIN                    = address(0xA001);
address constant ADMIN_OPERATOR           = address(0xA002);
address constant ORACLE_SIGNER_1          = address(0xB001);
address constant ORACLE_SIGNER_2          = address(0xB002);
address constant ORACLE_SIGNER_3          = address(0xB003);
address constant ORACLE_SAFE              = address(0xB000);
address constant BACKEND_SIGNER           = address(0xC001);
address constant COMPLIANCE_OFFICER       = address(0xD001);
address constant COMPLIANCE_OFFICER_SUPLENTE = address(0xD002);
address constant TREASURY_SRL             = address(0xE001);
address constant ALMACEN_AUTORIZADO       = address(0xE002);
address constant BUYER_1                  = address(0x1001);
address constant BUYER_2                  = address(0x1002);
address constant BUYER_SANCTIONED         = address(0x1003);
address constant BUYER_FROZEN             = address(0x1004);
address constant NON_KYC                  = address(0x1005);
// FASE 2:
// address constant LAB_BOLIVIA           = address(0xF001);  // IBNORCA mock
// address constant LAB_EUROPA            = address(0xF002);  // Eurofins mock
```

---

## 2. Inventario real de tests (216 total)

| Archivo | Tests | Notas |
|---|---|---|
| `test/unit/AssetVault.t.sol` | 45 | Incluye 1 fuzz |
| `test/unit/IdentityRegistry.t.sol` | 33 | Incluye 1 fuzz |
| `test/unit/RedemptionManager.t.sol` | 71 | Incluye 1 fuzz, ADR-015/016/017 |
| `test/unit/AssetVaultBranches.t.sol` | 44 | Branch coverage 100% |
| `test/unit/IdentityRegistryBranches.t.sol` | 13 | Branch coverage 100% |
| `test/integration/Lifecycle.t.sol` | 5 | E2E cross-contract |
| `test/integration/DeployPlume.t.sol` | 5 | Deploy orchestrator |
| **Total** | **216** | **100% branch coverage (3 contratos MVP)** |

**Suite de invariants:** existe pero se excluye del CI de coverage (OOM — RM-29 pendiente).

---

## 3. Tests por contrato

### 3.1 `AssetVault.sol` — 45 tests unit + 44 branch = 89 total

#### 3.1.1 Constructor / initialization (`FIX M-08`)

Archivo: `AssetVault.t.sol`

- `test_constructor_SetsAllRoles_Correctly()` — verifica `defaultAdmin()`, todos los roles, delay 3 días

Archivo: `AssetVaultBranches.t.sol` (branch coverage del constructor)

- `test_RevertWhen_Constructor_AdminOperatorZero()`
- `test_RevertWhen_Constructor_BackendSignerZero()`
- `test_RevertWhen_Constructor_ComplianceOfficerZero()`
- `test_RevertWhen_Constructor_ComplianceOfficerSuplenteZero()`
- `test_RevertWhen_Constructor_OracleSafeZero()`
- `test_RevertWhen_Constructor_TreasurySRLZero()`
- `test_RevertWhen_Constructor_UsdcZero()`
- `test_RevertWhen_Constructor_IdentityRegistryZero()`
- `test_RevertWhen_SetRedemptionManager_ZeroAddress()`
- `test_RevertWhen_SetRedemptionManager_AlreadySet()`

#### 3.1.2 `crearLote()` — solo `ADMIN_ROLE`

Archivo: `AssetVault.t.sol`

- `test_crearLote_HappyPath_CreatesLoteInPreventa()` — verifica estado, kgEsperados, precio, escrow 0
- `test_crearLote_OnlyAdmin_RevertWhen_NonAdmin()` — `BACKEND_SIGNER` falla
- `test_crearLote_RevertWhen_ReservaBpsBelowMin()` — `reservaBps < 1500` → `ReservaBpsOutOfRange`
- `test_crearLote_RevertWhen_ReservaBpsAboveMax()` — `reservaBps > 2000` → `ReservaBpsOutOfRange`
- `test_crearLote_RevertWhen_LoteIdAlreadyExists()` — `LoteAlreadyExists`
- `test_crearLote_RevertWhen_HashFSAZero()` — `InvalidHash`
- `test_crearLote_EmitsLoteCreadoEvent()`

Archivo: `AssetVaultBranches.t.sol`

- `test_RevertWhen_CrearLote_KgEsperadosZero()` — `InvalidKgEsperados`
- `test_RevertWhen_CrearLote_PrecioZero()` — `InvalidPrecio`
- `test_RevertWhen_CrearLote_ProductorSRLZero()` — `ZeroAddress`

#### 3.1.3 `comprar()` — solo `BACKEND_SIGNER_ROLE`

Modelo: **Escrow total (FIX H-01 Opción A)**. El USDC queda en el contrato en PREVENTA; el productor recibe el monto neto solo en `confirmarCosecha()`. La reserva técnica queda en el contrato hasta `liberarReservaTecnica()`.

Archivo: `AssetVault.t.sol`

- `test_comprar_HappyPath_MintsCorrectAmount()` — balance correcto post-compra
- `test_comprar_EscrowTotal_USDCStaysInContract()` — `FIX H-01`: productor NO recibe USDC en `comprar()`
- `test_comprar_EscrowTotal_TracksMontoNetoPendiente()` — reserva y monto neto contabilizados
- `test_comprar_RevertWhen_NoKYC()` — `NotKYCVerified`
- `test_comprar_RevertWhen_Sanctioned()` — `NotKYCVerified`
- `test_comprar_RevertWhen_KgExcedeSupplyDisponible()` — `KgSolicitadosExcedenSupply` (`FIX H-02`: validación en gramos)
- `test_comprar_AllowsExactCapacity()` — 200 tokens × 500 g = 100 kg exactos
- `test_comprar_RevertWhen_MontoUSDCInsuficiente()` — `MontoUSDCInsuficiente`
- `test_comprar_RevertWhen_LoteNotInPreventa()` — `LoteNotInPreventa`
- `test_comprar_RevertWhen_Paused()`

Archivo: `AssetVaultBranches.t.sol`

- `test_RevertWhen_Comprar_LoteNotExists()` — `LoteNotExists`
- `test_RevertWhen_Comprar_CantidadTokensCero()` — `CantidadTokensCero`
- `test_RevertWhen_Comprar_InvalidPaymentRefHash()` — `InvalidHash`

#### 3.1.4 `_update()` override — bloqueo de transfers P2P

Archivo: `AssetVault.t.sol`

- `test_transfer_RevertWhen_P2PBetweenUsers()` — `TransferP2PNoPermitido` (via `safeTransferFrom`)
- `test_setApprovalForAll_RevertWhen_AnyCall()` — `TransferP2PNoPermitido`

Archivo: `AssetVaultBranches.t.sol`

- `test_RevertWhen_BurnForRedemption_RedemptionManagerNotSet()` — `RedemptionManagerNotSet`
- `test_RevertWhen_BurnForRedemption_OnlyRedemptionCanBurn()` — `OnlyRedemptionCanBurn`
- `test_RevertWhen_BurnForRedemption_CantidadTokensCero()` — `CantidadTokensCero` (caller = RM)

#### 3.1.5 `confirmarCosecha()` — solo `ORACLE_ROLE`

Libera `montoNetoPendiente` al productor (`FIX H-01` escrow release).

Archivo: `AssetVault.t.sol`

- `test_confirmarCosecha_HappyPath_TransitionsToCosechado()` — estado + `kgCosechadosReal`
- `test_confirmarCosecha_ReleasesMontoNetoToProductor()` — `FIX H-01`: productor recibe monto neto
- `test_confirmarCosecha_OnlyOracle_RevertWhen_NonOracle()`
- `test_confirmarCosecha_RevertWhen_LoteNotInPreventa()` — `LoteNotInPreventa`

Archivo: `AssetVaultBranches.t.sol`

- `test_RevertWhen_ConfirmarCosecha_LoteNotExists()` — `LoteNotExists`
- `test_RevertWhen_ConfirmarCosecha_KgRealZero()` — `InvalidKgEsperados`
- `test_RevertWhen_ConfirmarCosecha_HashSenasagInvalid()` — `InvalidHash`
- `test_RevertWhen_ConfirmarCosecha_HashAnalisisLabInvalid()` — `InvalidHash`
- `test_RevertWhen_ConfirmarCosecha_HashActaCosechaInvalid()` — `InvalidHash`
- `test_RevertWhen_ConfirmarCosecha_HashFotosApiarioInvalid()` — `InvalidHash`
- `test_RevertWhen_ConfirmarCosecha_HashCertificadoOrigenInvalid()` — `InvalidHash`

> **[FASE 2]** `confirmarCalidad()` / estado `QUALITY_ATTESTED` / `QualityAttestation` — ver sección 6.

#### 3.1.6 `confirmarAlmacenamiento()` — solo `ORACLE_ROLE`

Transición **MVP**: `COSECHADO → ALMACENADO` directo (sin paso intermedio `QUALITY_ATTESTED`).

Archivo: `AssetVault.t.sol`

- `test_confirmarAlmacenamiento_HappyPath_TransitionsToAlmacenado()`
- `test_confirmarAlmacenamiento_RevertWhen_LoteNotInCosechado()` — `LoteNotInCosechado`

Archivo: `AssetVaultBranches.t.sol`

- `test_RevertWhen_ConfirmarAlmacenamiento_LoteNotExists()` — `LoteNotExists`
- `test_RevertWhen_ConfirmarAlmacenamiento_HashDepositoInvalid()` — `InvalidHash`
- `test_RevertWhen_ConfirmarAlmacenamiento_AlmacenZero()` — `ZeroAddress`

#### 3.1.7 `marcarFallido()` — solo `ORACLE_ROLE`

`FIX M-05`: solo permitido desde `PREVENTA` y `COSECHADO` (no desde `ALMACENADO` ni `AGOTADO`).

Archivo: `AssetVault.t.sol`

- `test_marcarFallido_FromPreventa_Allowed()` — transiciona a `FALLIDO`, guarda motivo
- `test_marcarFallido_FromCosechado_Allowed()`
- `test_marcarFallido_RevertWhen_FromAlmacenado()` — `CannotFailLoteInThisState`
- `test_marcarFallido_RevertWhen_AlreadyFallido()` — `CannotFailLoteInThisState`

Archivo: `AssetVaultBranches.t.sol`

- `test_RevertWhen_MarcarFallido_LoteNotExists()` — `LoteNotExists`
- `test_RevertWhen_MarcarFallido_EmptyMotivo()` — `EmptyMotivo`

#### 3.1.8 `reembolsarLoteFallido()` — solo `ORACLE_ROLE`

Modelo: **escrow total = reembolso 100%** (`FIX H-01`). Batch limitado a `MAX_REFUND_BATCH = 100`.

Archivo: `AssetVault.t.sol`

- `test_reembolsarLoteFallido_PreCosecha_Refunds100Percent()` — `FIX H-01`: reembolso = pago original
- `test_reembolsarLoteFallido_RevertWhen_LoteNotFallido()` — `LoteNotInFallido`
- `test_reembolsarLoteFallido_RevertWhen_BuyerSanctioned()` — `CannotRefundBlockedAddress`
- `test_reembolsarLoteFallido_RevertWhen_BuyerRevoked()` — `CannotRefundRevokedAddress` (KYC revocado post-compra)
- `test_reembolsarLoteFallido_RevertWhen_BatchTooLarge()` — `BatchTooLarge` (> 100 entries)

Archivo: `AssetVaultBranches.t.sol`

- `test_RevertWhen_ReembolsarLoteFallido_LoteNotExists()` — `LoteNotExists`
- `test_RevertWhen_ReembolsarLoteFallido_ReembolsoYaEjecutado()` — `ReembolsoYaEjecutado` (post-`finalizarReembolso`)
- `test_RevertWhen_ReembolsarLoteFallido_EmptyBuyers()` — `EmptyBuyers`
- `test_ReembolsarLoteFallido_EarlyReturn_WhenTotalSupplyZero()` — early-return, sets `_reembolsado = true`
- `test_ReembolsarLoteFallido_SkipBuyer_BalanceZero()` — `continue` cuando buyer tiene balance 0
- `test_RevertWhen_ReembolsarLoteFallido_FrozenBuyerWithBalance()` — `CannotRefundBlockedAddress`
- `test_RevertWhen_FinalizarReembolso_LoteNotExists()` — `LoteNotExists`
- `test_RevertWhen_FinalizarReembolso_LoteNotInFallido()` — `LoteNotInFallido`
- `test_RevertWhen_FinalizarReembolso_ReembolsoYaEjecutado()` — doble `finalizarReembolso`

#### 3.1.9 `liberarReservaTecnica()` — solo `TREASURY_SRL_ROLE`

Disponible desde `COSECHADO` (`CONFLICT-1 Opción A`).

Archivo: `AssetVault.t.sol`

- `test_liberarReservaTecnica_HappyPath_TransfersUSDCToProductor()` — transfiere reserva, la pone a 0
- `test_liberarReservaTecnica_RevertWhen_Preventa()` — `LoteNotInCosechado`
- `test_liberarReservaTecnica_RevertWhen_AlreadyReleased()` — `ReservaAlreadyReleased`

Archivo: `AssetVaultBranches.t.sol`

- `test_RevertWhen_LiberarReservaTecnica_LoteNotExists()` — `LoteNotExists`

#### 3.1.10 `pause()` / `unpause()` — asimetría `ADR-016`

Regla: `pause()` = `COMPLIANCE_OFFICER_ROLE` OR `DEFAULT_ADMIN_ROLE`; `unpause()` = `DEFAULT_ADMIN_ROLE` únicamente.

Archivo: `AssetVault.t.sol`

- `test_pause_ByComplianceOfficer_HappyPath()`
- `test_pause_ByDefaultAdmin_HappyPath()`
- `test_pause_RevertWhen_UnauthorizedActor()` — `UnauthorizedPauseActor`
- `test_unpause_RestoresComprar()` — solo `ADMIN` puede despausar; `comprar()` funciona post-unpause
- `test_unpause_RevertWhen_ComplianceOfficer()` — `COMPLIANCE_OFFICER` no puede despausar
- `test_unpause_RevertWhen_NonDefaultAdmin()`

#### 3.1.11 View functions

Archivo: `AssetVault.t.sol`

- `test_kgDisponibles_ReturnsCorrectAmount()` — antes y después de `comprar()`

Archivo: `AssetVaultBranches.t.sol`

- `test_KgDisponibles_ReturnsZero_WhenLoteNotExists()`
- `test_SupportsInterface_ERC165_ReturnsTrue()`
- `test_SupportsInterface_InvalidId_ReturnsFalse()`

---

### 3.2 `IdentityRegistry.sol` — 33 tests unit + 13 branch = 46 total

#### 3.2.1 Constructor (`FIX M-08`)

Archivo: `IdentityRegistry.t.sol`

- `test_constructor_SetsAllRoles_Correctly()` — `defaultAdmin()`, `BACKEND_SIGNER_ROLE`, `COMPLIANCE_OFFICER_ROLE`, delay 3 días

Archivo: `IdentityRegistryBranches.t.sol`

- `test_RevertWhen_Constructor_BackendSignerZero()` — `ZeroAddressUser`
- `test_RevertWhen_Constructor_ComplianceOfficerZero()` — `ZeroAddressUser`
- `test_RevertWhen_Constructor_ComplianceSuplenteZero()` — `ZeroAddressUser`

#### 3.2.2 `setKYC()` — solo `BACKEND_SIGNER_ROLE`

Archivo: `IdentityRegistry.t.sol`

- `test_setKYC_HappyPath_StoresKYCData()` — tier, jurisdiction, `canMint() = true`
- `test_setKYC_OnlyBackendSigner_RevertWhen_NonBackend()` — `ADMIN` falla
- `test_setKYC_RevertWhen_TierAboveMax()` — tier 4 → `InvalidTier`
- `test_setKYC_RevertWhen_ExpiryInPast()` — `ExpiryInPast`
- `test_setKYC_RevertWhen_ZeroAddress()` — `ZeroAddressUser`
- `test_setKYC_EmitsKYCUpdatedEvent()` — `FIX M-03`: evento incluye `msg.sender` indexed
- `test_setKYC_RevertWhen_TierZero()` — `FIX M-04`: tier 0 → `TierZeroNotAllowed`
- `testFuzz_setKYC_RoundtripData(uint8 tier, uint64 expiry, bytes2 jurisdiction)`

#### 3.2.3 `markSanctioned()` / `unmarkSanctioned()` — solo `COMPLIANCE_OFFICER_ROLE`

Archivo: `IdentityRegistry.t.sol`

- `test_markSanctioned_HappyPath_BlocksCanMint()` — `isSanctioned() = true`, `canMint() = false`
- `test_markSanctioned_OnlyOfficer_RevertWhen_NonOfficer()`
- `test_markSanctioned_RevertWhen_EvidenceHashZero()` — `FIX M-01`: `InvalidEvidenceHash`
- `test_markSanctioned_RevertWhen_AlreadySanctioned()` — `AlreadySanctioned`
- `test_markSanctioned_RevertWhen_EmptyReason()` — `EmptyReason`
- `test_unmarkSanctioned_RestoresCanMint()`
- `test_unmarkSanctioned_RevertWhen_NotSanctioned()` — `NotSanctioned`

Archivo: `IdentityRegistryBranches.t.sol`

- `test_RevertWhen_MarkSanctioned_UserZero()` — `ZeroAddressUser`
- `test_RevertWhen_UnmarkSanctioned_UserZero()` — `ZeroAddressUser`
- `test_RevertWhen_UnmarkSanctioned_EmptyReason()` — `EmptyReason`

#### 3.2.4 `freezeAddress()` / `unfreezeAddress()` — solo `COMPLIANCE_OFFICER_ROLE`

Archivo: `IdentityRegistry.t.sol`

- `test_freezeAddress_HappyPath_BlocksCanMintAndCanRedeem()` — `isFrozen() = true`, ambas views = false
- `test_freezeAddress_RevertWhen_AlreadyFrozen()` — `AlreadyFrozen`
- `test_freezeAddress_RevertWhen_OrderHashZero()` — `FIX M-01b`: `InvalidOrderHash`
- `test_unfreezeAddress_Restores()` — `canRedeem()` vuelve a `true`

Archivo: `IdentityRegistryBranches.t.sol`

- `test_RevertWhen_FreezeAddress_UserZero()` — `ZeroAddressUser`
- `test_RevertWhen_FreezeAddress_EmptyOrder()` — `EmptyReason`
- `test_RevertWhen_UnfreezeAddress_UserZero()` — `ZeroAddressUser`
- `test_RevertWhen_UnfreezeAddress_EmptyReason()` — `EmptyReason`
- `test_RevertWhen_UnfreezeAddress_NotFrozen()` — `NotFrozen`

#### 3.2.5 `revokeKYC()` — solo `BACKEND_SIGNER_ROLE`

Archivo: `IdentityRegistry.t.sol`

- `test_revokeKYC_HappyPath_SetsTier0()` — tier → 0, `canMint() = false`
- `test_revokeKYC_RevertWhen_AlreadyTier0()` — `AlreadyRevoked`

Archivo: `IdentityRegistryBranches.t.sol`

- `test_RevertWhen_RevokeKYC_UserZero()` — `ZeroAddressUser`
- `test_RevertWhen_RevokeKYC_EmptyReason()` — `EmptyReason`

#### 3.2.6 View functions

Archivo: `IdentityRegistry.t.sol`

- `test_canMint_Tier0_ReturnsFalse()`
- `test_canMint_Tier1Valid_ReturnsTrue()`
- `test_canMint_Expired_ReturnsFalse()` — `vm.warp` para expirar
- `test_canRedeem_Tier1_ReturnsFalse()` — requiere tier ≥ 2
- `test_canRedeem_Tier2Valid_ReturnsTrue()`
- `test_canRedeem_Tier3Valid_ReturnsTrue()`

#### 3.2.7 `pause()` / `unpause()` — asimetría `ADR-016` (`FIX H-02`)

Views **no se bloquean** durante pause (los demás contratos siguen consultando `canMint`, `canRedeem`).

Archivo: `IdentityRegistry.t.sol`

- `test_pause_OnlyComplianceOfficerOrAdmin()` — 5 actores (titular, ADMIN, suplente, BACKEND_SIGNER → revert, EOA → revert)
- `test_pause_BlocksMutators()` — los 6 mutators revierten con `Pausable.EnforcedPause`
- `test_pause_DoesNotBlockViews()` — `canMint`, `canRedeem`, `getTier`, `getJurisdiction`, `getKYCData` siguen funcionando
- `test_unpause_OnlyAdmin()` — `COMPLIANCE_OFFICER`, suplente, `BACKEND_SIGNER` revierten; solo `ADMIN` puede
- `test_unpause_RestoresMutators()` — `setKYC` y `markSanctioned` funcionan post-unpause

---

### 3.3 `RedemptionManager.sol` — 71 tests unit

#### 3.3.1 Constructor (`FIX M-08`, `RM-26`)

- `test_constructor_SetsAllRoles_Correctly()` — `defaultAdmin()`, `ORACLE_ROLE`, `COMPLIANCE_OFFICER_ROLE`, delay 3 días
- `test_constants_MaxDueNumeroLength()` — `MAX_DUE_NUMERO_LENGTH() == 64`
- `test_constructor_RevertWhen_OracleSafeZero()` — `ZeroAddress`
- `test_constructor_RevertWhen_ComplianceOfficerZero()` — `ZeroAddress`
- `test_constructor_RevertWhen_ComplianceOfficerSuplenteZero()` — `ZeroAddress`
- `test_constructor_RevertWhen_AssetVaultZero()` — `ZeroAddress`
- `test_constructor_RevertWhen_IdentityRegistryZero()` — `ZeroAddress`
- `test_constructor_RevertWhen_AdminZero()` — delegado a OZ v5

#### 3.3.2 `iniciarRedencion()` — `ALMACENADO`, caller = buyer

Modelo: **lock accumulator (Opción B)**. Tokens quedan en balance del buyer (sin transferir) pero se registran como lockeados. El burn ocurre en `completarRedencion()`.

- `test_iniciarRedencion_HappyPath()` — redencionId correcto, estado `INICIADA`, comprador y cantidadTokens
- `test_iniciarRedencion_RevertWhen_KYCTier1()` — tier 1 no puede redimir → `CannotRedeem`
- `test_iniciarRedencion_RevertWhen_LoteNotInAlmacenado()` — `LoteNotInAlmacenado`
- `test_iniciarRedencion_RevertWhen_CantidadCero()` — `CantidadCero`
- `test_iniciarRedencion_RevertWhen_DatosEnvioZero()` — `InvalidHash`
- `test_iniciarRedencion_RevertWhen_LoteIdDoesNotExist()` — `LoteNotFound(loteId)` (`RM-08`)
- `test_iniciarRedencion_RevertWhen_LoteNotFound()` — alias semántico de `RM-08`
- `test_iniciarRedencion_RevertWhen_BalanceInsuficiente()` — `RM-02`: buyer pide más de su balance disponible
- `test_iniciarRedencion_RevertWhen_CantidadExcedeSupplyTotal()` — `RM-19` defense-in-depth: `CantidadExcedeSupply`
- `test_iniciarRedencion_AcumuladorIncrementa_AfterValidCall()` — `RM-01`: `availableBalance` baja en `cantidadTokens`
- `test_iniciarRedencion_MultipleRedenciones_NoSeAcumulanSobreBalance()` — segunda redención revierte si excede available
- `test_iniciarRedencion_DoubleRedemption_Blocked()` — alias semántico doble redencion completa
- `test_iniciarRedencion_IncrementsLockAccumulator()` — `tokensLockedFor` refleja el lock
- `test_iniciarRedencion_RevertWhen_Paused()` — `whenNotPaused` aplica solo a `iniciarRedencion`
- `testFuzz_iniciarRedencion_AcumuladorNoExcedeBalance(uint256 c1, uint256 c2, uint256 c3)` — invariante `available <= balance`

##### `availableBalance` / `tokensLockedFor` views (`RM-01`)

- `test_availableBalance_ZeroLocked_EqualsBalance()` — sin locks, available = balance ERC1155
- `test_availableBalance_ReturnsBalanceMinusLocked()` — available = balance - locked

#### 3.3.3 `confirmarExportacion()` — solo `ORACLE_ROLE` (Fase 1 de `ADR-017`)

Transiciona `INICIADA → EN_EXPORTACION`. Registra `dueNumero`. **No burn**.

- `test_confirmarExportacion_HappyPath_BurnsTokens()` — test combinado: confirmar + completar = burn y `COMPLETADA`
- `test_confirmarExportacion_OnlyOracle_RevertWhen_NonOracle()`
- `test_confirmarExportacion_RevertWhen_RedencionAlreadyCompleted()` — `RedencionAlreadyFinalized` (desde `EN_EXPORTACION`)
- `test_confirmarExportacion_RevertWhen_DUEEmpty()` — `EmptyDUE`
- `test_confirmarExportacion_RevertWhen_DUENumeroExceedsMaxLength()` — `RM-10`: 65 chars → `DUENumeroTooLong`
- `test_confirmarExportacion_PassesWhen_DUENumeroExactlyMaxLength()` — 64 chars exactos → pasa
- `test_confirmarExportacion_FailsEarly_WhenBalanceInsuficiente()` — `RM-04`: defense-in-depth (dos buyers, flujos entrelazados)
- `test_confirmarExportacion_AcumuladorDecrementa_AfterBurn()` — `RM-01`: lock NO cambia en confirmar; solo en completar
- `test_confirmarExportacion_RevertWhen_RedencionNotIniciada()` — redencionId inexistente → `RedencionNotIniciada`
- `test_confirmarExportacion_TransitionsTo_EnExportacion()` — `ADR-017`: estado = `EN_EXPORTACION`, no `COMPLETADA`
- `test_confirmarExportacion_DoesNotBurnTokens()` — `ADR-017`: balance idéntico post-confirmar
- `test_confirmarExportacion_DecrementsLockAccumulator()` — `RM-01`: lock permanece en confirmar, baja a 0 en completar
- `test_confirmarExportacion_DoesNotRevertWhen_Paused()` — `RM-05 + ADR-016`: oracle puede confirmar durante pause
- `test_confirmarExportacion_EmitsEventsWithActor()` — `RM-18`: `RedencionEnExportacion` con actor indexed

#### 3.3.4 `completarRedencion()` — solo `ORACLE_ROLE` (Fase 2 de `ADR-017`)

Transiciona `EN_EXPORTACION → COMPLETADA`. Registra `hashBLAWB`. Ejecuta burn vía `assetVault.burnForRedemption()`. Decrementa acumulador.

- `test_completarRedencion_HappyPath_BurnsTokens()` — `ADR-017`: happy path de 2 fases
- `test_completarRedencion_RevertWhen_RedencionNotInExportacion()` — desde `INICIADA` → `NotInExportacion`
- `test_completarRedencion_RevertWhen_RedencionNotIniciada()` — redencionId inexistente
- `test_completarRedencion_OnlyOracle_RevertWhen_NonOracle()`
- `test_completarRedencion_RevertWhen_HashBLAWBZero()` — `InvalidHash`
- `test_completarRedencion_DefensiveRevert_WhenBalanceMockedBelowCantidad()` — `RM-04`: check defensivo vía `vm.mockCall`
- `test_completarRedencion_DoesNotRevertWhen_Paused()` — `ADR-016 + RM-05`: oracle puede completar durante pause
- `test_confirmarExportacion_RevertEarly_WhenBalanceInsuficiente()` — `RM-04`: safety net pre-state-change
- `test_confirmarExportacion_EmitsEventsWithActor()` — `RM-18`: `RedencionCompletada` con actor indexed

#### 3.3.5 `cancelarRedencion()` — `ADR-015` (3 paths)

Cancela desde `INICIADA` **o** `EN_EXPORTACION`. Libera acumulador. No quema tokens.

**Path 1:** `ORACLE_ROLE` o `COMPLIANCE_OFFICER_ROLE` — siempre, sin timeout.
**Path 2:** buyer — solo después de `REDENCION_TIMEOUT` (60 días desde `iniciarRedencion`).

- `test_cancelarRedencion_HappyPath()` — oracle cancela desde `INICIADA`, tokens preservados, estado `CANCELADA`
- `test_cancelarRedencion_RevertWhen_AlreadyCompleted()` — `RedencionAlreadyFinalized` (post-`completarRedencion`)
- `test_cancelarRedencion_AcumuladorDecrementa_AfterCancel()` — `RM-01`: available vuelve al total
- `test_cancelarRedencion_PermiteNuevaRedencion_DespuesDeCancelar()` — lock liberado, nueva redención posible
- `test_cancelarRedencion_DecrementsLockAccumulator()` — `tokensLockedFor` baja a 0
- `test_cancelarRedencion_ByComplianceOfficer_HappyPath()` — `ADR-015 Path 2`: CO puede cancelar siempre
- `test_cancelarRedencion_ByComplianceOfficerSuplente_HappyPath()` — suplente también
- `test_cancelarRedencion_ByBuyer_AfterTimeout_HappyPath()` — `ADR-015 Path 3`: buyer post-60d
- `test_cancelarRedencion_RevertWhen_BuyerCallsBeforeTimeout()` — buyer antes de 60d → `OnlyAuthorizedCanceler`
- `test_cancelarRedencion_RevertWhen_RandomCallerEvenAfterTimeout()` — random nunca puede → `OnlyAuthorizedCanceler`
- `test_cancelarRedencion_FromEnExportacion_HappyPath()` — `ADR-017`: cancelar desde `EN_EXPORTACION` OK
- `test_cancelarRedencion_RevertWhen_RedencionNotIniciada()` — redencionId inexistente → `RedencionNotIniciada`
- `test_cancelarRedencion_RevertWhen_ReasonZero()` — `EmptyReason`
- `test_cancelarRedencion_DoesNotRevertWhen_Paused()` — `ADR-016 + RM-05`: oracle puede cancelar durante pause
- `test_cancelarRedencion_EmitsEventWithActor()` — `RM-18`: `RedencionCancelada` con actor indexed

#### 3.3.6 `pause()` / `unpause()` — asimetría `ADR-016` (`RM-25`)

- `test_pause_ByComplianceOfficer_HappyPath()`
- `test_pause_ByDefaultAdmin_HappyPath()`
- `test_pause_RevertWhen_UnauthorizedActor()` — `UnauthorizedPauseActor`
- `test_unpause_ByDefaultAdmin_HappyPath()` — `ADR-016`: solo `ADMIN` puede despausar
- `test_unpause_RevertWhen_ComplianceOfficer()` — `COMPLIANCE_OFFICER` no puede despausar
- `test_unpause_RevertWhen_NonDefaultAdmin()`
- `test_pause_EmitsEmergencyPausedEvent()` — `RM-15`: `EmergencyPaused(actor, timestamp)`
- `test_unpause_EmitsEmergencyUnpausedEvent()` — `RM-15`: `EmergencyUnpaused(actor, timestamp)`, actor = `ADMIN`

#### 3.3.7 View functions

- `test_getNextRedencionId_StartsAtOne_AndIncrements()` — `RM-27`: 1 → 2 → 3

---

## 4. Tests de integración — `test/integration/`

### 4.1 `Lifecycle.t.sol` — 5 E2E cross-contract

- `test_lifecycle_HappyPath_BuyThroughRedemptionCompleted()` — buy → cosecha → almacenamiento → iniciarRedencion → confirmarExportacion → completarRedencion → `COMPLETADA`, tokens quemados, lote `AGOTADO`
- `test_lifecycle_LoteFallido_RefundsBuyerEscrow()` — `marcarFallido` → `reembolsarLoteFallido` → `finalizarReembolso`, reembolso 100%
- `test_lifecycle_Cancel_FromIniciada_ReleasesLock()` — cancel desde `INICIADA`, lock = 0, tokens preservados
- `test_lifecycle_Cancel_FromEnExportacion_ByCompliance()` — `ADR-015/017`: CO cancela desde `EN_EXPORTACION`
- `test_lifecycle_Cancel_BuyerSelfCancelOnlyAfterTimeout()` — `ADR-015`: buyer no puede pre-60d, sí post-60d

### 4.2 `DeployPlume.t.sol` — 5 tests del orchestrator de deploy

- `test_deploy_HappyPath_WiresContractsAndBreaksCycle()` — deploy() crea los 3 contratos; admin rompe ciclo con `setRedemptionManager`
- `test_deploy_HappyPath_GrantsRolesToConfiguredAddresses()` — todos los roles asignados
- `test_getConfig_RevertsWhen_UnsupportedChain()` — `UnsupportedChainId`
- `test_getConfig_LocalProfile_ReturnsUsableConfig()` — `chainId = 31_337` (Anvil)
- `test_getConfig_RevertsWhen_MainnetConfigMissing()` — Plume mainnet sin env vars → revert

---

## 5. Suite de invariants (excluida de CI de coverage — RM-29)

**Path:** `packages/contracts/test/invariant/`

La suite existe pero se excluye de las runs de coverage por OOM. `RM-29` track la solución (workers separados, reducción de depth, o perfil alternativo).

**Para correr manualmente:**
```bash
forge test --match-path '*invariant*' --invariant-runs 50000 --invariant-depth 100
```

Invariantes documentadas:

- `invariant_NoUserCanReceiveTokens_WithoutValidKYC()`
- `invariant_NoTokenTransferP2P_EverHappens()`
- `invariant_TotalSupply_EqualsSumOfBuyersBalances()`
- `invariant_ReservaTecnicaInContract_EqualsAccountingInLotes()`
- `invariant_OnlyRedemptionManager_CanCauseBurn()`
- `invariant_LoteEstado_OnlyForwardTransitions_ExceptToFallido()`
- `invariant_FailedLote_TotalRefunds_EqualsTotalPaid()`
- `invariant_AvailableBalance_NeverExceeds_ERC1155Balance()` — clave para Opción B lock accumulator

---

## 6. [FASE 2] Tests reservados — LabRegistry + QualityAttestation

> Los tests de esta sección **no existen** en la suite actual. Se implementarán cuando LabRegistry y
> QualityAttestation se activen (ADR-010). No eliminar; sirven como spec de referencia.

### 6.1 Estado `QUALITY_ATTESTED` (FASE 2)

En FASE 2 el flujo de estado es `PREVENTA → COSECHADO → QUALITY_ATTESTED → ALMACENADO`.
En MVP el paso intermedio está ausente; `confirmarAlmacenamiento()` acepta desde `COSECHADO`.

Tests FASE 2 que cubrirán `QUALITY_ATTESTED`:

- `test_confirmarCalidad_HappyPath_TransitionsToQualityAttested()`
- `test_confirmarCalidad_HappyPath_ComputesIsMonofloralCertified()` (≥ 45% pollen + NMR + C4 + residues)
- `test_confirmarCalidad_RevertWhen_LessThan2Labs()`
- `test_confirmarCalidad_RevertWhen_NoBolivianLab()`
- `test_confirmarCalidad_RevertWhen_NoForeignLab()`
- `test_confirmarCalidad_RevertWhen_LabNotInRegistry()`
- `test_confirmarCalidad_RevertWhen_LabDeactivated()`
- `test_confirmarCalidad_RevertWhen_SignatureInvalid()`
- `test_confirmarCalidad_RevertWhen_LoteNotInCosechado()`
- `test_confirmarCalidad_IsNotMonofloralWhen_PollenBelow45()`
- `test_confirmarCalidad_IsNotMonofloralWhen_NMRFailed()`
- `test_confirmarCalidad_IsNotMonofloralWhen_C4Failed()`
- `test_confirmarCalidad_IsNotMonofloralWhen_ResiduesFailed()`
- `test_confirmarCalidad_EmitsCalidadConfirmadaEvent()`
- `test_confirmarAlmacenamiento_RevertWhen_LoteNotInQualityAttested()` ← cambia desde `LoteNotInCosechado`
- `test_marcarFallido_FromQualityAttested_Allowed()` (actualmente `FALLIDO` solo desde PREVENTA/COSECHADO)
- `test_liberarReservaTecnica_AllowedFrom_QualityAttested()` (actualmente solo desde COSECHADO)

### 6.2 `LabRegistry.sol` (FASE 2) — target: 20-30 unit tests

#### 6.2.1 `addLab()` — solo `ADMIN_ROLE`

- `test_addLab_HappyPath_StoresLabData()`
- `test_addLab_OnlyAdmin_RevertWhen_NonAdmin()`
- `test_addLab_RevertWhen_SignerAddressZero()`
- `test_addLab_RevertWhen_SpecializationsEmpty()`
- `test_addLab_RevertWhen_AlreadyExists()`
- `test_addLab_EmitsLabAddedEvent()`

#### 6.2.2 `deactivateLab()` — solo `COMPLIANCE_OFFICER_ROLE`

- `test_deactivateLab_HappyPath_SetsActiveFalse()`
- `test_deactivateLab_OnlyOfficer_RevertWhen_NonOfficer()`
- `test_deactivateLab_RevertWhen_LabNotExists()`
- `test_deactivateLab_RevertWhen_AlreadyDeactivated()`
- `test_deactivateLab_StoresDeactivatedAt()`
- `test_deactivateLab_EmitsLabDeactivatedEvent()`

#### 6.2.3 `verifyAttestationSignature()` view

- `test_verifyAttestationSignature_ValidSignature_ReturnsTrue()`
- `test_verifyAttestationSignature_InvalidSignature_ReturnsFalse()`
- `test_verifyAttestationSignature_LabNotInRegistry_ReturnsFalse()`
- `test_verifyAttestationSignature_LabDeactivated_ReturnsFalse()`

#### 6.2.4 `isLabCertifiedFor()` view

- `test_isLabCertifiedFor_LabWithSpecialization_ReturnsTrue()`
- `test_isLabCertifiedFor_LabWithoutSpecialization_ReturnsFalse()`
- `test_isLabCertifiedFor_LabDeactivated_ReturnsFalse()`

#### 6.2.5 Fuzz (FASE 2)

- `testFuzz_verifyAttestationSignature_RoundtripValidSignatures(bytes32 attestationHash)`

### 6.3 Helpers de BaseTest para FASE 2 (no existen en MVP)

- `_seedLabs()` — registra `LAB_BOLIVIA` (IBNORCA mock) + `LAB_EUROPA` (Eurofins mock) en LabRegistry
- `_buildQualityAttestation(uint256 loteId, uint8 pollenPct, bool nmr, bool c4, bool residues)`

### 6.4 Invariants FASE 2

- `invariant_QualityAttestation_RequiresMinimum2Labs_PostQualityAttested()`
- `invariant_LabSignatures_AlwaysValid_PostConfirmarCalidad()`
- `invariant_qualityAttestation_AlwaysHasAtLeast2Labs_PostQualityAttested()`

---

## 7. Gas snapshots (regression prevention)

**Comando:** `forge snapshot`

Capturar y versionar en `.gas-snapshot`:
- `crearLote` — ~150K gas
- `comprar` — ~280K gas (USDC mint + ERC1155 mint + escrow accounting)
- `confirmarCosecha` — ~120K gas (libera escrow al productor)
- `confirmarAlmacenamiento` — ~80K gas
- `liberarReservaTecnica` — ~80K gas
- `iniciarRedencion` — ~120K gas (lock accumulator update)
- `confirmarExportacion` — ~80K gas (estado → `EN_EXPORTACION`, registra DUE)
- `completarRedencion` — ~140K gas (burn + estado → `COMPLETADA`)
- `reembolsarLoteFallido` (1 buyer) — ~150K gas
- `reembolsarLoteFallido` (10 buyers) — ~800K gas

**Política:** cualquier PR que aumente gas > 5% sin justificación es bloqueado.

---

## 8. Slither (análisis estático obligatorio en CI)

**Comando:** `slither .`

**Política:**
- Issues **High**: bloquean merge
- Issues **Medium**: requieren justificación en PR + ADR
- Issues **Low** / **Informational**: opcionales

**Configurar `slither.config.json`** con:
- Filtrar false-positives conocidos (revisados uno a uno)
- Detectores habilitados: TODOS por default

---

## 9. Mainnet fork tests (opcional pero recomendado)

**Path:** `packages/contracts/test/fork/`

```solidity
function setUp() public {
    plumeFork = vm.createSelectFork(vm.envString("PLUME_TESTNET_RPC_URL"));
}
```

- `test_fork_USDCRealTransfer()`
- `test_fork_PlumeArcIntegration()` (si Plume Arc disponible en testnet)
- `test_fork_ChainlinkPoRFeedRead()` (si PoR feed disponible)

---

## 10. Reglas de implementación de tests

1. **TDD obligatorio:** test PRIMERO. RED → GREEN → Refactor.
2. **Un test por caso:** NO multiplexar varios scenarios.
3. **Setup mínimo necesario:** usar helpers de `BaseTest` en lugar de duplicar setup.
4. **Mocks claros:** `MockUSDC` para USDC; FASE 2 usa firmas ECDSA reales con `vm.sign`.
5. **Custom errors verificados** con `vm.expectRevert(CustomError.selector)`.
6. **Events verificados** con `vm.expectEmit(true, true, true, true)`.
7. **Time manipulation** con `vm.warp(...)`.
8. **Storage verification** con `vm.load(...)` cuando es interno.
9. **Acumulador de lock:** tests de `iniciarRedencion` deben verificar `tokensLockedFor` y `availableBalance`, no solo estado de la redención.

---

## 11. CI integration

```yaml
- name: Forge Tests (unit + fuzz)
  run: |
    cd packages/contracts
    forge test --fuzz-runs 10000 -vvv

- name: Forge Coverage
  run: |
    cd packages/contracts
    forge coverage --report lcov --report-file coverage.lcov

- name: Slither Analysis
  uses: crytic/slither-action@v0.4.0
  with:
    target: packages/contracts/
    slither-config: packages/contracts/slither.config.json
    fail-on: high

- name: Gas Snapshot Check
  run: |
    cd packages/contracts
    forge snapshot --check

# Invariants excluidos del CI de coverage (OOM — RM-29 pendiente):
# forge test --match-path '*invariant*' --invariant-runs 50000 --invariant-depth 100
```

---

**Última actualización:** 2026-05-29
**Coverage real:** 100% líneas + branches + funciones (3 contratos MVP)
**Total de tests reales:** 216 (unit + branch coverage + integración); invariants excluidos del conteo de CI
