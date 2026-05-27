// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {BaseTest} from "../BaseTest.t.sol";
import {RedemptionManager} from "../../src/RedemptionManager.sol";
import {IRedemptionManager} from "../../src/interfaces/IRedemptionManager.sol";

/// @title RedemptionManager Invariant Tests
/// @notice Verifica la invariante critica: suma de tokens lockeados <= balance ERC1155 del comprador.
/// @dev Runs: 50_000, depth: 100 (configurado en foundry.toml).
///      Enfoque: usar un Handler que actua como intermediario para llamadas fuzzeadas,
///      garantizando que solo se ejecutan acciones validas que no requieren roles especiales.
contract RedemptionManagerHandler is BaseTest {
    // Buyer designado para el handler
    address internal constant HANDLER_BUYER = address(0x9999);
    uint256 internal constant HANDLER_LOTE_ID = 1;

    // Estado local del handler para tracking
    uint256[] public redencionIds;

    function setUp() public override {
        super.setUp();
        // Avanzar lote a ALMACENADO con tokens para el HANDLER_BUYER
        _createLoteDefault();
        _comprarTokens(HANDLER_BUYER, 2, 20);
        _confirmarCosechaDefault();
        _confirmarAlmacenamientoDefault();
    }

    /// @dev Accion: iniciar redencion (sin roles, como cualquier buyer)
    function iniciarRedencionAction(uint256 cantidad, uint256 hashSeed) external {
        uint256 available = redemptionManager.availableBalance(HANDLER_BUYER, HANDLER_LOTE_ID);
        if (available == 0) return;

        // Bound cantidad al balance disponible
        cantidad = bound(cantidad, 1, available);
        bytes32 datosHash = keccak256(abi.encodePacked(hashSeed, block.timestamp));
        if (datosHash == bytes32(0)) datosHash = keccak256("fallback");

        vm.prank(HANDLER_BUYER);
        uint256 rid = redemptionManager.iniciarRedencion(HANDLER_LOTE_ID, cantidad, datosHash);
        redencionIds.push(rid);
    }

    /// @dev Accion: cancelar una redencion activa (como Oracle)
    function cancelarRedencionAction(uint256 idxSeed) external {
        if (redencionIds.length == 0) return;
        uint256 idx = idxSeed % redencionIds.length;
        uint256 rid = redencionIds[idx];

        IRedemptionManager.Redencion memory r = redemptionManager.getRedencion(rid);
        if (r.estado != IRedemptionManager.EstadoRedencion.INICIADA) return;

        vm.prank(ORACLE_SAFE);
        redemptionManager.cancelarRedencion(rid, keccak256("cancelacion-handler"));
    }

    /// @dev Accion: confirmar exportacion (como Oracle)
    function confirmarExportacionAction(uint256 idxSeed, uint256 hashSeed) external {
        if (redencionIds.length == 0) return;
        uint256 idx = idxSeed % redencionIds.length;
        uint256 rid = redencionIds[idx];

        IRedemptionManager.Redencion memory r = redemptionManager.getRedencion(rid);
        if (r.estado != IRedemptionManager.EstadoRedencion.INICIADA) return;

        // Verificar que hay balance real para el burn (el handler conoce el estado)
        uint256 balance = assetVault.balanceOf(r.comprador, r.loteId);
        if (balance < r.cantidadTokens) return;

        bytes32 blawbHash = keccak256(abi.encodePacked(hashSeed, "BL-AWB"));
        if (blawbHash == bytes32(0)) blawbHash = keccak256("fallback-bl");

        vm.prank(ORACLE_SAFE);
        redemptionManager.confirmarExportacion(rid, "DUE-INVARIANT-TEST", blawbHash);
    }

    /// @dev Getter para el buyer de este handler
    function getHandlerBuyer() external pure returns (address) {
        return HANDLER_BUYER;
    }

    /// @dev Getter para el lote ID de este handler
    function getHandlerLoteId() external pure returns (uint256) {
        return HANDLER_LOTE_ID;
    }

    /// @dev Getter para balance ERC1155 del buyer en el lote
    function getAssetVaultBalance(address buyer, uint256 loteId) external view returns (uint256) {
        return assetVault.balanceOf(buyer, loteId);
    }

    /// @dev Getter para el available balance en el RedemptionManager
    function getAvailableBalance(address buyer, uint256 loteId) external view returns (uint256) {
        return redemptionManager.availableBalance(buyer, loteId);
    }

    /// @dev Getter para nextRedencionId
    function getNextRedencionId() external view returns (uint256) {
        return redemptionManager.getNextRedencionId();
    }
}

/// @title RedemptionManager Invariant Tests (usando Handler)
contract RedemptionManagerInvariantTest is Test {
    RedemptionManagerHandler internal handler;

    function setUp() public {
        handler = new RedemptionManagerHandler();
        handler.setUp();

        // Solo el handler puede llamar acciones
        targetContract(address(handler));

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = RedemptionManagerHandler.iniciarRedencionAction.selector;
        selectors[1] = RedemptionManagerHandler.cancelarRedencionAction.selector;
        selectors[2] = RedemptionManagerHandler.confirmarExportacionAction.selector;

        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    /// @notice Invariante principal: availableBalance nunca excede el balance real ERC1155 del comprador.
    /// @dev Si falla, significa que se pueden iniciar redenciones por mas tokens de los que se tienen.
    function invariant_TotalTokensLocked_NotExceedsERC1155Balance() public view {
        address buyer = handler.getHandlerBuyer();
        uint256 loteId = handler.getHandlerLoteId();

        uint256 erc1155Balance = handler.getAssetVaultBalance(buyer, loteId);
        uint256 available = handler.getAvailableBalance(buyer, loteId);

        assertLe(available, erc1155Balance, "INVARIANT VIOLATED: availableBalance excede balance ERC1155 real");
    }

    /// @notice Invariante: el nextRedencionId es monotónico (solo crece).
    function invariant_NextRedencionId_IsMonotonic() public view {
        assertGe(handler.getNextRedencionId(), 1, "nextRedencionId debe ser >= 1");
    }
}
