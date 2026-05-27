// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

/// @title IRedemptionManager
/// @notice Interface del gestor de redenciones fisicas (lock contable + exportacion).
/// @dev Modelo Option B (Lock Acumulator): los tokens permanecen en el wallet del comprador.
///      El contrato lleva un registro contable de cuantos tokens estan "lockeados" en redenciones
///      activas, previniendo la doble-redencion sin requerir transfers al escrow.
interface IRedemptionManager {
    /// @notice Estados del ciclo de redencion.
    enum EstadoRedencion {
        INICIADA,
        EN_EXPORTACION,
        COMPLETADA,
        CANCELADA
    }

    /// @notice Datos de una redencion en curso.
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
    /// @notice Emitted when the oracle confirms the customs declaration is filed.
    /// @param redencionId ID of the redemption transitioning toward export.
    /// @param actor ORACLE_ROLE address (Safe signer) that submitted the DUE number.
    /// @param dueNumero Customs declaration number (DUE). Max 64 chars.
    event RedencionEnExportacion(uint256 indexed redencionId, address indexed actor, string dueNumero);

    /// @notice Emitted when the redemption is fully completed (tokens burned, BL/AWB recorded).
    /// @param redencionId ID of the completed redemption.
    /// @param actor ORACLE_ROLE address (Safe signer) that finalized the redemption.
    /// @param hashBLAWB Hash of the Bill of Lading or Air Waybill.
    event RedencionCompletada(uint256 indexed redencionId, address indexed actor, bytes32 hashBLAWB);

    /// @notice Emitted when the redemption is cancelled (lock released, no burn).
    /// @param redencionId ID of the cancelled redemption.
    /// @param actor ORACLE_ROLE address (Safe signer) that triggered the cancellation.
    /// @param reason Hash of the cancellation reason (e.g., keccak256("aduana-rechazada")).
    event RedencionCancelada(uint256 indexed redencionId, address indexed actor, bytes32 reason);

    /// @notice Emitted when the contract is paused via emergency procedure (RM-15, ADR-013 alignment).
    /// @dev Emitted ADDITIONALLY to OpenZeppelin's default `Paused(account)`. Indexers reading the
    ///      project convention should listen for this event for actor + timestamp forensics.
    /// @param actor Address (COMPLIANCE_OFFICER_ROLE) that called pause().
    /// @param timestamp Block timestamp of the pause event.
    event EmergencyPaused(address indexed actor, uint64 timestamp);

    /// @notice Emitted when the contract is unpaused after an emergency.
    /// @dev Emitted ADDITIONALLY to OpenZeppelin's default `Unpaused(account)`.
    /// @param actor Address (COMPLIANCE_OFFICER_ROLE) that called unpause().
    /// @param timestamp Block timestamp of the unpause event.
    event EmergencyUnpaused(address indexed actor, uint64 timestamp);

    // ---- Mutating functions ----

    /// @notice Inicia una redencion fisica registrando un lock contable sobre los tokens del comprador.
    /// @dev El comprador debe tener tier >= 2 en IdentityRegistry y balance suficiente no lockeado.
    /// @param loteId ID del lote a redimir. Debe estar en ALMACENADO o REDENCION_PARCIAL.
    /// @param cantidadTokens Cantidad de tokens a redimir. Debe ser > 0 y <= availableBalance.
    /// @param datosEnvioHash Hash de los datos de envio (direccion, contacto, instrucciones de entrega).
    /// @return redencionId ID asignado a la nueva redencion.
    function iniciarRedencion(uint256 loteId, uint256 cantidadTokens, bytes32 datosEnvioHash)
        external
        returns (uint256 redencionId);

    /// @notice Confirma la exportacion fisica y quema los tokens del comprador.
    /// @dev Solo ORACLE_ROLE. No bloqueado por pause (ver CONTRACT-SPECS §6.13.8).
    /// @param redencionId ID de la redencion a confirmar.
    /// @param dueNumero Numero de DUE (Declaracion Unica de Exportacion). Max 64 chars.
    /// @param hashBLAWB Hash del Bill of Lading o Air Waybill.
    function confirmarExportacion(uint256 redencionId, string calldata dueNumero, bytes32 hashBLAWB) external;

    /// @notice Cancela una redencion en curso, liberando el lock contable del comprador.
    /// @dev Solo ORACLE_ROLE. No bloqueado por pause (ver CONTRACT-SPECS §6.13.8).
    /// @param redencionId ID de la redencion a cancelar.
    /// @param reason Hash del motivo de cancelacion (e.g., keccak256("aduana-rechazada")).
    function cancelarRedencion(uint256 redencionId, bytes32 reason) external;

    // ---- View functions ----

    /// @notice Retorna los datos completos de una redencion.
    /// @param redencionId ID de la redencion.
    /// @return Struct Redencion completo.
    function getRedencion(uint256 redencionId) external view returns (Redencion memory);

    /// @notice Retorna el proximo ID de redencion que sera asignado.
    /// @return ID del siguiente redencionId.
    function getNextRedencionId() external view returns (uint256);

    /// @notice Retorna el balance disponible del comprador para nuevas redenciones en un lote.
    /// @dev Calcula: balanceOf(buyer, loteId) - suma_de_tokens_en_redenciones_activas.
    ///      Este valor puede ser < balanceOf si hay redenciones INICIADA activas.
    /// @param buyer Wallet del comprador.
    /// @param loteId ID del lote.
    /// @return Tokens disponibles para iniciar nuevas redenciones.
    function availableBalance(address buyer, uint256 loteId) external view returns (uint256);

    /// @notice Retorna la cantidad de tokens lockeados de un comprador para un lote.
    /// @dev Valor > 0 solo mientras haya redenciones en estado INICIADA.
    ///      Decrementa cuando la redencion se confirma o cancela.
    /// @param buyer Wallet del comprador.
    /// @param loteId ID del lote.
    /// @return Tokens actualmente lockeados en redenciones activas.
    function tokensLockedFor(address buyer, uint256 loteId) external view returns (uint256);

    /// @notice Longitud maxima del numero DUE en caracteres.
    /// @return Limite de caracteres para dueNumero (64).
    /// @dev Slither flagea esto como naming-convention violation porque el getter auto-generado
    ///      de la constante publica MAX_DUE_NUMERO_LENGTH no esta en mixedCase. Es falso positivo:
    ///      las constantes deben ser SCREAMING_SNAKE_CASE per CLAUDE.md §5 + Solidity style guide.
    // slither-disable-next-line naming-convention
    function MAX_DUE_NUMERO_LENGTH() external view returns (uint256);
}
