// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {BaseTest} from "../BaseTest.t.sol";
import {RedemptionManager} from "../../src/RedemptionManager.sol";
import {IRedemptionManager} from "../../src/interfaces/IRedemptionManager.sol";

/// @title RedemptionManagerFuzz
/// @notice Fuzz tests (>=10k runs) para el acumulador de lock contable (Opción B) de RedemptionManager.
/// @dev Invariantes derivadas EXACTAMENTE del código en src/RedemptionManager.sol:
///        - iniciarRedencion exige: alreadyLocked + cantidad <= balanceOf(buyer, lote)
///          ⇒ tokensLockedFor[buyer][lote] <= balanceOf(buyer, lote) en todo momento.
///        - availableBalance = balance > locked ? balance - locked : 0  (resta guardada, sin underflow).
///        - Como locked <= balance siempre, available == balance - locked y locked + available == balance.
contract RedemptionManagerFuzz is BaseTest {
    /// @dev Lleva un lote a ALMACENADO con BUYER_1 (tier 2) poseyendo `cantidadCompra` tokens.
    ///      No usa _advanceToAlmacenado (hardcodea 20) — necesitamos un balance fuzzeable.
    function _setupBuyerConBalance(uint256 cantidadCompra) internal {
        _createLoteDefault();
        _comprarTokens(BUYER_1, 2, cantidadCompra);
        _confirmarCosechaDefault();
        _confirmarAlmacenamientoDefault();
    }

    /// @dev Verifica las 3 invariantes del acumulador para BUYER_1 en LOTE_ID_DEFAULT.
    function _assertLockInvariants(string memory ctx) internal view {
        uint256 balance = assetVault.balanceOf(BUYER_1, LOTE_ID_DEFAULT);
        uint256 locked = redemptionManager.tokensLockedFor(BUYER_1, LOTE_ID_DEFAULT);
        uint256 available = redemptionManager.availableBalance(BUYER_1, LOTE_ID_DEFAULT);

        // (1) locked nunca excede el balance ERC1155.
        assertLe(locked, balance, string.concat(ctx, ": locked <= balance"));
        // (2) available == balance - locked (resta guardada nunca underflow porque locked <= balance).
        assertEq(available, balance - locked, string.concat(ctx, ": available == balance - locked"));
        // (3) locked + available == balance ⇒ nunca exceden el balance real.
        assertEq(locked + available, balance, string.concat(ctx, ": locked + available == balance"));
    }

    // ============================================================================
    // Lock accumulator — secuencia de redenciones
    // ============================================================================

    /// @dev Fuzz de una secuencia de hasta 3 iniciarRedencion con cantidades arbitrarias.
    ///      Cada intento que cabe en el available se ejecuta; el que no cabe debe revertir
    ///      con BalanceInsuficiente. Tras cada paso se verifican las 3 invariantes del acumulador.
    function testFuzz_lockAccumulator_SecuenciaNoExcedeBalance(
        uint256 cantidadCompra,
        uint256 amount1,
        uint256 amount2,
        uint256 amount3
    ) public {
        // Balance inicial fuzzeable ∈ [1, 200] (cap de kgEsperados=100 ⇒ 200 tokens).
        cantidadCompra = bound(cantidadCompra, 1, 200);
        _setupBuyerConBalance(cantidadCompra);

        uint256 balance = assetVault.balanceOf(BUYER_1, LOTE_ID_DEFAULT);
        assertEq(balance, cantidadCompra, "balance inicial == cantidadCompra");

        // amounts ∈ [1, balance] — el constructor del fuzz no necesita assume; bound evita rejects.
        amount1 = bound(amount1, 1, balance);
        amount2 = bound(amount2, 1, balance);
        amount3 = bound(amount3, 1, balance);

        _intentarRedencion(amount1, keccak256("ship-1"));
        _assertLockInvariants("post-1");

        _intentarRedencion(amount2, keccak256("ship-2"));
        _assertLockInvariants("post-2");

        _intentarRedencion(amount3, keccak256("ship-3"));
        _assertLockInvariants("post-3");

        // Invariante final redundante de cierre.
        uint256 lockedFinal = redemptionManager.tokensLockedFor(BUYER_1, LOTE_ID_DEFAULT);
        assertLe(lockedFinal, assetVault.balanceOf(BUYER_1, LOTE_ID_DEFAULT), "INVARIANTE FINAL: locked <= balance");
    }

    /// @dev Helper: intenta iniciar una redención. Si cabe en el available, espera éxito y
    ///      que el lock aumente en `amount`; si no cabe, espera revert BalanceInsuficiente.
    function _intentarRedencion(uint256 amount, bytes32 shipHash) internal {
        uint256 availableBefore = redemptionManager.availableBalance(BUYER_1, LOTE_ID_DEFAULT);
        uint256 lockedBefore = redemptionManager.tokensLockedFor(BUYER_1, LOTE_ID_DEFAULT);

        if (amount <= availableBefore) {
            vm.prank(BUYER_1);
            redemptionManager.iniciarRedencion(LOTE_ID_DEFAULT, amount, shipHash);
            assertEq(
                redemptionManager.tokensLockedFor(BUYER_1, LOTE_ID_DEFAULT),
                lockedBefore + amount,
                "lock += amount cuando cabe"
            );
        } else {
            vm.prank(BUYER_1);
            vm.expectRevert(RedemptionManager.BalanceInsuficiente.selector);
            redemptionManager.iniciarRedencion(LOTE_ID_DEFAULT, amount, shipHash);
            assertEq(
                redemptionManager.tokensLockedFor(BUYER_1, LOTE_ID_DEFAULT),
                lockedBefore,
                "lock no cambia cuando revierte"
            );
        }
    }

    /// @dev El acumulador debe ser exactamente la suma de redenciones activas, sin importar el orden:
    ///      tras lockear amountA y amountB (ambos cabiendo), locked == amountA + amountB.
    ///      Verifica explícitamente que dos locks no se pisan y mantienen la invariante.
    function testFuzz_lockAccumulator_SumaDeActivas(uint256 cantidadCompra, uint256 amountA, uint256 amountB) public {
        cantidadCompra = bound(cantidadCompra, 2, 200);
        _setupBuyerConBalance(cantidadCompra);

        uint256 balance = assetVault.balanceOf(BUYER_1, LOTE_ID_DEFAULT);

        // Garantizamos que ambos caben: amountA ∈ [1, balance-1], amountB ∈ [1, balance-amountA].
        amountA = bound(amountA, 1, balance - 1);
        amountB = bound(amountB, 1, balance - amountA);

        vm.prank(BUYER_1);
        redemptionManager.iniciarRedencion(LOTE_ID_DEFAULT, amountA, keccak256("ship-A"));
        _assertLockInvariants("post-A");

        vm.prank(BUYER_1);
        redemptionManager.iniciarRedencion(LOTE_ID_DEFAULT, amountB, keccak256("ship-B"));
        _assertLockInvariants("post-B");

        assertEq(
            redemptionManager.tokensLockedFor(BUYER_1, LOTE_ID_DEFAULT),
            amountA + amountB,
            "locked == amountA + amountB (suma de activas)"
        );
        assertEq(
            redemptionManager.availableBalance(BUYER_1, LOTE_ID_DEFAULT),
            balance - amountA - amountB,
            "available == balance - (amountA + amountB)"
        );
    }

    /// @dev Ciclo lock → cancel: cancelar libera EXACTAMENTE lo lockeado y el available vuelve al
    ///      balance total (los tokens no se queman en cancelación). Invariantes se mantienen.
    function testFuzz_lockAccumulator_CancelLiberaLockExacto(uint256 cantidadCompra, uint256 amount) public {
        cantidadCompra = bound(cantidadCompra, 1, 200);
        _setupBuyerConBalance(cantidadCompra);

        uint256 balance = assetVault.balanceOf(BUYER_1, LOTE_ID_DEFAULT);
        amount = bound(amount, 1, balance);

        vm.prank(BUYER_1);
        uint256 redencionId = redemptionManager.iniciarRedencion(LOTE_ID_DEFAULT, amount, keccak256("ship"));
        _assertLockInvariants("post-iniciar");
        assertEq(redemptionManager.tokensLockedFor(BUYER_1, LOTE_ID_DEFAULT), amount, "lock == amount tras iniciar");

        vm.prank(ORACLE_SAFE);
        redemptionManager.cancelarRedencion(redencionId, keccak256("aduana-rechazada"));

        _assertLockInvariants("post-cancel");
        assertEq(redemptionManager.tokensLockedFor(BUYER_1, LOTE_ID_DEFAULT), 0, "lock == 0 tras cancelar");
        // Cancelar no quema: available == balance total de nuevo.
        assertEq(
            redemptionManager.availableBalance(BUYER_1, LOTE_ID_DEFAULT),
            balance,
            "available vuelve al balance total tras cancelar"
        );
    }

    /// @dev Ciclo lock → completar (burn): completar libera el lock Y quema los tokens.
    ///      Propiedad: balanceAfter == balanceBefore - amount, lock vuelve a 0, available == balanceAfter.
    ///      Invariantes del acumulador se mantienen tras el burn.
    function testFuzz_lockAccumulator_CompletarBurneaYLiberaLock(uint256 cantidadCompra, uint256 amount) public {
        cantidadCompra = bound(cantidadCompra, 1, 200);
        _setupBuyerConBalance(cantidadCompra);

        uint256 balanceBefore = assetVault.balanceOf(BUYER_1, LOTE_ID_DEFAULT);
        amount = bound(amount, 1, balanceBefore);

        vm.prank(BUYER_1);
        uint256 redencionId = redemptionManager.iniciarRedencion(LOTE_ID_DEFAULT, amount, keccak256("ship"));
        _assertLockInvariants("post-iniciar");

        // ADR-017: dos fases — confirmar (registra DUE) + completar (libera lock + burn).
        vm.prank(ORACLE_SAFE);
        redemptionManager.confirmarExportacion(redencionId, "DUE-FUZZ");
        _assertLockInvariants("post-confirmar");

        vm.prank(ORACLE_SAFE);
        redemptionManager.completarRedencion(redencionId, keccak256("BL-FUZZ"));

        _assertLockInvariants("post-completar");
        uint256 balanceAfter = assetVault.balanceOf(BUYER_1, LOTE_ID_DEFAULT);
        assertEq(balanceAfter, balanceBefore - amount, "balance -= amount tras burn");
        assertEq(redemptionManager.tokensLockedFor(BUYER_1, LOTE_ID_DEFAULT), 0, "lock == 0 tras completar");
        assertEq(
            redemptionManager.availableBalance(BUYER_1, LOTE_ID_DEFAULT),
            balanceAfter,
            "available == balance restante (lock liberado)"
        );
    }
}
