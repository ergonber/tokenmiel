// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ILabRegistry} from "./interfaces/ILabRegistry.sol";

/// @title LabRegistry
/// @author Dany Hidalgo F.
/// @notice Registro on-chain de laboratorios certificados que pueden emitir attestations
///         de calidad (palinología, NMR, C4, residuos) sobre lotes tokenizados.
/// @dev Cada lab tiene una clave pública registrada. AssetVault verifica firmas off-chain
///      contra `verifyAttestationSignature` antes de aceptar una QualityAttestation.
/// @custom:security Compromiso de la clave de un lab → atestaciones falsas posibles
///                  hasta deactivateLab. Mitigación: revisión periódica + monitoreo.
contract LabRegistry is AccessControl, ILabRegistry {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    // ---- Roles ----
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant COMPLIANCE_OFFICER_ROLE = keccak256("COMPLIANCE_OFFICER_ROLE");

    // ---- Storage ----
    mapping(address => Lab) private _labs;

    // ---- Errors ----
    error ZeroAddress();
    error EmptySpecializations();
    error LabAlreadyExists();
    error LabNotExists();
    error LabAlreadyActive();
    error LabAlreadyDeactivated();
    error EmptyReason();

    /// @notice Inicializa el contrato con admin y oficiales de cumplimiento.
    constructor(
        address admin,
        address adminOperator,
        address complianceOfficer,
        address complianceOfficerSuplente
    ) {
        if (admin == address(0)) revert ZeroAddress();
        if (adminOperator == address(0)) revert ZeroAddress();
        if (complianceOfficer == address(0)) revert ZeroAddress();
        if (complianceOfficerSuplente == address(0)) revert ZeroAddress();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, adminOperator);
        _grantRole(COMPLIANCE_OFFICER_ROLE, complianceOfficer);
        _grantRole(COMPLIANCE_OFFICER_ROLE, complianceOfficerSuplente);
    }

    // ---- Mutating: ADMIN_ROLE ----

    /// @inheritdoc ILabRegistry
    function addLab(
        address signerAddress,
        bytes32 nameHash,
        bytes2 jurisdiction,
        Specialization[] calldata specializations,
        bytes32 accreditationHash
    ) external onlyRole(ADMIN_ROLE) {
        if (signerAddress == address(0)) revert ZeroAddress();
        if (specializations.length == 0) revert EmptySpecializations();
        if (_labs[signerAddress].signerAddress != address(0)) revert LabAlreadyExists();

        Lab storage lab = _labs[signerAddress];
        lab.signerAddress = signerAddress;
        lab.nameHash = nameHash;
        lab.jurisdiction = jurisdiction;
        for (uint256 i = 0; i < specializations.length; i++) {
            lab.specializations.push(specializations[i]);
        }
        lab.accreditationHash = accreditationHash;
        lab.active = true;
        lab.addedAt = uint64(block.timestamp);
        lab.deactivatedAt = 0;

        emit LabAdded(signerAddress, jurisdiction, specializations, accreditationHash);
    }

    // ---- Mutating: COMPLIANCE_OFFICER_ROLE ----

    /// @inheritdoc ILabRegistry
    function deactivateLab(address lab, string calldata reason) external onlyRole(COMPLIANCE_OFFICER_ROLE) {
        if (lab == address(0)) revert ZeroAddress();
        if (bytes(reason).length == 0) revert EmptyReason();
        if (_labs[lab].signerAddress == address(0)) revert LabNotExists();
        if (!_labs[lab].active) revert LabAlreadyDeactivated();

        _labs[lab].active = false;
        _labs[lab].deactivatedAt = uint64(block.timestamp);

        emit LabDeactivated(lab, reason, uint64(block.timestamp));
    }

    /// @inheritdoc ILabRegistry
    function reactivateLab(address lab, string calldata reason) external onlyRole(COMPLIANCE_OFFICER_ROLE) {
        if (lab == address(0)) revert ZeroAddress();
        if (bytes(reason).length == 0) revert EmptyReason();
        if (_labs[lab].signerAddress == address(0)) revert LabNotExists();
        if (_labs[lab].active) revert LabAlreadyActive();

        _labs[lab].active = true;
        _labs[lab].deactivatedAt = 0;

        emit LabReactivated(lab, reason);
    }

    // ---- View functions ----

    /// @inheritdoc ILabRegistry
    function verifyAttestationSignature(address lab, bytes32 attestationHash, bytes calldata signature)
        external
        view
        returns (bool)
    {
        if (_labs[lab].signerAddress == address(0)) return false;
        if (!_labs[lab].active) return false;

        bytes32 ethSignedHash = attestationHash.toEthSignedMessageHash();
        (address recovered, ECDSA.RecoverError err,) = ethSignedHash.tryRecover(signature);
        if (err != ECDSA.RecoverError.NoError) return false;
        return recovered == lab;
    }

    /// @inheritdoc ILabRegistry
    function isLabCertifiedFor(address lab, Specialization spec) external view returns (bool) {
        if (!_labs[lab].active) return false;

        Specialization[] storage specs = _labs[lab].specializations;
        for (uint256 i = 0; i < specs.length; i++) {
            if (specs[i] == spec) return true;
        }
        return false;
    }

    /// @inheritdoc ILabRegistry
    function isLabActive(address lab) external view returns (bool) {
        return _labs[lab].active;
    }

    /// @inheritdoc ILabRegistry
    function getLab(address lab) external view returns (Lab memory) {
        return _labs[lab];
    }
}
