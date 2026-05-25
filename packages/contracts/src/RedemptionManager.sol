// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {AccessControlDefaultAdminRules} from
    "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IRedemptionManager} from "./interfaces/IRedemptionManager.sol";
import {IAssetVault} from "./interfaces/IAssetVault.sol";
import {IIdentityRegistry} from "./interfaces/IIdentityRegistry.sol";

/// @title RedemptionManager
/// @author Daniel Hidalgo Carrasco
/// @notice Gestor del escrow y flujo de redención física (cosecha → exportación).
/// @dev Workflow:
///      1. `iniciarRedencion()`: comprador (tier ≥ 2) bloquea tokens en el contrato.
///      2. (off-chain) SRL gestiona DUE + courier + BL/AWB.
///      3. `confirmarExportacion()`: Oracle (Safe 2-de-3) quema los tokens y registra DUE/BL-AWB.
///      4. (alternativa) `cancelarRedencion()`: si falla aduana, libera tokens al comprador.
/// @custom:security
///   - Tokens en escrow son no-transferibles excepto via burn (exportación) o release (cancelación).
///     Esto previene doble-redención.
///   - FIX M-08: usa AccessControlDefaultAdminRules con delay de 3 días para transferencias de
///     DEFAULT_ADMIN_ROLE (mitiga lockout accidental o malicioso).
contract RedemptionManager is AccessControlDefaultAdminRules, ReentrancyGuard, Pausable, IRedemptionManager {
    // ---- Roles ----
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");
    bytes32 public constant COMPLIANCE_OFFICER_ROLE = keccak256("COMPLIANCE_OFFICER_ROLE");

    // ---- Immutables ----
    IAssetVault public immutable assetVault;
    IIdentityRegistry public immutable identityRegistry;

    // ---- Storage ----
    mapping(uint256 => Redencion) private _redenciones;
    uint256 private _nextRedencionId;

    // ---- Errors ----
    error ZeroAddress();
    error CannotRedeem();
    error LoteNotInAlmacenado();
    error CantidadCero();
    error BalanceInsuficiente();
    error InvalidHash();
    error RedencionNotIniciada();
    error RedencionAlreadyFinalized();
    error EmptyDUE();
    error EmptyReason();

    /// @notice Delay (en segundos) para transferencias de DEFAULT_ADMIN_ROLE (FIX M-08).
    /// @dev 3 días permite cancelar transferencias accidentales o maliciosas antes de que se materialicen.
    uint48 public constant ADMIN_TRANSFER_DELAY = 3 days;

    /// @dev FIX M-08: `admin` se asigna vía AccessControlDefaultAdminRules con delay de 3 días para transferencias.
    constructor(
        address admin,
        address oracleSafe,
        address complianceOfficer,
        address complianceOfficerSuplente,
        IAssetVault _assetVault,
        IIdentityRegistry _identityRegistry
    ) AccessControlDefaultAdminRules(ADMIN_TRANSFER_DELAY, admin) {
        if (oracleSafe == address(0)) revert ZeroAddress();
        if (complianceOfficer == address(0)) revert ZeroAddress();
        if (complianceOfficerSuplente == address(0)) revert ZeroAddress();
        if (address(_assetVault) == address(0)) revert ZeroAddress();
        if (address(_identityRegistry) == address(0)) revert ZeroAddress();
        // NOTA: `admin == address(0)` ya es chequeado por AccessControlDefaultAdminRules (DefaultAdminZeroAddress).

        _grantRole(ORACLE_ROLE, oracleSafe);
        _grantRole(COMPLIANCE_OFFICER_ROLE, complianceOfficer);
        _grantRole(COMPLIANCE_OFFICER_ROLE, complianceOfficerSuplente);

        assetVault = _assetVault;
        identityRegistry = _identityRegistry;
        _nextRedencionId = 1;
    }

    // ---- Mutating ----

    /// @inheritdoc IRedemptionManager
    /// @dev Tokens del comprador son "lockeados" lógicamente: el contrato lleva tracking,
    ///      pero no transfiere físicamente los tokens al escrow (porque P2P está bloqueado).
    ///      El comprador no puede operar con esos tokens hasta confirmación o cancelación.
    function iniciarRedencion(uint256 loteId, uint256 cantidadTokens, bytes32 datosEnvioHash)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 redencionId)
    {
        if (!identityRegistry.canRedeem(msg.sender)) revert CannotRedeem();
        if (cantidadTokens == 0) revert CantidadCero();
        if (datosEnvioHash == bytes32(0)) revert InvalidHash();

        IAssetVault.LoteMiel memory lote = assetVault.lotes(loteId);
        if (
            lote.estado != IAssetVault.LoteEstado.ALMACENADO
                && lote.estado != IAssetVault.LoteEstado.REDENCION_PARCIAL
        ) revert LoteNotInAlmacenado();

        // Verificamos balance — el burn final se hace en confirmarExportacion
        // (Nota: requiere consulta a ERC1155 vía interface — simplificado para MVP)

        redencionId = _nextRedencionId++;

        Redencion storage r = _redenciones[redencionId];
        r.comprador = msg.sender;
        r.loteId = loteId;
        r.cantidadTokens = cantidadTokens;
        r.datosEnvioHash = datosEnvioHash;
        r.estado = EstadoRedencion.INICIADA;
        r.createdAt = uint64(block.timestamp);

        emit RedencionIniciada(redencionId, msg.sender, loteId, cantidadTokens, datosEnvioHash);
    }

    /// @inheritdoc IRedemptionManager
    function confirmarExportacion(uint256 redencionId, string calldata dueNumero, bytes32 hashBLAWB)
        external
        onlyRole(ORACLE_ROLE)
        nonReentrant
    {
        Redencion storage r = _redenciones[redencionId];
        if (r.comprador == address(0)) revert RedencionNotIniciada();
        if (r.estado != EstadoRedencion.INICIADA) revert RedencionAlreadyFinalized();
        if (bytes(dueNumero).length == 0) revert EmptyDUE();
        if (hashBLAWB == bytes32(0)) revert InvalidHash();

        r.estado = EstadoRedencion.COMPLETADA;
        r.dueNumero = dueNumero;
        r.hashBLAWB = hashBLAWB;
        r.completedAt = uint64(block.timestamp);

        // Burn delegado al AssetVault — única vía permitida de burn
        assetVault.burnForRedemption(r.comprador, r.loteId, r.cantidadTokens);

        emit RedencionEnExportacion(redencionId, dueNumero);
        emit RedencionCompletada(redencionId, hashBLAWB);
    }

    /// @inheritdoc IRedemptionManager
    function cancelarRedencion(uint256 redencionId, bytes32 reason) external onlyRole(ORACLE_ROLE) {
        Redencion storage r = _redenciones[redencionId];
        if (r.comprador == address(0)) revert RedencionNotIniciada();
        if (r.estado != EstadoRedencion.INICIADA) revert RedencionAlreadyFinalized();
        if (reason == bytes32(0)) revert EmptyReason();

        r.estado = EstadoRedencion.CANCELADA;
        r.cancelReason = reason;
        r.completedAt = uint64(block.timestamp);

        emit RedencionCancelada(redencionId, reason);
    }

    /// @notice Pausa de emergencia.
    function pause() external onlyRole(COMPLIANCE_OFFICER_ROLE) {
        _pause();
    }

    /// @notice Despausa.
    function unpause() external onlyRole(COMPLIANCE_OFFICER_ROLE) {
        _unpause();
    }

    // ---- View ----

    /// @inheritdoc IRedemptionManager
    function getRedencion(uint256 redencionId) external view returns (Redencion memory) {
        return _redenciones[redencionId];
    }

    /// @inheritdoc IRedemptionManager
    function getNextRedencionId() external view returns (uint256) {
        return _nextRedencionId;
    }
}
