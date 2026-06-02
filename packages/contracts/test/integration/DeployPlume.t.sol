// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {DeployPlume, MockUSDC} from "../../script/DeployPlume.s.sol";
import {IdentityRegistry} from "../../src/IdentityRegistry.sol";
import {AssetVault} from "../../src/AssetVault.sol";
import {RedemptionManager} from "../../src/RedemptionManager.sol";

/// @title DeployPlumeTest
/// @notice Integration tests for the Gap 2 deploy orchestrator. Verifies that
///         deploy() wires the 3 MVP contracts and that an admin can break the
///         cyclic dependency (AssetVault.setRedemptionManager).
contract DeployPlumeTest is Test {
    DeployPlume internal deployer;
    MockUSDC internal usdc;

    address internal constant ADMIN = address(0xA001);
    address internal constant ADMIN_OPERATOR = address(0xA002);
    address internal constant BACKEND_SIGNER = address(0xC001);
    address internal constant COMPLIANCE_OFFICER = address(0xD001);
    address internal constant COMPLIANCE_OFFICER_SUPLENTE = address(0xD002);
    address internal constant ORACLE_SAFE = address(0xB000);
    address internal constant TREASURY_SRL = address(0xE001);

    function setUp() public {
        deployer = new DeployPlume();
        usdc = new MockUSDC();
    }

    function _config() internal view returns (DeployPlume.DeployConfig memory) {
        return DeployPlume.DeployConfig({
            admin: ADMIN,
            adminOperator: ADMIN_OPERATOR,
            backendSigner: BACKEND_SIGNER,
            complianceOfficer: COMPLIANCE_OFFICER,
            complianceOfficerSuplente: COMPLIANCE_OFFICER_SUPLENTE,
            oracleSafe: ORACLE_SAFE,
            treasurySRL: TREASURY_SRL,
            usdc: IERC20(address(usdc)),
            uri: "https://meta.example/{id}.json"
        });
    }

    /// @notice deploy() creates the 3 contracts in order; admin then breaks the cycle.
    function test_deploy_HappyPath_WiresContractsAndBreaksCycle() public {
        (IdentityRegistry ir, AssetVault av, RedemptionManager rm) = deployer.deploy(_config());

        // deploy() leaves AssetVault unwired (cycle not yet broken).
        assertEq(av.redemptionManager(), address(0), "cycle broken too early");

        // Authority (admin) breaks the cycle — same pattern as BaseTest.
        vm.prank(ADMIN);
        av.setRedemptionManager(address(rm));

        assertEq(av.redemptionManager(), address(rm), "cycle not broken");
        assertEq(address(rm.assetVault()), address(av), "rm.assetVault mismatch");
        assertEq(address(rm.identityRegistry()), address(ir), "rm.identityRegistry mismatch");
        assertEq(address(av.usdc()), address(usdc), "av.usdc mismatch");
        assertEq(address(av.identityRegistry()), address(ir), "av.identityRegistry mismatch");
    }

    /// @notice deploy() grants every role to the address configured for it.
    function test_deploy_HappyPath_GrantsRolesToConfiguredAddresses() public {
        (, AssetVault av,) = deployer.deploy(_config());

        assertTrue(av.hasRole(av.ADMIN_ROLE(), ADMIN_OPERATOR), "ADMIN_ROLE not granted");
        assertTrue(av.hasRole(av.BACKEND_SIGNER_ROLE(), BACKEND_SIGNER), "BACKEND_SIGNER_ROLE not granted");
        assertTrue(av.hasRole(av.COMPLIANCE_OFFICER_ROLE(), COMPLIANCE_OFFICER), "COMPLIANCE not granted");
        assertTrue(av.hasRole(av.ORACLE_ROLE(), ORACLE_SAFE), "ORACLE_ROLE not granted");
        assertTrue(av.hasRole(av.TREASURY_SRL_ROLE(), TREASURY_SRL), "TREASURY_SRL_ROLE not granted");
    }

    /// @notice An unknown chainid has no profile and must revert.
    function test_getConfig_RevertsWhen_UnsupportedChain() public {
        vm.chainId(999);
        vm.expectRevert(abi.encodeWithSelector(DeployPlume.UnsupportedChainId.selector, uint256(999)));
        deployer.getConfig();
    }

    /// @notice The Anvil (local) profile deploys a mock USDC and returns a usable config.
    function test_getConfig_LocalProfile_ReturnsUsableConfig() public {
        vm.chainId(31_337);
        DeployPlume.DeployConfig memory cfg = deployer.getConfig();
        assertTrue(address(cfg.usdc) != address(0), "usdc not set");
        assertTrue(cfg.admin != address(0), "admin not set");
        assertTrue(cfg.oracleSafe != address(0), "oracleSafe not set");
    }

    /// @notice The Plume mainnet profile reverts when required env addresses are absent.
    function test_getConfig_RevertsWhen_MainnetConfigMissing() public {
        vm.chainId(98_866);
        vm.expectRevert(); // MissingConfig — role env vars unset in the test environment
        deployer.getConfig();
    }
}
