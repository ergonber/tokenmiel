// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

/// @title IRedemptionManager
/// @notice Interface del gestor de redenciones físicas (escrow + exportación).
interface IRedemptionManager {
    /// @notice Estados del ciclo de redención.
    enum EstadoRedencion {
        INICIADA,
        EN_EXPORTACION,
        COMPLETADA,
        CANCELADA
    }

    /// @notice Datos de una redención en curso.
    struct Redencion {
        address comprador;
        uint256 loteId;
        uint256 cantidadTokens;
        bytes32 datosEnvioHash;
        EstadoRedencion estado;
        string dueNumero;
        bytes32 hashBLAWB;
        uint64 createdAt;
        uint64 completedAt;
        bytes32 cancelReason;
    }

    // ---- Eventos ----
    event RedencionIniciada(
        uint256 indexed redencionId,
        address indexed comprador,
        uint256 indexed loteId,
        uint256 cantidadTokens,
        bytes32 datosEnvioHash
    );
    event RedencionEnExportacion(uint256 indexed redencionId, string dueNumero);
    event RedencionCompletada(uint256 indexed redencionId, bytes32 hashBLAWB);
    event RedencionCancelada(uint256 indexed redencionId, bytes32 reason);

    // ---- Mutating functions ----
    function iniciarRedencion(uint256 loteId, uint256 cantidadTokens, bytes32 datosEnvioHash)
        external
        returns (uint256 redencionId);

    function confirmarExportacion(uint256 redencionId, string calldata dueNumero, bytes32 hashBLAWB) external;
    function cancelarRedencion(uint256 redencionId, bytes32 reason) external;

    // ---- View functions ----
    function getRedencion(uint256 redencionId) external view returns (Redencion memory);
    function getNextRedencionId() external view returns (uint256);
}
