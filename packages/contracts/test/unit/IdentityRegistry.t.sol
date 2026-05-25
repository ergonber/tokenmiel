// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {BaseTest} from "../BaseTest.t.sol";
import {IdentityRegistry} from "../../src/IdentityRegistry.sol";
import {IIdentityRegistry} from "../../src/interfaces/IIdentityRegistry.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract IdentityRegistryTest is BaseTest {
    // ---- Constructor / FIX M-08 ----

    /// @dev FIX M-08: el constructor debe asignar DEFAULT_ADMIN_ROLE vía AccessControlDefaultAdminRules.
    ///      Verifica que `defaultAdmin()` retorna el ADMIN configurado.
    function test_constructor_SetsAllRoles_Correctly() public view {
        // DEFAULT_ADMIN_ROLE via AccessControlDefaultAdminRules
        assertEq(identityRegistry.defaultAdmin(), ADMIN);
        assertTrue(identityRegistry.hasRole(identityRegistry.DEFAULT_ADMIN_ROLE(), ADMIN));

        // Roles operativos
        assertTrue(identityRegistry.hasRole(identityRegistry.BACKEND_SIGNER_ROLE(), BACKEND_SIGNER));
        assertTrue(identityRegistry.hasRole(identityRegistry.COMPLIANCE_OFFICER_ROLE(), COMPLIANCE_OFFICER));
        assertTrue(identityRegistry.hasRole(identityRegistry.COMPLIANCE_OFFICER_ROLE(), COMPLIANCE_OFFICER_SUPLENTE));

        // Delay configurado
        assertEq(uint256(identityRegistry.defaultAdminDelay()), 3 days);
    }

    // ---- setKYC ----

    function test_setKYC_HappyPath_StoresKYCData() public {
        vm.prank(BACKEND_SIGNER);
        identityRegistry.setKYC(BUYER_1, 1, uint64(block.timestamp + 365 days), "DE", keccak256("app1"));

        assertEq(identityRegistry.getTier(BUYER_1), 1);
        assertEq(identityRegistry.getJurisdiction(BUYER_1), bytes2("DE"));
        assertTrue(identityRegistry.canMint(BUYER_1));
    }

    function test_setKYC_OnlyBackendSigner_RevertWhen_NonBackend() public {
        vm.prank(ADMIN);
        vm.expectRevert();
        identityRegistry.setKYC(BUYER_1, 1, uint64(block.timestamp + 365 days), "BO", bytes32(0));
    }

    function test_setKYC_RevertWhen_TierAboveMax() public {
        vm.prank(BACKEND_SIGNER);
        vm.expectRevert(IdentityRegistry.InvalidTier.selector);
        identityRegistry.setKYC(BUYER_1, 4, uint64(block.timestamp + 365 days), "BO", bytes32(0));
    }

    function test_setKYC_RevertWhen_ExpiryInPast() public {
        vm.prank(BACKEND_SIGNER);
        vm.expectRevert(IdentityRegistry.ExpiryInPast.selector);
        identityRegistry.setKYC(BUYER_1, 1, uint64(block.timestamp - 1), "BO", bytes32(0));
    }

    function test_setKYC_RevertWhen_ZeroAddress() public {
        vm.prank(BACKEND_SIGNER);
        vm.expectRevert(IdentityRegistry.ZeroAddressUser.selector);
        identityRegistry.setKYC(address(0), 1, uint64(block.timestamp + 365 days), "BO", bytes32(0));
    }

    function test_setKYC_EmitsKYCUpdatedEvent() public {
        // FIX M-03: evento incluye msg.sender indexed (el BACKEND_SIGNER que ejecutó)
        vm.expectEmit(true, true, false, true);
        emit IIdentityRegistry.KYCUpdated(BUYER_1, BACKEND_SIGNER, 1, uint64(block.timestamp + 365 days), "BO");

        vm.prank(BACKEND_SIGNER);
        identityRegistry.setKYC(BUYER_1, 1, uint64(block.timestamp + 365 days), "BO", bytes32(0));
    }

    /// @dev FIX M-04: setKYC con tier=0 revierte (usar revokeKYC para revocar)
    function test_setKYC_RevertWhen_TierZero() public {
        vm.prank(BACKEND_SIGNER);
        vm.expectRevert(IdentityRegistry.TierZeroNotAllowed.selector);
        identityRegistry.setKYC(BUYER_1, 0, uint64(block.timestamp + 365 days), "BO", bytes32(0));
    }

    // ---- markSanctioned ----

    function test_markSanctioned_HappyPath_BlocksCanMint() public {
        _setupKYC(BUYER_1, 1);
        assertTrue(identityRegistry.canMint(BUYER_1));

        vm.prank(COMPLIANCE_OFFICER);
        identityRegistry.markSanctioned(BUYER_1, "OFAC SDN match", keccak256("evidence"));

        assertFalse(identityRegistry.canMint(BUYER_1));
        assertTrue(identityRegistry.isSanctioned(BUYER_1));
    }

    function test_markSanctioned_OnlyOfficer_RevertWhen_NonOfficer() public {
        vm.prank(BACKEND_SIGNER);
        vm.expectRevert();
        identityRegistry.markSanctioned(BUYER_1, "reason", keccak256("evidence"));
    }

    /// @dev FIX M-01: evidenceHash mandatorio
    function test_markSanctioned_RevertWhen_EvidenceHashZero() public {
        vm.prank(COMPLIANCE_OFFICER);
        vm.expectRevert(IdentityRegistry.InvalidEvidenceHash.selector);
        identityRegistry.markSanctioned(BUYER_1, "reason", bytes32(0));
    }

    function test_markSanctioned_RevertWhen_AlreadySanctioned() public {
        vm.startPrank(COMPLIANCE_OFFICER);
        identityRegistry.markSanctioned(BUYER_1, "reason1", keccak256("evidence-1"));
        vm.expectRevert(IdentityRegistry.AlreadySanctioned.selector);
        identityRegistry.markSanctioned(BUYER_1, "reason2", keccak256("evidence-2"));
        vm.stopPrank();
    }

    function test_markSanctioned_RevertWhen_EmptyReason() public {
        vm.prank(COMPLIANCE_OFFICER);
        vm.expectRevert(IdentityRegistry.EmptyReason.selector);
        identityRegistry.markSanctioned(BUYER_1, "", keccak256("evidence"));
    }

    function test_unmarkSanctioned_RestoresCanMint() public {
        _setupKYC(BUYER_1, 1);

        vm.startPrank(COMPLIANCE_OFFICER);
        identityRegistry.markSanctioned(BUYER_1, "ofac", keccak256("evidence"));
        identityRegistry.unmarkSanctioned(BUYER_1, "ofac-removed");
        vm.stopPrank();

        assertTrue(identityRegistry.canMint(BUYER_1));
    }

    function test_unmarkSanctioned_RevertWhen_NotSanctioned() public {
        vm.prank(COMPLIANCE_OFFICER);
        vm.expectRevert(IdentityRegistry.NotSanctioned.selector);
        identityRegistry.unmarkSanctioned(BUYER_1, "no-op");
    }

    // ---- freezeAddress ----

    function test_freezeAddress_HappyPath_BlocksCanMintAndCanRedeem() public {
        _setupKYC(BUYER_1, 2);
        assertTrue(identityRegistry.canMint(BUYER_1));
        assertTrue(identityRegistry.canRedeem(BUYER_1));

        vm.prank(COMPLIANCE_OFFICER);
        identityRegistry.freezeAddress(BUYER_1, "regulatory order", keccak256("order"));

        assertFalse(identityRegistry.canMint(BUYER_1));
        assertFalse(identityRegistry.canRedeem(BUYER_1));
        assertTrue(identityRegistry.isFrozen(BUYER_1));
    }

    function test_freezeAddress_RevertWhen_AlreadyFrozen() public {
        vm.startPrank(COMPLIANCE_OFFICER);
        identityRegistry.freezeAddress(BUYER_1, "order1", keccak256("order-doc-1"));
        vm.expectRevert(IdentityRegistry.AlreadyFrozen.selector);
        identityRegistry.freezeAddress(BUYER_1, "order2", keccak256("order-doc-2"));
        vm.stopPrank();
    }

    /// @dev FIX M-01b: orderHash mandatorio
    function test_freezeAddress_RevertWhen_OrderHashZero() public {
        vm.prank(COMPLIANCE_OFFICER);
        vm.expectRevert(IdentityRegistry.InvalidOrderHash.selector);
        identityRegistry.freezeAddress(BUYER_1, "order", bytes32(0));
    }

    function test_unfreezeAddress_Restores() public {
        _setupKYC(BUYER_1, 2);

        vm.startPrank(COMPLIANCE_OFFICER);
        identityRegistry.freezeAddress(BUYER_1, "order", keccak256("order-doc"));
        identityRegistry.unfreezeAddress(BUYER_1, "released");
        vm.stopPrank();

        assertTrue(identityRegistry.canRedeem(BUYER_1));
    }

    // ---- revokeKYC ----

    function test_revokeKYC_HappyPath_SetsTier0() public {
        _setupKYC(BUYER_1, 2);

        vm.prank(BACKEND_SIGNER);
        identityRegistry.revokeKYC(BUYER_1, "expired-renewal-failed");

        assertEq(identityRegistry.getTier(BUYER_1), 0);
        assertFalse(identityRegistry.canMint(BUYER_1));
    }

    function test_revokeKYC_RevertWhen_AlreadyTier0() public {
        vm.prank(BACKEND_SIGNER);
        vm.expectRevert(IdentityRegistry.AlreadyRevoked.selector);
        identityRegistry.revokeKYC(BUYER_1, "no-op");
    }

    // ---- canMint variants ----

    function test_canMint_Tier0_ReturnsFalse() public {
        assertFalse(identityRegistry.canMint(BUYER_1));
    }

    function test_canMint_Tier1Valid_ReturnsTrue() public {
        _setupKYC(BUYER_1, 1);
        assertTrue(identityRegistry.canMint(BUYER_1));
    }

    function test_canMint_Expired_ReturnsFalse() public {
        vm.prank(BACKEND_SIGNER);
        identityRegistry.setKYC(BUYER_1, 1, uint64(block.timestamp + 1 days), "BO", bytes32(0));
        assertTrue(identityRegistry.canMint(BUYER_1));

        vm.warp(block.timestamp + 2 days);
        assertFalse(identityRegistry.canMint(BUYER_1));
    }

    // ---- canRedeem ----

    function test_canRedeem_Tier1_ReturnsFalse() public {
        _setupKYC(BUYER_1, 1);
        assertFalse(identityRegistry.canRedeem(BUYER_1));
    }

    function test_canRedeem_Tier2Valid_ReturnsTrue() public {
        _setupKYC(BUYER_1, 2);
        assertTrue(identityRegistry.canRedeem(BUYER_1));
    }

    function test_canRedeem_Tier3Valid_ReturnsTrue() public {
        _setupKYC(BUYER_1, 3);
        assertTrue(identityRegistry.canRedeem(BUYER_1));
    }

    // ---- Fuzz ----

    function testFuzz_setKYC_RoundtripData(uint8 tier, uint64 expiry, bytes2 jurisdiction) public {
        tier = uint8(bound(tier, 1, 3));
        expiry = uint64(bound(expiry, block.timestamp + 1, type(uint64).max));

        vm.prank(BACKEND_SIGNER);
        identityRegistry.setKYC(BUYER_1, tier, expiry, jurisdiction, bytes32(0));

        assertEq(identityRegistry.getTier(BUYER_1), tier);
        assertEq(identityRegistry.getJurisdiction(BUYER_1), jurisdiction);
    }

    // ============================================================================
    // FIX H-02 — pause / unpause (scope limitado a mutators)
    // ============================================================================

    /// @dev FIX H-02: pause callable por COMPLIANCE_OFFICER_ROLE o DEFAULT_ADMIN_ROLE.
    ///      Cualquier otro rol o EOA debe revertir.
    function test_pause_OnlyComplianceOfficerOrAdmin() public {
        // COMPLIANCE_OFFICER titular → OK
        vm.prank(COMPLIANCE_OFFICER);
        identityRegistry.pause();

        // Re-deploy fresh para volver al estado unpaused
        identityRegistry = new IdentityRegistry(ADMIN, BACKEND_SIGNER, COMPLIANCE_OFFICER, COMPLIANCE_OFFICER_SUPLENTE);

        // DEFAULT_ADMIN_ROLE → OK (defensa cruzada)
        vm.prank(ADMIN);
        identityRegistry.pause();

        identityRegistry = new IdentityRegistry(ADMIN, BACKEND_SIGNER, COMPLIANCE_OFFICER, COMPLIANCE_OFFICER_SUPLENTE);

        // COMPLIANCE_OFFICER suplente también → OK (mismo rol)
        vm.prank(COMPLIANCE_OFFICER_SUPLENTE);
        identityRegistry.pause();

        identityRegistry = new IdentityRegistry(ADMIN, BACKEND_SIGNER, COMPLIANCE_OFFICER, COMPLIANCE_OFFICER_SUPLENTE);

        // BACKEND_SIGNER (no tiene ninguno de los dos roles) → revierte
        vm.prank(BACKEND_SIGNER);
        vm.expectRevert(IdentityRegistry.UnauthorizedPauseActor.selector);
        identityRegistry.pause();

        // EOA random → revierte
        vm.prank(BUYER_1);
        vm.expectRevert(IdentityRegistry.UnauthorizedPauseActor.selector);
        identityRegistry.pause();
    }

    /// @dev FIX H-02: en estado pausado, los 6 mutators revierten con Pausable.EnforcedPause.
    function test_pause_BlocksMutators() public {
        // Pre-setup: KYC para tener estado base para sancionar/freezear
        _setupKYC(BUYER_1, 2);

        vm.prank(COMPLIANCE_OFFICER);
        identityRegistry.pause();

        // setKYC
        vm.prank(BACKEND_SIGNER);
        vm.expectRevert(); // Pausable: paused
        identityRegistry.setKYC(BUYER_2, 1, uint64(block.timestamp + 365 days), "BO", bytes32(0));

        // revokeKYC
        vm.prank(BACKEND_SIGNER);
        vm.expectRevert();
        identityRegistry.revokeKYC(BUYER_1, "revoke during pause");

        // markSanctioned
        vm.prank(COMPLIANCE_OFFICER);
        vm.expectRevert();
        identityRegistry.markSanctioned(BUYER_1, "OFAC", keccak256("evidence"));

        // unmarkSanctioned (también bloqueado por whenNotPaused)
        vm.prank(COMPLIANCE_OFFICER);
        vm.expectRevert();
        identityRegistry.unmarkSanctioned(BUYER_1, "noop");

        // freezeAddress
        vm.prank(COMPLIANCE_OFFICER);
        vm.expectRevert();
        identityRegistry.freezeAddress(BUYER_1, "court order", keccak256("order"));

        // unfreezeAddress
        vm.prank(COMPLIANCE_OFFICER);
        vm.expectRevert();
        identityRegistry.unfreezeAddress(BUYER_1, "noop");
    }

    /// @dev FIX H-02: las views (`canMint`, `canRedeem`, `getTier`, etc.) NO se bloquean
    ///      durante el pause. AssetVault y RedemptionManager dependen de ellas para
    ///      seguir operando con usuarios legítimos.
    function test_pause_DoesNotBlockViews() public {
        _setupKYC(BUYER_1, 2);

        vm.prank(COMPLIANCE_OFFICER);
        identityRegistry.pause();

        // Todas las views siguen respondiendo correctamente.
        assertEq(identityRegistry.getTier(BUYER_1), 2);
        assertTrue(identityRegistry.canMint(BUYER_1));
        assertTrue(identityRegistry.canRedeem(BUYER_1));
        assertFalse(identityRegistry.isSanctioned(BUYER_1));
        assertFalse(identityRegistry.isFrozen(BUYER_1));
        assertFalse(identityRegistry.isExpired(BUYER_1));
        assertEq(identityRegistry.getJurisdiction(BUYER_1), bytes2("BO"));
        // getKYCData también disponible
        IIdentityRegistry.KYCData memory data = identityRegistry.getKYCData(BUYER_1);
        assertEq(data.tier, 2);
    }

    /// @dev FIX H-02: unpause restringido a DEFAULT_ADMIN_ROLE.
    ///      El Compliance Officer NO puede deshacer el pause de emergencia (defensa
    ///      contra abuse si el rol está comprometido).
    function test_unpause_OnlyAdmin() public {
        vm.prank(COMPLIANCE_OFFICER);
        identityRegistry.pause();

        // COMPLIANCE_OFFICER NO puede unpause
        vm.prank(COMPLIANCE_OFFICER);
        vm.expectRevert();
        identityRegistry.unpause();

        // COMPLIANCE_OFFICER_SUPLENTE tampoco
        vm.prank(COMPLIANCE_OFFICER_SUPLENTE);
        vm.expectRevert();
        identityRegistry.unpause();

        // BACKEND_SIGNER tampoco
        vm.prank(BACKEND_SIGNER);
        vm.expectRevert();
        identityRegistry.unpause();

        // Solo DEFAULT_ADMIN_ROLE (Safe) puede
        vm.prank(ADMIN);
        identityRegistry.unpause();
    }

    /// @dev FIX H-02: tras unpause los mutators vuelven a funcionar normalmente.
    function test_unpause_RestoresMutators() public {
        vm.prank(COMPLIANCE_OFFICER);
        identityRegistry.pause();

        vm.prank(ADMIN);
        identityRegistry.unpause();

        // setKYC funciona post-unpause
        vm.prank(BACKEND_SIGNER);
        identityRegistry.setKYC(BUYER_1, 2, uint64(block.timestamp + 365 days), "BO", keccak256("applicant"));
        assertEq(identityRegistry.getTier(BUYER_1), 2);

        // markSanctioned también
        vm.prank(COMPLIANCE_OFFICER);
        identityRegistry.markSanctioned(BUYER_1, "OFAC", keccak256("evidence"));
        assertTrue(identityRegistry.isSanctioned(BUYER_1));
    }
}
