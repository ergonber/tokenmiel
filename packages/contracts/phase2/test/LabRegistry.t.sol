// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {LabRegistry} from "../../src/LabRegistry.sol";
import {ILabRegistry} from "../../src/interfaces/ILabRegistry.sol";

/// @title LabRegistryTest
/// @notice Tests standalone para LabRegistry. NOTA: LabRegistry queda preparado para fase 2
///         (QualityAttestation con palinología + NMR). NO se despliega ni integra con AssetVault
///         en el MVP simplificado. Estos tests validan el contrato en isolación.
contract LabRegistryTest is Test {
    address internal constant ADMIN = address(0xA001);
    address internal constant ADMIN_OPERATOR = address(0xA002);
    address internal constant COMPLIANCE_OFFICER = address(0xD001);
    address internal constant COMPLIANCE_OFFICER_SUPLENTE = address(0xD002);
    address internal constant BACKEND_SIGNER = address(0xC001);

    uint256 internal constant LAB_BOLIVIA_PK = 0xB01171A;
    uint256 internal constant LAB_EUROPA_PK = 0xEFE01171A;
    address internal labBolivia;
    address internal labEuropa;

    LabRegistry internal labRegistry;

    function setUp() public {
        labBolivia = vm.addr(LAB_BOLIVIA_PK);
        labEuropa = vm.addr(LAB_EUROPA_PK);

        labRegistry = new LabRegistry(ADMIN, ADMIN_OPERATOR, COMPLIANCE_OFFICER, COMPLIANCE_OFFICER_SUPLENTE);

        // Seed labs
        ILabRegistry.Specialization[] memory specs = new ILabRegistry.Specialization[](4);
        specs[0] = ILabRegistry.Specialization.PALINOLOGIA;
        specs[1] = ILabRegistry.Specialization.NMR;
        specs[2] = ILabRegistry.Specialization.C4_SUGAR;
        specs[3] = ILabRegistry.Specialization.PESTICIDES;

        vm.startPrank(ADMIN_OPERATOR);
        labRegistry.addLab(labBolivia, keccak256("IBNORCA"), "BO", specs, keccak256("acred-bo"));
        labRegistry.addLab(labEuropa, keccak256("EUROFINS"), "DE", specs, keccak256("acred-de"));
        vm.stopPrank();
    }

    // ---- addLab ----

    function test_addLab_HappyPath_StoresLabData() public {
        ILabRegistry.Specialization[] memory specs = new ILabRegistry.Specialization[](1);
        specs[0] = ILabRegistry.Specialization.NMR;

        address newLab = address(0xCAFE);

        vm.prank(ADMIN_OPERATOR);
        labRegistry.addLab(newLab, keccak256("NewLab"), "FR", specs, keccak256("acred"));

        ILabRegistry.Lab memory lab = labRegistry.getLab(newLab);
        assertEq(lab.signerAddress, newLab);
        assertEq(lab.jurisdiction, bytes2("FR"));
        assertTrue(lab.active);
    }

    function test_addLab_OnlyAdmin_RevertWhen_NonAdmin() public {
        ILabRegistry.Specialization[] memory specs = new ILabRegistry.Specialization[](1);
        specs[0] = ILabRegistry.Specialization.NMR;

        vm.prank(BACKEND_SIGNER);
        vm.expectRevert();
        labRegistry.addLab(address(0xCAFE), bytes32(0), "FR", specs, bytes32(0));
    }

    function test_addLab_RevertWhen_ZeroAddress() public {
        ILabRegistry.Specialization[] memory specs = new ILabRegistry.Specialization[](1);
        specs[0] = ILabRegistry.Specialization.NMR;

        vm.prank(ADMIN_OPERATOR);
        vm.expectRevert(LabRegistry.ZeroAddress.selector);
        labRegistry.addLab(address(0), bytes32(0), "FR", specs, bytes32(0));
    }

    function test_addLab_RevertWhen_EmptySpecializations() public {
        ILabRegistry.Specialization[] memory specs = new ILabRegistry.Specialization[](0);

        vm.prank(ADMIN_OPERATOR);
        vm.expectRevert(LabRegistry.EmptySpecializations.selector);
        labRegistry.addLab(address(0xCAFE), bytes32(0), "FR", specs, bytes32(0));
    }

    function test_addLab_RevertWhen_AlreadyExists() public {
        ILabRegistry.Specialization[] memory specs = new ILabRegistry.Specialization[](1);
        specs[0] = ILabRegistry.Specialization.NMR;

        // labBolivia ya seedado en setUp
        vm.prank(ADMIN_OPERATOR);
        vm.expectRevert(LabRegistry.LabAlreadyExists.selector);
        labRegistry.addLab(labBolivia, bytes32(0), "BO", specs, bytes32(0));
    }

    // ---- deactivateLab ----

    function test_deactivateLab_HappyPath_SetsActiveFalse() public {
        assertTrue(labRegistry.isLabActive(labBolivia));

        vm.prank(COMPLIANCE_OFFICER);
        labRegistry.deactivateLab(labBolivia, "annual review failed");

        assertFalse(labRegistry.isLabActive(labBolivia));
    }

    function test_deactivateLab_OnlyOfficer_RevertWhen_NonOfficer() public {
        vm.prank(ADMIN_OPERATOR);
        vm.expectRevert();
        labRegistry.deactivateLab(labBolivia, "reason");
    }

    function test_deactivateLab_RevertWhen_LabNotExists() public {
        vm.prank(COMPLIANCE_OFFICER);
        vm.expectRevert(LabRegistry.LabNotExists.selector);
        labRegistry.deactivateLab(address(0xDEAD), "reason");
    }

    function test_deactivateLab_RevertWhen_AlreadyDeactivated() public {
        vm.startPrank(COMPLIANCE_OFFICER);
        labRegistry.deactivateLab(labBolivia, "first");
        vm.expectRevert(LabRegistry.LabAlreadyDeactivated.selector);
        labRegistry.deactivateLab(labBolivia, "second");
        vm.stopPrank();
    }

    function test_reactivateLab_RestoresActive() public {
        vm.startPrank(COMPLIANCE_OFFICER);
        labRegistry.deactivateLab(labBolivia, "deactivated");
        labRegistry.reactivateLab(labBolivia, "reactivated after review");
        vm.stopPrank();

        assertTrue(labRegistry.isLabActive(labBolivia));
    }

    // ---- verifyAttestationSignature ----

    function test_verifyAttestationSignature_ValidSignature_ReturnsTrue() public view {
        bytes32 msgHash = keccak256("test message");
        bytes32 ethSigned = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", msgHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(LAB_BOLIVIA_PK, ethSigned);
        bytes memory sig = abi.encodePacked(r, s, v);

        assertTrue(labRegistry.verifyAttestationSignature(labBolivia, msgHash, sig));
    }

    function test_verifyAttestationSignature_InvalidSignature_ReturnsFalse() public view {
        bytes32 msgHash = keccak256("test message");
        bytes memory invalidSig = abi.encodePacked(bytes32(uint256(1)), bytes32(uint256(2)), uint8(27));

        assertFalse(labRegistry.verifyAttestationSignature(labBolivia, msgHash, invalidSig));
    }

    function test_verifyAttestationSignature_LabNotInRegistry_ReturnsFalse() public {
        bytes32 msgHash = keccak256("test message");
        bytes32 ethSigned = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", msgHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(LAB_BOLIVIA_PK, ethSigned);
        bytes memory sig = abi.encodePacked(r, s, v);

        assertFalse(labRegistry.verifyAttestationSignature(address(0xDEAD), msgHash, sig));
    }

    function test_verifyAttestationSignature_LabDeactivated_ReturnsFalse() public {
        vm.prank(COMPLIANCE_OFFICER);
        labRegistry.deactivateLab(labBolivia, "deact");

        bytes32 msgHash = keccak256("test");
        bytes32 ethSigned = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", msgHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(LAB_BOLIVIA_PK, ethSigned);
        bytes memory sig = abi.encodePacked(r, s, v);

        assertFalse(labRegistry.verifyAttestationSignature(labBolivia, msgHash, sig));
    }

    // ---- isLabCertifiedFor ----

    function test_isLabCertifiedFor_LabWithSpecialization_ReturnsTrue() public view {
        assertTrue(labRegistry.isLabCertifiedFor(labBolivia, ILabRegistry.Specialization.PALINOLOGIA));
        assertTrue(labRegistry.isLabCertifiedFor(labBolivia, ILabRegistry.Specialization.NMR));
    }

    function test_isLabCertifiedFor_LabWithoutSpecialization_ReturnsFalse() public view {
        assertFalse(labRegistry.isLabCertifiedFor(labBolivia, ILabRegistry.Specialization.ANTIBIOTICS));
    }

    function test_isLabCertifiedFor_LabDeactivated_ReturnsFalse() public {
        vm.prank(COMPLIANCE_OFFICER);
        labRegistry.deactivateLab(labBolivia, "deact");
        assertFalse(labRegistry.isLabCertifiedFor(labBolivia, ILabRegistry.Specialization.NMR));
    }
}
