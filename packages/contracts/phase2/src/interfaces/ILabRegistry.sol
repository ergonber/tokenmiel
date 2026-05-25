// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

/// @title ILabRegistry
/// @notice Interface del registro on-chain de laboratorios certificados que pueden emitir
///         attestations de calidad para los lotes tokenizados.
/// @dev Consultado por AssetVault al confirmar calidad (palinología + NMR + C4 + residuos).
interface ILabRegistry {
    /// @notice Especializaciones que un lab puede tener acreditadas.
    enum Specialization {
        PALINOLOGIA,
        NMR,
        C4_SUGAR,
        PESTICIDES,
        ANTIBIOTICS,
        HMF_DIASTASE_MOISTURE
    }

    /// @notice Datos de un laboratorio registrado.
    /// @dev signerAddress es la clave pública ECDSA del lab.
    struct Lab {
        address signerAddress;
        bytes32 nameHash;
        bytes2 jurisdiction;
        Specialization[] specializations;
        bytes32 accreditationHash;
        bool active;
        uint64 addedAt;
        uint64 deactivatedAt;
    }

    // ---- Eventos ----
    event LabAdded(
        address indexed lab,
        bytes2 jurisdiction,
        Specialization[] specializations,
        bytes32 accreditationHash
    );
    event LabDeactivated(address indexed lab, string reason, uint64 deactivatedAt);
    event LabReactivated(address indexed lab, string reason);

    // ---- Mutating functions ----
    function addLab(
        address signerAddress,
        bytes32 nameHash,
        bytes2 jurisdiction,
        Specialization[] calldata specializations,
        bytes32 accreditationHash
    ) external;

    function deactivateLab(address lab, string calldata reason) external;
    function reactivateLab(address lab, string calldata reason) external;

    // ---- View functions ----
    function verifyAttestationSignature(address lab, bytes32 attestationHash, bytes calldata signature)
        external
        view
        returns (bool);

    function isLabCertifiedFor(address lab, Specialization spec) external view returns (bool);
    function isLabActive(address lab) external view returns (bool);
    function getLab(address lab) external view returns (Lab memory);
}
