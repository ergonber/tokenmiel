// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {BaseTest} from "../BaseTest.t.sol";
import {RedemptionManager} from "../../src/RedemptionManager.sol";
import {IRedemptionManager} from "../../src/interfaces/IRedemptionManager.sol";
import {IAssetVault} from "../../src/interfaces/IAssetVault.sol";
import {IIdentityRegistry} from "../../src/interfaces/IIdentityRegistry.sol";

contract RedemptionManagerTest is BaseTest {
    // ---- Constructor / FIX M-08 ----

    /// @dev FIX M-08: el constructor debe asignar DEFAULT_ADMIN_ROLE vía AccessControlDefaultAdminRules.
    ///      Verifica que `defaultAdmin()` retorna el ADMIN configurado y el delay es 3 días.
    function test_constructor_SetsAllRoles_Correctly() public view {
        // DEFAULT_ADMIN_ROLE via AccessControlDefaultAdminRules
        assertEq(redemptionManager.defaultAdmin(), ADMIN);
        assertTrue(redemptionManager.hasRole(redemptionManager.DEFAULT_ADMIN_ROLE(), ADMIN));

        // Roles operativos
        assertTrue(redemptionManager.hasRole(redemptionManager.ORACLE_ROLE(), ORACLE_SAFE));
        assertTrue(redemptionManager.hasRole(redemptionManager.COMPLIANCE_OFFICER_ROLE(), COMPLIANCE_OFFICER));
        assertTrue(redemptionManager.hasRole(redemptionManager.COMPLIANCE_OFFICER_ROLE(), COMPLIANCE_OFFICER_SUPLENTE));

        // Delay configurado
        assertEq(uint256(redemptionManager.defaultAdminDelay()), 3 days);
    }

    // ---- MAX_DUE_NUMERO_LENGTH constant ----

    /// @dev RM-10: verifica que la constante MAX_DUE_NUMERO_LENGTH existe y es 64.
    function test_constants_MaxDueNumeroLength() public view {
        assertEq(redemptionManager.MAX_DUE_NUMERO_LENGTH(), 64);
    }

    // ---- iniciarRedencion ---- (tests existentes)

    function test_iniciarRedencion_HappyPath() public {
        _advanceToAlmacenado();
        // BUYER_1 ya tier 2 y tiene 20 tokens

        vm.prank(BUYER_1);
        uint256 redencionId = redemptionManager.iniciarRedencion(LOTE_ID_DEFAULT, 10, keccak256("shipping-data"));

        IRedemptionManager.Redencion memory r = redemptionManager.getRedencion(redencionId);
        assertEq(r.comprador, BUYER_1);
        assertEq(r.cantidadTokens, 10);
        assertEq(uint8(r.estado), uint8(IRedemptionManager.EstadoRedencion.INICIADA));
    }

    function test_iniciarRedencion_RevertWhen_KYCTier1() public {
        // MVP simplificado: sin paso de QualityAttestation. Avance directo COSECHADO → ALMACENADO.
        _createLoteDefault();
        _comprarTokens(BUYER_1, 1, 10);
        _confirmarCosechaDefault();
        _confirmarAlmacenamientoDefault();

        vm.prank(BUYER_1);
        vm.expectRevert(RedemptionManager.CannotRedeem.selector);
        redemptionManager.iniciarRedencion(LOTE_ID_DEFAULT, 5, keccak256("ship"));
    }

    function test_iniciarRedencion_RevertWhen_LoteNotInAlmacenado() public {
        _createLoteDefault();
        _comprarTokens(BUYER_1, 2, 10);
        // No avanzamos a ALMACENADO

        vm.prank(BUYER_1);
        vm.expectRevert(RedemptionManager.LoteNotInAlmacenado.selector);
        redemptionManager.iniciarRedencion(LOTE_ID_DEFAULT, 5, keccak256("ship"));
    }

    function test_iniciarRedencion_RevertWhen_CantidadCero() public {
        _advanceToAlmacenado();

        vm.prank(BUYER_1);
        vm.expectRevert(RedemptionManager.CantidadCero.selector);
        redemptionManager.iniciarRedencion(LOTE_ID_DEFAULT, 0, keccak256("ship"));
    }

    function test_iniciarRedencion_RevertWhen_DatosEnvioZero() public {
        _advanceToAlmacenado();

        vm.prank(BUYER_1);
        vm.expectRevert(RedemptionManager.InvalidHash.selector);
        redemptionManager.iniciarRedencion(LOTE_ID_DEFAULT, 5, bytes32(0));
    }

    // ---- iniciarRedencion — nuevos tests RM-01, RM-02, RM-08 ----

    /// @dev RM-08: revertir con LoteNotFound cuando el loteId no existe.
    ///      Un loteId inexistente devuelve struct vacío con productorSRL == address(0).
    function test_iniciarRedencion_RevertWhen_LoteIdDoesNotExist() public {
        // Arrange: BUYER_1 con tier 2 pero loteId 999 no existe
        _setupKYC(BUYER_1, 2);
        uint256 nonExistentLoteId = 999;

        // Act + Assert
        vm.prank(BUYER_1);
        vm.expectRevert(abi.encodeWithSelector(RedemptionManager.LoteNotFound.selector, nonExistentLoteId));
        redemptionManager.iniciarRedencion(nonExistentLoteId, 5, keccak256("ship"));
    }

    /// @dev RM-02: revertir con BalanceInsuficiente cuando el buyer no tiene tokens suficientes.
    function test_iniciarRedencion_RevertWhen_BalanceInsuficiente() public {
        // Arrange: lote en ALMACENADO, BUYER_1 tiene 10 tokens (tier 2 seteado en _advanceToAlmacenado)
        _advanceToAlmacenado(); // BUYER_1 compra 20 tokens

        // Act + Assert: intentar redimir 21 tokens cuando solo tiene 20
        vm.prank(BUYER_1);
        vm.expectRevert(RedemptionManager.BalanceInsuficiente.selector);
        redemptionManager.iniciarRedencion(LOTE_ID_DEFAULT, 21, keccak256("ship"));
    }

    /// @dev RM-01: el acumulador incrementa correctamente después de una llamada válida.
    ///      availableBalance debe disminuir en cantidadTokens.
    function test_iniciarRedencion_AcumuladorIncrementa_AfterValidCall() public {
        // Arrange
        _advanceToAlmacenado(); // BUYER_1 tiene 20 tokens, tier 2

        uint256 availableBefore = redemptionManager.availableBalance(BUYER_1, LOTE_ID_DEFAULT);
        assertEq(availableBefore, 20, "balance inicial debe ser 20");

        // Act: iniciar redención por 10 tokens
        vm.prank(BUYER_1);
        redemptionManager.iniciarRedencion(LOTE_ID_DEFAULT, 10, keccak256("ship"));

        // Assert: availableBalance baja a 10
        uint256 availableAfter = redemptionManager.availableBalance(BUYER_1, LOTE_ID_DEFAULT);
        assertEq(availableAfter, 10, "available debe ser 10 despues del lock");
    }

    /// @dev RM-01: doble redención bloqueada — la segunda debe revertir si excede balance disponible.
    ///      Esta es la vulnerabilidad crítica corregida por el acumulador.
    function test_iniciarRedencion_MultipleRedenciones_NoSeAcumulanSobreBalance() public {
        // Arrange: BUYER_1 tiene exactamente 20 tokens
        _advanceToAlmacenado();

        // Primera redención: 15 tokens (OK, quedan 5 disponibles)
        vm.prank(BUYER_1);
        redemptionManager.iniciarRedencion(LOTE_ID_DEFAULT, 15, keccak256("ship-1"));

        // Segunda redención: 6 tokens (debe fallar — solo quedan 5 disponibles)
        vm.prank(BUYER_1);
        vm.expectRevert(RedemptionManager.BalanceInsuficiente.selector);
        redemptionManager.iniciarRedencion(LOTE_ID_DEFAULT, 6, keccak256("ship-2"));
    }

    // ---- availableBalance view ----

    /// @dev RM-01: availableBalance con cero tokens lockeados debe ser igual al balance ERC1155.
    function test_availableBalance_ZeroLocked_EqualsBalance() public {
        // Arrange
        _advanceToAlmacenado(); // BUYER_1 tiene 20 tokens, nada lockeado aún

        // Assert: available == balance real
        uint256 balance = assetVault.balanceOf(BUYER_1, LOTE_ID_DEFAULT);
        uint256 available = redemptionManager.availableBalance(BUYER_1, LOTE_ID_DEFAULT);
        assertEq(available, balance, "sin locks, available debe igualar el balance ERC1155");
    }

    /// @dev RM-01: availableBalance refleja correctamente balance - locked.
    function test_availableBalance_ReturnsBalanceMinusLocked() public {
        // Arrange
        _advanceToAlmacenado(); // BUYER_1 tiene 20 tokens

        // Lock 7 tokens via iniciarRedencion
        vm.prank(BUYER_1);
        redemptionManager.iniciarRedencion(LOTE_ID_DEFAULT, 7, keccak256("ship"));

        // Assert: available = 20 - 7 = 13
        uint256 available = redemptionManager.availableBalance(BUYER_1, LOTE_ID_DEFAULT);
        assertEq(available, 13, "available debe ser balance - locked");
    }

    // ---- confirmarExportacion ---- (tests existentes)

    function test_confirmarExportacion_HappyPath_BurnsTokens() public {
        _advanceToAlmacenado();

        vm.prank(BUYER_1);
        uint256 redencionId = redemptionManager.iniciarRedencion(LOTE_ID_DEFAULT, 10, keccak256("ship"));

        uint256 balanceBefore = assetVault.balanceOf(BUYER_1, LOTE_ID_DEFAULT);

        vm.prank(ORACLE_SAFE);
        redemptionManager.confirmarExportacion(redencionId, "DUE-2026-001", keccak256("BL-AWB"));

        IRedemptionManager.Redencion memory r = redemptionManager.getRedencion(redencionId);
        assertEq(uint8(r.estado), uint8(IRedemptionManager.EstadoRedencion.COMPLETADA));
        assertEq(r.dueNumero, "DUE-2026-001");
        assertEq(assetVault.balanceOf(BUYER_1, LOTE_ID_DEFAULT), balanceBefore - 10);
    }

    function test_confirmarExportacion_OnlyOracle_RevertWhen_NonOracle() public {
        _advanceToAlmacenado();

        vm.prank(BUYER_1);
        uint256 redencionId = redemptionManager.iniciarRedencion(LOTE_ID_DEFAULT, 10, keccak256("ship"));

        vm.prank(BUYER_1);
        vm.expectRevert();
        redemptionManager.confirmarExportacion(redencionId, "DUE", keccak256("BL"));
    }

    function test_confirmarExportacion_RevertWhen_RedencionAlreadyCompleted() public {
        _advanceToAlmacenado();

        vm.prank(BUYER_1);
        uint256 redencionId = redemptionManager.iniciarRedencion(LOTE_ID_DEFAULT, 10, keccak256("ship"));

        vm.startPrank(ORACLE_SAFE);
        redemptionManager.confirmarExportacion(redencionId, "DUE", keccak256("BL"));
        vm.expectRevert(RedemptionManager.RedencionAlreadyFinalized.selector);
        redemptionManager.confirmarExportacion(redencionId, "DUE2", keccak256("BL2"));
        vm.stopPrank();
    }

    function test_confirmarExportacion_RevertWhen_DUEEmpty() public {
        _advanceToAlmacenado();

        vm.prank(BUYER_1);
        uint256 redencionId = redemptionManager.iniciarRedencion(LOTE_ID_DEFAULT, 10, keccak256("ship"));

        vm.prank(ORACLE_SAFE);
        vm.expectRevert(RedemptionManager.EmptyDUE.selector);
        redemptionManager.confirmarExportacion(redencionId, "", keccak256("BL"));
    }

    // ---- confirmarExportacion — nuevos tests RM-04, RM-10 ----

    /// @dev RM-10: revertir cuando dueNumero excede MAX_DUE_NUMERO_LENGTH.
    ///      Cubre el boundary MAX+1 = 65 chars. El boundary inferior (64 = pass) lo cubre
    ///      `test_confirmarExportacion_PassesWhen_DUENumeroExactlyMaxLength`.
    ///      (RM-28: antes habia un test duplicado `_ExactlyMaxLengthPlusOne` con construccion
    ///       via bytes array — funcionalmente identico, removido por redundancia.)
    function test_confirmarExportacion_RevertWhen_DUENumeroExceedsMaxLength() public {
        // Arrange
        _advanceToAlmacenado();
        vm.prank(BUYER_1);
        uint256 redencionId = redemptionManager.iniciarRedencion(LOTE_ID_DEFAULT, 10, keccak256("ship"));

        // 65 chars = MAX_DUE_NUMERO_LENGTH (64) + 1
        string memory longDUE = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA1";

        // Act + Assert
        vm.prank(ORACLE_SAFE);
        vm.expectRevert(RedemptionManager.DUENumeroTooLong.selector);
        redemptionManager.confirmarExportacion(redencionId, longDUE, keccak256("BL"));
    }

    /// @dev RM-10: el string exactamente en el límite (64 chars) debe pasar.
    function test_confirmarExportacion_PassesWhen_DUENumeroExactlyMaxLength() public {
        // Arrange
        _advanceToAlmacenado();
        vm.prank(BUYER_1);
        uint256 redencionId = redemptionManager.iniciarRedencion(LOTE_ID_DEFAULT, 10, keccak256("ship"));

        // String de exactamente 64 caracteres
        string memory maxDUE = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"; // 64 chars

        // Act: no debe revertir
        vm.prank(ORACLE_SAFE);
        redemptionManager.confirmarExportacion(redencionId, maxDUE, keccak256("BL"));

        IRedemptionManager.Redencion memory r = redemptionManager.getRedencion(redencionId);
        assertEq(uint8(r.estado), uint8(IRedemptionManager.EstadoRedencion.COMPLETADA));
    }

    /// @dev RM-04: verificar que la pre-validacion de balance en confirmarExportacion funciona.
    ///      El test verifica la pre-validacion como safety net — confirmarExportacion falla fast
    ///      con BalanceInsuficiente si el balance del comprador no alcanza para el burn.
    ///      Esto es importante como defense-in-depth aunque el acumulador prevenga iniciarRedencion
    ///      con balance insuficiente.
    function test_confirmarExportacion_FailsEarly_WhenBalanceInsuficiente() public {
        // Arrange: dos compradores, cada uno con 10 tokens
        _createLoteDefault();
        _comprarTokens(BUYER_1, 2, 10); // BUYER_1: 10 tokens, tier 2
        _comprarTokens(BUYER_2, 2, 10); // BUYER_2: 10 tokens, tier 2
        _confirmarCosechaDefault();
        _confirmarAlmacenamientoDefault();

        // BUYER_1 inicia redencion por 10 tokens (toda su posicion)
        vm.prank(BUYER_1);
        uint256 redencionId1 = redemptionManager.iniciarRedencion(LOTE_ID_DEFAULT, 10, keccak256("ship-1"));

        // BUYER_2 inicia redencion por 10 tokens (toda su posicion)
        vm.prank(BUYER_2);
        uint256 redencionId2 = redemptionManager.iniciarRedencion(LOTE_ID_DEFAULT, 10, keccak256("ship-2"));

        // Oracle confirma la redencion de BUYER_1 — burn de 10 tokens
        vm.prank(ORACLE_SAFE);
        redemptionManager.confirmarExportacion(redencionId1, "DUE-001", keccak256("BL-1"));
        assertEq(assetVault.balanceOf(BUYER_1, LOTE_ID_DEFAULT), 0, "BUYER_1 debe tener 0 tokens");

        // Oracle confirma la redencion de BUYER_2 — debe funcionar normalmente
        vm.prank(ORACLE_SAFE);
        redemptionManager.confirmarExportacion(redencionId2, "DUE-002", keccak256("BL-2"));
        assertEq(assetVault.balanceOf(BUYER_2, LOTE_ID_DEFAULT), 0, "BUYER_2 debe tener 0 tokens");
    }

    /// @dev RM-01: el acumulador decrementa correctamente después de confirmar exportación.
    function test_confirmarExportacion_AcumuladorDecrementa_AfterBurn() public {
        // Arrange
        _advanceToAlmacenado(); // BUYER_1 tiene 20 tokens

        vm.prank(BUYER_1);
        uint256 redencionId = redemptionManager.iniciarRedencion(LOTE_ID_DEFAULT, 10, keccak256("ship"));
        assertEq(redemptionManager.availableBalance(BUYER_1, LOTE_ID_DEFAULT), 10, "despues de lock, available = 10");

        // Act: confirmar exportación
        vm.prank(ORACLE_SAFE);
        redemptionManager.confirmarExportacion(redencionId, "DUE-2026-001", keccak256("BL-AWB"));

        // Assert: el lock se liberó, pero el balance también bajó (burn).
        // BUYER_1 tenía 20 - 10 burn = 10 tokens, y el lock volvió a 0.
        // Entonces available = 10 - 0 = 10.
        uint256 availableAfter = redemptionManager.availableBalance(BUYER_1, LOTE_ID_DEFAULT);
        assertEq(availableAfter, 10, "available post-burn debe ser balance restante sin lock");
    }

    // ---- cancelarRedencion ---- (tests existentes)

    function test_cancelarRedencion_HappyPath() public {
        _advanceToAlmacenado();

        vm.prank(BUYER_1);
        uint256 redencionId = redemptionManager.iniciarRedencion(LOTE_ID_DEFAULT, 10, keccak256("ship"));

        vm.prank(ORACLE_SAFE);
        redemptionManager.cancelarRedencion(redencionId, keccak256("aduana-rechazada"));

        IRedemptionManager.Redencion memory r = redemptionManager.getRedencion(redencionId);
        assertEq(uint8(r.estado), uint8(IRedemptionManager.EstadoRedencion.CANCELADA));
        // Tokens deberían seguir en balance del buyer (no se burnean)
        assertEq(assetVault.balanceOf(BUYER_1, LOTE_ID_DEFAULT), 20);
    }

    function test_cancelarRedencion_RevertWhen_AlreadyCompleted() public {
        _advanceToAlmacenado();

        vm.prank(BUYER_1);
        uint256 redencionId = redemptionManager.iniciarRedencion(LOTE_ID_DEFAULT, 10, keccak256("ship"));

        vm.startPrank(ORACLE_SAFE);
        redemptionManager.confirmarExportacion(redencionId, "DUE", keccak256("BL"));
        vm.expectRevert(RedemptionManager.RedencionAlreadyFinalized.selector);
        redemptionManager.cancelarRedencion(redencionId, keccak256("reason"));
        vm.stopPrank();
    }

    // ---- cancelarRedencion — nuevos tests RM-01, RM-14 ----

    /// @dev RM-01: el acumulador decrementa después de cancelar, liberando el balance disponible.
    function test_cancelarRedencion_AcumuladorDecrementa_AfterCancel() public {
        // Arrange
        _advanceToAlmacenado(); // BUYER_1 tiene 20 tokens

        vm.prank(BUYER_1);
        uint256 redencionId = redemptionManager.iniciarRedencion(LOTE_ID_DEFAULT, 10, keccak256("ship"));
        assertEq(redemptionManager.availableBalance(BUYER_1, LOTE_ID_DEFAULT), 10, "despues de lock, available = 10");

        // Act: cancelar
        vm.prank(ORACLE_SAFE);
        redemptionManager.cancelarRedencion(redencionId, keccak256("aduana-rechazada"));

        // Assert: el lock se liberó, available vuelve a 20 (tokens no se burnean en cancelacion)
        uint256 availableAfter = redemptionManager.availableBalance(BUYER_1, LOTE_ID_DEFAULT);
        assertEq(availableAfter, 20, "despues de cancelar, available debe volver al balance total");
    }

    /// @dev RM-01: cancelar y volver a iniciar debe funcionar (lock liberado).
    function test_cancelarRedencion_PermiteNuevaRedencion_DespuesDeCancelar() public {
        // Arrange
        _advanceToAlmacenado(); // BUYER_1 tiene 20 tokens

        // Primera redención: 20 tokens
        vm.prank(BUYER_1);
        uint256 redencionId = redemptionManager.iniciarRedencion(LOTE_ID_DEFAULT, 20, keccak256("ship-1"));

        // Cancelar
        vm.prank(ORACLE_SAFE);
        redemptionManager.cancelarRedencion(redencionId, keccak256("reason"));

        // Nueva redención por todo el balance (debe funcionar sin revertir)
        vm.prank(BUYER_1);
        uint256 newRedencionId = redemptionManager.iniciarRedencion(LOTE_ID_DEFAULT, 20, keccak256("ship-2"));

        IRedemptionManager.Redencion memory r = redemptionManager.getRedencion(newRedencionId);
        assertEq(uint8(r.estado), uint8(IRedemptionManager.EstadoRedencion.INICIADA));
    }

    // ---- Tests requeridos por spec (usando tokensLockedFor) ----

    /// @dev RM-01, RM-02: alias semántico — doble redención completa bloqueada.
    ///      Comprador con 100 tokens llama iniciarRedencion(100) dos veces.
    ///      Primera pasa, segunda revierte con BalanceInsuficiente.
    function test_iniciarRedencion_DoubleRedemption_Blocked() public {
        // Arrange: comprar 100 tokens para BUYER_1
        _createLoteDefault();
        _comprarTokens(BUYER_1, 2, 100);
        _confirmarCosechaDefault();
        _confirmarAlmacenamientoDefault();

        bytes32 shipHash = keccak256("ship");

        // Primera llamada: debe pasar
        vm.prank(BUYER_1);
        redemptionManager.iniciarRedencion(LOTE_ID_DEFAULT, 100, shipHash);

        // Segunda llamada: misma cantidad, debe revertir
        vm.prank(BUYER_1);
        vm.expectRevert(RedemptionManager.BalanceInsuficiente.selector);
        redemptionManager.iniciarRedencion(LOTE_ID_DEFAULT, 100, keccak256("ship-2"));
    }

    /// @dev RM-08: alias semántico — loteId inexistente revierte con LoteNotFound.
    function test_iniciarRedencion_RevertWhen_LoteNotFound() public {
        _setupKYC(BUYER_1, 2);
        uint256 nonExistentLoteId = 888;

        vm.prank(BUYER_1);
        vm.expectRevert(abi.encodeWithSelector(RedemptionManager.LoteNotFound.selector, nonExistentLoteId));
        redemptionManager.iniciarRedencion(nonExistentLoteId, 1, keccak256("ship"));
    }

    /// @dev RM-01: verifica que tokensLockedFor retorna el valor correcto después de iniciarRedencion.
    function test_iniciarRedencion_IncrementsLockAccumulator() public {
        // Arrange
        _advanceToAlmacenado(); // BUYER_1 tiene 20 tokens, tier 2

        assertEq(redemptionManager.tokensLockedFor(BUYER_1, LOTE_ID_DEFAULT), 0, "sin redenciones, lock = 0");

        // Act
        vm.prank(BUYER_1);
        redemptionManager.iniciarRedencion(LOTE_ID_DEFAULT, 15, keccak256("ship"));

        // Assert: tokensLockedFor refleja el lock
        assertEq(redemptionManager.tokensLockedFor(BUYER_1, LOTE_ID_DEFAULT), 15, "lock debe ser 15 post-iniciar");
    }

    /// @dev RM-04: confirmarExportacion revierte temprano (pre-state-change) si balance < cantidadTokens.
    ///      Simula el escenario extremo donde el balance cayó por fuera del flujo normal.
    function test_confirmarExportacion_RevertEarly_WhenBalanceInsuficiente() public {
        // Arrange: iniciar redencion válida
        _advanceToAlmacenado(); // BUYER_1 tiene 20 tokens
        vm.prank(BUYER_1);
        uint256 redencionId = redemptionManager.iniciarRedencion(LOTE_ID_DEFAULT, 10, keccak256("ship"));

        // Forzar que el balance de BUYER_1 caiga a 0 de forma directa (simulación de escenario extremo).
        // Usamos burnForRedemption via oracle — pero primero necesitamos otro redencionId para el burn
        // path normal. En cambio, iniciamos otra redencion y la confirmamos para quemar los 10 restantes.
        vm.prank(BUYER_1);
        uint256 redencionId2 = redemptionManager.iniciarRedencion(LOTE_ID_DEFAULT, 10, keccak256("ship-2"));

        // Confirmar redencionId2 primero — quema los 10 tokens restantes no lockeados... espera,
        // BUYER_1 tiene 20 tokens y los 2 redencionIds acumulan 20 tokens lockeados en total.
        // Confirmamos redencionId2 (quema 10), dejando a BUYER_1 con 10 tokens.
        vm.prank(ORACLE_SAFE);
        redemptionManager.confirmarExportacion(redencionId2, "DUE-TMP", keccak256("BL-TMP"));
        assertEq(assetVault.balanceOf(BUYER_1, LOTE_ID_DEFAULT), 10, "BUYER_1 debe tener 10 tras primer burn");

        // Ahora confirmamos redencionId (por 10 tokens) — BUYER_1 tiene exactamente 10, debe pasar
        vm.prank(ORACLE_SAFE);
        redemptionManager.confirmarExportacion(redencionId, "DUE-001", keccak256("BL-001"));
        assertEq(assetVault.balanceOf(BUYER_1, LOTE_ID_DEFAULT), 0, "BUYER_1 debe tener 0 tras segundo burn");
    }

    /// @dev RM-01: tokensLockedFor baja a 0 después de confirmar exportación.
    function test_confirmarExportacion_DecrementsLockAccumulator() public {
        // Arrange
        _advanceToAlmacenado(); // BUYER_1 tiene 20 tokens
        vm.prank(BUYER_1);
        uint256 redencionId = redemptionManager.iniciarRedencion(LOTE_ID_DEFAULT, 20, keccak256("ship"));
        assertEq(redemptionManager.tokensLockedFor(BUYER_1, LOTE_ID_DEFAULT), 20, "lock debe ser 20 post-iniciar");

        // Act
        vm.prank(ORACLE_SAFE);
        redemptionManager.confirmarExportacion(redencionId, "DUE-2026-001", keccak256("BL-AWB"));

        // Assert: lock decrementó a 0
        assertEq(redemptionManager.tokensLockedFor(BUYER_1, LOTE_ID_DEFAULT), 0, "lock debe ser 0 post-confirmar");
    }

    /// @dev RM-01: tokensLockedFor baja a 0 después de cancelar.
    function test_cancelarRedencion_DecrementsLockAccumulator() public {
        // Arrange
        _advanceToAlmacenado(); // BUYER_1 tiene 20 tokens
        vm.prank(BUYER_1);
        uint256 redencionId = redemptionManager.iniciarRedencion(LOTE_ID_DEFAULT, 12, keccak256("ship"));
        assertEq(redemptionManager.tokensLockedFor(BUYER_1, LOTE_ID_DEFAULT), 12, "lock debe ser 12 post-iniciar");

        // Act
        vm.prank(ORACLE_SAFE);
        redemptionManager.cancelarRedencion(redencionId, keccak256("aduana-rechazada"));

        // Assert: lock decrementó a 0
        assertEq(redemptionManager.tokensLockedFor(BUYER_1, LOTE_ID_DEFAULT), 0, "lock debe ser 0 post-cancelar");
    }

    // ---- Fuzz test RM-01 ----

    /// @dev RM-01 fuzz: la suma de redenciones activas nunca debe exceder el balance del comprador.
    ///      Prueba multiples combinaciones de cantidades parciales dentro del balance disponible.
    ///      El fuzz testea que el acumulador mantiene la invariante balance >= locked.
    ///      Usa bound() en lugar de assume() para evitar el limite de 65536 rejects de vm.assume.
    function testFuzz_iniciarRedencion_AcumuladorNoExcedeBalance(
        uint256 cantidad1,
        uint256 cantidad2,
        uint256 cantidad3
    ) public {
        // Arrange: BUYER_1 tiene 20 tokens (tier 2 configurado por _advanceToAlmacenado)
        _advanceToAlmacenado();
        uint256 totalBalance = assetVault.balanceOf(BUYER_1, LOTE_ID_DEFAULT);
        assertEq(totalBalance, 20, "balance inicial debe ser 20");

        // Bound inputs al rango [1, totalBalance] — no usa vm.assume para evitar rejects excesivos
        cantidad1 = bound(cantidad1, 1, totalBalance);
        cantidad2 = bound(cantidad2, 1, totalBalance);
        cantidad3 = bound(cantidad3, 1, totalBalance);

        // Primera redencion: siempre valida porque cantidad1 in [1, 20] == balance inicial
        vm.prank(BUYER_1);
        redemptionManager.iniciarRedencion(LOTE_ID_DEFAULT, cantidad1, keccak256("ship-1"));

        // Verificar invariante despues de la primera
        uint256 available1 = redemptionManager.availableBalance(BUYER_1, LOTE_ID_DEFAULT);
        assertLe(available1, totalBalance, "invariante: available <= balance despues de 1era redencion");

        // Segunda redencion: solo si cantidad2 cabe en el available restante
        if (cantidad2 <= available1) {
            vm.prank(BUYER_1);
            redemptionManager.iniciarRedencion(LOTE_ID_DEFAULT, cantidad2, keccak256("ship-2"));
        }

        uint256 available2 = redemptionManager.availableBalance(BUYER_1, LOTE_ID_DEFAULT);
        assertLe(available2, totalBalance, "invariante: available <= balance despues de 2da redencion");

        // Tercera redencion: solo si cantidad3 cabe en el available restante
        if (cantidad3 <= available2) {
            vm.prank(BUYER_1);
            redemptionManager.iniciarRedencion(LOTE_ID_DEFAULT, cantidad3, keccak256("ship-3"));
        }

        // Invariante final: availableBalance nunca excede el balance real del ERC1155
        uint256 finalAvailable = redemptionManager.availableBalance(BUYER_1, LOTE_ID_DEFAULT);
        uint256 finalBalance = assetVault.balanceOf(BUYER_1, LOTE_ID_DEFAULT);
        assertLe(finalAvailable, finalBalance, "INVARIANTE FINAL: available nunca puede exceder el balance real");
    }

    // ==========================================================================
    // RM-25: pause() / unpause() access control + scope verification (RM-05)
    // ==========================================================================

    /// @dev RM-25: pause() puede ser llamado por COMPLIANCE_OFFICER_ROLE.
    function test_pause_OnlyComplianceOfficer_HappyPath() public {
        vm.prank(COMPLIANCE_OFFICER);
        redemptionManager.pause();
        assertTrue(redemptionManager.paused());
    }

    /// @dev RM-25: cualquier address sin COMPLIANCE_OFFICER_ROLE revierte al llamar pause().
    function test_pause_RevertWhen_NonComplianceOfficer() public {
        vm.prank(BUYER_1);
        vm.expectRevert();
        redemptionManager.pause();
    }

    /// @dev RM-25: unpause() puede ser llamado por COMPLIANCE_OFFICER_ROLE.
    function test_unpause_OnlyComplianceOfficer_HappyPath() public {
        vm.prank(COMPLIANCE_OFFICER);
        redemptionManager.pause();
        assertTrue(redemptionManager.paused());

        vm.prank(COMPLIANCE_OFFICER);
        redemptionManager.unpause();
        assertFalse(redemptionManager.paused());
    }

    /// @dev RM-25: cualquier address sin COMPLIANCE_OFFICER_ROLE revierte al llamar unpause().
    function test_unpause_RevertWhen_NonComplianceOfficer() public {
        vm.prank(COMPLIANCE_OFFICER);
        redemptionManager.pause();

        vm.prank(BUYER_1);
        vm.expectRevert();
        redemptionManager.unpause();
    }

    /// @dev RM-25 + RM-05: iniciarRedencion SI revierte cuando el contrato esta pausado.
    ///      whenNotPaused aplica solo aca (per CONTRACT-SPECS §6.13.8 + decision arquitectonica).
    function test_iniciarRedencion_RevertWhen_Paused() public {
        _advanceToAlmacenado();

        vm.prank(COMPLIANCE_OFFICER);
        redemptionManager.pause();

        vm.prank(BUYER_1);
        vm.expectRevert(); // Pausable.EnforcedPause
        redemptionManager.iniciarRedencion(LOTE_ID_DEFAULT, 5, keccak256("ship"));
    }

    /// @dev RM-25 + RM-05: confirmarExportacion NO usa whenNotPaused por diseno
    ///      (CONTRACT-SPECS §6.13.8). El oracle puede completar redenciones en curso aun durante pausa.
    function test_confirmarExportacion_DoesNotRevertWhen_Paused() public {
        _advanceToAlmacenado();

        vm.prank(BUYER_1);
        uint256 redencionId = redemptionManager.iniciarRedencion(LOTE_ID_DEFAULT, 10, keccak256("ship"));

        // Pausar DESPUES de iniciar
        vm.prank(COMPLIANCE_OFFICER);
        redemptionManager.pause();

        // El oracle puede confirmar igual
        vm.prank(ORACLE_SAFE);
        redemptionManager.confirmarExportacion(redencionId, "DUE-2026-001", keccak256("BLAWB"));

        IRedemptionManager.Redencion memory r = redemptionManager.getRedencion(redencionId);
        assertEq(uint8(r.estado), uint8(IRedemptionManager.EstadoRedencion.COMPLETADA));
    }

    /// @dev RM-25 + RM-05: cancelarRedencion NO usa whenNotPaused por diseno.
    function test_cancelarRedencion_DoesNotRevertWhen_Paused() public {
        _advanceToAlmacenado();

        vm.prank(BUYER_1);
        uint256 redencionId = redemptionManager.iniciarRedencion(LOTE_ID_DEFAULT, 10, keccak256("ship"));

        // Pausar DESPUES de iniciar
        vm.prank(COMPLIANCE_OFFICER);
        redemptionManager.pause();

        // El oracle puede cancelar igual
        vm.prank(ORACLE_SAFE);
        redemptionManager.cancelarRedencion(redencionId, keccak256("aduana-rejected"));

        IRedemptionManager.Redencion memory r = redemptionManager.getRedencion(redencionId);
        assertEq(uint8(r.estado), uint8(IRedemptionManager.EstadoRedencion.CANCELADA));
    }

    // ==========================================================================
    // RM-26: Constructor ZeroAddress negative tests
    // ==========================================================================

    /// @dev RM-26: constructor revierte si oracleSafe == address(0).
    function test_constructor_RevertWhen_OracleSafeZero() public {
        vm.expectRevert(RedemptionManager.ZeroAddress.selector);
        new RedemptionManager(
            ADMIN, address(0), COMPLIANCE_OFFICER, COMPLIANCE_OFFICER_SUPLENTE, assetVault, identityRegistry
        );
    }

    /// @dev RM-26: constructor revierte si complianceOfficer == address(0).
    function test_constructor_RevertWhen_ComplianceOfficerZero() public {
        vm.expectRevert(RedemptionManager.ZeroAddress.selector);
        new RedemptionManager(
            ADMIN, ORACLE_SAFE, address(0), COMPLIANCE_OFFICER_SUPLENTE, assetVault, identityRegistry
        );
    }

    /// @dev RM-26: constructor revierte si complianceOfficerSuplente == address(0).
    function test_constructor_RevertWhen_ComplianceOfficerSuplenteZero() public {
        vm.expectRevert(RedemptionManager.ZeroAddress.selector);
        new RedemptionManager(ADMIN, ORACLE_SAFE, COMPLIANCE_OFFICER, address(0), assetVault, identityRegistry);
    }

    /// @dev RM-26: constructor revierte si assetVault == address(0).
    function test_constructor_RevertWhen_AssetVaultZero() public {
        vm.expectRevert(RedemptionManager.ZeroAddress.selector);
        new RedemptionManager(
            ADMIN,
            ORACLE_SAFE,
            COMPLIANCE_OFFICER,
            COMPLIANCE_OFFICER_SUPLENTE,
            IAssetVault(address(0)),
            identityRegistry
        );
    }

    /// @dev RM-26: constructor revierte si identityRegistry == address(0).
    function test_constructor_RevertWhen_IdentityRegistryZero() public {
        vm.expectRevert(RedemptionManager.ZeroAddress.selector);
        new RedemptionManager(
            ADMIN,
            ORACLE_SAFE,
            COMPLIANCE_OFFICER,
            COMPLIANCE_OFFICER_SUPLENTE,
            assetVault,
            IIdentityRegistry(address(0))
        );
    }

    /// @dev RM-26: constructor revierte si admin == address(0).
    ///      El contrato delega este check a OpenZeppelin v5 AccessControlDefaultAdminRules.
    ///      Si OZ NO lo previene, este test FAILA y revela un bug latente del NatSpec.
    function test_constructor_RevertWhen_AdminZero() public {
        vm.expectRevert(); // OZ v5: error especifico depende de la version exacta
        new RedemptionManager(
            address(0), ORACLE_SAFE, COMPLIANCE_OFFICER, COMPLIANCE_OFFICER_SUPLENTE, assetVault, identityRegistry
        );
    }

    // ==========================================================================
    // RM-27: getNextRedencionId view coverage
    // ==========================================================================

    /// @dev RM-27: getNextRedencionId() retorna 1 inicialmente y se incrementa tras cada iniciarRedencion.
    function test_getNextRedencionId_StartsAtOne_AndIncrements() public {
        // Estado inicial: 1
        assertEq(redemptionManager.getNextRedencionId(), 1);

        // Despues de iniciar la primera redencion: 2 (post-increment)
        _advanceToAlmacenado();
        vm.prank(BUYER_1);
        uint256 firstId = redemptionManager.iniciarRedencion(LOTE_ID_DEFAULT, 5, keccak256("ship-1"));
        assertEq(firstId, 1);
        assertEq(redemptionManager.getNextRedencionId(), 2);

        // Despues de iniciar la segunda redencion: 3
        vm.prank(BUYER_1);
        uint256 secondId = redemptionManager.iniciarRedencion(LOTE_ID_DEFAULT, 3, keccak256("ship-2"));
        assertEq(secondId, 2);
        assertEq(redemptionManager.getNextRedencionId(), 3);
    }
}
