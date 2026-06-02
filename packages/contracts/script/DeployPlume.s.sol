// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {IdentityRegistry} from "../src/IdentityRegistry.sol";
import {AssetVault} from "../src/AssetVault.sol";
import {RedemptionManager} from "../src/RedemptionManager.sol";

/// @dev Minimal 6-decimal USDC mock, deployed only on the local (Anvil) profile.
contract MockUSDC is ERC20 {
    constructor() ERC20("USD Coin", "USDC") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}

/// @title DeployPlume
/// @notice Gap 2 deploy orchestrator for the 3 MVP contracts (IdentityRegistry,
///         AssetVault, RedemptionManager). Selects a per-network config by
///         block.chainid and deploys the contracts in dependency order.
/// @dev The cyclic dependency (AssetVault needs RedemptionManager's address) is
///      resolved by deploy ORDER; the final wiring call
///      (AssetVault.setRedemptionManager) is gated by DEFAULT_ADMIN_ROLE and is
///      executed by the admin authority, not by this orchestrator.
contract DeployPlume is Script {
    // ---- Supported chain ids ----
    uint256 internal constant ANVIL_CHAIN_ID = 31_337;
    uint256 internal constant PLUME_TESTNET_CHAIN_ID = 98_867;
    uint256 internal constant PLUME_MAINNET_CHAIN_ID = 98_866;

    // ---- Local (Anvil) dev role holders ----
    address internal constant LOCAL_ADMIN = address(0xA001);
    address internal constant LOCAL_ADMIN_OPERATOR = address(0xA002);
    address internal constant LOCAL_BACKEND_SIGNER = address(0xC001);
    address internal constant LOCAL_COMPLIANCE = address(0xD001);
    address internal constant LOCAL_COMPLIANCE_SUPLENTE = address(0xD002);
    address internal constant LOCAL_ORACLE_SAFE = address(0xB000);
    address internal constant LOCAL_TREASURY_SRL = address(0xE001);

    error UnsupportedChainId(uint256 chainId);
    error MissingConfig(string field);

    /// @notice Per-network deployment parameters (role holders + payment token + metadata URI).
    struct DeployConfig {
        address admin;
        address adminOperator;
        address backendSigner;
        address complianceOfficer;
        address complianceOfficerSuplente;
        address oracleSafe;
        address treasurySRL;
        IERC20 usdc;
        string uri;
    }

    /// @notice forge script entry point: resolves config, deploys, and wires the cycle if authorized.
    /// @dev Run with: forge script script/DeployPlume.s.sol --rpc-url <plume_testnet> --broadcast.
    ///      The setRedemptionManager call only executes if the broadcaster holds
    ///      DEFAULT_ADMIN_ROLE; otherwise it is left for the admin Safe to call.
    function run() external returns (IdentityRegistry ir, AssetVault av, RedemptionManager rm) {
        DeployConfig memory cfg = getConfig();

        vm.startBroadcast();
        (ir, av, rm) = deploy(cfg);
        if (av.hasRole(av.DEFAULT_ADMIN_ROLE(), msg.sender)) {
            av.setRedemptionManager(address(rm));
        }
        vm.stopBroadcast();

        console2.log("IdentityRegistry: ", address(ir));
        console2.log("AssetVault:       ", address(av));
        console2.log("RedemptionManager:", address(rm));
        if (av.redemptionManager() == address(0)) {
            console2.log("WIRING PENDING -> admin must call AssetVault.setRedemptionManager(redemptionManager)");
        }
    }

    /// @notice Resolves the deploy config for the current chain (block.chainid).
    /// @dev Anvil deploys a MockUSDC; Plume testnet/mainnet read role holders from env vars.
    /// @return The resolved per-network config.
    function getConfig() public returns (DeployConfig memory) {
        if (block.chainid == ANVIL_CHAIN_ID) return _localConfig();
        if (block.chainid == PLUME_TESTNET_CHAIN_ID || block.chainid == PLUME_MAINNET_CHAIN_ID) {
            return _envConfig();
        }
        revert UnsupportedChainId(block.chainid);
    }

    /// @dev Local profile: fixed dev role holders + a freshly deployed MockUSDC.
    function _localConfig() internal returns (DeployConfig memory) {
        return DeployConfig({
            admin: LOCAL_ADMIN,
            adminOperator: LOCAL_ADMIN_OPERATOR,
            backendSigner: LOCAL_BACKEND_SIGNER,
            complianceOfficer: LOCAL_COMPLIANCE,
            complianceOfficerSuplente: LOCAL_COMPLIANCE_SUPLENTE,
            oracleSafe: LOCAL_ORACLE_SAFE,
            treasurySRL: LOCAL_TREASURY_SRL,
            usdc: IERC20(address(new MockUSDC())),
            uri: "https://meta.local/{id}.json"
        });
    }

    /// @dev Plume profile (testnet/mainnet): every role holder + USDC address read from env vars.
    function _envConfig() internal view returns (DeployConfig memory cfg) {
        cfg = DeployConfig({
            admin: vm.envOr("SAFE_ADMIN_ADDR", address(0)),
            adminOperator: vm.envOr("SAFE_OPERATOR_ADDR", address(0)),
            backendSigner: vm.envOr("BACKEND_SIGNER_ADDR", address(0)),
            complianceOfficer: vm.envOr("COMPLIANCE_ADDR", address(0)),
            complianceOfficerSuplente: vm.envOr("COMPLIANCE_SUPLENTE_ADDR", address(0)),
            oracleSafe: vm.envOr("ORACLE_SAFE_ADDR", address(0)),
            treasurySRL: vm.envOr("TREASURY_SRL_ADDR", address(0)),
            usdc: IERC20(vm.envOr("USDC_ADDR", address(0))),
            uri: vm.envOr("TOKEN_URI", string("https://meta.plume.example/{id}.json"))
        });
        _requireConfig(cfg);
    }

    /// @dev Reverts MissingConfig for any unset (zero) address in a non-local profile.
    function _requireConfig(DeployConfig memory cfg) internal pure {
        if (cfg.admin == address(0)) revert MissingConfig("SAFE_ADMIN_ADDR");
        if (cfg.adminOperator == address(0)) revert MissingConfig("SAFE_OPERATOR_ADDR");
        if (cfg.backendSigner == address(0)) revert MissingConfig("BACKEND_SIGNER_ADDR");
        if (cfg.complianceOfficer == address(0)) revert MissingConfig("COMPLIANCE_ADDR");
        if (cfg.complianceOfficerSuplente == address(0)) revert MissingConfig("COMPLIANCE_SUPLENTE_ADDR");
        if (cfg.oracleSafe == address(0)) revert MissingConfig("ORACLE_SAFE_ADDR");
        if (cfg.treasurySRL == address(0)) revert MissingConfig("TREASURY_SRL_ADDR");
        if (address(cfg.usdc) == address(0)) revert MissingConfig("USDC_ADDR");
    }

    /// @notice Deploys the 3 MVP contracts in dependency order.
    /// @dev Does NOT call AssetVault.setRedemptionManager (onlyRole DEFAULT_ADMIN_ROLE):
    ///      the admin authority wires it post-deploy (a prank in tests, the
    ///      deployer-admin broadcast on-chain via run()).
    /// @param cfg Per-network role holders, payment token and metadata URI.
    /// @return identityRegistry The deployed IdentityRegistry.
    /// @return assetVault The deployed AssetVault (redemptionManager still unset).
    /// @return redemptionManager The deployed RedemptionManager.
    function deploy(DeployConfig memory cfg)
        public
        returns (IdentityRegistry identityRegistry, AssetVault assetVault, RedemptionManager redemptionManager)
    {
        identityRegistry = new IdentityRegistry(
            cfg.admin, cfg.backendSigner, cfg.complianceOfficer, cfg.complianceOfficerSuplente
        );

        assetVault = new AssetVault(
            AssetVault.InitParams({
                admin: cfg.admin,
                adminOperator: cfg.adminOperator,
                backendSigner: cfg.backendSigner,
                complianceOfficer: cfg.complianceOfficer,
                complianceOfficerSuplente: cfg.complianceOfficerSuplente,
                oracleSafe: cfg.oracleSafe,
                treasurySRL: cfg.treasurySRL,
                usdc: cfg.usdc,
                identityRegistry: identityRegistry,
                uri: cfg.uri
            })
        );

        redemptionManager = new RedemptionManager(
            cfg.admin,
            cfg.oracleSafe,
            cfg.complianceOfficer,
            cfg.complianceOfficerSuplente,
            assetVault,
            identityRegistry
        );
    }
}
