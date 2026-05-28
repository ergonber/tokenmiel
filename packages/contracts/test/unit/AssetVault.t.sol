// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {BaseTest} from "../BaseTest.t.sol";
import {AssetVault} from "../../src/AssetVault.sol";
import {IAssetVault} from "../../src/interfaces/IAssetVault.sol";
import {ComplianceConstants} from "../../src/libraries/ComplianceConstants.sol";

contract AssetVaultTest is BaseTest {
    // ============================================================================
    // Constructor / FIX M-08
    // ============================================================================

    /// @dev FIX M-08: el constructor debe asignar DEFAULT_ADMIN_ROLE vía AccessControlDefaultAdminRules.
    ///      Verifica que `defaultAdmin()` retorna el ADMIN configurado y el delay es 3 días.
    function test_constructor_SetsAllRoles_Correctly() public view {
        // DEFAULT_ADMIN_ROLE via AccessControlDefaultAdminRules
        assertEq(assetVault.defaultAdmin(), ADMIN);
        assertTrue(assetVault.hasRole(assetVault.DEFAULT_ADMIN_ROLE(), ADMIN));

        // Roles operativos
        assertTrue(assetVault.hasRole(assetVault.ADMIN_ROLE(), ADMIN_OPERATOR));
        assertTrue(assetVault.hasRole(assetVault.BACKEND_SIGNER_ROLE(), BACKEND_SIGNER));
        assertTrue(assetVault.hasRole(assetVault.COMPLIANCE_OFFICER_ROLE(), COMPLIANCE_OFFICER));
        assertTrue(assetVault.hasRole(assetVault.COMPLIANCE_OFFICER_ROLE(), COMPLIANCE_OFFICER_SUPLENTE));
        assertTrue(assetVault.hasRole(assetVault.ORACLE_ROLE(), ORACLE_SAFE));
        assertTrue(assetVault.hasRole(assetVault.TREASURY_SRL_ROLE(), TREASURY_SRL));

        // Delay configurado
        assertEq(uint256(assetVault.defaultAdminDelay()), 3 days);
    }

    // ============================================================================
    // crearLote
    // ============================================================================

    function test_crearLote_HappyPath_CreatesLoteInPreventa() public {
        _createLoteDefault();

        IAssetVault.LoteMiel memory lote = assetVault.lotes(LOTE_ID_DEFAULT);
        assertEq(uint8(lote.estado), uint8(IAssetVault.LoteEstado.PREVENTA));
        assertEq(lote.kgEsperados, KG_ESPERADOS_DEFAULT);
        assertEq(lote.precioPorTokenUSDC, PRECIO_POR_TOKEN_DEFAULT);
        assertEq(lote.productorSRL, TREASURY_SRL);
        // Pre-compra: no hay USDC en escrow
        assertEq(lote.montoNetoPendiente, 0);
        assertEq(lote.reservaTecnicaUSDC, 0);
    }

    function test_crearLote_OnlyAdmin_RevertWhen_NonAdmin() public {
        vm.prank(BACKEND_SIGNER);
        vm.expectRevert();
        assetVault.crearLote(
            LOTE_ID_DEFAULT,
            KG_ESPERADOS_DEFAULT,
            PRECIO_POR_TOKEN_DEFAULT,
            uint64(block.timestamp + 90 days),
            ORIGEN_BOLIVIA,
            TREASURY_SRL,
            keccak256("FSA"),
            RESERVA_BPS_DEFAULT,
            VARIEDAD_ROMERO
        );
    }

    function test_crearLote_RevertWhen_ReservaBpsBelowMin() public {
        vm.prank(ADMIN_OPERATOR);
        vm.expectRevert(AssetVault.ReservaBpsOutOfRange.selector);
        assetVault.crearLote(
            LOTE_ID_DEFAULT,
            KG_ESPERADOS_DEFAULT,
            PRECIO_POR_TOKEN_DEFAULT,
            uint64(block.timestamp + 90 days),
            ORIGEN_BOLIVIA,
            TREASURY_SRL,
            keccak256("FSA"),
            1499,
            VARIEDAD_ROMERO
        );
    }

    function test_crearLote_RevertWhen_ReservaBpsAboveMax() public {
        vm.prank(ADMIN_OPERATOR);
        vm.expectRevert(AssetVault.ReservaBpsOutOfRange.selector);
        assetVault.crearLote(
            LOTE_ID_DEFAULT,
            KG_ESPERADOS_DEFAULT,
            PRECIO_POR_TOKEN_DEFAULT,
            uint64(block.timestamp + 90 days),
            ORIGEN_BOLIVIA,
            TREASURY_SRL,
            keccak256("FSA"),
            2001,
            VARIEDAD_ROMERO
        );
    }

    function test_crearLote_RevertWhen_LoteIdAlreadyExists() public {
        _createLoteDefault();

        vm.prank(ADMIN_OPERATOR);
        vm.expectRevert(AssetVault.LoteAlreadyExists.selector);
        assetVault.crearLote(
            LOTE_ID_DEFAULT,
            KG_ESPERADOS_DEFAULT,
            PRECIO_POR_TOKEN_DEFAULT,
            uint64(block.timestamp + 90 days),
            ORIGEN_BOLIVIA,
            TREASURY_SRL,
            keccak256("FSA"),
            RESERVA_BPS_DEFAULT,
            VARIEDAD_ROMERO
        );
    }

    function test_crearLote_RevertWhen_HashFSAZero() public {
        vm.prank(ADMIN_OPERATOR);
        vm.expectRevert(AssetVault.InvalidHash.selector);
        assetVault.crearLote(
            LOTE_ID_DEFAULT,
            KG_ESPERADOS_DEFAULT,
            PRECIO_POR_TOKEN_DEFAULT,
            uint64(block.timestamp + 90 days),
            ORIGEN_BOLIVIA,
            TREASURY_SRL,
            bytes32(0),
            RESERVA_BPS_DEFAULT,
            VARIEDAD_ROMERO
        );
    }

    function test_crearLote_EmitsLoteCreadoEvent() public {
        vm.expectEmit(true, false, true, true);
        emit IAssetVault.LoteCreado(
            LOTE_ID_DEFAULT,
            KG_ESPERADOS_DEFAULT,
            PRECIO_POR_TOKEN_DEFAULT,
            TREASURY_SRL,
            keccak256("FSA-DOC"),
            RESERVA_BPS_DEFAULT
        );
        _createLoteDefault();
    }

    // ============================================================================
    // comprar — Escrow total (H-01 Opción A)
    // ============================================================================

    function test_comprar_HappyPath_MintsCorrectAmount() public {
        _createLoteDefault();
        _setupKYC(BUYER_1, 1);

        uint256 cantidad = 10;
        uint256 monto = cantidad * PRECIO_POR_TOKEN_DEFAULT;
        usdc.mint(address(assetVault), monto);

        vm.prank(BACKEND_SIGNER);
        assetVault.comprar(LOTE_ID_DEFAULT, cantidad, BUYER_1, monto, keccak256("payment"));

        assertEq(assetVault.balanceOf(BUYER_1, LOTE_ID_DEFAULT), cantidad);
    }

    /// @dev FIX H-01: USDC del comprador queda en escrow, NO se transfiere al productor en comprar()
    function test_comprar_EscrowTotal_USDCStaysInContract() public {
        _createLoteDefault();
        _setupKYC(BUYER_1, 1);

        uint256 cantidad = 10;
        uint256 monto = cantidad * PRECIO_POR_TOKEN_DEFAULT;
        usdc.mint(address(assetVault), monto);

        uint256 contractBalanceBefore = usdc.balanceOf(address(assetVault));
        uint256 productorBalanceBefore = usdc.balanceOf(TREASURY_SRL);

        vm.prank(BACKEND_SIGNER);
        assetVault.comprar(LOTE_ID_DEFAULT, cantidad, BUYER_1, monto, keccak256("payment"));

        // Productor NO recibe USDC en comprar (escrow total)
        assertEq(usdc.balanceOf(TREASURY_SRL), productorBalanceBefore);
        // El contrato retiene 100% del pago
        assertEq(usdc.balanceOf(address(assetVault)), contractBalanceBefore);
    }

    function test_comprar_EscrowTotal_TracksMontoNetoPendiente() public {
        _createLoteDefault();
        _setupKYC(BUYER_1, 1);

        uint256 cantidad = 10;
        uint256 monto = cantidad * PRECIO_POR_TOKEN_DEFAULT;
        usdc.mint(address(assetVault), monto);

        vm.prank(BACKEND_SIGNER);
        assetVault.comprar(LOTE_ID_DEFAULT, cantidad, BUYER_1, monto, keccak256("payment"));

        uint256 reservaEsperada = (monto * RESERVA_BPS_DEFAULT) / 10_000;
        uint256 montoNetoEsperado = monto - reservaEsperada;

        IAssetVault.LoteMiel memory lote = assetVault.lotes(LOTE_ID_DEFAULT);
        assertEq(lote.reservaTecnicaUSDC, reservaEsperada);
        assertEq(lote.montoNetoPendiente, montoNetoEsperado);
    }

    function test_comprar_RevertWhen_NoKYC() public {
        _createLoteDefault();

        uint256 cantidad = 10;
        uint256 monto = cantidad * PRECIO_POR_TOKEN_DEFAULT;
        usdc.mint(address(assetVault), monto);

        vm.prank(BACKEND_SIGNER);
        vm.expectRevert(AssetVault.NotKYCVerified.selector);
        assetVault.comprar(LOTE_ID_DEFAULT, cantidad, NON_KYC, monto, keccak256("payment"));
    }

    function test_comprar_RevertWhen_Sanctioned() public {
        _createLoteDefault();
        _setupKYC(BUYER_SANCTIONED, 1);

        vm.prank(COMPLIANCE_OFFICER);
        identityRegistry.markSanctioned(BUYER_SANCTIONED, "OFAC", keccak256("OFAC-evidence"));

        uint256 cantidad = 10;
        uint256 monto = cantidad * PRECIO_POR_TOKEN_DEFAULT;
        usdc.mint(address(assetVault), monto);

        vm.prank(BACKEND_SIGNER);
        vm.expectRevert(AssetVault.NotKYCVerified.selector);
        assetVault.comprar(LOTE_ID_DEFAULT, cantidad, BUYER_SANCTIONED, monto, keccak256("payment"));
    }

    /// @dev FIX H-02: validación en gramos previene overmint por rounding
    function test_comprar_RevertWhen_KgExcedeSupplyDisponible() public {
        _createLoteDefault();
        _setupKYC(BUYER_1, 1);

        // KG_ESPERADOS = 100kg → max 200 tokens (cada token = 0.5 kg)
        uint256 cantidad = 201;
        uint256 monto = cantidad * PRECIO_POR_TOKEN_DEFAULT;
        usdc.mint(address(assetVault), monto);

        vm.prank(BACKEND_SIGNER);
        vm.expectRevert(AssetVault.KgSolicitadosExcedenSupply.selector);
        assetVault.comprar(LOTE_ID_DEFAULT, cantidad, BUYER_1, monto, keccak256("payment"));
    }

    /// @dev FIX H-02: con la validación en gramos, 200 tokens es exactamente 100 kg (límite)
    function test_comprar_AllowsExactCapacity() public {
        _createLoteDefault();
        _setupKYC(BUYER_1, 1);

        // 200 tokens × 500g = 100,000g = 100kg (exactly kgEsperados)
        uint256 cantidad = 200;
        uint256 monto = cantidad * PRECIO_POR_TOKEN_DEFAULT;
        usdc.mint(address(assetVault), monto);

        vm.prank(BACKEND_SIGNER);
        assetVault.comprar(LOTE_ID_DEFAULT, cantidad, BUYER_1, monto, keccak256("payment"));

        assertEq(assetVault.balanceOf(BUYER_1, LOTE_ID_DEFAULT), cantidad);
        assertEq(assetVault.kgDisponibles(LOTE_ID_DEFAULT), 0);
    }

    function test_comprar_RevertWhen_MontoUSDCInsuficiente() public {
        _createLoteDefault();
        _setupKYC(BUYER_1, 1);

        uint256 cantidad = 10;
        uint256 monto = cantidad * PRECIO_POR_TOKEN_DEFAULT - 1;
        usdc.mint(address(assetVault), monto);

        vm.prank(BACKEND_SIGNER);
        vm.expectRevert(AssetVault.MontoUSDCInsuficiente.selector);
        assetVault.comprar(LOTE_ID_DEFAULT, cantidad, BUYER_1, monto, keccak256("payment"));
    }

    function test_comprar_RevertWhen_LoteNotInPreventa() public {
        _createLoteDefault();
        _comprarTokens(BUYER_1, 1, 10);
        _confirmarCosechaDefault();
        // Now estado = COSECHADO

        _setupKYC(BUYER_2, 1);
        uint256 monto = 5 * PRECIO_POR_TOKEN_DEFAULT;
        usdc.mint(address(assetVault), monto);

        vm.prank(BACKEND_SIGNER);
        vm.expectRevert(AssetVault.LoteNotInPreventa.selector);
        assetVault.comprar(LOTE_ID_DEFAULT, 5, BUYER_2, monto, keccak256("payment"));
    }

    function test_comprar_RevertWhen_Paused() public {
        _createLoteDefault();
        _setupKYC(BUYER_1, 1);

        vm.prank(COMPLIANCE_OFFICER);
        assetVault.pause();

        uint256 cantidad = 10;
        uint256 monto = cantidad * PRECIO_POR_TOKEN_DEFAULT;
        usdc.mint(address(assetVault), monto);

        vm.prank(BACKEND_SIGNER);
        vm.expectRevert();
        assetVault.comprar(LOTE_ID_DEFAULT, cantidad, BUYER_1, monto, keccak256("payment"));
    }

    // ============================================================================
    // _update / P2P blocking
    // ============================================================================

    function test_transfer_RevertWhen_P2PBetweenUsers() public {
        _createLoteDefault();
        _comprarTokens(BUYER_1, 1, 10);
        _setupKYC(BUYER_2, 1);

        vm.prank(BUYER_1);
        vm.expectRevert(AssetVault.TransferP2PNoPermitido.selector);
        assetVault.safeTransferFrom(BUYER_1, BUYER_2, LOTE_ID_DEFAULT, 5, "");
    }

    function test_setApprovalForAll_RevertWhen_AnyCall() public {
        vm.prank(BUYER_1);
        vm.expectRevert(AssetVault.TransferP2PNoPermitido.selector);
        assetVault.setApprovalForAll(BUYER_2, true);
    }

    // ============================================================================
    // confirmarCosecha — libera monto neto al productor (escrow release)
    // ============================================================================

    function test_confirmarCosecha_HappyPath_TransitionsToCosechado() public {
        _createLoteDefault();
        _comprarTokens(BUYER_1, 1, 10);
        _confirmarCosechaDefault();

        IAssetVault.LoteMiel memory lote = assetVault.lotes(LOTE_ID_DEFAULT);
        assertEq(uint8(lote.estado), uint8(IAssetVault.LoteEstado.COSECHADO));
        assertEq(lote.kgCosechadosReal, KG_ESPERADOS_DEFAULT);
    }

    /// @dev FIX H-01: confirmarCosecha libera el montoNetoPendiente al productor (escrow release)
    function test_confirmarCosecha_ReleasesMontoNetoToProductor() public {
        _createLoteDefault();
        _comprarTokens(BUYER_1, 1, 10);

        // Pre-cosecha: montoNetoPendiente > 0
        IAssetVault.LoteMiel memory loteBefore = assetVault.lotes(LOTE_ID_DEFAULT);
        uint256 montoNetoPendientePre = loteBefore.montoNetoPendiente;
        assertGt(montoNetoPendientePre, 0);

        uint256 productorBalanceBefore = usdc.balanceOf(TREASURY_SRL);

        _confirmarCosechaDefault();

        // Post-cosecha: productor recibe montoNetoPendiente
        assertEq(usdc.balanceOf(TREASURY_SRL) - productorBalanceBefore, montoNetoPendientePre);

        IAssetVault.LoteMiel memory loteAfter = assetVault.lotes(LOTE_ID_DEFAULT);
        assertEq(loteAfter.montoNetoPendiente, 0);
    }

    function test_confirmarCosecha_OnlyOracle_RevertWhen_NonOracle() public {
        _createLoteDefault();
        vm.prank(BACKEND_SIGNER);
        vm.expectRevert();
        assetVault.confirmarCosecha(
            LOTE_ID_DEFAULT,
            KG_ESPERADOS_DEFAULT,
            keccak256("SENASAG"),
            keccak256("LAB"),
            keccak256("ACTA"),
            keccak256("FOTOS"),
            keccak256("ORIGEN"),
            IAssetVault.TipoCertificadoOrigen.FORM_A
        );
    }

    function test_confirmarCosecha_RevertWhen_LoteNotInPreventa() public {
        _createLoteDefault();
        _confirmarCosechaDefault();

        vm.prank(ORACLE_SAFE);
        vm.expectRevert(AssetVault.LoteNotInPreventa.selector);
        assetVault.confirmarCosecha(
            LOTE_ID_DEFAULT,
            KG_ESPERADOS_DEFAULT,
            keccak256("SENASAG"),
            keccak256("LAB"),
            keccak256("ACTA"),
            keccak256("FOTOS"),
            keccak256("ORIGEN"),
            IAssetVault.TipoCertificadoOrigen.FORM_A
        );
    }

    // ============================================================================
    // confirmarAlmacenamiento (PREVENTA → COSECHADO → ALMACENADO, sin QUALITY_ATTESTED)
    // ============================================================================

    function test_confirmarAlmacenamiento_HappyPath_TransitionsToAlmacenado() public {
        _createLoteDefault();
        _comprarTokens(BUYER_1, 1, 10);
        _confirmarCosechaDefault();
        _confirmarAlmacenamientoDefault();

        IAssetVault.LoteMiel memory lote = assetVault.lotes(LOTE_ID_DEFAULT);
        assertEq(uint8(lote.estado), uint8(IAssetVault.LoteEstado.ALMACENADO));
    }

    /// @dev Estado COSECHADO → ALMACENADO directo (sin QUALITY_ATTESTED en MVP)
    function test_confirmarAlmacenamiento_RevertWhen_LoteNotInCosechado() public {
        _createLoteDefault();
        // No avanzamos a COSECHADO

        vm.prank(ORACLE_SAFE);
        vm.expectRevert(AssetVault.LoteNotInCosechado.selector);
        assetVault.confirmarAlmacenamiento(LOTE_ID_DEFAULT, keccak256("DEP"), ALMACEN_AUTORIZADO);
    }

    // ============================================================================
    // marcarFallido — FIX M-05 restricciones
    // ============================================================================

    function test_marcarFallido_FromPreventa_Allowed() public {
        _createLoteDefault();

        vm.prank(ORACLE_SAFE);
        assetVault.marcarFallido(LOTE_ID_DEFAULT, "robo de colmenas");

        IAssetVault.LoteMiel memory lote = assetVault.lotes(LOTE_ID_DEFAULT);
        assertEq(uint8(lote.estado), uint8(IAssetVault.LoteEstado.FALLIDO));
        assertEq(lote.motivoFallo, "robo de colmenas");
    }

    function test_marcarFallido_FromCosechado_Allowed() public {
        _createLoteDefault();
        _comprarTokens(BUYER_1, 1, 10);
        _confirmarCosechaDefault();

        vm.prank(ORACLE_SAFE);
        assetVault.marcarFallido(LOTE_ID_DEFAULT, "contaminacion post-cosecha");

        IAssetVault.LoteMiel memory lote = assetVault.lotes(LOTE_ID_DEFAULT);
        assertEq(uint8(lote.estado), uint8(IAssetVault.LoteEstado.FALLIDO));
    }

    /// @dev FIX M-05: marcarFallido revierte desde ALMACENADO
    function test_marcarFallido_RevertWhen_FromAlmacenado() public {
        _advanceToAlmacenado();

        vm.prank(ORACLE_SAFE);
        vm.expectRevert(AssetVault.CannotFailLoteInThisState.selector);
        assetVault.marcarFallido(LOTE_ID_DEFAULT, "no permitido");
    }

    function test_marcarFallido_RevertWhen_AlreadyFallido() public {
        _createLoteDefault();

        vm.startPrank(ORACLE_SAFE);
        assetVault.marcarFallido(LOTE_ID_DEFAULT, "first");
        vm.expectRevert(AssetVault.CannotFailLoteInThisState.selector);
        assetVault.marcarFallido(LOTE_ID_DEFAULT, "second");
        vm.stopPrank();
    }

    // ============================================================================
    // reembolsarLoteFallido — FIX H-01 Escrow total = reembolso 100%
    // ============================================================================

    /// @dev FIX H-01: si lote FALLA en PREVENTA, reembolso es del 100% del pago original
    function test_reembolsarLoteFallido_PreCosecha_Refunds100Percent() public {
        _createLoteDefault();
        _comprarTokens(BUYER_1, 1, 10);

        // Pago original = 10 × 20 USDC = 200 USDC
        uint256 pagoOriginal = 10 * PRECIO_POR_TOKEN_DEFAULT;

        vm.prank(ORACLE_SAFE);
        assetVault.marcarFallido(LOTE_ID_DEFAULT, "fallo pre-cosecha");

        address[] memory buyers = new address[](1);
        buyers[0] = BUYER_1;

        uint256 balanceBefore = usdc.balanceOf(BUYER_1);

        vm.prank(ORACLE_SAFE);
        assetVault.reembolsarLoteFallido(LOTE_ID_DEFAULT, buyers);

        // Reembolso = 100% del pago original
        assertEq(usdc.balanceOf(BUYER_1) - balanceBefore, pagoOriginal);
        assertEq(assetVault.balanceOf(BUYER_1, LOTE_ID_DEFAULT), 0);
    }

    function test_reembolsarLoteFallido_RevertWhen_LoteNotFallido() public {
        _createLoteDefault();

        address[] memory buyers = new address[](1);
        buyers[0] = BUYER_1;

        vm.prank(ORACLE_SAFE);
        vm.expectRevert(AssetVault.LoteNotInFallido.selector);
        assetVault.reembolsarLoteFallido(LOTE_ID_DEFAULT, buyers);
    }

    /// @dev FIX M-06: reembolso a sancionados bloqueado
    function test_reembolsarLoteFallido_RevertWhen_BuyerSanctioned() public {
        _createLoteDefault();
        _comprarTokens(BUYER_1, 1, 10);

        // Sancionar al buyer DESPUÉS de la compra
        vm.prank(COMPLIANCE_OFFICER);
        identityRegistry.markSanctioned(BUYER_1, "OFAC", keccak256("OFAC-evidence"));

        vm.prank(ORACLE_SAFE);
        assetVault.marcarFallido(LOTE_ID_DEFAULT, "fallo");

        address[] memory buyers = new address[](1);
        buyers[0] = BUYER_1;

        vm.prank(ORACLE_SAFE);
        vm.expectRevert(AssetVault.CannotRefundBlockedAddress.selector);
        assetVault.reembolsarLoteFallido(LOTE_ID_DEFAULT, buyers);
    }

    /// @dev FIX H-01: reembolso bloqueado si el KYC del buyer fue revocado post-compra.
    ///      Setup: tier 1 → compra → revokeKYC → marcarFallido → reembolso debe revertir.
    function test_reembolsarLoteFallido_RevertWhen_BuyerRevoked() public {
        _createLoteDefault();
        _comprarTokens(BUYER_1, 1, 10);

        // Revocar KYC al buyer DESPUÉS de la compra (EDD failure, etc.)
        vm.prank(BACKEND_SIGNER);
        identityRegistry.revokeKYC(BUYER_1, "EDD failure post-compra");

        vm.prank(ORACLE_SAFE);
        assetVault.marcarFallido(LOTE_ID_DEFAULT, "fallo pre-cosecha");

        address[] memory buyers = new address[](1);
        buyers[0] = BUYER_1;

        vm.prank(ORACLE_SAFE);
        vm.expectRevert(AssetVault.CannotRefundRevokedAddress.selector);
        assetVault.reembolsarLoteFallido(LOTE_ID_DEFAULT, buyers);
    }

    /// @dev FIX Opt-B2: batch size limitado a MAX_REFUND_BATCH = 100
    function test_reembolsarLoteFallido_RevertWhen_BatchTooLarge() public {
        _createLoteDefault();
        _comprarTokens(BUYER_1, 1, 10);

        vm.prank(ORACLE_SAFE);
        assetVault.marcarFallido(LOTE_ID_DEFAULT, "fallo");

        // Array de 101 buyers (excede MAX_REFUND_BATCH = 100)
        address[] memory buyers = new address[](101);
        for (uint256 i = 0; i < 101; i++) {
            buyers[i] = address(uint160(0x9000 + i));
        }

        vm.prank(ORACLE_SAFE);
        vm.expectRevert(AssetVault.BatchTooLarge.selector);
        assetVault.reembolsarLoteFallido(LOTE_ID_DEFAULT, buyers);
    }

    // ============================================================================
    // liberarReservaTecnica — desde COSECHADO (CONFLICT-1 Opción A)
    // ============================================================================

    function test_liberarReservaTecnica_HappyPath_TransfersUSDCToProductor() public {
        _createLoteDefault();
        _comprarTokens(BUYER_1, 1, 10);
        _confirmarCosechaDefault();
        // Estado = COSECHADO (montoNeto ya liberado, queda reserva)

        uint256 reservaInicial = assetVault.reservaTecnicaActual(LOTE_ID_DEFAULT);
        assertGt(reservaInicial, 0);

        uint256 balanceBefore = usdc.balanceOf(TREASURY_SRL);

        vm.prank(TREASURY_SRL);
        assetVault.liberarReservaTecnica(LOTE_ID_DEFAULT);

        assertEq(usdc.balanceOf(TREASURY_SRL) - balanceBefore, reservaInicial);
        assertEq(assetVault.reservaTecnicaActual(LOTE_ID_DEFAULT), 0);
    }

    /// @dev CONFLICT-1: liberar reserva NO permitido en PREVENTA (pre-cosecha)
    function test_liberarReservaTecnica_RevertWhen_Preventa() public {
        _createLoteDefault();
        _comprarTokens(BUYER_1, 1, 10);
        // Estado = PREVENTA (cosecha no confirmada)

        vm.prank(TREASURY_SRL);
        vm.expectRevert(AssetVault.LoteNotInCosechado.selector);
        assetVault.liberarReservaTecnica(LOTE_ID_DEFAULT);
    }

    function test_liberarReservaTecnica_RevertWhen_AlreadyReleased() public {
        _createLoteDefault();
        _comprarTokens(BUYER_1, 1, 10);
        _confirmarCosechaDefault();

        vm.startPrank(TREASURY_SRL);
        assetVault.liberarReservaTecnica(LOTE_ID_DEFAULT);
        vm.expectRevert(AssetVault.ReservaAlreadyReleased.selector);
        assetVault.liberarReservaTecnica(LOTE_ID_DEFAULT);
        vm.stopPrank();
    }

    // ============================================================================
    // pause / unpause — ADR-016 (asymmetry: pause=Compliance|Admin, unpause=Admin only)
    // ============================================================================

    /// @dev ADR-016: COMPLIANCE_OFFICER_ROLE puede pausar (path 1).
    function test_pause_ByComplianceOfficer_HappyPath() public {
        vm.prank(COMPLIANCE_OFFICER);
        assetVault.pause();
        assertTrue(assetVault.paused());
    }

    /// @dev ADR-016: DEFAULT_ADMIN_ROLE tambien puede pausar (path 2 — defensa cruzada).
    function test_pause_ByDefaultAdmin_HappyPath() public {
        vm.prank(ADMIN);
        assetVault.pause();
        assertTrue(assetVault.paused());
    }

    /// @dev ADR-016: address sin COMPLIANCE_OFFICER ni DEFAULT_ADMIN revierte con UnauthorizedPauseActor.
    function test_pause_RevertWhen_UnauthorizedActor() public {
        vm.prank(BUYER_1);
        vm.expectRevert(AssetVault.UnauthorizedPauseActor.selector);
        assetVault.pause();
    }

    /// @dev ADR-016: unpause SOLO via DEFAULT_ADMIN_ROLE (Safe 2-de-3) — restaura comprar despues.
    function test_unpause_RestoresComprar() public {
        _createLoteDefault();

        // Pausar via COMPLIANCE_OFFICER (rapido, sigue siendo valido)
        vm.prank(COMPLIANCE_OFFICER);
        assetVault.pause();
        assertTrue(assetVault.paused());

        // Despausar via ADMIN (Safe 2-de-3) — decision deliberada post-incidente
        vm.prank(ADMIN);
        assetVault.unpause();
        assertFalse(assetVault.paused());

        // Comprar funciona normalmente despues del unpause
        _comprarTokens(BUYER_1, 1, 1);
        assertEq(assetVault.balanceOf(BUYER_1, LOTE_ID_DEFAULT), 1);
    }

    /// @dev ADR-016 (cambio de seguridad): COMPLIANCE_OFFICER ya NO puede despausar.
    function test_unpause_RevertWhen_ComplianceOfficer() public {
        vm.prank(COMPLIANCE_OFFICER);
        assetVault.pause();

        vm.prank(COMPLIANCE_OFFICER);
        vm.expectRevert(); // OZ AccessControl — Compliance Officer no tiene DEFAULT_ADMIN_ROLE
        assetVault.unpause();
    }

    /// @dev ADR-016: address random sin DEFAULT_ADMIN_ROLE revierte al unpause.
    function test_unpause_RevertWhen_NonDefaultAdmin() public {
        vm.prank(COMPLIANCE_OFFICER);
        assetVault.pause();

        vm.prank(BUYER_1);
        vm.expectRevert();
        assetVault.unpause();
    }

    // ============================================================================
    // View functions
    // ============================================================================

    function test_kgDisponibles_ReturnsCorrectAmount() public {
        _createLoteDefault();
        assertEq(assetVault.kgDisponibles(LOTE_ID_DEFAULT), KG_ESPERADOS_DEFAULT);

        _comprarTokens(BUYER_1, 1, 20); // 20 tokens = 10 kg
        assertEq(assetVault.kgDisponibles(LOTE_ID_DEFAULT), KG_ESPERADOS_DEFAULT - 10);
    }
}
