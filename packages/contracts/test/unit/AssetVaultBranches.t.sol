// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {BaseTest} from "../BaseTest.t.sol";
import {AssetVault} from "../../src/AssetVault.sol";
import {IdentityRegistry} from "../../src/IdentityRegistry.sol";
import {IAssetVault} from "../../src/interfaces/IAssetVault.sol";
import {IIdentityRegistry} from "../../src/interfaces/IIdentityRegistry.sol";
import {MockUSDC} from "../BaseTest.t.sol";

/// @title AssetVaultBranchesTest
/// @notice Targeted branch-coverage tests for AssetVault.sol.
///         Each test covers exactly one uncovered branch identified by the lcov report.
contract AssetVaultBranchesTest is BaseTest {
    // ---- Branch 160: _requireNonZero via constructor ----

    /// @dev Deploy with adminOperator = address(0) → ZeroAddress (first _requireNonZero call)
    function test_RevertWhen_Constructor_AdminOperatorZero() public {
        AssetVault.InitParams memory p = AssetVault.InitParams({
            admin: ADMIN,
            adminOperator: address(0),
            backendSigner: BACKEND_SIGNER,
            complianceOfficer: COMPLIANCE_OFFICER,
            complianceOfficerSuplente: COMPLIANCE_OFFICER_SUPLENTE,
            oracleSafe: ORACLE_SAFE,
            treasurySRL: TREASURY_SRL,
            usdc: usdc,
            identityRegistry: identityRegistry,
            uri: "https://meta.example/{id}.json"
        });
        vm.expectRevert(AssetVault.ZeroAddress.selector);
        new AssetVault(p);
    }

    /// @dev Deploy with backendSigner = address(0) → ZeroAddress
    function test_RevertWhen_Constructor_BackendSignerZero() public {
        AssetVault.InitParams memory p = AssetVault.InitParams({
            admin: ADMIN,
            adminOperator: ADMIN_OPERATOR,
            backendSigner: address(0),
            complianceOfficer: COMPLIANCE_OFFICER,
            complianceOfficerSuplente: COMPLIANCE_OFFICER_SUPLENTE,
            oracleSafe: ORACLE_SAFE,
            treasurySRL: TREASURY_SRL,
            usdc: usdc,
            identityRegistry: identityRegistry,
            uri: "https://meta.example/{id}.json"
        });
        vm.expectRevert(AssetVault.ZeroAddress.selector);
        new AssetVault(p);
    }

    /// @dev Deploy with complianceOfficer = address(0) → ZeroAddress
    function test_RevertWhen_Constructor_ComplianceOfficerZero() public {
        AssetVault.InitParams memory p = AssetVault.InitParams({
            admin: ADMIN,
            adminOperator: ADMIN_OPERATOR,
            backendSigner: BACKEND_SIGNER,
            complianceOfficer: address(0),
            complianceOfficerSuplente: COMPLIANCE_OFFICER_SUPLENTE,
            oracleSafe: ORACLE_SAFE,
            treasurySRL: TREASURY_SRL,
            usdc: usdc,
            identityRegistry: identityRegistry,
            uri: "https://meta.example/{id}.json"
        });
        vm.expectRevert(AssetVault.ZeroAddress.selector);
        new AssetVault(p);
    }

    /// @dev Deploy with complianceOfficerSuplente = address(0) → ZeroAddress
    function test_RevertWhen_Constructor_ComplianceOfficerSuplenteZero() public {
        AssetVault.InitParams memory p = AssetVault.InitParams({
            admin: ADMIN,
            adminOperator: ADMIN_OPERATOR,
            backendSigner: BACKEND_SIGNER,
            complianceOfficer: COMPLIANCE_OFFICER,
            complianceOfficerSuplente: address(0),
            oracleSafe: ORACLE_SAFE,
            treasurySRL: TREASURY_SRL,
            usdc: usdc,
            identityRegistry: identityRegistry,
            uri: "https://meta.example/{id}.json"
        });
        vm.expectRevert(AssetVault.ZeroAddress.selector);
        new AssetVault(p);
    }

    /// @dev Deploy with oracleSafe = address(0) → ZeroAddress
    function test_RevertWhen_Constructor_OracleSafeZero() public {
        AssetVault.InitParams memory p = AssetVault.InitParams({
            admin: ADMIN,
            adminOperator: ADMIN_OPERATOR,
            backendSigner: BACKEND_SIGNER,
            complianceOfficer: COMPLIANCE_OFFICER,
            complianceOfficerSuplente: COMPLIANCE_OFFICER_SUPLENTE,
            oracleSafe: address(0),
            treasurySRL: TREASURY_SRL,
            usdc: usdc,
            identityRegistry: identityRegistry,
            uri: "https://meta.example/{id}.json"
        });
        vm.expectRevert(AssetVault.ZeroAddress.selector);
        new AssetVault(p);
    }

    /// @dev Deploy with treasurySRL = address(0) → ZeroAddress
    function test_RevertWhen_Constructor_TreasurySRLZero() public {
        AssetVault.InitParams memory p = AssetVault.InitParams({
            admin: ADMIN,
            adminOperator: ADMIN_OPERATOR,
            backendSigner: BACKEND_SIGNER,
            complianceOfficer: COMPLIANCE_OFFICER,
            complianceOfficerSuplente: COMPLIANCE_OFFICER_SUPLENTE,
            oracleSafe: ORACLE_SAFE,
            treasurySRL: address(0),
            usdc: usdc,
            identityRegistry: identityRegistry,
            uri: "https://meta.example/{id}.json"
        });
        vm.expectRevert(AssetVault.ZeroAddress.selector);
        new AssetVault(p);
    }

    /// @dev Deploy with usdc = address(0) → ZeroAddress
    function test_RevertWhen_Constructor_UsdcZero() public {
        AssetVault.InitParams memory p = AssetVault.InitParams({
            admin: ADMIN,
            adminOperator: ADMIN_OPERATOR,
            backendSigner: BACKEND_SIGNER,
            complianceOfficer: COMPLIANCE_OFFICER,
            complianceOfficerSuplente: COMPLIANCE_OFFICER_SUPLENTE,
            oracleSafe: ORACLE_SAFE,
            treasurySRL: TREASURY_SRL,
            usdc: MockUSDC(address(0)),
            identityRegistry: identityRegistry,
            uri: "https://meta.example/{id}.json"
        });
        vm.expectRevert(AssetVault.ZeroAddress.selector);
        new AssetVault(p);
    }

    /// @dev Deploy with identityRegistry = address(0) → ZeroAddress
    function test_RevertWhen_Constructor_IdentityRegistryZero() public {
        AssetVault.InitParams memory p = AssetVault.InitParams({
            admin: ADMIN,
            adminOperator: ADMIN_OPERATOR,
            backendSigner: BACKEND_SIGNER,
            complianceOfficer: COMPLIANCE_OFFICER,
            complianceOfficerSuplente: COMPLIANCE_OFFICER_SUPLENTE,
            oracleSafe: ORACLE_SAFE,
            treasurySRL: TREASURY_SRL,
            usdc: usdc,
            identityRegistry: IdentityRegistry(address(0)),
            uri: "https://meta.example/{id}.json"
        });
        vm.expectRevert(AssetVault.ZeroAddress.selector);
        new AssetVault(p);
    }

    // ---- Branch 166: setRedemptionManager(address(0)) ----

    function test_RevertWhen_SetRedemptionManager_ZeroAddress() public {
        // Deploy a fresh vault without a RM set
        AssetVault.InitParams memory p = AssetVault.InitParams({
            admin: ADMIN,
            adminOperator: ADMIN_OPERATOR,
            backendSigner: BACKEND_SIGNER,
            complianceOfficer: COMPLIANCE_OFFICER,
            complianceOfficerSuplente: COMPLIANCE_OFFICER_SUPLENTE,
            oracleSafe: ORACLE_SAFE,
            treasurySRL: TREASURY_SRL,
            usdc: usdc,
            identityRegistry: identityRegistry,
            uri: "https://meta.example/{id}.json"
        });
        AssetVault freshVault = new AssetVault(p);

        vm.prank(ADMIN);
        vm.expectRevert(AssetVault.ZeroAddress.selector);
        freshVault.setRedemptionManager(address(0));
    }

    // ---- Branch 167: setRedemptionManager twice (already set) ----

    function test_RevertWhen_SetRedemptionManager_AlreadySet() public {
        // setUp() already called setRedemptionManager once
        vm.prank(ADMIN);
        vm.expectRevert(AssetVault.RedemptionManagerAlreadySet.selector);
        assetVault.setRedemptionManager(address(redemptionManager));
    }

    // ---- Branch 186: crearLote kgEsperados = 0 ----

    function test_RevertWhen_CrearLote_KgEsperadosZero() public {
        vm.prank(ADMIN_OPERATOR);
        vm.expectRevert(AssetVault.InvalidKgEsperados.selector);
        assetVault.crearLote(
            LOTE_ID_DEFAULT,
            0, // kgEsperados = 0
            PRECIO_POR_TOKEN_DEFAULT,
            uint64(block.timestamp + 90 days),
            ORIGEN_BOLIVIA,
            TREASURY_SRL,
            keccak256("FSA-DOC"),
            RESERVA_BPS_DEFAULT,
            VARIEDAD_ROMERO
        );
    }

    // ---- Branch 187: crearLote precioPorTokenUSDC = 0 ----

    function test_RevertWhen_CrearLote_PrecioZero() public {
        vm.prank(ADMIN_OPERATOR);
        vm.expectRevert(AssetVault.InvalidPrecio.selector);
        assetVault.crearLote(
            LOTE_ID_DEFAULT,
            KG_ESPERADOS_DEFAULT,
            0, // precio = 0
            uint64(block.timestamp + 90 days),
            ORIGEN_BOLIVIA,
            TREASURY_SRL,
            keccak256("FSA-DOC"),
            RESERVA_BPS_DEFAULT,
            VARIEDAD_ROMERO
        );
    }

    // ---- Branch 188: crearLote productorSRL = address(0) ----

    function test_RevertWhen_CrearLote_ProductorSRLZero() public {
        vm.prank(ADMIN_OPERATOR);
        vm.expectRevert(AssetVault.ZeroAddress.selector);
        assetVault.crearLote(
            LOTE_ID_DEFAULT,
            KG_ESPERADOS_DEFAULT,
            PRECIO_POR_TOKEN_DEFAULT,
            uint64(block.timestamp + 90 days),
            ORIGEN_BOLIVIA,
            address(0), // productorSRL = address(0)
            keccak256("FSA-DOC"),
            RESERVA_BPS_DEFAULT,
            VARIEDAD_ROMERO
        );
    }

    // ---- Branch 223: comprar on non-existent lote ----

    function test_RevertWhen_Comprar_LoteNotExists() public {
        vm.prank(BACKEND_SIGNER);
        vm.expectRevert(AssetVault.LoteNotExists.selector);
        assetVault.comprar(999, 10, BUYER_1, 200e6, keccak256("pay"));
    }

    // ---- Branch 225: comprar cantidadTokens = 0 ----

    function test_RevertWhen_Comprar_CantidadTokensCero() public {
        _createLoteDefault();
        _setupKYC(BUYER_1, 2);

        vm.prank(BACKEND_SIGNER);
        vm.expectRevert(AssetVault.CantidadTokensCero.selector);
        assetVault.comprar(LOTE_ID_DEFAULT, 0, BUYER_1, 0, keccak256("pay"));
    }

    // ---- Branch 226: comprar paymentRefHash = bytes32(0) ----

    function test_RevertWhen_Comprar_InvalidPaymentRefHash() public {
        _createLoteDefault();
        _setupKYC(BUYER_1, 2);

        vm.prank(BACKEND_SIGNER);
        vm.expectRevert(AssetVault.InvalidHash.selector);
        assetVault.comprar(LOTE_ID_DEFAULT, 10, BUYER_1, 200e6, bytes32(0));
    }

    // ---- Branch 278: confirmarCosecha non-existent lote ----

    function test_RevertWhen_ConfirmarCosecha_LoteNotExists() public {
        vm.prank(ORACLE_SAFE);
        vm.expectRevert(AssetVault.LoteNotExists.selector);
        assetVault.confirmarCosecha(
            999,
            KG_ESPERADOS_DEFAULT,
            keccak256("SENASAG"),
            keccak256("LAB"),
            keccak256("ACTA"),
            keccak256("FOTOS"),
            keccak256("ORIGEN"),
            IAssetVault.TipoCertificadoOrigen.FORM_A
        );
    }

    // ---- Branch 280: confirmarCosecha kgRealCosechado = 0 ----

    function test_RevertWhen_ConfirmarCosecha_KgRealZero() public {
        _createLoteDefault();

        vm.prank(ORACLE_SAFE);
        vm.expectRevert(AssetVault.InvalidKgEsperados.selector);
        assetVault.confirmarCosecha(
            LOTE_ID_DEFAULT,
            0, // kgRealCosechado = 0
            keccak256("SENASAG"),
            keccak256("LAB"),
            keccak256("ACTA"),
            keccak256("FOTOS"),
            keccak256("ORIGEN"),
            IAssetVault.TipoCertificadoOrigen.FORM_A
        );
    }

    // ---- Branch 281: confirmarCosecha hashSenasag = bytes32(0) ----

    function test_RevertWhen_ConfirmarCosecha_HashSenasagInvalid() public {
        _createLoteDefault();

        vm.prank(ORACLE_SAFE);
        vm.expectRevert(AssetVault.InvalidHash.selector);
        assetVault.confirmarCosecha(
            LOTE_ID_DEFAULT,
            KG_ESPERADOS_DEFAULT,
            bytes32(0), // hashSenasag = 0
            keccak256("LAB"),
            keccak256("ACTA"),
            keccak256("FOTOS"),
            keccak256("ORIGEN"),
            IAssetVault.TipoCertificadoOrigen.FORM_A
        );
    }

    // ---- Branch 282: confirmarCosecha hashAnalisisLab = bytes32(0) ----

    function test_RevertWhen_ConfirmarCosecha_HashAnalisisLabInvalid() public {
        _createLoteDefault();

        vm.prank(ORACLE_SAFE);
        vm.expectRevert(AssetVault.InvalidHash.selector);
        assetVault.confirmarCosecha(
            LOTE_ID_DEFAULT,
            KG_ESPERADOS_DEFAULT,
            keccak256("SENASAG"),
            bytes32(0), // hashAnalisisLab = 0
            keccak256("ACTA"),
            keccak256("FOTOS"),
            keccak256("ORIGEN"),
            IAssetVault.TipoCertificadoOrigen.FORM_A
        );
    }

    // ---- Branch 283: confirmarCosecha hashActaCosecha = bytes32(0) ----

    function test_RevertWhen_ConfirmarCosecha_HashActaCosechaInvalid() public {
        _createLoteDefault();

        vm.prank(ORACLE_SAFE);
        vm.expectRevert(AssetVault.InvalidHash.selector);
        assetVault.confirmarCosecha(
            LOTE_ID_DEFAULT,
            KG_ESPERADOS_DEFAULT,
            keccak256("SENASAG"),
            keccak256("LAB"),
            bytes32(0), // hashActaCosecha = 0
            keccak256("FOTOS"),
            keccak256("ORIGEN"),
            IAssetVault.TipoCertificadoOrigen.FORM_A
        );
    }

    // ---- Branch 284: confirmarCosecha hashFotosApiario = bytes32(0) ----

    function test_RevertWhen_ConfirmarCosecha_HashFotosApiarioInvalid() public {
        _createLoteDefault();

        vm.prank(ORACLE_SAFE);
        vm.expectRevert(AssetVault.InvalidHash.selector);
        assetVault.confirmarCosecha(
            LOTE_ID_DEFAULT,
            KG_ESPERADOS_DEFAULT,
            keccak256("SENASAG"),
            keccak256("LAB"),
            keccak256("ACTA"),
            bytes32(0), // hashFotosApiario = 0
            keccak256("ORIGEN"),
            IAssetVault.TipoCertificadoOrigen.FORM_A
        );
    }

    // ---- Branch 285: confirmarCosecha hashCertificadoOrigen = bytes32(0) ----

    function test_RevertWhen_ConfirmarCosecha_HashCertificadoOrigenInvalid() public {
        _createLoteDefault();

        vm.prank(ORACLE_SAFE);
        vm.expectRevert(AssetVault.InvalidHash.selector);
        assetVault.confirmarCosecha(
            LOTE_ID_DEFAULT,
            KG_ESPERADOS_DEFAULT,
            keccak256("SENASAG"),
            keccak256("LAB"),
            keccak256("ACTA"),
            keccak256("FOTOS"),
            bytes32(0), // hashCertificadoOrigen = 0
            IAssetVault.TipoCertificadoOrigen.FORM_A
        );
    }

    // ---- Branch 320: confirmarAlmacenamiento non-existent lote ----

    function test_RevertWhen_ConfirmarAlmacenamiento_LoteNotExists() public {
        vm.prank(ORACLE_SAFE);
        vm.expectRevert(AssetVault.LoteNotExists.selector);
        assetVault.confirmarAlmacenamiento(999, keccak256("DEPOSITO"), ALMACEN_AUTORIZADO);
    }

    // ---- Branch 322: confirmarAlmacenamiento hashContratoDeposito = bytes32(0) ----

    function test_RevertWhen_ConfirmarAlmacenamiento_HashDepositoInvalid() public {
        _createLoteDefault();
        _comprarTokens(BUYER_1, 2, 10);
        _confirmarCosechaDefault();

        vm.prank(ORACLE_SAFE);
        vm.expectRevert(AssetVault.InvalidHash.selector);
        assetVault.confirmarAlmacenamiento(LOTE_ID_DEFAULT, bytes32(0), ALMACEN_AUTORIZADO);
    }

    // ---- Branch 323: confirmarAlmacenamiento almacenAutorizado = address(0) ----

    function test_RevertWhen_ConfirmarAlmacenamiento_AlmacenZero() public {
        _createLoteDefault();
        _comprarTokens(BUYER_1, 2, 10);
        _confirmarCosechaDefault();

        vm.prank(ORACLE_SAFE);
        vm.expectRevert(AssetVault.ZeroAddress.selector);
        assetVault.confirmarAlmacenamiento(LOTE_ID_DEFAULT, keccak256("DEPOSITO"), address(0));
    }

    // ---- Branch 338: marcarFallido non-existent lote ----

    function test_RevertWhen_MarcarFallido_LoteNotExists() public {
        vm.prank(ORACLE_SAFE);
        vm.expectRevert(AssetVault.LoteNotExists.selector);
        assetVault.marcarFallido(999, "motivo valido");
    }

    // ---- Branch 342: marcarFallido motivo = "" ----

    function test_RevertWhen_MarcarFallido_EmptyMotivo() public {
        _createLoteDefault();

        vm.prank(ORACLE_SAFE);
        vm.expectRevert(AssetVault.EmptyMotivo.selector);
        assetVault.marcarFallido(LOTE_ID_DEFAULT, "");
    }

    // ---- Branch 372: reembolsarLoteFallido non-existent lote ----

    function test_RevertWhen_ReembolsarLoteFallido_LoteNotExists() public {
        address[] memory buyers = new address[](1);
        buyers[0] = BUYER_1;

        vm.prank(ORACLE_SAFE);
        vm.expectRevert(AssetVault.LoteNotExists.selector);
        assetVault.reembolsarLoteFallido(999, buyers);
    }

    // ---- Branch 374: reembolsarLoteFallido after finalizarReembolso (ReembolsoYaEjecutado) ----

    function test_RevertWhen_ReembolsarLoteFallido_ReembolsoYaEjecutado() public {
        _createLoteDefault();

        vm.prank(ORACLE_SAFE);
        assetVault.marcarFallido(LOTE_ID_DEFAULT, "Cosecha fallida por helada");

        // finalizarReembolso sets _reembolsado = true
        vm.prank(ORACLE_SAFE);
        assetVault.finalizarReembolso(LOTE_ID_DEFAULT);

        address[] memory buyers = new address[](1);
        buyers[0] = BUYER_1;

        vm.prank(ORACLE_SAFE);
        vm.expectRevert(AssetVault.ReembolsoYaEjecutado.selector);
        assetVault.reembolsarLoteFallido(LOTE_ID_DEFAULT, buyers);
    }

    // ---- Branch 375: reembolsarLoteFallido empty buyers array ----

    function test_RevertWhen_ReembolsarLoteFallido_EmptyBuyers() public {
        _createLoteDefault();

        vm.prank(ORACLE_SAFE);
        assetVault.marcarFallido(LOTE_ID_DEFAULT, "Cosecha fallida");

        address[] memory buyers = new address[](0);

        vm.prank(ORACLE_SAFE);
        vm.expectRevert(AssetVault.EmptyBuyers.selector);
        assetVault.reembolsarLoteFallido(LOTE_ID_DEFAULT, buyers);
    }

    // ---- Branch 379: early-return when totalSupply == 0 (FALLIDO lote, no purchases) ----

    function test_ReembolsarLoteFallido_EarlyReturn_WhenTotalSupplyZero() public {
        _createLoteDefault();
        // NO purchases — totalSupply(loteId) == 0

        vm.prank(ORACLE_SAFE);
        assetVault.marcarFallido(LOTE_ID_DEFAULT, "Cosecha fallida sin compradores");

        address[] memory buyers = new address[](1);
        buyers[0] = BUYER_1;

        // Should NOT revert — early return sets _reembolsado = true
        vm.prank(ORACLE_SAFE);
        assetVault.reembolsarLoteFallido(LOTE_ID_DEFAULT, buyers);

        // Verify _reembolsado is true by confirming finalizarReembolso reverts with ReembolsoYaEjecutado
        vm.prank(ORACLE_SAFE);
        vm.expectRevert(AssetVault.ReembolsoYaEjecutado.selector);
        assetVault.finalizarReembolso(LOTE_ID_DEFAULT);
    }

    // ---- Branch 392: continue branch — buyer balance == 0 in array ----

    function test_ReembolsarLoteFallido_SkipBuyer_BalanceZero() public {
        _createLoteDefault();
        _comprarTokens(BUYER_1, 2, 10); // only BUYER_1 bought

        vm.prank(ORACLE_SAFE);
        assetVault.marcarFallido(LOTE_ID_DEFAULT, "Cosecha fallida");

        // Pass BUYER_2 who never bought — balance == 0 → continue
        address[] memory buyers = new address[](1);
        buyers[0] = BUYER_2;

        // Should NOT revert
        vm.prank(ORACLE_SAFE);
        assetVault.reembolsarLoteFallido(LOTE_ID_DEFAULT, buyers);

        // BUYER_1 tokens still exist (BUYER_2 was skipped)
        assertGt(assetVault.balanceOf(BUYER_1, LOTE_ID_DEFAULT), 0);
    }

    // ---- Branch 395: CannotRefundBlockedAddress — frozen buyer with balance ----

    function test_RevertWhen_ReembolsarLoteFallido_FrozenBuyerWithBalance() public {
        _createLoteDefault();
        _comprarTokens(BUYER_FROZEN, 2, 10); // BUYER_FROZEN buys first (while not frozen)

        // Now freeze BUYER_FROZEN
        vm.prank(COMPLIANCE_OFFICER);
        identityRegistry.freezeAddress(BUYER_FROZEN, "regulatory order", keccak256("order-hash"));

        vm.prank(ORACLE_SAFE);
        assetVault.marcarFallido(LOTE_ID_DEFAULT, "Cosecha fallida");

        address[] memory buyers = new address[](1);
        buyers[0] = BUYER_FROZEN;

        vm.prank(ORACLE_SAFE);
        vm.expectRevert(AssetVault.CannotRefundBlockedAddress.selector);
        assetVault.reembolsarLoteFallido(LOTE_ID_DEFAULT, buyers);
    }

    // ---- Branch 416: finalizarReembolso non-existent lote ----

    function test_RevertWhen_FinalizarReembolso_LoteNotExists() public {
        vm.prank(ORACLE_SAFE);
        vm.expectRevert(AssetVault.LoteNotExists.selector);
        assetVault.finalizarReembolso(999);
    }

    // ---- Branch 417: finalizarReembolso on non-FALLIDO lote ----

    function test_RevertWhen_FinalizarReembolso_LoteNotInFallido() public {
        _createLoteDefault(); // lote is in PREVENTA

        vm.prank(ORACLE_SAFE);
        vm.expectRevert(AssetVault.LoteNotInFallido.selector);
        assetVault.finalizarReembolso(LOTE_ID_DEFAULT);
    }

    // ---- Branch 418: finalizarReembolso twice → ReembolsoYaEjecutado ----

    function test_RevertWhen_FinalizarReembolso_ReembolsoYaEjecutado() public {
        _createLoteDefault();

        vm.prank(ORACLE_SAFE);
        assetVault.marcarFallido(LOTE_ID_DEFAULT, "Cosecha fallida");

        vm.prank(ORACLE_SAFE);
        assetVault.finalizarReembolso(LOTE_ID_DEFAULT);

        vm.prank(ORACLE_SAFE);
        vm.expectRevert(AssetVault.ReembolsoYaEjecutado.selector);
        assetVault.finalizarReembolso(LOTE_ID_DEFAULT);
    }

    // ---- Branch 430: liberarReservaTecnica non-existent lote ----

    function test_RevertWhen_LiberarReservaTecnica_LoteNotExists() public {
        vm.prank(TREASURY_SRL);
        vm.expectRevert(AssetVault.LoteNotExists.selector);
        assetVault.liberarReservaTecnica(999);
    }

    // ---- Branch 456: burnForRedemption when redemptionManager NOT set ----

    function test_RevertWhen_BurnForRedemption_RedemptionManagerNotSet() public {
        // Deploy a fresh AssetVault WITHOUT setting RedemptionManager
        AssetVault.InitParams memory p = AssetVault.InitParams({
            admin: ADMIN,
            adminOperator: ADMIN_OPERATOR,
            backendSigner: BACKEND_SIGNER,
            complianceOfficer: COMPLIANCE_OFFICER,
            complianceOfficerSuplente: COMPLIANCE_OFFICER_SUPLENTE,
            oracleSafe: ORACLE_SAFE,
            treasurySRL: TREASURY_SRL,
            usdc: usdc,
            identityRegistry: identityRegistry,
            uri: "https://meta.example/{id}.json"
        });
        AssetVault freshVault = new AssetVault(p);
        // Do NOT call setRedemptionManager

        vm.expectRevert(AssetVault.RedemptionManagerNotSet.selector);
        freshVault.burnForRedemption(BUYER_1, LOTE_ID_DEFAULT, 10);
    }

    // ---- Branch 457: burnForRedemption from non-RM caller ----

    function test_RevertWhen_BurnForRedemption_OnlyRedemptionCanBurn() public {
        // assetVault already has redemptionManager set in setUp()
        vm.prank(BUYER_1); // not the redemption manager
        vm.expectRevert(AssetVault.OnlyRedemptionCanBurn.selector);
        assetVault.burnForRedemption(BUYER_1, LOTE_ID_DEFAULT, 10);
    }

    // ---- Branch 458: burnForRedemption cantidad = 0 as RM ----

    function test_RevertWhen_BurnForRedemption_CantidadTokensCero() public {
        vm.prank(address(redemptionManager));
        vm.expectRevert(AssetVault.CantidadTokensCero.selector);
        assetVault.burnForRedemption(BUYER_1, LOTE_ID_DEFAULT, 0);
    }

    // ---- Branch 512: kgDisponibles returns 0 for non-existent lote ----

    function test_KgDisponibles_ReturnsZero_WhenLoteNotExists() public view {
        uint256 kg = assetVault.kgDisponibles(999);
        assertEq(kg, 0);
    }

    // ---- supportsInterface ----

    function test_SupportsInterface_ERC165_ReturnsTrue() public view {
        // ERC165 interface ID = 0x01ffc9a7
        assertTrue(assetVault.supportsInterface(0x01ffc9a7));
    }

    function test_SupportsInterface_InvalidId_ReturnsFalse() public view {
        // 0xffffffff is defined to return false by ERC165
        assertFalse(assetVault.supportsInterface(0xffffffff));
    }
}
