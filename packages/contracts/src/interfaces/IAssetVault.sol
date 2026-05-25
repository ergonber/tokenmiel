// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

/// @title IAssetVault
/// @author Daniel Hidalgo Carrasco
/// @notice Interface del contrato principal de tokenización (ERC-1155 + lifecycle + reserve + escrow).
/// @dev MVP simplificado: sin QualityAttestation (reservado para fase 2 via LabRegistry standalone).
///      Modelo escrow total: USDC del comprador retenido hasta `confirmarCosecha`.
interface IAssetVault {
    /// @notice Estados del ciclo de vida de un lote.
    /// @dev Flujo: PREVENTA → COSECHADO → ALMACENADO → REDENCION_PARCIAL → AGOTADO.
    ///      Desde PREVENTA o COSECHADO también puede ir a FALLIDO.
    ///      QUALITY_ATTESTED reservado para fase 2 (no usado en MVP).
    enum LoteEstado {
        PREVENTA,
        COSECHADO,
        ALMACENADO,
        REDENCION_PARCIAL,
        AGOTADO,
        FALLIDO
    }

    /// @notice Tipo de certificado de origen para exportación.
    enum TipoCertificadoOrigen {
        NONE,
        FORM_A,
        EUR_1,
        OTHER
    }

    /// @notice Datos de un lote tokenizado.
    /// @dev Storage packing optimizado.
    struct LoteMiel {
        uint256 kgEsperados;
        uint256 kgCosechadosReal;
        uint256 kgRedimidos;
        uint256 precioPorTokenUSDC;
        uint256 reservaTecnicaUSDC;
        uint256 reservaTecnicaLiberada;
        /// @notice Monto neto retenido en escrow (post-FIX H-01). Se libera al productor en `confirmarCosecha`.
        ///         Si el lote FALLA en PREVENTA, queda disponible para reembolso 100% on-chain.
        uint256 montoNetoPendiente;
        uint64 fechaCosechaEstimada;
        LoteEstado estado;
        uint64 fechaCreacion;
        bytes2 origenGeografico;
        uint16 reservaBps;
        bytes32 hashFSA;
        bytes32 hashSenasag;
        bytes32 hashAnalisisLab;
        bytes32 hashContratoDeposito;
        bytes32 hashCertificadoOrigen;
        bytes32 hashActaCosecha;
        bytes32 hashFotosApiario;
        address productorSRL;
        uint8 variedadMonofloral;
        TipoCertificadoOrigen tipoCertificadoOrigen;
        string motivoFallo;
    }

    // ---- Eventos ----
    event LoteCreado(
        uint256 indexed loteId,
        uint256 kgEsperados,
        uint256 precioPorTokenUSDC,
        address indexed productorSRL,
        bytes32 hashFSA,
        uint16 reservaBps
    );
    event LoteComprado(
        uint256 indexed loteId,
        address indexed comprador,
        uint256 cantidadTokens,
        uint256 montoUSDC,
        uint256 reservaRetenida,
        bytes32 paymentRefHash
    );
    event CosechaConfirmada(
        uint256 indexed loteId,
        uint256 kgRealCosechado,
        bytes32 hashSenasag,
        bytes32 hashAnalisisLab,
        bytes32 hashActaCosecha,
        bytes32 hashCertificadoOrigen
    );
    /// @notice Emitido cuando el monto neto retenido en escrow se libera al productor (post-cosecha).
    event MontoNetoLiberado(uint256 indexed loteId, uint256 monto, address indexed destinatario);
    event AlmacenamientoConfirmado(
        uint256 indexed loteId, bytes32 hashContratoDeposito, address indexed almacenAutorizado
    );
    event LoteFallido(uint256 indexed loteId, string motivo);
    event ReservaTecnicaLiberada(uint256 indexed loteId, uint256 monto, address indexed destinatario);
    event ReembolsoEjecutado(
        uint256 indexed loteId, address indexed comprador, uint256 tokensQuemados, uint256 usdcDevuelto
    );
    event EmergencyPaused(address indexed officer, uint64 timestamp);
    event EmergencyUnpaused(address indexed officer, uint64 timestamp);

    // ---- Mutating functions ----
    function crearLote(
        uint256 loteId,
        uint256 kgEsperados,
        uint256 precioPorTokenUSDC,
        uint64 fechaCosechaEstimada,
        bytes2 origenGeografico,
        address productorSRL,
        bytes32 hashFSA,
        uint16 reservaBps,
        uint8 variedadMonofloral
    ) external;

    function comprar(
        uint256 loteId,
        uint256 cantidadTokens,
        address comprador,
        uint256 montoUSDCPagado,
        bytes32 paymentRefHash
    ) external;

    function confirmarCosecha(
        uint256 loteId,
        uint256 kgRealCosechado,
        bytes32 hashSenasag,
        bytes32 hashAnalisisLab,
        bytes32 hashActaCosecha,
        bytes32 hashFotosApiario,
        bytes32 hashCertificadoOrigen,
        TipoCertificadoOrigen tipoCertificado
    ) external;

    function confirmarAlmacenamiento(uint256 loteId, bytes32 hashContratoDeposito, address almacenAutorizado)
        external;

    function marcarFallido(uint256 loteId, string calldata motivo) external;

    function liberarReservaTecnica(uint256 loteId) external;

    function reembolsarLoteFallido(uint256 loteId, address[] calldata compradores) external;

    function finalizarReembolso(uint256 loteId) external;

    function burnForRedemption(address from, uint256 loteId, uint256 cantidad) external;

    function pause() external;
    function unpause() external;

    // ---- View functions ----
    function lotes(uint256 loteId) external view returns (LoteMiel memory);
    function kgDisponibles(uint256 loteId) external view returns (uint256);
    function reservaTecnicaActual(uint256 loteId) external view returns (uint256);
}
