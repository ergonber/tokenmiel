// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {
    AccessControlDefaultAdminRules
} from "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IIdentityRegistry} from "./interfaces/IIdentityRegistry.sol";
import {ComplianceConstants} from "./libraries/ComplianceConstants.sol";

/// @title IdentityRegistry
/// @author Daniel Hidalgo Carrasco
/// @notice Registro on-chain de identidades verificadas (KYC) con tiers, sancionados y congelados.
/// @dev Consultado por AssetVault (`canMint`) y RedemptionManager (`canRedeem`).
///      Sincronizado desde Sumsub off-chain via BACKEND_SIGNER_ROLE.
///      Acciones regulatorias (sancionar/congelar) requieren COMPLIANCE_OFFICER_ROLE.
/// @custom:security
///   - Modificaciones de KYC tienen efecto inmediato en blockchain. Sin retroactividad.
///   - FIX M-08: usa AccessControlDefaultAdminRules con delay de 3 días para transferencias de
///     DEFAULT_ADMIN_ROLE (mitiga lockout accidental o malicioso).
///   - FIX H-02: incluye Pausable con scope limitado a mutators (views siguen funcionando).
contract IdentityRegistry is AccessControlDefaultAdminRules, Pausable, IIdentityRegistry {
    // ---- Roles ----
    bytes32 public constant BACKEND_SIGNER_ROLE = keccak256("BACKEND_SIGNER_ROLE");
    bytes32 public constant COMPLIANCE_OFFICER_ROLE = keccak256("COMPLIANCE_OFFICER_ROLE");

    // ---- Storage ----
    mapping(address => KYCData) private _kyc;

    // ---- Errors ----
    error InvalidTier();
    error ExpiryInPast();
    error AlreadySanctioned();
    error NotSanctioned();
    error AlreadyFrozen();
    error NotFrozen();
    error AlreadyRevoked();
    error EmptyReason();
    error ZeroAddressUser();
    // FIX M-01: hash de evidencia mandatorio para auditoría regulatoria
    error InvalidEvidenceHash();
    // FIX M-01b: hash de orden regulatoria mandatorio para freeze
    error InvalidOrderHash();
    // FIX M-04: tier=0 no se setea via setKYC (usar revokeKYC en su lugar — separa semánticamente)
    error TierZeroNotAllowed();
    // FIX H-02: caller de pause() sin COMPLIANCE_OFFICER_ROLE ni DEFAULT_ADMIN_ROLE
    error UnauthorizedPauseActor();

    /// @notice Delay (en segundos) para transferencias de DEFAULT_ADMIN_ROLE (FIX M-08).
    /// @dev 3 días permite cancelar transferencias accidentales o maliciosas antes de que se materialicen.
    uint48 public constant ADMIN_TRANSFER_DELAY = 3 days;

    /// @notice Inicializa el contrato con admin y los roles operativos.
    /// @param admin Dirección con DEFAULT_ADMIN_ROLE (típicamente Safe Wyoming 2-de-3).
    /// @param backendSigner Wallet del backend (HSM-managed) que sincroniza KYC.
    /// @param complianceOfficer Oficial de Cumplimiento titular.
    /// @param complianceOfficerSuplente Oficial de Cumplimiento suplente.
    /// @dev FIX M-08: `admin` se asigna vía AccessControlDefaultAdminRules con delay de 3 días para transferencias.
    constructor(address admin, address backendSigner, address complianceOfficer, address complianceOfficerSuplente)
        AccessControlDefaultAdminRules(ADMIN_TRANSFER_DELAY, admin)
    {
        if (backendSigner == address(0)) revert ZeroAddressUser();
        if (complianceOfficer == address(0)) revert ZeroAddressUser();
        if (complianceOfficerSuplente == address(0)) revert ZeroAddressUser();
        // NOTA: `admin == address(0)` ya es chequeado por AccessControlDefaultAdminRules (DefaultAdminZeroAddress).

        _grantRole(BACKEND_SIGNER_ROLE, backendSigner);
        _grantRole(COMPLIANCE_OFFICER_ROLE, complianceOfficer);
        _grantRole(COMPLIANCE_OFFICER_ROLE, complianceOfficerSuplente);
    }

    // ---- Mutating: BACKEND_SIGNER_ROLE ----

    /// @inheritdoc IIdentityRegistry
    function setKYC(address user, uint8 tier, uint64 expiresAt, bytes2 jurisdiction, bytes32 sumsubApplicantHash)
        external
        onlyRole(BACKEND_SIGNER_ROLE)
        whenNotPaused
    {
        if (user == address(0)) revert ZeroAddressUser();
        // FIX M-04: tier=0 no se setea acá; usar revokeKYC para separar semánticamente
        // "nunca verificado" (default storage) de "fue verificado y revocado".
        if (tier == 0) revert TierZeroNotAllowed();
        if (tier > ComplianceConstants.MAX_KYC_TIER) revert InvalidTier();
        if (expiresAt <= block.timestamp) revert ExpiryInPast();

        KYCData storage data = _kyc[user];
        data.tier = tier;
        data.expiresAt = expiresAt;
        data.updatedAt = uint64(block.timestamp);
        data.jurisdiction = jurisdiction;
        data.sumsubApplicantHash = sumsubApplicantHash;

        // FIX M-03: incluir msg.sender indexed para forensics post-incidente
        emit KYCUpdated(user, msg.sender, tier, expiresAt, jurisdiction);
    }

    /// @inheritdoc IIdentityRegistry
    /// @dev FIX Opt-B1: cachear storage pointer para evitar repeated SLOAD del mismo slot.
    function revokeKYC(address user, string calldata reason) external onlyRole(BACKEND_SIGNER_ROLE) whenNotPaused {
        if (user == address(0)) revert ZeroAddressUser();
        if (bytes(reason).length == 0) revert EmptyReason();

        KYCData storage data = _kyc[user];
        if (data.tier == 0) revert AlreadyRevoked();

        data.tier = 0;
        data.updatedAt = uint64(block.timestamp);

        // FIX M-03: msg.sender indexed
        emit KYCRevoked(user, msg.sender, reason);
    }

    // ---- Mutating: COMPLIANCE_OFFICER_ROLE ----

    /// @inheritdoc IIdentityRegistry
    /// @dev FIX M-01: evidenceHash mandatorio (no aceptamos sanciones sin documento de soporte).
    ///      FIX M-03: msg.sender indexed para forensics.
    ///      FIX Opt-B1: cache storage pointer.
    function markSanctioned(address user, string calldata reason, bytes32 evidenceHash)
        external
        onlyRole(COMPLIANCE_OFFICER_ROLE)
        whenNotPaused
    {
        if (user == address(0)) revert ZeroAddressUser();
        if (bytes(reason).length == 0) revert EmptyReason();
        if (evidenceHash == bytes32(0)) revert InvalidEvidenceHash();

        KYCData storage data = _kyc[user];
        if (data.sanctioned) revert AlreadySanctioned();

        data.sanctioned = true;
        data.updatedAt = uint64(block.timestamp);

        emit Sanctioned(user, msg.sender, reason, evidenceHash, uint64(block.timestamp));
    }

    /// @inheritdoc IIdentityRegistry
    function unmarkSanctioned(address user, string calldata reason)
        external
        onlyRole(COMPLIANCE_OFFICER_ROLE)
        whenNotPaused
    {
        if (user == address(0)) revert ZeroAddressUser();
        if (bytes(reason).length == 0) revert EmptyReason();

        KYCData storage data = _kyc[user];
        if (!data.sanctioned) revert NotSanctioned();

        data.sanctioned = false;
        data.updatedAt = uint64(block.timestamp);

        emit Unsanctioned(user, msg.sender, reason);
    }

    /// @inheritdoc IIdentityRegistry
    /// @dev FIX M-01b: orderHash mandatorio (no aceptamos freeze sin orden judicial/regulatoria documentada).
    function freezeAddress(address user, string calldata regulatoryOrder, bytes32 orderHash)
        external
        onlyRole(COMPLIANCE_OFFICER_ROLE)
        whenNotPaused
    {
        if (user == address(0)) revert ZeroAddressUser();
        if (bytes(regulatoryOrder).length == 0) revert EmptyReason();
        if (orderHash == bytes32(0)) revert InvalidOrderHash();

        KYCData storage data = _kyc[user];
        if (data.frozen) revert AlreadyFrozen();

        data.frozen = true;
        data.updatedAt = uint64(block.timestamp);

        emit Frozen(user, msg.sender, regulatoryOrder, orderHash);
    }

    /// @inheritdoc IIdentityRegistry
    function unfreezeAddress(address user, string calldata reason)
        external
        onlyRole(COMPLIANCE_OFFICER_ROLE)
        whenNotPaused
    {
        if (user == address(0)) revert ZeroAddressUser();
        if (bytes(reason).length == 0) revert EmptyReason();

        KYCData storage data = _kyc[user];
        if (!data.frozen) revert NotFrozen();

        data.frozen = false;
        data.updatedAt = uint64(block.timestamp);

        emit Unfrozen(user, msg.sender, reason);
    }

    // ---- Mutating: emergency pause (FIX H-02) ----

    /// @inheritdoc IIdentityRegistry
    /// @dev FIX H-02: pause de emergencia callable por COMPLIANCE_OFFICER_ROLE o DEFAULT_ADMIN_ROLE
    ///      (defensa cruzada: si el Compliance Officer está comprometido, el admin Safe puede pausar).
    ///      Solo afecta los mutators KYC/compliance — las views (`canMint`, `canRedeem`, etc.) siguen
    ///      funcionando para no detener AssetVault/RedemptionManager.
    function pause() external whenNotPaused {
        if (!hasRole(COMPLIANCE_OFFICER_ROLE, msg.sender) && !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            revert UnauthorizedPauseActor();
        }
        _pause();
        emit EmergencyPaused(msg.sender, uint64(block.timestamp));
    }

    /// @inheritdoc IIdentityRegistry
    /// @dev FIX H-02: unpause restringido a DEFAULT_ADMIN_ROLE (Safe 2-de-3) para evitar abuse:
    ///      un Compliance Officer comprometido NO puede deshacer el pause de emergencia.
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
        emit EmergencyUnpaused(msg.sender, uint64(block.timestamp));
    }

    // ---- View functions ----

    /// @inheritdoc IIdentityRegistry
    function getTier(address user) external view returns (uint8) {
        return _kyc[user].tier;
    }

    /// @inheritdoc IIdentityRegistry
    function isSanctioned(address user) external view returns (bool) {
        return _kyc[user].sanctioned;
    }

    /// @inheritdoc IIdentityRegistry
    function isFrozen(address user) external view returns (bool) {
        return _kyc[user].frozen;
    }

    /// @inheritdoc IIdentityRegistry
    function isExpired(address user) external view returns (bool) {
        return _kyc[user].expiresAt <= block.timestamp;
    }

    /// @inheritdoc IIdentityRegistry
    function canMint(address user) external view returns (bool) {
        KYCData storage data = _kyc[user];
        return data.tier >= ComplianceConstants.MIN_KYC_TIER_PARA_COMPRAR && !data.sanctioned && !data.frozen
            && data.expiresAt > block.timestamp;
    }

    /// @inheritdoc IIdentityRegistry
    function canRedeem(address user) external view returns (bool) {
        KYCData storage data = _kyc[user];
        return data.tier >= ComplianceConstants.MIN_KYC_TIER_PARA_REDIMIR && !data.sanctioned && !data.frozen
            && data.expiresAt > block.timestamp;
    }

    /// @inheritdoc IIdentityRegistry
    function getJurisdiction(address user) external view returns (bytes2) {
        return _kyc[user].jurisdiction;
    }

    /// @inheritdoc IIdentityRegistry
    function getKYCData(address user) external view returns (KYCData memory) {
        return _kyc[user];
    }
}
