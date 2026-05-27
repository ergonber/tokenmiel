// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {
    AccessControlDefaultAdminRules
} from "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IRedemptionManager} from "./interfaces/IRedemptionManager.sol";
import {IAssetVault} from "./interfaces/IAssetVault.sol";
import {IIdentityRegistry} from "./interfaces/IIdentityRegistry.sol";

/// @title RedemptionManager
/// @author Daniel Hidalgo Carrasco
/// @notice Gestor del flujo de redencion fisica (almacenamiento → exportacion) con modelo de lock contable.
/// @dev Workflow:
///      1. `iniciarRedencion()`: comprador (tier >= 2) registra la intencion de redimir tokens.
///         Los tokens NO se transfieren — se registra un lock logico en `_tokensLockedFor`.
///         El comprador no puede iniciar mas redenciones que cubran mas tokens de los que tiene.
///      2. (off-chain) SRL gestiona DUE + courier + BL/AWB.
///      3. `confirmarExportacion()`: Oracle (Safe 2-de-3) quema los tokens del comprador
///         directamente (via AssetVault.burnForRedemption) y registra DUE/BL-AWB.
///      4. (alternativa) `cancelarRedencion()`: si falla aduana, libera el lock al comprador.
/// @custom:security
///   - Modelo de lock contable (Option B): los tokens permanecen en el wallet del comprador
///     todo el tiempo. El lock es contable — registrado en `_tokensLockedFor[loteId][buyer]`.
///   - La invariante critica es: sum(redenciones INICIADAS para buyer en loteId) <=
///     IERC1155(assetVault).balanceOf(buyer, loteId). Esto se enforcea en `iniciarRedencion`.
///   - El AssetVault NO se modifica — su invariante "NUNCA P2P" queda intacto.
///   - FIX M-08: usa AccessControlDefaultAdminRules con delay de 3 dias para transferencias de
///     DEFAULT_ADMIN_ROLE (mitiga lockout accidental o malicioso).
contract RedemptionManager is AccessControlDefaultAdminRules, ReentrancyGuard, Pausable, IRedemptionManager {
    // ---- Roles ----
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");
    bytes32 public constant COMPLIANCE_OFFICER_ROLE = keccak256("COMPLIANCE_OFFICER_ROLE");

    // ---- Immutables ----
    IAssetVault public immutable assetVault;
    IIdentityRegistry public immutable identityRegistry;

    // ---- Constants ----

    /// @notice Delay (en segundos) para transferencias de DEFAULT_ADMIN_ROLE (FIX M-08).
    /// @dev 3 dias permite cancelar transferencias accidentales o maliciosas antes de que se materialicen.
    uint48 public constant ADMIN_TRANSFER_DELAY = 3 days;

    /// @notice Longitud maxima del numero DUE en caracteres.
    /// @dev Los numeros DUE reales son < 64 chars. Limita storage inflation por parte del Oracle.
    uint256 public constant MAX_DUE_NUMERO_LENGTH = 64;

    // ---- Storage ----
    mapping(uint256 => Redencion) private _redenciones;
    uint256 private _nextRedencionId;

    /// @notice Acumulador de tokens lockeados logicamente por loteId y comprador.
    /// @dev Invariante: _tokensLockedFor[loteId][buyer] <= IERC1155(assetVault).balanceOf(buyer, loteId).
    ///      Se incrementa en iniciarRedencion y decrementa en confirmarExportacion / cancelarRedencion.
    mapping(uint256 loteId => mapping(address buyer => uint256)) private _tokensLockedFor;

    // ---- Errors ----
    error ZeroAddress();
    error CannotRedeem();
    error LoteNotFound(uint256 loteId);
    error LoteNotInAlmacenado();
    error CantidadCero();
    error BalanceInsuficiente();
    error InvalidHash();
    error RedencionNotIniciada();
    error RedencionAlreadyFinalized();
    error EmptyDUE();
    error DUENumeroTooLong();
    error EmptyReason();

    /// @dev FIX M-08: `admin` se asigna via AccessControlDefaultAdminRules con delay de 3 dias.
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
        // NOTA: `admin == address(0)` ya es chequeado por AccessControlDefaultAdminRules.

        _grantRole(ORACLE_ROLE, oracleSafe);
        _grantRole(COMPLIANCE_OFFICER_ROLE, complianceOfficer);
        _grantRole(COMPLIANCE_OFFICER_ROLE, complianceOfficerSuplente);

        assetVault = _assetVault;
        identityRegistry = _identityRegistry;
        _nextRedencionId = 1;
    }

    // ---- Mutating ----

    /// @inheritdoc IRedemptionManager
    /// @notice Inicia una redencion fisica registrando un lock contable sobre los tokens del comprador.
    /// @dev Modelo Option B — Lock Acumulator:
    ///      Los tokens NO se transfieren al contrato. El lock es un registro contable en
    ///      `_tokensLockedFor[loteId][msg.sender]`. La validacion garantiza que la suma de
    ///      tokens lockeados no excede el balance real del comprador en AssetVault.
    ///      Esto previene la doble-redencion sin modificar AssetVault ni romper el invariante P2P.
    /// @custom:security
    ///   - Checks (1) KYC canRedeem, (2) cantidad > 0, (3) datosEnvioHash != 0,
    ///     (4) lote existe (productorSRL != 0), (5) lote en estado valido,
    ///     (6) balance disponible >= cantidadTokens.
    ///   - CEI: todas las checks antes del state update, sin external calls mutantes despues del write.
    function iniciarRedencion(uint256 loteId, uint256 cantidadTokens, bytes32 datosEnvioHash)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 redencionId)
    {
        // ---- Checks ----
        if (!identityRegistry.canRedeem(msg.sender)) revert CannotRedeem();
        if (cantidadTokens == 0) revert CantidadCero();
        if (datosEnvioHash == bytes32(0)) revert InvalidHash();

        // RM-08: validar que el lote existe antes de evaluar su estado
        IAssetVault.LoteMiel memory lote = assetVault.lotes(loteId);
        if (lote.productorSRL == address(0)) revert LoteNotFound(loteId);

        if (lote.estado != IAssetVault.LoteEstado.ALMACENADO && lote.estado != IAssetVault.LoteEstado.REDENCION_PARCIAL)
        {
            revert LoteNotInAlmacenado();
        }

        // RM-01 + RM-02: validar balance disponible (balance real - tokens ya lockeados)
        uint256 currentBalance = IERC1155(address(assetVault)).balanceOf(msg.sender, loteId);
        uint256 alreadyLocked = _tokensLockedFor[loteId][msg.sender];
        if (alreadyLocked + cantidadTokens > currentBalance) revert BalanceInsuficiente();

        // ---- Effects ----
        // Incrementar el acumulador de tokens lockeados
        _tokensLockedFor[loteId][msg.sender] = alreadyLocked + cantidadTokens;

        redencionId = _nextRedencionId++;

        Redencion storage r = _redenciones[redencionId];
        r.comprador = msg.sender;
        r.loteId = loteId;
        r.cantidadTokens = cantidadTokens;
        r.datosEnvioHash = datosEnvioHash;
        r.estado = EstadoRedencion.INICIADA;
        r.createdAt = uint64(block.timestamp);

        // ---- Interactions (none — no external calls mutantes) ----
        emit RedencionIniciada(redencionId, msg.sender, loteId, cantidadTokens, datosEnvioHash);
    }

    /// @inheritdoc IRedemptionManager
    /// @notice Confirma la exportacion fisica quemando los tokens del comprador.
    /// @dev Solo ORACLE_ROLE (Safe 2-de-3). NO usa `whenNotPaused` por diseno (CONTRACT-SPECS §6.13.8):
    ///      una vez iniciada una redencion, el flujo de exportacion debe poder completarse o cancelarse
    ///      incluso si el contrato se pausa por incidente. Pausar bloquea solo `iniciarRedencion`.
    /// @custom:security
    ///   - NO usa whenNotPaused por diseno — ver CONTRACT-SPECS §6.13.8.
    ///   - CEI estricto: (1) Checks (estado, DUE, hash, balance), (2) Effects (estado, lock decrement,
    ///     campos), (3) Interactions (burn via AssetVault).
    ///   - El Oracle Safe es responsable de NO confirmar exportaciones durante un incidente
    ///     que afecte la cadena de custodia fisica.
    ///   - RM-04: pre-validacion de balance antes de state changes para fail fast.
    function confirmarExportacion(uint256 redencionId, string calldata dueNumero, bytes32 hashBLAWB)
        external
        onlyRole(ORACLE_ROLE)
        nonReentrant
    {
        // ---- Checks ----
        Redencion storage r = _redenciones[redencionId];
        if (r.comprador == address(0)) revert RedencionNotIniciada();
        if (r.estado != EstadoRedencion.INICIADA) revert RedencionAlreadyFinalized();

        bytes memory dueBytes = bytes(dueNumero);
        if (dueBytes.length == 0) revert EmptyDUE();
        if (dueBytes.length > MAX_DUE_NUMERO_LENGTH) revert DUENumeroTooLong();

        if (hashBLAWB == bytes32(0)) revert InvalidHash();

        // RM-04: pre-validacion de balance para fail fast (antes de cualquier state change)
        uint256 balance = IERC1155(address(assetVault)).balanceOf(r.comprador, r.loteId);
        if (balance < r.cantidadTokens) revert BalanceInsuficiente();

        // ---- Effects ----
        // Decrementar el lock acumulator ANTES del burn (CEI strict)
        _tokensLockedFor[r.loteId][r.comprador] -= r.cantidadTokens;

        r.estado = EstadoRedencion.COMPLETADA;
        r.dueNumero = dueNumero;
        r.hashBLAWB = hashBLAWB;
        r.completedAt = uint64(block.timestamp);

        // Capturar valores locales para el burn (evita re-reads de storage tras cambio de estado)
        address comprador = r.comprador;
        uint256 loteId = r.loteId;
        uint256 cantidadTokens = r.cantidadTokens;

        // ---- Interactions ----
        // Burn delegado al AssetVault — unica via permitida de burn
        assetVault.burnForRedemption(comprador, loteId, cantidadTokens);

        emit RedencionEnExportacion(redencionId, dueNumero);
        emit RedencionCompletada(redencionId, hashBLAWB);
    }

    /// @inheritdoc IRedemptionManager
    /// @notice Cancela una redencion en curso, liberando el lock contable del comprador.
    /// @dev Solo ORACLE_ROLE. NO usa `whenNotPaused` por diseno (CONTRACT-SPECS §6.13.8):
    ///      la cancelacion debe estar disponible incluso durante una pausa de emergencia
    ///      para resolver redenciones stuck.
    /// @custom:security
    ///   - NO usa whenNotPaused por diseno — ver CONTRACT-SPECS §6.13.8.
    ///   - RM-14: nonReentrant por defense-in-depth. Hoy no hay external calls, pero si en
    ///     futuras iteraciones se agrega AssetVault.returnRedemptionTokens, el modifier ya esta.
    ///   - El lock se libera antes del emit (CEI, aunque no hay external calls aqui).
    function cancelarRedencion(uint256 redencionId, bytes32 reason) external onlyRole(ORACLE_ROLE) nonReentrant {
        // ---- Checks ----
        Redencion storage r = _redenciones[redencionId];
        if (r.comprador == address(0)) revert RedencionNotIniciada();
        if (r.estado != EstadoRedencion.INICIADA) revert RedencionAlreadyFinalized();
        if (reason == bytes32(0)) revert EmptyReason();

        // ---- Effects ----
        // Liberar el lock contable (RM-01: el acumulador decrementa en cancelacion)
        _tokensLockedFor[r.loteId][r.comprador] -= r.cantidadTokens;

        r.estado = EstadoRedencion.CANCELADA;
        r.cancelReason = reason;
        r.completedAt = uint64(block.timestamp);

        // ---- Interactions (none) ----
        emit RedencionCancelada(redencionId, reason);
    }

    /// @notice Pausa de emergencia. Bloquea unicamente `iniciarRedencion`.
    /// @dev Solo COMPLIANCE_OFFICER_ROLE.
    ///      confirmarExportacion y cancelarRedencion NO se bloquean (ver CONTRACT-SPECS §6.13.8).
    function pause() external onlyRole(COMPLIANCE_OFFICER_ROLE) {
        _pause();
    }

    /// @notice Despausa el contrato.
    /// @dev Solo COMPLIANCE_OFFICER_ROLE.
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

    /// @inheritdoc IRedemptionManager
    /// @notice Retorna el balance disponible del comprador para nuevas redenciones.
    /// @dev balance disponible = balanceOf(buyer, loteId) - _tokensLockedFor[loteId][buyer].
    ///      Este valor representa cuantos tokens puede el buyer lockear en nuevas redenciones.
    /// @param buyer Wallet del comprador.
    /// @param loteId ID del lote.
    /// @return Tokens disponibles para iniciar nuevas redenciones.
    function availableBalance(address buyer, uint256 loteId) external view returns (uint256) {
        uint256 balance = IERC1155(address(assetVault)).balanceOf(buyer, loteId);
        uint256 locked = _tokensLockedFor[loteId][buyer];
        // balance > locked es invariante garantizado por iniciarRedencion,
        // pero la resta tiene guardia explícita para protección ante paths inesperados.
        return balance > locked ? balance - locked : 0;
    }

    /// @inheritdoc IRedemptionManager
    /// @notice Retorna la cantidad de tokens lockeados de un comprador para un lote.
    /// @dev El valor es > 0 solo mientras haya redenciones en estado INICIADA.
    ///      Decrementa cuando la redencion se confirma o cancela.
    /// @param buyer Wallet del comprador.
    /// @param loteId ID del lote.
    /// @return Tokens actualmente lockeados en redenciones activas.
    function tokensLockedFor(address buyer, uint256 loteId) external view returns (uint256) {
        return _tokensLockedFor[loteId][buyer];
    }
}
