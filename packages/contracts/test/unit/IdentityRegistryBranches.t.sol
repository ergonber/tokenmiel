// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {BaseTest} from "../BaseTest.t.sol";
import {IdentityRegistry} from "../../src/IdentityRegistry.sol";

/// @title IdentityRegistryBranchesTest
/// @notice Targeted branch-coverage tests for IdentityRegistry.sol (Gap 4).
///         Each test covers one uncovered revert branch identified by lcov.
contract IdentityRegistryBranchesTest is BaseTest {
    // ---- Constructor: ZeroAddressUser (branches 62-64) ----

    function test_RevertWhen_Constructor_BackendSignerZero() public {
        vm.expectRevert(IdentityRegistry.ZeroAddressUser.selector);
        new IdentityRegistry(ADMIN, address(0), COMPLIANCE_OFFICER, COMPLIANCE_OFFICER_SUPLENTE);
    }

    function test_RevertWhen_Constructor_ComplianceOfficerZero() public {
        vm.expectRevert(IdentityRegistry.ZeroAddressUser.selector);
        new IdentityRegistry(ADMIN, BACKEND_SIGNER, address(0), COMPLIANCE_OFFICER_SUPLENTE);
    }

    function test_RevertWhen_Constructor_ComplianceSuplenteZero() public {
        vm.expectRevert(IdentityRegistry.ZeroAddressUser.selector);
        new IdentityRegistry(ADMIN, BACKEND_SIGNER, COMPLIANCE_OFFICER, address(0));
    }

    // ---- revokeKYC (branches 101-102) ----

    function test_RevertWhen_RevokeKYC_UserZero() public {
        vm.prank(BACKEND_SIGNER);
        vm.expectRevert(IdentityRegistry.ZeroAddressUser.selector);
        identityRegistry.revokeKYC(address(0), "off-boarding");
    }

    function test_RevertWhen_RevokeKYC_EmptyReason() public {
        vm.prank(BACKEND_SIGNER);
        vm.expectRevert(IdentityRegistry.EmptyReason.selector);
        identityRegistry.revokeKYC(BUYER_1, "");
    }

    // ---- markSanctioned (branch 125) ----

    function test_RevertWhen_MarkSanctioned_UserZero() public {
        vm.prank(COMPLIANCE_OFFICER);
        vm.expectRevert(IdentityRegistry.ZeroAddressUser.selector);
        identityRegistry.markSanctioned(address(0), "OFAC match", keccak256("evidence"));
    }

    // ---- unmarkSanctioned (branches 144-145) ----

    function test_RevertWhen_UnmarkSanctioned_UserZero() public {
        vm.prank(COMPLIANCE_OFFICER);
        vm.expectRevert(IdentityRegistry.ZeroAddressUser.selector);
        identityRegistry.unmarkSanctioned(address(0), "cleared");
    }

    function test_RevertWhen_UnmarkSanctioned_EmptyReason() public {
        vm.prank(COMPLIANCE_OFFICER);
        vm.expectRevert(IdentityRegistry.EmptyReason.selector);
        identityRegistry.unmarkSanctioned(BUYER_1, "");
    }

    // ---- freezeAddress (branches 163-164) ----

    function test_RevertWhen_FreezeAddress_UserZero() public {
        vm.prank(COMPLIANCE_OFFICER);
        vm.expectRevert(IdentityRegistry.ZeroAddressUser.selector);
        identityRegistry.freezeAddress(address(0), "court order", keccak256("orderhash"));
    }

    function test_RevertWhen_FreezeAddress_EmptyOrder() public {
        vm.prank(COMPLIANCE_OFFICER);
        vm.expectRevert(IdentityRegistry.EmptyReason.selector);
        identityRegistry.freezeAddress(BUYER_1, "", keccak256("orderhash"));
    }

    // ---- unfreezeAddress (branches 182-183, 186) ----

    function test_RevertWhen_UnfreezeAddress_UserZero() public {
        vm.prank(COMPLIANCE_OFFICER);
        vm.expectRevert(IdentityRegistry.ZeroAddressUser.selector);
        identityRegistry.unfreezeAddress(address(0), "order lifted");
    }

    function test_RevertWhen_UnfreezeAddress_EmptyReason() public {
        vm.prank(COMPLIANCE_OFFICER);
        vm.expectRevert(IdentityRegistry.EmptyReason.selector);
        identityRegistry.unfreezeAddress(BUYER_1, "");
    }

    function test_RevertWhen_UnfreezeAddress_NotFrozen() public {
        // BUYER_1 was never frozen → NotFrozen
        vm.prank(COMPLIANCE_OFFICER);
        vm.expectRevert(IdentityRegistry.NotFrozen.selector);
        identityRegistry.unfreezeAddress(BUYER_1, "order lifted");
    }
}
