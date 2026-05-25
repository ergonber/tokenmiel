// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {BaseTest} from "../BaseTest.t.sol";
import {RedemptionManager} from "../../src/RedemptionManager.sol";
import {IRedemptionManager} from "../../src/interfaces/IRedemptionManager.sol";
import {IAssetVault} from "../../src/interfaces/IAssetVault.sol";

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
        assertTrue(
            redemptionManager.hasRole(redemptionManager.COMPLIANCE_OFFICER_ROLE(), COMPLIANCE_OFFICER_SUPLENTE)
        );

        // Delay configurado
        assertEq(uint256(redemptionManager.defaultAdminDelay()), 3 days);
    }

    // ---- iniciarRedencion ----

    function test_iniciarRedencion_HappyPath() public {
        _advanceToAlmacenado();
        // BUYER_1 ya tier 2 y tiene 20 tokens

        vm.prank(BUYER_1);
        uint256 redencionId = redemptionManager.iniciarRedencion(
            LOTE_ID_DEFAULT, 10, keccak256("shipping-data")
        );

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

    // ---- confirmarExportacion ----

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

    // ---- cancelarRedencion ----

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
}
