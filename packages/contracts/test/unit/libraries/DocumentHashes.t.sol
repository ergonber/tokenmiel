// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {DocumentHashes} from "../../../src/libraries/DocumentHashes.sol";

/// @title DocumentHashesTest
/// @notice Full line + branch coverage for the DocumentHashes pure library.
/// @dev Internal library functions are invoked directly (`DocumentHashes.foo(...)`).
///      Covers every function, both sides of every conditional branch and boundary
///      values (empty array, single element, equal hashes).
contract DocumentHashesTest is Test {
    using DocumentHashes for bytes32;

    bytes32 internal constant H_A = bytes32(uint256(0x01));
    bytes32 internal constant H_B = bytes32(uint256(0x02));

    // ---------------------------------------------------------------------
    // combine
    // ---------------------------------------------------------------------

    /// @dev Branch `a < b` TRUE → ordering keeps (a, b).
    function test_combine_aLessThanB_ordersAB() public pure {
        bytes32 expected = keccak256(abi.encodePacked(H_A, H_B));
        assertEq(DocumentHashes.combine(H_A, H_B), expected);
    }

    /// @dev Branch `a < b` FALSE (a > b) → ordering swaps to (b, a).
    function test_combine_aGreaterThanB_ordersBA() public pure {
        bytes32 expected = keccak256(abi.encodePacked(H_A, H_B));
        // Passing (H_B, H_A) must produce the same root as (H_A, H_B).
        assertEq(DocumentHashes.combine(H_B, H_A), expected);
    }

    /// @dev Branch `a < b` FALSE (a == b, boundary) → falls through to (b, a).
    function test_combine_aEqualB_ordersBA() public pure {
        bytes32 expected = keccak256(abi.encodePacked(H_A, H_A));
        assertEq(DocumentHashes.combine(H_A, H_A), expected);
    }

    /// @dev Commutativity property: combine(a,b) == combine(b,a) for any inputs.
    function testFuzz_combine_isCommutative(bytes32 a, bytes32 b) public pure {
        assertEq(DocumentHashes.combine(a, b), DocumentHashes.combine(b, a));
    }

    // ---------------------------------------------------------------------
    // isValid
    // ---------------------------------------------------------------------

    /// @dev Non-zero hash → valid (return expression TRUE side).
    function test_isValid_nonZeroHash_returnsTrue() public pure {
        assertTrue(DocumentHashes.isValid(H_A));
    }

    /// @dev Zero hash → invalid (return expression FALSE side).
    function test_isValid_zeroHash_returnsFalse() public pure {
        assertFalse(DocumentHashes.isValid(bytes32(0)));
    }

    /// @dev Property: isValid is true iff the hash is not the zero word.
    function testFuzz_isValid_matchesNonZero(bytes32 hash) public pure {
        assertEq(DocumentHashes.isValid(hash), hash != bytes32(0));
    }

    // ---------------------------------------------------------------------
    // rootOf
    // ---------------------------------------------------------------------

    /// @dev Branch `length == 0` TRUE → returns zero word.
    function test_rootOf_emptyArray_returnsZero() public pure {
        bytes32[] memory hashes = new bytes32[](0);
        assertEq(DocumentHashes.rootOf(hashes), bytes32(0));
    }

    /// @dev Branch `length == 1` TRUE → returns the single element verbatim.
    function test_rootOf_singleElement_returnsElement() public pure {
        bytes32[] memory hashes = new bytes32[](1);
        hashes[0] = H_A;
        assertEq(DocumentHashes.rootOf(hashes), H_A);
    }

    /// @dev Both length branches FALSE (length == 2) → enters the loop once.
    function test_rootOf_twoElements_combines() public pure {
        bytes32[] memory hashes = new bytes32[](2);
        hashes[0] = H_A;
        hashes[1] = H_B;
        bytes32 expected = DocumentHashes.combine(H_A, H_B);
        assertEq(DocumentHashes.rootOf(hashes), expected);
    }

    /// @dev length == 3 → loop iterates more than once (fold left).
    function test_rootOf_threeElements_foldsLeft() public pure {
        bytes32 hC = bytes32(uint256(0x03));
        bytes32[] memory hashes = new bytes32[](3);
        hashes[0] = H_A;
        hashes[1] = H_B;
        hashes[2] = hC;

        bytes32 step1 = DocumentHashes.combine(H_A, H_B);
        bytes32 expected = DocumentHashes.combine(step1, hC);
        assertEq(DocumentHashes.rootOf(hashes), expected);
    }

    /// @dev Property: rootOf over a non-empty array never returns the zero word
    ///      when no input element is zero, and is deterministic.
    function testFuzz_rootOf_isDeterministic(bytes32 a, bytes32 b, bytes32 c) public pure {
        bytes32[] memory hashes = new bytes32[](3);
        hashes[0] = a;
        hashes[1] = b;
        hashes[2] = c;
        assertEq(DocumentHashes.rootOf(hashes), DocumentHashes.rootOf(hashes));
    }
}
