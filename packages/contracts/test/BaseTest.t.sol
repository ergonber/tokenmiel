// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {AssetVault} from "../src/AssetVault.sol";
import {IdentityRegistry} from "../src/IdentityRegistry.sol";
import {RedemptionManager} from "../src/RedemptionManager.sol";
import {IAssetVault} from "../src/interfaces/IAssetVault.sol";
import {ComplianceConstants} from "../src/libraries/ComplianceConstants.sol";

/// @dev Mock USDC con 6 decimales (igual a Circle USDC nativo).
contract MockUSDC is ERC20 {
    constructor() ERC20("USD Coin", "USDC") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}

/// @title BaseTest
/// @notice Setup compartido para tests del MVP simplificado (sin QualityAttestation).
///         Despliega 3 contratos activos + mock USDC, configura roles, provee helpers.
///         LabRegistry NO se despliega en MVP (reservado para fase 2).
abstract contract BaseTest is Test {
    // ---- Actors ----
    address internal constant ADMIN = address(0xA001);
    address internal constant ADMIN_OPERATOR = address(0xA002);
    address internal constant ORACLE_SIGNER_1 = address(0xB001);
    address internal constant ORACLE_SIGNER_2 = address(0xB002);
    address internal constant ORACLE_SIGNER_3 = address(0xB003);
    address internal constant ORACLE_SAFE = address(0xB000);
    address internal constant BACKEND_SIGNER = address(0xC001);
    address internal constant COMPLIANCE_OFFICER = address(0xD001);
    address internal constant COMPLIANCE_OFFICER_SUPLENTE = address(0xD002);
    address internal constant TREASURY_SRL = address(0xE001);
    address internal constant ALMACEN_AUTORIZADO = address(0xE002);
    address internal constant BUYER_1 = address(0x1001);
    address internal constant BUYER_2 = address(0x1002);
    address internal constant BUYER_SANCTIONED = address(0x1003);
    address internal constant BUYER_FROZEN = address(0x1004);
    address internal constant NON_KYC = address(0x1005);

    // ---- Contracts ----
    MockUSDC internal usdc;
    IdentityRegistry internal identityRegistry;
    AssetVault internal assetVault;
    RedemptionManager internal redemptionManager;

    // ---- Constants para tests ----
    uint256 internal constant LOTE_ID_DEFAULT = 1;
    uint256 internal constant KG_ESPERADOS_DEFAULT = 100; // 100 kg
    uint256 internal constant PRECIO_POR_TOKEN_DEFAULT = 20 * 1e6; // USDC 20.00 por token (0.5 kg)
    uint16 internal constant RESERVA_BPS_DEFAULT = 1500; // 15%
    bytes2 internal constant ORIGEN_BOLIVIA = "BO";
    uint8 internal constant VARIEDAD_ROMERO = 1;

    function setUp() public virtual {
        // Warp para tener timestamp predecible
        vm.warp(1_700_000_000); // ~2023-11-14

        // 1. Deploy mock USDC
        usdc = new MockUSDC();

        // 2. Deploy IdentityRegistry
        identityRegistry = new IdentityRegistry(ADMIN, BACKEND_SIGNER, COMPLIANCE_OFFICER, COMPLIANCE_OFFICER_SUPLENTE);

        // 3. Deploy AssetVault — usando struct InitParams (sin labRegistry, MVP simplificado)
        AssetVault.InitParams memory params = AssetVault.InitParams({
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
        assetVault = new AssetVault(params);

        // 4. Deploy RedemptionManager
        redemptionManager = new RedemptionManager(
            ADMIN, ORACLE_SAFE, COMPLIANCE_OFFICER, COMPLIANCE_OFFICER_SUPLENTE, assetVault, identityRegistry
        );

        // 5. Set RedemptionManager in AssetVault
        vm.prank(ADMIN);
        assetVault.setRedemptionManager(address(redemptionManager));
    }

    // ---- Helpers ----

    function _setupKYC(address user, uint8 tier) internal {
        _setupKYC(user, tier, "BO");
    }

    function _setupKYC(address user, uint8 tier, bytes2 jurisdiction) internal {
        vm.prank(BACKEND_SIGNER);
        identityRegistry.setKYC(user, tier, uint64(block.timestamp + 365 days), jurisdiction, keccak256("applicant"));
    }

    function _createLoteDefault() internal {
        vm.prank(ADMIN_OPERATOR);
        assetVault.crearLote(
            LOTE_ID_DEFAULT,
            KG_ESPERADOS_DEFAULT,
            PRECIO_POR_TOKEN_DEFAULT,
            uint64(block.timestamp + 90 days),
            ORIGEN_BOLIVIA,
            TREASURY_SRL,
            keccak256("FSA-DOC"),
            RESERVA_BPS_DEFAULT,
            VARIEDAD_ROMERO
        );
    }

    /// @dev Helper: fund AssetVault con USDC + ejecuta comprar.
    ///      En el modelo escrow total, el USDC del comprador queda en el contrato (no se transfiere al productor).
    function _comprarTokens(address buyer, uint8 tier, uint256 cantidadTokens) internal {
        _setupKYC(buyer, tier);

        uint256 monto = cantidadTokens * PRECIO_POR_TOKEN_DEFAULT;
        usdc.mint(address(assetVault), monto);

        vm.prank(BACKEND_SIGNER);
        assetVault.comprar(LOTE_ID_DEFAULT, cantidadTokens, buyer, monto, keccak256("payment"));
    }

    function _confirmarCosechaDefault() internal {
        vm.prank(ORACLE_SAFE);
        assetVault.confirmarCosecha(
            LOTE_ID_DEFAULT,
            KG_ESPERADOS_DEFAULT,
            keccak256("SENASAG"),
            keccak256("LAB-ANALYSIS"),
            keccak256("ACTA"),
            keccak256("FOTOS"),
            keccak256("ORIGEN"),
            IAssetVault.TipoCertificadoOrigen.FORM_A
        );
    }

    function _confirmarAlmacenamientoDefault() internal {
        vm.prank(ORACLE_SAFE);
        assetVault.confirmarAlmacenamiento(LOTE_ID_DEFAULT, keccak256("DEPOSITO"), ALMACEN_AUTORIZADO);
    }

    /// @dev Avanza un lote hasta ALMACENADO: crear → comprar → cosecha → almacenamiento.
    ///      MVP simplificado: sin paso intermedio de QualityAttestation.
    function _advanceToAlmacenado() internal {
        _createLoteDefault();
        _comprarTokens(BUYER_1, 2, 20); // 20 tokens = 10 kg
        _confirmarCosechaDefault();
        _confirmarAlmacenamientoDefault();
    }
}
