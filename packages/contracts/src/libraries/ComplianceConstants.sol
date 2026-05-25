// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

/// @title ComplianceConstants
/// @notice Constantes legales y operacionales del sistema de tokenización RWA.
/// @dev Estas constantes son inmutables y se referencian desde los 4 contratos del sistema.
///      Cualquier cambio requiere ADR y migración a v2 (ver ADR-003).
/// @custom:security Modificar estas constantes cambia las garantías legales del producto.
library ComplianceConstants {
    /// @notice Equivalencia de un token a gramos (1 token = 0.5 kg = 500 g).
    /// @dev Trabajamos internamente en gramos para evitar rounding por división entera.
    uint256 internal constant GRAMOS_POR_TOKEN = 500;

    /// @notice Reserva técnica mínima en basis points (15%).
    uint16 internal constant RESERVA_TECNICA_BPS_MIN = 1500;

    /// @notice Reserva técnica máxima en basis points (20%).
    uint16 internal constant RESERVA_TECNICA_BPS_MAX = 2000;

    /// @notice Denominador para cálculos en basis points (10000 = 100%).
    uint16 internal constant BPS_DENOMINATOR = 10_000;

    /// @notice Tier mínimo de KYC requerido para comprar tokens.
    uint8 internal constant MIN_KYC_TIER_PARA_COMPRAR = 1;

    /// @notice Tier mínimo de KYC requerido para iniciar redención física.
    uint8 internal constant MIN_KYC_TIER_PARA_REDIMIR = 2;

    /// @notice Tier máximo válido de KYC.
    uint8 internal constant MAX_KYC_TIER = 3;

    /// @notice Porcentaje mínimo de polen dominante para clasificar como "monofloral" (estándar UE).
    /// @dev Conforme a Directiva 2014/63/UE.
    /// @custom:phase2 Reservada para fase 2 cuando se reactive LabRegistry/QualityAttestation.
    ///                Ver `phase2/README.md` y ADR-010.
    uint8 internal constant MIN_POLLEN_PERCENTAGE_MONOFLORAL = 45;

    /// @notice Mínimo de labs independientes requeridos para una QualityAttestation.
    /// @custom:phase2 Reservada para fase 2 cuando se reactive LabRegistry/QualityAttestation.
    uint8 internal constant MIN_LABS_PARA_ATTESTATION = 2;

    /// @notice USDC decimales (6, consistente con Circle USDC).
    uint8 internal constant USDC_DECIMALS = 6;
}
