// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {ERC1155Supply} from "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import {ERC1155Pausable} from "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Pausable.sol";
import {
    AccessControlDefaultAdminRules
} from "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IAssetVault} from "./interfaces/IAssetVault.sol";
import {IIdentityRegistry} from "./interfaces/IIdentityRegistry.sol";
import {ComplianceConstants} from "./libraries/ComplianceConstants.sol";
import {QualityRules} from "./libraries/QualityRules.sol";
import {DocumentHashes} from "./libraries/DocumentHashes.sol";

/// @title AssetVault
/// @author Daniel Hidalgo Carrasco
/// @notice Contrato principal de tokenización RWA. ERC-1155 multi-token con ciclo de vida
///         simplificado de lotes (PREVENTA → COSECHADO → ALMACENADO →
///         REDENCION_PARCIAL → AGOTADO, o FALLIDO desde PREVENTA/COSECHADO).
/// @dev Modelo de escrow total: USDC del comprador queda en el contrato hasta confirmarCosecha,
///      momento en que se transfiere monto neto al productor. La reserva técnica (15-20% BPS)
///      se libera al productor post-COSECHADO via liberarReservaTecnica.
/// @custom:security
///   - Sin proxy (inmutable post-deploy). Bug crítico → pause + migración v2.
///   - Custom errors gas-efficient.
///   - Override `_update()` previene P2P transfers (Solo primario).
///   - Burn solo desde RedemptionManager.
///   - Escrow total: comprar() retiene USDC; confirmarCosecha() libera monto neto.
///   - MVP simplificado: QualityAttestation (LabRegistry) reservado para fase 2.
///   - FIX M-08: usa AccessControlDefaultAdminRules con delay de 3 días para transferencias de
///     DEFAULT_ADMIN_ROLE (mitiga lockout accidental o malicioso).
contract AssetVault is
    ERC1155,
    ERC1155Supply,
    ERC1155Pausable,
    AccessControlDefaultAdminRules,
    ReentrancyGuard,
    IAssetVault
{
    using SafeERC20 for IERC20;
    using QualityRules for *;

    // ---- Roles ----
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant BACKEND_SIGNER_ROLE = keccak256("BACKEND_SIGNER_ROLE");
    bytes32 public constant COMPLIANCE_OFFICER_ROLE = keccak256("COMPLIANCE_OFFICER_ROLE");
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");
    bytes32 public constant TREASURY_SRL_ROLE = keccak256("TREASURY_SRL_ROLE");

    // ---- Immutables ----
    IERC20 public immutable usdc;
    IIdentityRegistry public immutable identityRegistry;
    address public redemptionManager;
    // NOTA: LabRegistry removido del MVP. QualityAttestation se reactiva en fase 2.

    // ---- Storage ----
    mapping(uint256 => LoteMiel) private _lotes;
    mapping(uint256 => bool) private _reembolsado;

    // ---- Errors ----
    error ZeroAddress();
    error LoteAlreadyExists();
    error LoteNotExists();
    error InvalidKgEsperados();
    error InvalidPrecio();
    error InvalidHash();
    error ReservaBpsOutOfRange();
    error NotKYCVerified();
    error LoteNotInPreventa();
    error LoteNotInCosechado();
    error LoteNotInAlmacenado();
    error LoteNotInFallido();
    error LoteAlreadyFinalized();
    error CannotFailLoteInThisState();
    error KgSolicitadosExcedenSupply();
    error MontoUSDCInsuficiente();
    error CantidadTokensCero();
    error TransferP2PNoPermitido();
    error OnlyRedemptionCanBurn();
    error ReservaAlreadyReleased();
    error MontoNetoAlreadyReleased();
    error ReembolsoYaEjecutado();
    error EmptyMotivo();
    error EmptyBuyers();
    error RedemptionManagerNotSet();
    error RedemptionManagerAlreadySet();
    error CannotRefundBlockedAddress();
    error BatchTooLarge();
    /// @notice FIX H-01: buyer con KYC revocado (tier == 0) no recibe reembolso on-chain.
    /// @dev Defensa contra revocación post-compra (EDD failure, sanción no formal, etc.) que
    ///      `isSanctioned`/`isFrozen` no cubren. La recuperación off-chain queda en compliance.
    error CannotRefundRevokedAddress();

    /// @notice Cantidad máxima de buyers procesables en una sola llamada a `reembolsarLoteFallido`.
    /// @dev Prevenir DoS por out-of-gas con arrays grandes.
    ///      Para lotes con más buyers, llamar `reembolsarLoteFallido` múltiples veces con sub-arrays.
    uint256 public constant MAX_REFUND_BATCH = 100;

    /// @notice Delay (en segundos) para transferencias de DEFAULT_ADMIN_ROLE (FIX M-08).
    /// @dev 3 días permite cancelar transferencias accidentales o maliciosas antes de que se materialicen.
    uint48 public constant ADMIN_TRANSFER_DELAY = 3 days;

    /// @notice Parámetros de inicialización agrupados (patrón Uniswap V4 / Aave V3).
    /// @dev Evita stack-too-deep y reduce bytecode vs múltiples parámetros sueltos.
    ///      Permite tests pasar la config como struct sin verbose calldata.
    ///      NOTA: campo labRegistry removido en fase MVP (QualityAttestation reservado para fase 2).
    struct InitParams {
        address admin;
        address adminOperator;
        address backendSigner;
        address complianceOfficer;
        address complianceOfficerSuplente;
        address oracleSafe;
        address treasurySRL;
        IERC20 usdc;
        IIdentityRegistry identityRegistry;
        string uri;
    }

    /// @notice Despliegue del contrato.
    /// @dev SECURITY: el `admin` debería ser un Safe multi-sig (NO una EOA).
    ///      El deployment script DEBE transferir DEFAULT_ADMIN_ROLE al Safe y revocar
    ///      el rol del deployer EOA en el mismo tx batch.
    ///      FIX M-08: `p.admin` se asigna vía AccessControlDefaultAdminRules con delay de 3 días.
    ///      `p.admin == address(0)` ya es chequeado por AccessControlDefaultAdminRules (DefaultAdminZeroAddress).
    /// @param p Parámetros de inicialización (struct InitParams).
    constructor(InitParams memory p) ERC1155(p.uri) AccessControlDefaultAdminRules(ADMIN_TRANSFER_DELAY, p.admin) {
        _requireNonZero(p.adminOperator);
        _requireNonZero(p.backendSigner);
        _requireNonZero(p.complianceOfficer);
        _requireNonZero(p.complianceOfficerSuplente);
        _requireNonZero(p.oracleSafe);
        _requireNonZero(p.treasurySRL);
        _requireNonZero(address(p.usdc));
        _requireNonZero(address(p.identityRegistry));

        _grantRole(ADMIN_ROLE, p.adminOperator);
        _grantRole(BACKEND_SIGNER_ROLE, p.backendSigner);
        _grantRole(COMPLIANCE_OFFICER_ROLE, p.complianceOfficer);
        _grantRole(COMPLIANCE_OFFICER_ROLE, p.complianceOfficerSuplente);
        _grantRole(ORACLE_ROLE, p.oracleSafe);
        _grantRole(TREASURY_SRL_ROLE, p.treasurySRL);

        usdc = p.usdc;
        identityRegistry = p.identityRegistry;
    }

    /// @dev Helper privada para validar que una dirección no sea cero.
    /// @custom:security Reduce repetición de checks de zero address en el constructor.
    function _requireNonZero(address a) private pure {
        if (a == address(0)) revert ZeroAddress();
    }

    /// @notice Setea el RedemptionManager (one-time, post-deploy por circular dependency).
    /// @dev Necesario porque RedemptionManager depende de AssetVault y viceversa.
    function setRedemptionManager(address _redemptionManager) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_redemptionManager == address(0)) revert ZeroAddress();
        if (redemptionManager != address(0)) revert RedemptionManagerAlreadySet();
        redemptionManager = _redemptionManager;
    }

    // ---- Mutating: ADMIN_ROLE ----

    /// @inheritdoc IAssetVault
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
    ) external onlyRole(ADMIN_ROLE) {
        if (_lotes[loteId].productorSRL != address(0)) revert LoteAlreadyExists();
        if (kgEsperados == 0) revert InvalidKgEsperados();
        if (precioPorTokenUSDC == 0) revert InvalidPrecio();
        if (productorSRL == address(0)) revert ZeroAddress();
        if (!DocumentHashes.isValid(hashFSA)) revert InvalidHash();
        if (
            reservaBps < ComplianceConstants.RESERVA_TECNICA_BPS_MIN
                || reservaBps > ComplianceConstants.RESERVA_TECNICA_BPS_MAX
        ) revert ReservaBpsOutOfRange();

        LoteMiel storage lote = _lotes[loteId];
        lote.kgEsperados = kgEsperados;
        lote.precioPorTokenUSDC = precioPorTokenUSDC;
        lote.fechaCosechaEstimada = fechaCosechaEstimada;
        lote.estado = LoteEstado.PREVENTA;
        lote.fechaCreacion = uint64(block.timestamp);
        lote.origenGeografico = origenGeografico;
        lote.reservaBps = reservaBps;
        lote.hashFSA = hashFSA;
        lote.productorSRL = productorSRL;
        lote.variedadMonofloral = variedadMonofloral;

        emit LoteCreado(loteId, kgEsperados, precioPorTokenUSDC, productorSRL, hashFSA, reservaBps);
    }

    // ---- Mutating: BACKEND_SIGNER_ROLE ----

    /// @inheritdoc IAssetVault
    /// @dev USDC ya debe estar transferido al contrato antes de llamar (el backend confirma pago,
    ///      luego transfiere USDC, luego llama esta función).
    function comprar(
        uint256 loteId,
        uint256 cantidadTokens,
        address comprador,
        uint256 montoUSDCPagado,
        bytes32 paymentRefHash
    ) external onlyRole(BACKEND_SIGNER_ROLE) nonReentrant whenNotPaused {
        LoteMiel storage lote = _lotes[loteId];
        if (lote.productorSRL == address(0)) revert LoteNotExists();
        if (lote.estado != LoteEstado.PREVENTA) revert LoteNotInPreventa();
        if (cantidadTokens == 0) revert CantidadTokensCero();
        if (paymentRefHash == bytes32(0)) revert InvalidHash();

        // SECURITY: KYC validation runs in _update() override (line ~580).
        // No duplicar el check acá — ahorra ~5K gas/compra y mantiene single source of truth.

        // FIX H-02: validar capacidad en GRAMOS (no kg) para evitar overmint por rounding.
        // Antes: `totalSupply * 500 / 1000` truncaba para impares; `comprar(1)` repetido pasaba
        // el check aunque acumulaba más kg que `kgEsperados`. Ahora comparamos exacto a nivel gramos.
        uint256 gramosYaVendidos = totalSupply(loteId) * ComplianceConstants.GRAMOS_POR_TOKEN;
        uint256 gramosSolicitados = cantidadTokens * ComplianceConstants.GRAMOS_POR_TOKEN;
        uint256 gramosEsperados = lote.kgEsperados * 1000;
        if (gramosYaVendidos + gramosSolicitados > gramosEsperados) revert KgSolicitadosExcedenSupply();

        // Validar monto USDC
        uint256 montoEsperado = cantidadTokens * lote.precioPorTokenUSDC;
        if (montoUSDCPagado < montoEsperado) revert MontoUSDCInsuficiente();

        // Calcular reserva técnica + monto neto (escrow total — el productor NO cobra acá)
        (uint256 reservaRetenida, uint256 montoNeto) =
            QualityRules.calcularReservaTecnica(montoUSDCPagado, lote.reservaBps);

        // FIX H-01 (Opción A — Escrow total): el USDC del comprador queda íntegramente en
        // el contrato. NO se transfiere al productor en comprar(). El productor recibirá:
        //   - montoNeto en confirmarCosecha() (tras validar producción real)
        //   - reservaTecnicaUSDC en liberarReservaTecnica() (post-cosecha)
        // Esto garantiza reembolso 100% on-chain si el lote FALLA pre-cosecha.
        lote.reservaTecnicaUSDC += reservaRetenida;
        lote.montoNetoPendiente += montoNeto;

        // Mint tokens al comprador (KYC validado en _update override)
        _mint(comprador, loteId, cantidadTokens, "");

        emit LoteComprado(loteId, comprador, cantidadTokens, montoUSDCPagado, reservaRetenida, paymentRefHash);
    }

    // ---- Mutating: ORACLE_ROLE ----

    /// @inheritdoc IAssetVault
    /// @dev FIX H-01: tras validar producción real, libera el monto neto retenido en escrow
    ///      al productor SRL. La reserva técnica permanece en el contrato hasta que el
    ///      productor llame `liberarReservaTecnica` (permitido desde COSECHADO).
    function confirmarCosecha(
        uint256 loteId,
        uint256 kgRealCosechado,
        bytes32 hashSenasag,
        bytes32 hashAnalisisLab,
        bytes32 hashActaCosecha,
        bytes32 hashFotosApiario,
        bytes32 hashCertificadoOrigen,
        TipoCertificadoOrigen tipoCertificado
    ) external onlyRole(ORACLE_ROLE) nonReentrant {
        LoteMiel storage lote = _lotes[loteId];
        if (lote.productorSRL == address(0)) revert LoteNotExists();
        if (lote.estado != LoteEstado.PREVENTA) revert LoteNotInPreventa();
        if (kgRealCosechado == 0) revert InvalidKgEsperados();
        if (!DocumentHashes.isValid(hashSenasag)) revert InvalidHash();
        if (!DocumentHashes.isValid(hashAnalisisLab)) revert InvalidHash();
        if (!DocumentHashes.isValid(hashActaCosecha)) revert InvalidHash();
        if (!DocumentHashes.isValid(hashFotosApiario)) revert InvalidHash();
        if (!DocumentHashes.isValid(hashCertificadoOrigen)) revert InvalidHash();

        lote.kgCosechadosReal = kgRealCosechado;
        lote.hashSenasag = hashSenasag;
        lote.hashAnalisisLab = hashAnalisisLab;
        lote.hashActaCosecha = hashActaCosecha;
        lote.hashFotosApiario = hashFotosApiario;
        lote.hashCertificadoOrigen = hashCertificadoOrigen;
        lote.tipoCertificadoOrigen = tipoCertificado;
        lote.estado = LoteEstado.COSECHADO;

        // FIX H-01 (Escrow total): liberar monto neto retenido al productor.
        // La reserva técnica queda pendiente hasta `liberarReservaTecnica` (manual).
        uint256 montoLiberar = lote.montoNetoPendiente;
        if (montoLiberar > 0) {
            lote.montoNetoPendiente = 0;
            usdc.safeTransfer(lote.productorSRL, montoLiberar);
        }

        emit CosechaConfirmada(
            loteId, kgRealCosechado, hashSenasag, hashAnalisisLab, hashActaCosecha, hashCertificadoOrigen
        );
        if (montoLiberar > 0) {
            emit MontoNetoLiberado(loteId, montoLiberar, lote.productorSRL);
        }
    }

    /// @inheritdoc IAssetVault
    /// @dev Estado COSECHADO → ALMACENADO. Desde MVP no hay QUALITY_ATTESTED intermedio
    ///      (QualityAttestation queda reservado para fase 2 via LabRegistry standalone).
    function confirmarAlmacenamiento(uint256 loteId, bytes32 hashContratoDeposito, address almacenAutorizado)
        external
        onlyRole(ORACLE_ROLE)
    {
        LoteMiel storage lote = _lotes[loteId];
        if (lote.productorSRL == address(0)) revert LoteNotExists();
        if (lote.estado != LoteEstado.COSECHADO) revert LoteNotInCosechado();
        if (!DocumentHashes.isValid(hashContratoDeposito)) revert InvalidHash();
        if (almacenAutorizado == address(0)) revert ZeroAddress();

        lote.hashContratoDeposito = hashContratoDeposito;
        lote.estado = LoteEstado.ALMACENADO;

        emit AlmacenamientoConfirmado(loteId, hashContratoDeposito, almacenAutorizado);
    }

    /// @inheritdoc IAssetVault
    /// @dev FIX M-05: `marcarFallido` solo permitido desde PREVENTA o COSECHADO.
    ///      Post-ALMACENADO el producto físico ya existe en almacén autorizado, los riesgos
    ///      son logísticos (robo, incendio) y requieren governance superior (futuro:
    ///      `marcarFallidoPostAlmacenamiento` con SUPER_ORACLE_ROLE).
    function marcarFallido(uint256 loteId, string calldata motivo) external onlyRole(ORACLE_ROLE) {
        LoteMiel storage lote = _lotes[loteId];
        if (lote.productorSRL == address(0)) revert LoteNotExists();
        if (lote.estado != LoteEstado.PREVENTA && lote.estado != LoteEstado.COSECHADO) {
            revert CannotFailLoteInThisState();
        }
        if (bytes(motivo).length == 0) revert EmptyMotivo();

        lote.estado = LoteEstado.FALLIDO;
        lote.motivoFallo = motivo;

        emit LoteFallido(loteId, motivo);
    }

    /// @inheritdoc IAssetVault
    /// @dev FIX H-01 RESUELTO (Escrow total): reembolsa 100% del pago original. Pool disponible =
    ///      `montoNetoPendiente` (escrow) + `reservaTecnicaUSDC - reservaTecnicaLiberada`.
    ///      Como `marcarFallido` solo permite desde PREVENTA/COSECHADO, y `liberarReservaTecnica`
    ///      solo permite desde COSECHADO+, en práctica si el lote FALLA en PREVENTA todo el monto
    ///      sigue en escrow (100% reembolsable). Si FALLA en COSECHADO post-liberación de reserva,
    ///      el reembolso de la reserva es 0 — el `montoNetoPendiente` se libera al productor en
    ///      `confirmarCosecha`, así que también es 0 si ya cosechó. **Caso a documentar
    ///      operacionalmente:** FALLIDO post-COSECHADO requiere recuperación off-chain del productor.
    ///
    ///      FIX Opt-B2: cap de batch a MAX_REFUND_BATCH (paginación). Marca `_reembolsado` solo
    ///      cuando se llama `finalizarReembolso(loteId)` después de procesar todos los batches.
    ///      FIX M-06: bloquea reembolso a sancionados/frozen (riesgo OFAC).
    ///      FIX H-01: bloquea reembolso a buyers con KYC revocado (tier == 0). Cubre el caso de
    ///      revocación administrativa post-compra (EDD failure, etc.) que `isSanctioned`/`isFrozen`
    ///      no cubren. La recuperación off-chain queda como decisión de compliance.
    function reembolsarLoteFallido(uint256 loteId, address[] calldata compradores)
        external
        onlyRole(ORACLE_ROLE)
        nonReentrant
    {
        LoteMiel storage lote = _lotes[loteId];
        if (lote.productorSRL == address(0)) revert LoteNotExists();
        if (lote.estado != LoteEstado.FALLIDO) revert LoteNotInFallido();
        if (_reembolsado[loteId]) revert ReembolsoYaEjecutado();
        if (compradores.length == 0) revert EmptyBuyers();
        if (compradores.length > MAX_REFUND_BATCH) revert BatchTooLarge();

        uint256 totalSupplyLote = totalSupply(loteId);
        if (totalSupplyLote == 0) {
            _reembolsado[loteId] = true;
            return;
        }

        // FIX H-01: pool total = monto neto en escrow + reserva técnica no liberada.
        // Si `marcarFallido` se llamó pre-cosecha (PREVENTA), montoNetoPendiente > 0 (monto neto)
        // y reservaTecnicaUSDC > 0 (reserva), suma = 100% del pago de compradores.
        uint256 totalDisponible = lote.montoNetoPendiente + (lote.reservaTecnicaUSDC - lote.reservaTecnicaLiberada);

        for (uint256 i = 0; i < compradores.length; i++) {
            address buyer = compradores[i];
            uint256 balance = balanceOf(buyer, loteId);
            if (balance == 0) continue;

            if (identityRegistry.isSanctioned(buyer)) revert CannotRefundBlockedAddress();
            if (identityRegistry.isFrozen(buyer)) revert CannotRefundBlockedAddress();
            // FIX H-01: bloquea reembolso si el KYC del buyer fue revocado post-compra
            // (ej.: EDD failure detectado entre la compra y el fallo del lote).
            if (identityRegistry.getTier(buyer) == 0) revert CannotRefundRevokedAddress();

            uint256 reembolsoUSDC = (totalDisponible * balance) / totalSupplyLote;

            _burn(buyer, loteId, balance);

            if (reembolsoUSDC > 0) {
                usdc.safeTransfer(buyer, reembolsoUSDC);
            }

            emit ReembolsoEjecutado(loteId, buyer, balance, reembolsoUSDC);
        }
    }

    /// @notice Marca un lote FALLIDO como reembolso completado. Llamar tras procesar todos los batches.
    /// @dev Sin esto, `reembolsarLoteFallido` puede llamarse múltiples veces (paginación).
    function finalizarReembolso(uint256 loteId) external onlyRole(ORACLE_ROLE) {
        LoteMiel storage lote = _lotes[loteId];
        if (lote.productorSRL == address(0)) revert LoteNotExists();
        if (lote.estado != LoteEstado.FALLIDO) revert LoteNotInFallido();
        if (_reembolsado[loteId]) revert ReembolsoYaEjecutado();
        _reembolsado[loteId] = true;
    }

    // ---- Mutating: TREASURY_SRL_ROLE ----

    /// @inheritdoc IAssetVault
    /// @dev CONFLICT-1 (Opción A): liberar reserva técnica permitido desde COSECHADO en adelante
    ///      (no requiere QUALITY_ATTESTED — ese estado se removió del MVP).
    ///      Productor puede llamar esto inmediatamente después de `confirmarCosecha`.
    function liberarReservaTecnica(uint256 loteId) external onlyRole(TREASURY_SRL_ROLE) nonReentrant {
        LoteMiel storage lote = _lotes[loteId];
        if (lote.productorSRL == address(0)) revert LoteNotExists();
        // Permitido desde COSECHADO, ALMACENADO, REDENCION_PARCIAL, AGOTADO.
        // NO permitido en PREVENTA (cosecha no confirmada) ni FALLIDO (la reserva va a reembolso).
        if (
            lote.estado != LoteEstado.COSECHADO && lote.estado != LoteEstado.ALMACENADO
                && lote.estado != LoteEstado.REDENCION_PARCIAL && lote.estado != LoteEstado.AGOTADO
        ) revert LoteNotInCosechado();

        uint256 montoLiberable = lote.reservaTecnicaUSDC - lote.reservaTecnicaLiberada;
        if (montoLiberable == 0) revert ReservaAlreadyReleased();

        lote.reservaTecnicaLiberada = lote.reservaTecnicaUSDC;

        usdc.safeTransfer(lote.productorSRL, montoLiberable);

        emit ReservaTecnicaLiberada(loteId, montoLiberable, lote.productorSRL);
    }

    // ---- Mutating: RedemptionManager (vía función dedicated) ----

    /// @inheritdoc IAssetVault
    /// @dev Solo callable por RedemptionManager (única vía permitida de burn).
    /// FIX Bug-B1: orden de checks corregido. Primero validar que `redemptionManager` está seteado,
    /// después validar que el caller sea exactamente ese address. El orden anterior nunca disparaba
    /// `RedemptionManagerNotSet` porque `msg.sender != address(0)` siempre era true en práctica.
    function burnForRedemption(address from, uint256 loteId, uint256 cantidad) external {
        if (redemptionManager == address(0)) revert RedemptionManagerNotSet();
        if (msg.sender != redemptionManager) revert OnlyRedemptionCanBurn();
        if (cantidad == 0) revert CantidadTokensCero();

        LoteMiel storage lote = _lotes[loteId];

        // Actualizar estado del lote según redenciones — gramos para evitar rounding (consistente con FIX H-02)
        uint256 gramosRedimidos = cantidad * ComplianceConstants.GRAMOS_POR_TOKEN;
        lote.kgRedimidos += gramosRedimidos / 1000;

        if (lote.estado == LoteEstado.ALMACENADO) {
            lote.estado = LoteEstado.REDENCION_PARCIAL;
        }

        _burn(from, loteId, cantidad);

        // Si ya no hay supply, marcar AGOTADO
        if (totalSupply(loteId) == 0 && lote.estado == LoteEstado.REDENCION_PARCIAL) {
            lote.estado = LoteEstado.AGOTADO;
        }
    }

    // ---- Mutating: COMPLIANCE_OFFICER_ROLE ----

    /// @inheritdoc IAssetVault
    function pause() external onlyRole(COMPLIANCE_OFFICER_ROLE) {
        _pause();
        emit EmergencyPaused(msg.sender, uint64(block.timestamp));
    }

    /// @inheritdoc IAssetVault
    function unpause() external onlyRole(COMPLIANCE_OFFICER_ROLE) {
        _unpause();
        emit EmergencyUnpaused(msg.sender, uint64(block.timestamp));
    }

    // ---- View functions ----

    /// @inheritdoc IAssetVault
    function lotes(uint256 loteId) external view returns (LoteMiel memory) {
        return _lotes[loteId];
    }

    /// @inheritdoc IAssetVault
    /// @dev FIX H-02: usa gramos internamente, retorna kg redondeando hacia abajo (conservador).
    function kgDisponibles(uint256 loteId) external view returns (uint256) {
        LoteMiel storage lote = _lotes[loteId];
        if (lote.productorSRL == address(0)) return 0;
        uint256 gramosYaVendidos = totalSupply(loteId) * ComplianceConstants.GRAMOS_POR_TOKEN;
        uint256 gramosEsperados = lote.kgEsperados * 1000;
        if (gramosYaVendidos >= gramosEsperados) return 0;
        return (gramosEsperados - gramosYaVendidos) / 1000;
    }

    /// @inheritdoc IAssetVault
    function reservaTecnicaActual(uint256 loteId) external view returns (uint256) {
        LoteMiel storage lote = _lotes[loteId];
        return lote.reservaTecnicaUSDC - lote.reservaTecnicaLiberada;
    }

    // ---- Approval blocked ----

    /// @notice Aprobaciones ERC-1155 prohibidas (Solo primario, no hay P2P).
    /// @dev Override de setApprovalForAll para revertir cualquier aprobación.
    function setApprovalForAll(address, bool) public virtual override(ERC1155) {
        revert TransferP2PNoPermitido();
    }

    // ---- Override _update: bloqueo P2P + KYC enforcement ----

    /// @dev Override crítico que implementa el modelo "Solo primario":
    ///      - Mint (from == address(0)): permitido, valida KYC del destinatario
    ///      - Burn (to == address(0)): permitido solo desde RedemptionManager o internamente (reembolsos)
    ///      - Transfer P2P: BLOQUEADO siempre
    function _update(address from, address to, uint256[] memory ids, uint256[] memory values)
        internal
        override(ERC1155, ERC1155Supply, ERC1155Pausable)
    {
        bool isMint = (from == address(0));
        bool isBurn = (to == address(0));

        if (!isMint && !isBurn) revert TransferP2PNoPermitido();

        if (isMint) {
            if (!identityRegistry.canMint(to)) revert NotKYCVerified();
        }

        super._update(from, to, ids, values);
    }

    // ---- IERC165 ----

    /// @dev FIX M-08: override actualizado para incluir AccessControlDefaultAdminRules en la cadena.
    ///      `AccessControlDefaultAdminRules` extiende `AccessControl` (que ya implementa
    ///      `supportsInterface`); explícitamente listamos ambos para claridad y compatibilidad
    ///      con linters/solhint.
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC1155, AccessControlDefaultAdminRules)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
