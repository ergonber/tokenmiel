// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {QualityRules} from "../../../src/libraries/QualityRules.sol";
import {ComplianceConstants} from "../../../src/libraries/ComplianceConstants.sol";

/// @title QualityRulesTest
/// @notice Full line + branch coverage for the QualityRules pure library.
/// @dev Internal library functions are invoked directly (`QualityRules.foo(...)`).
///      `isMonofloralCertified` is a phase-2 reserved function; its short-circuit
///      `&&` chain is exercised on every branch. The conversion / reserve helpers
///      are pure arithmetic (no conditional branches) and are covered for lines,
///      boundaries and properties.
contract QualityRulesTest is Test {
    uint8 internal constant POLLEN_MIN = ComplianceConstants.MIN_POLLEN_PERCENTAGE_MONOFLORAL; // 45
    uint256 internal constant GRAMOS_POR_TOKEN = ComplianceConstants.GRAMOS_POR_TOKEN; // 500
    uint16 internal constant BPS_DENOMINATOR = ComplianceConstants.BPS_DENOMINATOR; // 10_000

    // ---------------------------------------------------------------------
    // isMonofloralCertified — short-circuit && chain (phase 2)
    // ---------------------------------------------------------------------

    /// @dev All criteria met (pollen at the boundary) → certified TRUE.
    function test_isMonofloralCertified_allMet_returnsTrue() public pure {
        assertTrue(QualityRules.isMonofloralCertified(POLLEN_MIN, true, true, true));
    }

    /// @dev Pollen strictly above boundary still certifies.
    function test_isMonofloralCertified_pollenAboveMin_returnsTrue() public pure {
        assertTrue(QualityRules.isMonofloralCertified(100, true, true, true));
    }

    /// @dev Pollen one below the boundary → first condition FALSE → not certified.
    function test_isMonofloralCertified_pollenBelowMin_returnsFalse() public pure {
        assertFalse(QualityRules.isMonofloralCertified(POLLEN_MIN - 1, true, true, true));
    }

    /// @dev Pollen ok but NMR failed → second condition FALSE → not certified.
    function test_isMonofloralCertified_nmrFailed_returnsFalse() public pure {
        assertFalse(QualityRules.isMonofloralCertified(POLLEN_MIN, false, true, true));
    }

    /// @dev Pollen + NMR ok but C4 failed → third condition FALSE → not certified.
    function test_isMonofloralCertified_c4Failed_returnsFalse() public pure {
        assertFalse(QualityRules.isMonofloralCertified(POLLEN_MIN, true, false, true));
    }

    /// @dev Pollen + NMR + C4 ok but residues failed → fourth condition FALSE → not certified.
    function test_isMonofloralCertified_residuesFailed_returnsFalse() public pure {
        assertFalse(QualityRules.isMonofloralCertified(POLLEN_MIN, true, true, false));
    }

    /// @dev Property: certification holds iff ALL four criteria are satisfied.
    function testFuzz_isMonofloralCertified_matchesConjunction(uint8 pollen, bool nmr, bool c4, bool residues)
        public
        pure
    {
        bool expected = pollen >= POLLEN_MIN && nmr && c4 && residues;
        assertEq(QualityRules.isMonofloralCertified(pollen, nmr, c4, residues), expected);
    }

    // ---------------------------------------------------------------------
    // tokensToKg
    // ---------------------------------------------------------------------

    /// @dev 2 tokens = 1 kg (2 * 500 / 1000).
    function test_tokensToKg_twoTokens_returnsOneKg() public pure {
        assertEq(QualityRules.tokensToKg(2), 1);
    }

    /// @dev Zero tokens → zero kg (boundary).
    function test_tokensToKg_zeroTokens_returnsZero() public pure {
        assertEq(QualityRules.tokensToKg(0), 0);
    }

    /// @dev Odd token count truncates (1 token = 0.5 kg → integer division floors to 0).
    function test_tokensToKg_oneToken_truncatesToZero() public pure {
        assertEq(QualityRules.tokensToKg(1), 0);
    }

    /// @dev Property: tokensToKg == cantidad * 500 / 1000.
    function testFuzz_tokensToKg_matchesFormula(uint256 cantidad) public pure {
        cantidad = bound(cantidad, 0, type(uint256).max / GRAMOS_POR_TOKEN);
        assertEq(QualityRules.tokensToKg(cantidad), (cantidad * GRAMOS_POR_TOKEN) / 1000);
    }

    // ---------------------------------------------------------------------
    // gramosToTokens
    // ---------------------------------------------------------------------

    /// @dev 1000 g = 2 tokens (1000 / 500).
    function test_gramosToTokens_thousandGrams_returnsTwoTokens() public pure {
        assertEq(QualityRules.gramosToTokens(1000), 2);
    }

    /// @dev Below one token worth of grams truncates to zero (boundary).
    function test_gramosToTokens_belowOneToken_truncatesToZero() public pure {
        assertEq(QualityRules.gramosToTokens(GRAMOS_POR_TOKEN - 1), 0);
    }

    /// @dev Property: gramosToTokens == gramos / 500.
    function testFuzz_gramosToTokens_matchesFormula(uint256 gramos) public pure {
        assertEq(QualityRules.gramosToTokens(gramos), gramos / GRAMOS_POR_TOKEN);
    }

    // ---------------------------------------------------------------------
    // calcularReservaTecnica
    // ---------------------------------------------------------------------

    /// @dev 15% reserva over 1000 USDC → 150 retained, 850 net.
    function test_calcularReservaTecnica_fifteenPercent_splitsCorrectly() public pure {
        (uint256 reserva, uint256 neto) = QualityRules.calcularReservaTecnica(1000, 1500);
        assertEq(reserva, 150);
        assertEq(neto, 850);
    }

    /// @dev Zero monto → both outputs zero (boundary).
    function test_calcularReservaTecnica_zeroMonto_returnsZero() public pure {
        (uint256 reserva, uint256 neto) = QualityRules.calcularReservaTecnica(0, 1500);
        assertEq(reserva, 0);
        assertEq(neto, 0);
    }

    /// @dev Zero bps → nothing retained, everything net (boundary).
    function test_calcularReservaTecnica_zeroBps_returnsAllNet() public pure {
        (uint256 reserva, uint256 neto) = QualityRules.calcularReservaTecnica(1000, 0);
        assertEq(reserva, 0);
        assertEq(neto, 1000);
    }

    /// @dev 100% bps (10000) → everything retained, zero net (upper boundary).
    function test_calcularReservaTecnica_fullBps_retainsAll() public pure {
        (uint256 reserva, uint256 neto) = QualityRules.calcularReservaTecnica(1000, BPS_DENOMINATOR);
        assertEq(reserva, 1000);
        assertEq(neto, 0);
    }

    /// @dev Property: reserva + neto == monto, and reserva == monto * bps / 10000.
    function testFuzz_calcularReservaTecnica_conserved(uint256 monto, uint16 bps) public pure {
        monto = bound(monto, 0, type(uint256).max / BPS_DENOMINATOR);
        bps = uint16(bound(bps, 0, BPS_DENOMINATOR));

        (uint256 reserva, uint256 neto) = QualityRules.calcularReservaTecnica(monto, bps);

        assertEq(reserva, (monto * bps) / BPS_DENOMINATOR);
        assertEq(reserva + neto, monto);
    }
}
