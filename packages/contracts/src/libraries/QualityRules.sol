// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {ComplianceConstants} from "./ComplianceConstants.sol";

/// @title QualityRules
/// @notice Reglas computacionales para conversiones, reserva técnica y (en fase 2) calidad monofloral.
/// @dev Pure functions, sin estado.
///      MVP: solo se usa `calcularReservaTecnica`, `tokensToKg`, `gramosToTokens`.
///      Fase 2 (cuando LabRegistry se reactive): `isMonofloralCertified`.
library QualityRules {
    /// @notice Computa si una attestation califica como monofloral certificada.
    /// @dev @custom:phase2 Esta función queda como código preparado para fase 2.
    ///      En MVP NO se usa (LabRegistry diferido). Ver `phase2/README.md` y ADR-010.
    /// @param pollenPercentage Porcentaje de polen dominante (0-100).
    /// @param nmrPassed Resultado del test NMR (true = sin adulteración).
    /// @param c4Passed Resultado del test C4 sugar (true = sin adulteración con azúcares C4).
    /// @param residuesPassed Resultado del test de residuos (true = dentro de límites EU MRL).
    /// @return monofloralCertified True si cumple TODOS los criterios.
    function isMonofloralCertified(
        uint8 pollenPercentage,
        bool nmrPassed,
        bool c4Passed,
        bool residuesPassed
    ) internal pure returns (bool monofloralCertified) {
        return pollenPercentage >= ComplianceConstants.MIN_POLLEN_PERCENTAGE_MONOFLORAL && nmrPassed && c4Passed
            && residuesPassed;
    }

    /// @notice Convierte una cantidad de tokens a kg (factor 0.5).
    /// @param cantidadTokens Cantidad de tokens (cada token = 0.5 kg).
    /// @return kg Equivalente en kilogramos (división entera, puede perder precisión < 0.5 kg).
    function tokensToKg(uint256 cantidadTokens) internal pure returns (uint256 kg) {
        return (cantidadTokens * ComplianceConstants.GRAMOS_POR_TOKEN) / 1000;
    }

    /// @notice Convierte gramos a cantidad de tokens.
    /// @param gramos Cantidad en gramos.
    /// @return cantidadTokens Tokens equivalentes (gramos / 500).
    function gramosToTokens(uint256 gramos) internal pure returns (uint256 cantidadTokens) {
        return gramos / ComplianceConstants.GRAMOS_POR_TOKEN;
    }

    /// @notice Calcula reserva técnica retenida sobre un monto USDC.
    /// @param montoUSDC Monto total pagado en USDC (6 decimales).
    /// @param reservaBps Basis points de reserva (1500-2000).
    /// @return reservaRetenida USDC retenido como reserva técnica.
    /// @return montoNeto USDC transferido al productor.
    function calcularReservaTecnica(uint256 montoUSDC, uint16 reservaBps)
        internal
        pure
        returns (uint256 reservaRetenida, uint256 montoNeto)
    {
        reservaRetenida = (montoUSDC * reservaBps) / ComplianceConstants.BPS_DENOMINATOR;
        montoNeto = montoUSDC - reservaRetenida;
    }
}
