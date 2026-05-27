// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

/// @title IIdentityRegistry
/// @notice Interface del registro on-chain de identidades verificadas (KYC).
/// @dev Consultado por AssetVault y RedemptionManager para validar operaciones.
interface IIdentityRegistry {
    /// @notice Struct con los datos de KYC de una dirección.
    /// @dev Storage packed: tier+sanctioned+frozen+jurisdiction en slot 0 (4 bytes),
    ///      expiresAt+updatedAt en slot 0 (16 bytes total con anteriores),
    ///      sumsubApplicantHash en slot 1.
    struct KYCData {
        uint8 tier;
        bool sanctioned;
        bool frozen;
        bytes2 jurisdiction;
        uint64 expiresAt;
        uint64 updatedAt;
        bytes32 sumsubApplicantHash;
    }

    // ---- Eventos ----
    // FIX M-03: incluir actor (msg.sender) indexed para forensics post-incidente.
    //          Permite distinguir qué Compliance Officer (titular vs suplente) hizo qué cambio,
    //          y validar que las acciones provienen del role correcto.
    event KYCUpdated(address indexed user, address indexed actor, uint8 tier, uint64 expiresAt, bytes2 jurisdiction);
    event Sanctioned(
        address indexed user, address indexed actor, string reason, bytes32 evidenceHash, uint64 timestamp
    );
    event Unsanctioned(address indexed user, address indexed actor, string reason);
    event Frozen(address indexed user, address indexed actor, string regulatoryOrder, bytes32 orderHash);
    event Unfrozen(address indexed user, address indexed actor, string reason);
    event KYCRevoked(address indexed user, address indexed actor, string reason);

    // FIX H-02: eventos de pausa de emergencia (scope limitado a mutators).
    event EmergencyPaused(address indexed actor, uint64 timestamp);
    event EmergencyUnpaused(address indexed actor, uint64 timestamp);

    // ---- Mutating functions ----
    function setKYC(address user, uint8 tier, uint64 expiresAt, bytes2 jurisdiction, bytes32 sumsubApplicantHash)
        external;

    function markSanctioned(address user, string calldata reason, bytes32 evidenceHash) external;
    function unmarkSanctioned(address user, string calldata reason) external;
    function freezeAddress(address user, string calldata regulatoryOrder, bytes32 orderHash) external;
    function unfreezeAddress(address user, string calldata reason) external;
    function revokeKYC(address user, string calldata reason) external;

    // FIX H-02: pause de emergencia (scope limitado a mutators KYC/compliance).
    function pause() external;
    function unpause() external;

    // ---- View functions ----
    function getTier(address user) external view returns (uint8);
    function isSanctioned(address user) external view returns (bool);
    function isFrozen(address user) external view returns (bool);
    function isExpired(address user) external view returns (bool);
    function canMint(address user) external view returns (bool);
    function canRedeem(address user) external view returns (bool);
    function getJurisdiction(address user) external view returns (bytes2);
    function getKYCData(address user) external view returns (KYCData memory);
}
