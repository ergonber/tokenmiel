# Test Specifications (Foundry) — Smart Contracts

> Specs exhaustivas de tests Foundry siguiendo TDD (Red-Green-Refactor). Cada test descrito acá debe existir antes de su implementación en código. Derivado de `CONTRACT-SPECS.md` v1.0 y `ARQUITECTURA-TECNICA-MVP.md` v2.0.

---

## 1. Convenciones globales

### 1.1 Coverage no negociable

- **Líneas:** 100%
- **Branches:** 100%
- **Funciones:** 100%
- **Fuzz runs:** ≥ 10,000 por test fuzz
- **Invariant runs:** ≥ 50,000, depth 100

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

**`BaseTest.t.sol`** debe incluir:
- Deploy de los 4 contratos
- Mock ERC20 USDC con `decimals = 6`
- Funciones helper:
  - `_setupKYC(address user, uint8 tier)`
  - `_createLote(uint256 loteId, uint256 kgEsperados, uint256 precio, uint16 reservaBps)`
  - `_advanceToState(uint256 loteId, LoteEstado targetState)` (con docs hashes mock)
  - `_seedLabs()` (agrega IBNORCA + Eurofins mock al LabRegistry)
  - `_buildQualityAttestation(uint256 loteId, uint8 pollenPct, bool nmr, bool c4, bool residues)`

### 1.5 Direcciones de actores estándar

```solidity
address constant ADMIN = address(0xA001);
address constant ORACLE_SIGNER_1 = address(0xB001);
address constant ORACLE_SIGNER_2 = address(0xB002);
address constant ORACLE_SIGNER_3 = address(0xB003);
address constant BACKEND_SIGNER = address(0xC001);
address constant COMPLIANCE_OFFICER = address(0xD001);
address constant COMPLIANCE_OFFICER_SUPLENTE = address(0xD002);
address constant TREASURY_SRL = address(0xE001);
address constant LAB_BOLIVIA = address(0xF001);  // IBNORCA mock
address constant LAB_EUROPA = address(0xF002);   // Eurofins mock
address constant BUYER_1 = address(0x1001);
address constant BUYER_2 = address(0x1002);
address constant BUYER_SANCTIONED = address(0x1003);
address constant BUYER_FROZEN = address(0x1004);
```

---

## 2. Tests por contrato

### 2.1 `AssetVault.sol` (target: 50-80 unit tests + fuzz + invariant)

#### 2.1.1 Constructor / initialization

- `test_constructor_SetsAllRoles_Correctly()`
- `test_constructor_RevertWhen_DependenciesZeroAddress()`
- `test_constructor_USDCAddressIsImmutable()`
- `test_constructor_IdentityRegistryAddressIsImmutable()`
- `test_constructor_RedemptionManagerAddressIsImmutable()`
- `test_constructor_LabRegistryAddressIsImmutable()`

#### 2.1.2 `crearLote()` — solo ADMIN_ROLE

- `test_crearLote_HappyPath_CreatesLoteInPreventa()`
- `test_crearLote_OnlyAdmin_RevertWhen_NonAdminCaller()`
- `test_crearLote_RevertWhen_ReservaBpsBelowMin()` (< 1500)
- `test_crearLote_RevertWhen_ReservaBpsAboveMax()` (> 2000)
- `test_crearLote_RevertWhen_LoteIdAlreadyExists()`
- `test_crearLote_RevertWhen_KgEsperadosZero()`
- `test_crearLote_RevertWhen_PrecioZero()`
- `test_crearLote_RevertWhen_ProductorSRLZeroAddress()`
- `test_crearLote_RevertWhen_HashFSAZero()`
- `test_crearLote_EmitsLoteCreado_Event()`
- `test_crearLote_StateIsPreventaInitially()`

#### 2.1.3 `comprar()` — solo BACKEND_SIGNER_ROLE

- `test_comprar_HappyPath_MintsCorrectAmount()`
- `test_comprar_HappyPath_RetainsReservaTecnica()` (15-20% del monto)
- `test_comprar_HappyPath_TransfersNetToProductorSRL()`
- `test_comprar_HappyPath_EmitsLoteCompradoEvent()`
- `test_comprar_OnlyBackendSigner_RevertWhen_NonBackend()`
- `test_comprar_RevertWhen_KYCTier0()`
- `test_comprar_RevertWhen_AddressSanctioned()`
- `test_comprar_RevertWhen_AddressFrozen()`
- `test_comprar_RevertWhen_KYCExpired()`
- `test_comprar_RevertWhen_LoteNotInPreventa()` (para cada estado distinto a PREVENTA)
- `test_comprar_RevertWhen_KgExcedeSupplyDisponible()`
- `test_comprar_RevertWhen_MontoUSDCInsuficiente()`
- `test_comprar_RevertWhen_CantidadTokensZero()`
- `test_comprar_RevertWhen_Paused()`
- `test_comprar_RevertWhen_PaymentRefHashZero()`

#### 2.1.4 `_update()` override — bloqueo de transfers

- `test_update_AllowsMintFromZeroAddress()`
- `test_update_AllowsBurnToZeroAddress_OnlyFromRedemptionManager()`
- `test_update_RevertWhen_BurnNotFromRedemption()`
- `test_update_RevertWhen_TransferP2PBetweenUsers()`
- `test_update_RevertWhen_SafeTransferFrom()`
- `test_update_RevertWhen_SafeBatchTransferFrom()`
- `test_update_RevertWhen_FromAndToBothNonZero()`
- `test_setApprovalForAll_RevertWhen_AnyCall()` (no aprobaciones tampoco)

#### 2.1.5 `confirmarCosecha()` — solo ORACLE_ROLE

- `test_confirmarCosecha_HappyPath_TransitionsToCosechado()`
- `test_confirmarCosecha_HappyPath_StoresAllHashes()`
- `test_confirmarCosecha_HappyPath_EmitsCosechaConfirmadaEvent()`
- `test_confirmarCosecha_OnlyOracle_RevertWhen_NonOracle()`
- `test_confirmarCosecha_RevertWhen_LoteNotInPreventa()`
- `test_confirmarCosecha_RevertWhen_KgRealCosechadoZero()`
- `test_confirmarCosecha_RevertWhen_AnyHashZero()`
- `test_confirmarCosecha_DoesNotChangeReservaTecnica()` (reserva se libera en función separada)

#### 2.1.6 `confirmarCalidad()` — solo ORACLE_ROLE

- `test_confirmarCalidad_HappyPath_TransitionsToQualityAttested()`
- `test_confirmarCalidad_HappyPath_StoresAttestation()`
- `test_confirmarCalidad_HappyPath_ComputesIsMonofloralCertified()` (true cuando ≥45% + NMR + C4 + residues)
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

#### 2.1.7 `confirmarAlmacenamiento()` — solo ORACLE_ROLE

- `test_confirmarAlmacenamiento_HappyPath_TransitionsToAlmacenado()`
- `test_confirmarAlmacenamiento_OnlyOracle_RevertWhen_NonOracle()`
- `test_confirmarAlmacenamiento_RevertWhen_LoteNotInQualityAttested()`
- `test_confirmarAlmacenamiento_RevertWhen_HashContratoDepositoZero()`
- `test_confirmarAlmacenamiento_RevertWhen_AlmacenZeroAddress()`
- `test_confirmarAlmacenamiento_EmitsAlmacenamientoConfirmadoEvent()`

#### 2.1.8 `marcarFallido()` — solo ORACLE_ROLE

- `test_marcarFallido_HappyPath_TransitionsToFallido()`
- `test_marcarFallido_FromPreventa_Allowed()`
- `test_marcarFallido_FromCosechado_Allowed()`
- `test_marcarFallido_FromQualityAttested_Allowed()`
- `test_marcarFallido_FromAlmacenado_Allowed()`
- `test_marcarFallido_FromAgotado_NotAllowed()`
- `test_marcarFallido_OnlyOracle_RevertWhen_NonOracle()`
- `test_marcarFallido_RevertWhen_MotivoEmpty()`
- `test_marcarFallido_StoresMotivo()`
- `test_marcarFallido_EmitsLoteFallidoEvent()`

#### 2.1.9 `liberarReservaTecnica()` — solo TREASURY_SRL_ROLE

- `test_liberarReservaTecnica_HappyPath_TransfersUSDCToSRL()`
- `test_liberarReservaTecnica_OnlyTreasurySRL_RevertWhen_NonTreasury()`
- `test_liberarReservaTecnica_RevertWhen_LoteNotInQualityAttestedOrAlmacenado()`
- `test_liberarReservaTecnica_RevertWhen_AlreadyReleased()`
- `test_liberarReservaTecnica_RevertWhen_LoteFallido()` (no se libera, se reembolsa)
- `test_liberarReservaTecnica_EmitsReservaTecnicaLiberadaEvent()`
- `test_liberarReservaTecnica_UpdatesReservaTecnicaLiberada()`

#### 2.1.10 `reembolsarLoteFallido()` — solo ORACLE_ROLE

- `test_reembolsarLoteFallido_HappyPath_BurnsTokensFromAllBuyers()`
- `test_reembolsarLoteFallido_HappyPath_TransfersProRataUSDC()`
- `test_reembolsarLoteFallido_OnlyOracle_RevertWhen_NonOracle()`
- `test_reembolsarLoteFallido_RevertWhen_LoteNotFallido()`
- `test_reembolsarLoteFallido_RevertWhen_EmptyBuyersArray()`
- `test_reembolsarLoteFallido_HandlesMultipleBuyers_Correctly()`
- `test_reembolsarLoteFallido_EmitsReembolsoEjecutadoPerBuyer()`
- `test_reembolsarLoteFallido_CalculatesProRataCorrectly()` (cada comprador recibe proporcional a sus tokens)
- `test_reembolsarLoteFallido_NoReembolsoTwice()` (no se puede reembolsar mismo lote dos veces)

#### 2.1.11 `pause()` / `unpause()` — solo COMPLIANCE_OFFICER_ROLE

- `test_pause_OnlyComplianceOfficer_RevertWhen_NonOfficer()`
- `test_pause_BlocksComprar()`
- `test_pause_DoesNotBlockOracleConfirmations()` (confirmaciones siguen, solo bloqueo de mints)
- `test_pause_EmitsEmergencyPausedEvent()`
- `test_unpause_RestoresComprar()`
- `test_unpause_OnlyComplianceOfficer()`
- `test_unpause_EmitsEmergencyUnpausedEvent()`

#### 2.1.12 View functions

- `test_kgDisponibles_ReturnsCorrectAmount()`
- `test_kgDisponibles_ZeroAfterAgotado()`
- `test_reservaTecnicaActual_ReturnsCorrectAmount()`
- `test_lotes_ReturnsCorrectStruct()`

#### 2.1.13 Fuzz tests

- `testFuzz_comprar_ReservaTecnicaCalculoCorrecto(uint256 monto, uint16 reservaBps)` — verifica que `reservaRetenida = monto * reservaBps / 10000` ± 1 wei rounding
- `testFuzz_reembolso_ProRataExacto(uint256[10] balances)` — verifica que sum(reembolsos) == totalRecaudado
- `testFuzz_kgVsTokens_NoOverflow(uint256 cantidadTokens)` — verifica que cantidadTokens * 500 no overflow
- `testFuzz_precioPorToken_NoUnderflow(uint256 precio, uint256 cantidad)` — verifica que `precio * cantidad >= reservaRetenida + montoNeto`
- `testFuzz_comprar_NeverExceedsKgEsperados(uint256[5] compras)` — secuencia de compras nunca excede kg disponibles

#### 2.1.14 Invariant tests

- `invariant_totalKgVendidos_LessOrEqual_kgEsperados()`
- `invariant_reservaTecnica_NuncaNegativa()`
- `invariant_supplyToken_Equals_2x_kgVendidos()` (1 token = 0.5 kg, factor 2)
- `invariant_reservaLiberada_LessOrEqual_reservaAcumulada()`
- `invariant_redencion_Equals_Burn_Tokens()`
- `invariant_loteFallidoSinReservaPendiente_PostReembolso()`
- `invariant_USDCBalance_GreaterOrEqual_TotalReservaTecnicaActiva()`
- `invariant_estados_OnlyForwardTransitions()` (excepto a FALLIDO)
- `invariant_qualityAttestation_AlwaysHasAtLeast2Labs_PostQualityAttested()`

---

### 2.2 `IdentityRegistry.sol` (target: 25-40 unit tests + fuzz)

#### 2.2.1 `setKYC()` — solo BACKEND_SIGNER_ROLE

- `test_setKYC_HappyPath_StoresKYCData()`
- `test_setKYC_OnlyBackendSigner_RevertWhen_NonBackend()`
- `test_setKYC_RevertWhen_TierInvalid()` (tier > 3)
- `test_setKYC_RevertWhen_ExpiryInPast()`
- `test_setKYC_UpdatesExisting()`
- `test_setKYC_EmitsKYCUpdatedEvent()`

#### 2.2.2 `markSanctioned()` / `unmarkSanctioned()` — solo COMPLIANCE_OFFICER_ROLE

- `test_markSanctioned_HappyPath_BlocksCanMint()`
- `test_markSanctioned_OnlyOfficer_RevertWhen_NonOfficer()`
- `test_markSanctioned_RevertWhen_AlreadySanctioned()`
- `test_markSanctioned_RevertWhen_ReasonEmpty()`
- `test_markSanctioned_EmitsSanctionedEvent()`
- `test_unmarkSanctioned_RestoresCanMint()`
- `test_unmarkSanctioned_RevertWhen_NotSanctioned()`

#### 2.2.3 `freezeAddress()` / `unfreezeAddress()` — solo COMPLIANCE_OFFICER_ROLE

- `test_freezeAddress_HappyPath_BlocksCanMintAndCanRedeem()`
- `test_freezeAddress_OnlyOfficer()`
- `test_freezeAddress_RevertWhen_AlreadyFrozen()`
- `test_freezeAddress_RevertWhen_RegulatoryOrderEmpty()`
- `test_freezeAddress_EmitsFrozenEvent()`
- `test_unfreezeAddress_Restores()`

#### 2.2.4 `revokeKYC()` — solo BACKEND_SIGNER_ROLE

- `test_revokeKYC_HappyPath_SetsTier0()`
- `test_revokeKYC_RevertWhen_AlreadyTier0()`
- `test_revokeKYC_EmitsKYCRevokedEvent()`

#### 2.2.5 View functions

- `test_canMint_Tier0_ReturnsFalse()`
- `test_canMint_Tier1Valid_ReturnsTrue()`
- `test_canMint_Sanctioned_ReturnsFalse()`
- `test_canMint_Frozen_ReturnsFalse()`
- `test_canMint_Expired_ReturnsFalse()`
- `test_canRedeem_Tier1_ReturnsFalse()` (requiere tier ≥ 2)
- `test_canRedeem_Tier2Valid_ReturnsTrue()`
- `test_canRedeem_Tier3Valid_ReturnsTrue()`
- `test_canRedeem_FrozenWithTier2_ReturnsFalse()`
- `test_getTier_ReturnsCorrectTier()`
- `test_isSanctioned_ReturnsCorrect()`
- `test_isFrozen_ReturnsCorrect()`
- `test_getJurisdiction_ReturnsCorrect()`

#### 2.2.6 Fuzz tests

- `testFuzz_setKYC_RoundtripData(address user, uint8 tier, uint64 expiry, bytes2 jurisdiction)`

---

### 2.3 `RedemptionManager.sol` (target: 25-40 unit tests)

#### 2.3.1 `iniciarRedencion()`

- `test_iniciarRedencion_HappyPath_LocksTokens()`
- `test_iniciarRedencion_HappyPath_EmitsEvent()`
- `test_iniciarRedencion_RevertWhen_KYCTier1()` (requiere tier ≥ 2)
- `test_iniciarRedencion_RevertWhen_AddressSanctioned()`
- `test_iniciarRedencion_RevertWhen_AddressFrozen()`
- `test_iniciarRedencion_RevertWhen_LoteNotInAlmacenado()`
- `test_iniciarRedencion_RevertWhen_LoteFallido()`
- `test_iniciarRedencion_RevertWhen_CantidadCero()`
- `test_iniciarRedencion_RevertWhen_BalanceInsuficiente()`
- `test_iniciarRedencion_RevertWhen_DatosEnvioHashZero()`
- `test_iniciarRedencion_RevertWhen_Paused()`

#### 2.3.2 `confirmarExportacion()` — solo ORACLE_ROLE

- `test_confirmarExportacion_HappyPath_BurnsTokens()`
- `test_confirmarExportacion_HappyPath_StoresDUEAndBLAWB()`
- `test_confirmarExportacion_HappyPath_TransitionsToCompletada()`
- `test_confirmarExportacion_OnlyOracle_RevertWhen_NonOracle()`
- `test_confirmarExportacion_RevertWhen_RedencionNotIniciada()`
- `test_confirmarExportacion_RevertWhen_DueNumeroEmpty()`
- `test_confirmarExportacion_RevertWhen_HashBLAWBZero()`
- `test_confirmarExportacion_EmitsRedencionCompletadaEvent()`

#### 2.3.3 `cancelarRedencion()` — solo ORACLE_ROLE

- `test_cancelarRedencion_HappyPath_ReleasesTokensToBuyer()`
- `test_cancelarRedencion_OnlyOracle_RevertWhen_NonOracle()`
- `test_cancelarRedencion_RevertWhen_RedencionAlreadyCompleted()`
- `test_cancelarRedencion_RevertWhen_RedencionAlreadyCancelled()`
- `test_cancelarRedencion_StoresReason()`
- `test_cancelarRedencion_EmitsRedencionCanceladaEvent()`

---

### 2.4 `LabRegistry.sol` (target: 20-30 unit tests)

#### 2.4.1 `addLab()` — solo ADMIN_ROLE

- `test_addLab_HappyPath_StoresLabData()`
- `test_addLab_OnlyAdmin_RevertWhen_NonAdmin()`
- `test_addLab_RevertWhen_SignerAddressZero()`
- `test_addLab_RevertWhen_SpecializationsEmpty()`
- `test_addLab_RevertWhen_AlreadyExists()`
- `test_addLab_EmitsLabAddedEvent()`

#### 2.4.2 `deactivateLab()` — solo COMPLIANCE_OFFICER_ROLE

- `test_deactivateLab_HappyPath_SetsActiveFalse()`
- `test_deactivateLab_OnlyOfficer_RevertWhen_NonOfficer()`
- `test_deactivateLab_RevertWhen_LabNotExists()`
- `test_deactivateLab_RevertWhen_AlreadyDeactivated()`
- `test_deactivateLab_StoresDeactivatedAt()`
- `test_deactivateLab_EmitsLabDeactivatedEvent()`

#### 2.4.3 `verifyAttestationSignature()` view

- `test_verifyAttestationSignature_ValidSignature_ReturnsTrue()`
- `test_verifyAttestationSignature_InvalidSignature_ReturnsFalse()`
- `test_verifyAttestationSignature_LabNotInRegistry_ReturnsFalse()`
- `test_verifyAttestationSignature_LabDeactivated_ReturnsFalse()`

#### 2.4.4 `isLabCertifiedFor()` view

- `test_isLabCertifiedFor_LabWithSpecialization_ReturnsTrue()`
- `test_isLabCertifiedFor_LabWithoutSpecialization_ReturnsFalse()`
- `test_isLabCertifiedFor_LabDeactivated_ReturnsFalse()`

#### 2.4.5 Fuzz tests

- `testFuzz_verifyAttestationSignature_RoundtripValidSignatures(bytes32 attestationHash)`

---

## 3. Integration tests (end-to-end scenarios)

**Path:** `packages/contracts/test/integration/`

### 3.1 `PurchaseFlow.t.sol` — flujo de compra completo

- `test_e2e_compradorEuropeoCompletoTier1Compra()`
  - Setup KYC tier 1, crea lote, compra → mint exitoso → balance correcto
- `test_e2e_compradorB2BTier3Compra()`
  - Tier 3, compra ticket grande
- `test_e2e_multipleCompras_SameLote_CorrectAccounting()`
  - Múltiples compradores en el mismo lote, reserva técnica acumula correcto

### 3.2 `LotLifecycleFlow.t.sol` — ciclo completo del lote

- `test_e2e_loteCompleto_PreventaACosechaAQualityAttestedAAlmacenadoARedencionAAgotado()`
- `test_e2e_loteCompleto_StateTransitionsCorrectOrder()`

### 3.3 `QualityAttestationFlow.t.sol` — oráculo de calidad

- `test_e2e_calidadAttestation_ConDosLabs_IBNORCAyEurofins()`
- `test_e2e_calidadAttestation_IsMonofloralCertifiedTrue_When45PolenAndAllTestsPass()`
- `test_e2e_calidadAttestation_NotMonofloral_When40Polen()`
- `test_e2e_calidadAttestation_RevertWhen_OnlyBolivianLabs()` (necesita al menos uno foráneo)
- `test_e2e_calidadAttestation_RevertWhen_OnlyForeignLabs()` (necesita al menos uno boliviano)

### 3.4 `RedemptionFlow.t.sol` — flujo de redención

- `test_e2e_redencionConDUEYBLAWB()`
  - Tier 2 inicia redención → tokens locked → oracle confirma exportación → burn → completada
- `test_e2e_redencionCancelada_TokensReturnedToBuyer()`
- `test_e2e_redencionPartial_PartialBurnCorrect()`

### 3.5 `FailedLotFlow.t.sol` — lote fallido

- `test_e2e_loteFallido_ReembolsoProRataAllBuyers()`
- `test_e2e_loteFallido_ReservaTecnicaIncludedInRefund()`
- `test_e2e_loteFallido_NoReembolsoTwice()`

### 3.6 `ComplianceScenarios.t.sol` — escenarios regulatorios

- `test_e2e_compradorOFACBloqueado_RevertOnPurchase()`
- `test_e2e_jurisdiccionSancionada_RevertOnPurchase()` (vía marca sanctioned)
- `test_e2e_kycExpirado_NoPuedeComprar()`
- `test_e2e_kycRevocadoPostCompra_NoAfectaTokensExistentes_PeroBloqueaRedencion()`
- `test_e2e_pauseEmergencia_BloqueoTotalCompras()`
- `test_e2e_freezeRegulatorio_BloqueaSoloAddressEspecifica()`
- `test_e2e_otrosCompradoresPuedenCompar_DurantePauseDeOtro()` (no — durante pause global, nadie puede)

### 3.7 `OracleFlow.t.sol` — Safe multi-sig

- `test_e2e_oracleSafe2of3_FirmasNecesariasParaConfirmacion()`
- `test_e2e_oracleSafe_UnaSolaFirmaNoEjecuta()`
- `test_e2e_oracleSafe_SwapOwnerProcess()` (rotación de firmante)

---

## 4. Fuzz tests cross-contract

**Path:** `packages/contracts/test/fuzz/`

- `testFuzz_complianceConstants_AreReflected_InAllContracts(uint16 reservaBps)`
- `testFuzz_qualityAttestation_DeterministicCertification(uint8 pollen, bool nmr, bool c4, bool residues)`
- `testFuzz_reembolsoTotal_EqualsTotalRecaudado_NoMatterDistribution(uint256[] amounts)`

---

## 5. Invariant tests sistémicos

**Path:** `packages/contracts/test/invariant/`

Para correr con `forge test --match-path '*invariant*' --invariant-runs 50000 --invariant-depth 100`:

- `invariant_NoUserCanReceiveTokens_WithoutValidKYC()`
- `invariant_NoTokenTransferP2P_EverHappens()`
- `invariant_TotalSupply_EqualsSumOfBuyersBalances()`
- `invariant_ReservaTecnicaInContract_EqualsAccountingInLotes()`
- `invariant_OnlyRedemptionManager_CanCauseBurn()`
- `invariant_LoteEstado_OnlyForwardTransitions_ExceptToFallido()`
- `invariant_QualityAttestation_RequiresMinimum2Labs_PostQualityAttested()`
- `invariant_LabSignatures_AlwaysValid_PostConfirmarCalidad()`
- `invariant_FailedLote_TotalRefunds_EqualsTotalPaid()`

---

## 6. Gas snapshots (regression prevention)

**Comando:** `forge snapshot`

Capturar y versionar en `.gas-snapshot`:
- `crearLote` — ~150K gas
- `comprar` — ~280K gas (incluyendo USDC transfer + mint)
- `confirmarCosecha` — ~120K gas
- `confirmarCalidad` — ~180K gas (verificación 2 firmas)
- `confirmarAlmacenamiento` — ~80K gas
- `liberarReservaTecnica` — ~80K gas
- `iniciarRedencion` — ~120K gas
- `confirmarExportacion` — ~140K gas (burn + storage)
- `reembolsarLoteFallido` (1 buyer) — ~150K gas
- `reembolsarLoteFallido` (10 buyers) — ~800K gas

**Política:** cualquier PR que aumente gas > 5% sin justificación es bloqueado.

---

## 7. Slither (análisis estático obligatorio en CI)

**Comando:** `slither .`

**Política:**
- Issues **High**: bloquean merge
- Issues **Medium**: requieren justificación en PR + ADR
- Issues **Low** / **Informational**: opcionales

**Configurar `slither.config.json`** con:
- Filtrar false-positives conocidos (después de revisar uno a uno)
- Detectores habilitados: TODOS por default

---

## 8. Mainnet fork tests (opcional pero recomendado)

**Path:** `packages/contracts/test/fork/`

Tests que corren contra fork de Plume Testnet (o Polygon Amoy) para validar integraciones reales:

- `test_fork_USDCRealTransfer()`
- `test_fork_PlumeArcIntegration()` (si Plume Arc disponible en testnet)
- `test_fork_ChainlinkPoRFeedRead()` (si PoR feed disponible)

**Setup:**
```solidity
function setUp() public {
    plumeFork = vm.createSelectFork(vm.envString("PLUME_TESTNET_RPC_URL"));
}
```

---

## 9. Reglas de implementación de tests

1. **TDD obligatorio:** test PRIMERO, después implementación. El test debe fallar inicialmente (RED), después pasar (GREEN), después refactor.
2. **Un test por caso:** NO multiplexar varios scenarios en un test.
3. **Setup mínimo necesario:** usar helpers (`_setupKYC`, `_createLote`, `_seedLabs`) en lugar de duplicar setup.
4. **Mocks claros:** usar `MockERC20` para USDC, mocks explícitos para labs (firmas ECDSA reales con `vm.sign`).
5. **Custom errors verificados** con `vm.expectRevert(CustomError.selector)`.
6. **Events verificados** con `vm.expectEmit(true, true, true, true)`.
7. **Time manipulation** con `vm.warp(...)`.
8. **Storage verification** con `vm.load(...)` cuando es interno.

---

## 10. CI integration

**`.github/workflows/ci.yml`** debe incluir:

```yaml
- name: Forge Tests (unit + fuzz)
  run: |
    cd packages/contracts
    forge test --fuzz-runs 10000 -vvv

- name: Forge Invariants
  run: |
    cd packages/contracts
    forge test --match-path '*invariant*' --invariant-runs 50000 --invariant-depth 100

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
```

---

**Última actualización:** 2026-05-19
**Coverage objetivo:** 100% líneas + branches + funciones
**Total de tests estimados:** ~200-280 (incluyendo fuzz e invariant)
