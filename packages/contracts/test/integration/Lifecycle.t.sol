// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {BaseTest} from "../BaseTest.t.sol";
import {IAssetVault} from "../../src/interfaces/IAssetVault.sol";
import {IRedemptionManager} from "../../src/interfaces/IRedemptionManager.sol";

/// @title LifecycleTest
/// @notice End-to-end cross-contract integration tests (Gap 1): the full
///         buy -> harvest -> storage -> redemption -> export lifecycle and its
///         alternative flows. Inherits BaseTest for the shared deploy + helpers.
contract LifecycleTest is BaseTest {
    /// @notice Full happy path: a KYC'd buyer redeems their whole balance through to COMPLETADA.
    function test_lifecycle_HappyPath_BuyThroughRedemptionCompleted() public {
        // Arrange: lote ALMACENADO with BUYER_1 holding 20 tokens (tier 2 => canRedeem).
        _advanceToAlmacenado();
        uint256 loteId = LOTE_ID_DEFAULT;
        uint256 cantidad = 20;

        // Act: iniciar -> confirmar exportación -> completar.
        vm.prank(BUYER_1);
        uint256 redencionId = redemptionManager.iniciarRedencion(loteId, cantidad, keccak256("envio"));

        vm.prank(ORACLE_SAFE);
        redemptionManager.confirmarExportacion(redencionId, "DUE-2026-001");

        vm.prank(ORACLE_SAFE);
        redemptionManager.completarRedencion(redencionId, keccak256("BLAWB"));

        // Assert: redemption COMPLETADA, tokens burned, lote exhausted.
        IRedemptionManager.Redencion memory r = redemptionManager.getRedencion(redencionId);
        assertEq(uint8(r.estado), uint8(IRedemptionManager.EstadoRedencion.COMPLETADA), "redemption not COMPLETADA");
        assertEq(assetVault.balanceOf(BUYER_1, loteId), 0, "tokens not burned");
        assertEq(assetVault.totalSupply(loteId), 0, "supply not zero");
        assertEq(uint8(assetVault.lotes(loteId).estado), uint8(IAssetVault.LoteEstado.AGOTADO), "lote not AGOTADO");
    }

    /// @notice Failed-batch flow: a lote marked FALLIDO refunds the buyer's escrowed USDC.
    function test_lifecycle_LoteFallido_RefundsBuyerEscrow() public {
        // Arrange: lote in PREVENTA (marcarFallido only allowed pre-storage) with a buyer.
        _createLoteDefault();
        _comprarTokens(BUYER_1, 2, 20);
        uint256 loteId = LOTE_ID_DEFAULT;
        uint256 montoPagado = 20 * PRECIO_POR_TOKEN_DEFAULT;

        // Act: mark the lote failed, refund buyers, finalize.
        vm.prank(ORACLE_SAFE);
        assetVault.marcarFallido(loteId, "cosecha perdida");

        address[] memory compradores = new address[](1);
        compradores[0] = BUYER_1;
        vm.prank(ORACLE_SAFE);
        assetVault.reembolsarLoteFallido(loteId, compradores);

        vm.prank(ORACLE_SAFE);
        assetVault.finalizarReembolso(loteId);

        // Assert: lote FALLIDO, tokens burned, full escrow refunded to the buyer.
        assertEq(uint8(assetVault.lotes(loteId).estado), uint8(IAssetVault.LoteEstado.FALLIDO), "lote not FALLIDO");
        assertEq(assetVault.balanceOf(BUYER_1, loteId), 0, "tokens not burned on refund");
        assertEq(usdc.balanceOf(BUYER_1), montoPagado, "buyer not fully refunded");
    }

    /// @notice Cancelling a redemption from INICIADA releases the lock and burns nothing.
    function test_lifecycle_Cancel_FromIniciada_ReleasesLock() public {
        _advanceToAlmacenado();
        uint256 loteId = LOTE_ID_DEFAULT;

        vm.prank(BUYER_1);
        uint256 redencionId = redemptionManager.iniciarRedencion(loteId, 20, keccak256("envio"));

        vm.prank(ORACLE_SAFE);
        redemptionManager.cancelarRedencion(redencionId, keccak256("motivo"));

        IRedemptionManager.Redencion memory r = redemptionManager.getRedencion(redencionId);
        assertEq(uint8(r.estado), uint8(IRedemptionManager.EstadoRedencion.CANCELADA), "not CANCELADA");
        assertEq(redemptionManager.tokensLockedFor(BUYER_1, loteId), 0, "lock not released");
        assertEq(assetVault.balanceOf(BUYER_1, loteId), 20, "tokens must not be burned on cancel");
    }

    /// @notice Customs rejection: compliance can cancel from EN_EXPORTACION (ADR-015/017).
    function test_lifecycle_Cancel_FromEnExportacion_ByCompliance() public {
        _advanceToAlmacenado();
        uint256 loteId = LOTE_ID_DEFAULT;

        vm.prank(BUYER_1);
        uint256 redencionId = redemptionManager.iniciarRedencion(loteId, 20, keccak256("envio"));
        vm.prank(ORACLE_SAFE);
        redemptionManager.confirmarExportacion(redencionId, "DUE-2026-001");

        vm.prank(COMPLIANCE_OFFICER);
        redemptionManager.cancelarRedencion(redencionId, keccak256("aduana-rechazada"));

        IRedemptionManager.Redencion memory r = redemptionManager.getRedencion(redencionId);
        assertEq(
            uint8(r.estado), uint8(IRedemptionManager.EstadoRedencion.CANCELADA), "not CANCELADA from EN_EXPORTACION"
        );
        assertEq(redemptionManager.tokensLockedFor(BUYER_1, loteId), 0, "lock not released");
    }

    /// @notice ADR-015: buyer cannot self-cancel before the 60-day timeout, but can after.
    function test_lifecycle_Cancel_BuyerSelfCancelOnlyAfterTimeout() public {
        _advanceToAlmacenado();
        uint256 loteId = LOTE_ID_DEFAULT;

        vm.prank(BUYER_1);
        uint256 redencionId = redemptionManager.iniciarRedencion(loteId, 20, keccak256("envio"));

        // Before the timeout the buyer is not authorized.
        vm.prank(BUYER_1);
        vm.expectRevert();
        redemptionManager.cancelarRedencion(redencionId, keccak256("buyer-early"));

        // After 60 days the buyer may self-cancel.
        vm.warp(block.timestamp + 60 days + 1);
        vm.prank(BUYER_1);
        redemptionManager.cancelarRedencion(redencionId, keccak256("buyer-timeout"));

        IRedemptionManager.Redencion memory r = redemptionManager.getRedencion(redencionId);
        assertEq(uint8(r.estado), uint8(IRedemptionManager.EstadoRedencion.CANCELADA), "buyer self-cancel failed");
    }
}
