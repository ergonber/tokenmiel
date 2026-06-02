# Smart Contract Specifications (v2.0)

> Specs detalladas de los **3 smart contracts MVP** de tokenización de RWA agrícola.
> Derivado de `ARQUITECTURA-TECNICA-MVP.md` v2.0 (Decisiones 5, 6, 7, 7B, sección 9).
> **Este documento NO contiene implementación**: solo signatures, NatSpec, structs, errors y eventos.
> Sirve como input directo para subagentes de implementación (Foundry) y tests.
>
> **v2.0 — reconciliación con código real (2026-05-28):** LabRegistry marcado como FASE 2 (ADR-010,
> ADR-017 2-phase export state machine, ADR-016 pause asymmetry, ADR-015 timeout policy,
> FIX M-08 AccessControlDefaultAdminRules, FIX H-02 IdentityRegistry Pausable).

---

## Tabla de contenidos

1. [Convenciones globales](#1-convenciones-globales)
2. [Constantes globales (`ComplianceConstants.sol`)](#2-constantes-globales-complianceconstantssol)
3. [Errores globales reutilizables](#3-errores-globales-reutilizables)
4. [Contrato 1: `AssetVault.sol`](#4-contrato-1-assetvaultsol)
5. [Contrato 2: `IdentityRegistry.sol`](#5-contrato-2-identityregistrysol)
6. [Contrato 3: `RedemptionManager.sol`](#6-contrato-3-redemptionmanagersol)
7. [FASE 2 — `LabRegistry.sol` (reservado, ADR-010)](#7-fase-2--labregistrysol-reservado-adr-010)
8. [Interfaces (`I*.sol`)](#8-interfaces-isol)
9. [Libraries](#9-libraries)
10. [Decisiones derivadas y conflictos detectados](#10-decisiones-derivadas-y-conflictos-detectados)

---

## 1. Convenciones globales

### 1.1 Encabezado obligatorio de cada archivo

```solidity
// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;
```

> `BUSL-1.1` es placeholder; la licencia final la define el responsable legal antes del freeze pre-auditoría.

### 1.2 Compilador

- **Versión solc:** `0.8.24` (fija, no `^0.8.24`)
- **Optimizer:** `enabled = true`, `runs = 200`
- **via_ir:** opcional, evaluado al final por overflow de stack
- **EVM target:** `paris` (compatibilidad Plume + Polygon)

### 1.3 Naming conventions

- **Contratos / interfaces / libraries:** `PascalCase` (`AssetVault`, `IIdentityRegistry`)
- **Funciones públicas / external:** `camelCase` en idioma del dominio (`comprar`, `confirmarCosecha`, `iniciarRedencion`)
  - Excepción: nombres OpenZeppelin (`grantRole`, `pause`) permanecen en inglés
- **Funciones internas / private:** prefijo `_` (`_validateKYC`, `_releaseReserva`)
- **State variables:** `camelCase`. Privadas con prefijo `_`. Públicas sin prefijo.
- **Constants / immutables:** `SCREAMING_SNAKE_CASE`
- **Events:** `PascalCase`, verbos en pasado (`LoteCreado`, `CosechaConfirmada`)
- **Custom errors:** `PascalCase`, descriptivos (`NotKYCVerified`, `TransferP2PNoPermitido`)
- **Roles:** `SCREAMING_SNAKE_CASE` terminado en `_ROLE` (`ADMIN_ROLE`)
- **Structs:** `PascalCase`
- **Enums:** `PascalCase` para el tipo, `SCREAMING_SNAKE_CASE` para miembros

### 1.4 Storage packing convention

- Para cada struct, **declarar los slots usados** en comentario NatSpec encima del struct.
- Empacar `bool`, `uint8`, `uint16`, `uint32`, `uint64`, `bytes2`, `bytes32`, `address` (20 bytes) buscando llenar slots de 32 bytes.
- **No mezclar** dynamic types (`bytes`, `string`, arrays dinámicos, mappings) dentro del packing analysis (cada uno consume slot propio para length + heap separado).
- Documentar storage layout en `@dev` del struct.

### 1.5 Errores: custom errors obligatorios

- **Prohibido** `require(cond, "msg")` o `revert("msg")`. Todo revert pasa por `revert CustomError(...)`.
- Errores con parámetros relevantes (loteId, cuenta, estado) para diagnóstico en testing y en explorers.

### 1.6 NatSpec obligatorio

Cada función external/public y cada evento debe tener:

- `@notice` — descripción en lenguaje natural (visible para usuarios end)
- `@dev` — notas para auditores y devs
- `@param` para cada parámetro
- `@return` para cada return value
- `@custom:security` — invariantes, suposiciones, riesgos relevantes

### 1.7 Visibility por defecto

- Funciones nunca usan visibility implícita.
- State variables nunca usan visibility implícita.
- Helpers internos: `internal` o `private` según corresponda.

### 1.8 Reglas de gas y patrones

- **Reentrancy:** `nonReentrant` modifier en toda función que mueva valor (USDC, ERC-1155) o cambie estado seguido de external call.
- **Checks-Effects-Interactions** sin excepciones.
- **No `tx.origin`** para auth.
- **No `block.timestamp`** como fuente de aleatoriedad; uso permitido para timestamps de auditoría.
- **No loops sin bound** explícito sobre arrays controlables por el caller.
- **Pull over push** para reembolsos cuando aplique.

### 1.9 Inmutabilidad y pausabilidad

- **Sin proxies** (sin UUPS, sin Transparent, sin Diamond). Los 3 contratos MVP son inmutables.
- **`Pausable`** se usa en los 3 contratos MVP: `AssetVault`, `RedemptionManager` e `IdentityRegistry`
  (FIX H-02 — ADR-016).
- **Asimetría de pause (ADR-016):** `pause()` = `COMPLIANCE_OFFICER_ROLE` OR `DEFAULT_ADMIN_ROLE`;
  `unpause()` = `DEFAULT_ADMIN_ROLE` únicamente. Aplica a los 3 contratos.
- `LabRegistry` (FASE 2) no se pausa globalmente; las desactivaciones individuales (`deactivateLab`) cumplen esa función.

---

## 2. Constantes globales (`ComplianceConstants.sol`)

Librería pura (no estado) que centraliza constantes consumidas por más de un contrato. No tiene funciones; solo `constant` declarations.

```solidity
library ComplianceConstants {
    // Granularidad del token
    uint256 internal constant GRAMOS_POR_TOKEN = 500;          // 1 token = 0.5 kg
    uint256 internal constant GRAMOS_POR_KILO  = 1_000;

    // Basis points
    uint16  internal constant BPS_DENOMINATOR        = 10_000;
    uint16  internal constant RESERVA_TECNICA_BPS_MIN = 1_500; // 15 %
    uint16  internal constant RESERVA_TECNICA_BPS_MAX = 2_000; // 20 %

    // KYC tiers
    uint8 internal constant TIER_NONE          = 0;
    uint8 internal constant TIER_BASICO        = 1;
    uint8 internal constant TIER_ESTANDAR      = 2;
    uint8 internal constant TIER_REFORZADO_EDD = 3;

    uint8 internal constant MIN_KYC_TIER_PARA_COMPRAR = 1;
    uint8 internal constant MIN_KYC_TIER_PARA_REDIMIR = 2;

    // Calidad / monofloral (Directiva UE 2014/63/UE)
    uint8 internal constant MIN_POLLEN_PERCENTAGE_MONOFLORAL = 45;
    uint8 internal constant MIN_LABS_PARA_ATTESTATION        = 2;
}
```

**Razón de cada constante:**

| Constante | Valor | Razón |
|---|---|---|
| `GRAMOS_POR_TOKEN` | 500 | 1 token = 0.5 kg. Permite operar en gramos enteros, evita rounding |
| `GRAMOS_POR_KILO` | 1000 | Helper conversion |
| `BPS_DENOMINATOR` | 10000 | Convención EVM estándar para % con dos decimales (10000 bps = 100%) |
| `RESERVA_TECNICA_BPS_MIN` | 1500 | 15% mínimo de USDC retenido como buffer operacional |
| `RESERVA_TECNICA_BPS_MAX` | 2000 | 20% máximo: por arriba afecta retorno al productor |
| `MIN_KYC_TIER_PARA_COMPRAR` | 1 | Tier básico para compra B2C minorista |
| `MIN_KYC_TIER_PARA_REDIMIR` | 2 | Tier estándar requerido para redención física (datos shipping + control export) |
| `MIN_POLLEN_PERCENTAGE_MONOFLORAL` | 45 | Estándar Directiva UE 2014/63/UE |
| `MIN_LABS_PARA_ATTESTATION` | 2 | Política de doble verificación cruzada (boliviano + internacional) |

---

## 3. Errores globales reutilizables

Estos errores aparecen en más de un contrato y se definen en cada contrato (no se importan vía librería para evitar Solidity quirks con custom errors de libraries en versiones < 0.8.25).

```solidity
// Identity / KYC
error NotKYCVerified(address account);
error InsufficientKYCTier(address account, uint8 currentTier, uint8 requiredTier);
error AddressSanctioned(address account);
error AddressFrozen(address account);
error KYCExpired(address account, uint64 expiredAt);

// Roles
error UnauthorizedRole(bytes32 role, address account);

// Lifecycle / estado
error InvalidLoteState(uint256 loteId, uint8 currentState, uint8 requiredState);
error InvalidStateTransition(uint8 fromState, uint8 toState);
error LoteNotFound(uint256 loteId);

// Inputs
error ZeroAddress();
error ZeroAmount();
error InvalidBasisPoints(uint16 bps);
error InvalidSignature();
error SignatureAlreadyUsed(bytes32 digest);

// Transfers
error TransferP2PNoPermitido(address from, address to);

// Reserva
error ReservaTecnicaAlreadyReleased(uint256 loteId);
error ReservaTecnicaInsufficient(uint256 loteId, uint256 requested, uint256 available);
```

---

## 4. Contrato 1: `AssetVault.sol`

### 4.1 Propósito

`AssetVault` es el **contrato principal del MVP**. Implementa el estándar ERC-1155 donde cada `tokenId` representa un lote (`LoteMiel`), con balance = cantidad de tokens (0.5 kg cada uno) propiedad de cada wallet. Mantiene el ciclo de vida del lote (PREVENTA → COSECHADO → ALMACENADO → REDENCION_PARCIAL → AGOTADO / FALLIDO), embebe la reserva técnica (15-20% del USDC prepagado retenido como buffer operacional con modelo escrow total), embebe el compliance hook (override de `_update` que prohíbe transferencias P2P) y valida KYC vía `IdentityRegistry`.

> **Nota MVP:** `QualityAttestation`, `confirmarCalidad`, el estado `QUALITY_ATTESTED` y la dependencia `ILabRegistry labRegistry` fueron removidos del MVP y reservados para FASE 2 vía `LabRegistry` standalone (ADR-010). El estado COSECHADO transiciona directamente a ALMACENADO en el MVP.

El contrato **maneja USDC directamente** con modelo escrow total (FIX H-01): el backend (`BACKEND_SIGNER_ROLE`) transfiere USDC al contrato antes de llamar `comprar()` para mintear tokens. El monto neto se libera al productor en `confirmarCosecha`; la reserva técnica queda en el contrato hasta `liberarReservaTecnica`. Si el lote falla en PREVENTA, el 100% es reembolsable on-chain vía `reembolsarLoteFallido`.

### 4.2 Herencias OpenZeppelin (orden C3)

```
contract AssetVault is
    ERC1155,
    ERC1155Supply,
    ERC1155Pausable,
    AccessControlDefaultAdminRules,
    ReentrancyGuard,
    IAssetVault
```

**Notas C3 linearization:**
- `ERC1155Supply` debe ir antes de `ERC1155Pausable` para que el `_update` chain compute supply correctamente antes del pause check.
- `AccessControlDefaultAdminRules` (FIX M-08) reemplaza `AccessControl`. Agrega un delay de 3 días para transferencias de `DEFAULT_ADMIN_ROLE`, mitigando lockout accidental o malicioso. La constante `ADMIN_TRANSFER_DELAY = 3 days` está declarada en el contrato.
- `ReentrancyGuard` al final (no afecta linearization, solo modifier).
- **Override obligatorio de `_update`** para combinar `ERC1155Supply._update` + `ERC1155Pausable._update` + el bloqueo de transfers P2P custom.
- **Override obligatorio de `supportsInterface`** para combinar `ERC1155.supportsInterface` + `AccessControlDefaultAdminRules.supportsInterface`.

### 4.3 Roles definidos

| Rol | Identidad típica | Funciones que controla |
|---|---|---|
| `DEFAULT_ADMIN_ROLE` | Safe multi-sig 2-de-3 (cofundadores) | `grantRole`, `revokeRole`, `unpause`. Bootstrap inicial. Con delay 3 días (FIX M-08) |
| `ADMIN_ROLE` | Safe multi-sig 2-de-3 | `crearLote` |
| `BACKEND_SIGNER_ROLE` | Wallet del backend (AWS KMS / GCP KMS) | `comprar` (mint tras pago + USDC transferido al contrato) |
| `COMPLIANCE_OFFICER_ROLE` | Compliance officer (hardware wallet) | `pause` (junto con DEFAULT_ADMIN_ROLE — ADR-016) |
| `ORACLE_ROLE` | Safe multi-sig 2-de-3 | `confirmarCosecha`, `confirmarAlmacenamiento`, `marcarFallido`, `reembolsarLoteFallido`, `finalizarReembolso` |
| `TREASURY_SRL_ROLE` | Hardware wallet del tesorero designado | `liberarReservaTecnica` (transfiere reserva técnica al productor desde escrow del contrato) |

> **ADR-016 pause asymmetry:** `pause()` puede ser invocado por `COMPLIANCE_OFFICER_ROLE` OR `DEFAULT_ADMIN_ROLE`. `unpause()` solo por `DEFAULT_ADMIN_ROLE`. Emite eventos `EmergencyPaused` / `EmergencyUnpaused`.

### 4.4 Constantes específicas

Re-export de `ComplianceConstants` vía `using` o referencias directas. No agregar constantes específicas en este contrato salvo:

```solidity
bytes32 public constant ADMIN_ROLE              = keccak256("ADMIN_ROLE");
bytes32 public constant BACKEND_SIGNER_ROLE     = keccak256("BACKEND_SIGNER_ROLE");
bytes32 public constant COMPLIANCE_OFFICER_ROLE = keccak256("COMPLIANCE_OFFICER_ROLE");
bytes32 public constant ORACLE_ROLE             = keccak256("ORACLE_ROLE");
bytes32 public constant TREASURY_SRL_ROLE       = keccak256("TREASURY_SRL_ROLE");
```

### 4.5 Enums

```solidity
/// @notice Estados válidos del ciclo de vida de un lote.
/// @dev Transiciones permitidas (MVP — sin QUALITY_ATTESTED):
///      PREVENTA → COSECHADO → ALMACENADO → REDENCION_PARCIAL → AGOTADO
///      Desde PREVENTA o COSECHADO → FALLIDO.
///      AGOTADO y FALLIDO son terminales (no se vuelve atrás).
///      NOTA: QUALITY_ATTESTED removido del MVP; reservado para FASE 2 vía LabRegistry (ADR-010).
enum LoteEstado {
    PREVENTA,            // 0 - inicial, recibe compras
    COSECHADO,           // 1 - cosecha confirmada con hash SENASAG
    ALMACENADO,          // 2 - contrato depósito firmado
    REDENCION_PARCIAL,   // 3 - al menos una redención completada (burn parcial)
    AGOTADO,             // 4 - todo redimido (terminal)
    FALLIDO              // 5 - terminal, reembolso pro-rata
}
```

### 4.6 Structs

> **Nota MVP:** `QualityAttestation` fue removido. No existe en el MVP; reservado para FASE 2 (ADR-010).

#### 4.6.1 `TipoCertificadoOrigen`

```solidity
/// @notice Tipo de certificado de origen para exportación.
enum TipoCertificadoOrigen {
    NONE,
    FORM_A,
    EUR_1,
    OTHER
}
```

#### 4.6.2 `LoteMiel`

```solidity
/// @notice Estado completo de un lote de miel tokenizado.
/// @dev Todos los campos escalares están en IAssetVault.sol (fuente de verdad).
struct LoteMiel {
    uint256 kgEsperados;
    uint256 kgCosechadosReal;
    uint256 kgRedimidos;
    uint256 precioPorTokenUSDC;
    uint256 reservaTecnicaUSDC;
    uint256 reservaTecnicaLiberada;
    /// @notice Monto neto retenido en escrow (FIX H-01). Liberado al productor en confirmarCosecha.
    ///         Si el lote FALLA en PREVENTA, disponible para reembolso 100% on-chain.
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
```

**Nota de diseño:** `confirmarCosecha` recibe 8 hashes (`hashSenasag`, `hashAnalisisLab`, `hashActaCosecha`, `hashFotosApiario`, `hashCertificadoOrigen`, `tipoCertificado`). El hash de análisis de lab que se almacena en `hashAnalisisLab` es el hash estándar (HMF, humedad, diastasa) — distinto del análisis palinológico de FASE 2.

### 4.7 State variables

```solidity
/// @notice Dirección del token USDC en la chain de despliegue.
/// @dev Inmutable. Modelo escrow total: USDC retenido en el contrato hasta confirmarCosecha.
IERC20 public immutable usdc;

/// @notice Dirección del contrato IdentityRegistry consultado para enforcement KYC.
IIdentityRegistry public immutable identityRegistry;

/// @notice Dirección del RedemptionManager autorizado a llamar burnForRedemption (one-time set).
/// @dev Mutable una sola vez: setRedemptionManager() callable por DEFAULT_ADMIN_ROLE.
///      Valor 0 antes de ser configurado (RedemptionManagerNotSet).
address public redemptionManager;

// NOTA: labRegistry removido del MVP. Se reactivará en FASE 2 (ADR-010).

/// @notice Storage de los lotes indexados por loteId.
mapping(uint256 => LoteMiel) private _lotes;

/// @notice Marca de reembolso completado por lote (paginación de reembolsarLoteFallido).
mapping(uint256 => bool) private _reembolsado;

/// @notice Cantidad máxima de compradores procesables en un batch de reembolso.
/// @dev Previene DoS por out-of-gas. Valor: 100.
uint256 public constant MAX_REFUND_BATCH = 100;

/// @notice Delay para transferencias de DEFAULT_ADMIN_ROLE (FIX M-08).
/// @dev Valor: 3 días (259200 segundos).
uint48 public constant ADMIN_TRANSFER_DELAY = 3 days;
```

#### 4.7.1 `InitParams` (struct de constructor)

```solidity
/// @notice Parámetros de inicialización agrupados.
/// @dev Patrón Uniswap V4 / Aave V3 — evita stack-too-deep.
///      NOTA: campo labRegistry removido en MVP (FASE 2, ADR-010).
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
```

### 4.8 Eventos

```solidity
/// @notice Emitido al crear un nuevo lote en estado PREVENTA.
event LoteCreado(
    uint256 indexed loteId,
    uint256 kgEsperados,
    uint256 precioPorTokenUSDC,
    address indexed productorSRL,
    bytes32 hashFSA,
    uint16 reservaBps
);

/// @notice Emitido tras una compra exitosa (mint).
event LoteComprado(
    uint256 indexed loteId,
    address indexed comprador,
    uint256 cantidadTokens,
    uint256 montoUSDC,
    uint256 reservaRetenida,
    bytes32 paymentRefHash
);

/// @notice Emitido al confirmar cosecha.
event CosechaConfirmada(
    uint256 indexed loteId,
    uint256 kgRealCosechado,
    bytes32 hashSenasag,
    bytes32 hashAnalisisLab,
    bytes32 hashActaCosecha,
    bytes32 hashCertificadoOrigen
);

/// @notice Emitido cuando el monto neto en escrow se libera al productor (post-cosecha).
event MontoNetoLiberado(uint256 indexed loteId, uint256 monto, address indexed destinatario);

/// @notice Emitido al confirmar almacenamiento (contrato de depósito firmado).
event AlmacenamientoConfirmado(
    uint256 indexed loteId,
    bytes32 hashContratoDeposito,
    address indexed almacenAutorizado
);

/// @notice Emitido al marcar un lote como FALLIDO.
event LoteFallido(uint256 indexed loteId, string motivo);

/// @notice Emitido cuando se libera la reserva técnica al productor.
event ReservaTecnicaLiberada(uint256 indexed loteId, uint256 monto, address indexed destinatario);

/// @notice Emitido durante reembolso pro-rata por lote fallido.
event ReembolsoEjecutado(
    uint256 indexed loteId,
    address indexed comprador,
    uint256 tokensQuemados,
    uint256 usdcDevuelto
);

/// @notice Emitido al pausar de emergencia (ADR-016).
event EmergencyPaused(address indexed officer, uint64 timestamp);

/// @notice Emitido al despausar (ADR-016).
event EmergencyUnpaused(address indexed officer, uint64 timestamp);
```

> **Removido:** `CalidadConfirmada` (FASE 2 — `confirmarCalidad` no existe en MVP). `TokensRedimidos` y `LoteURIUpdated` no están en el contrato real; el burn se observa como evento ERC-1155 `TransferSingle` con `to == address(0)`.

### 4.9 Custom errors

```solidity
// Zero address / inputs
error ZeroAddress();
error InvalidKgEsperados();
error InvalidPrecio();
error InvalidHash();
error ReservaBpsOutOfRange();
error CantidadTokensCero();
error EmptyMotivo();
error EmptyBuyers();

// KYC / compliance
error NotKYCVerified();

// Lote lifecycle
error LoteAlreadyExists();
error LoteNotExists();
error LoteNotInPreventa();
error LoteNotInCosechado();
error LoteNotInAlmacenado();
error LoteNotInFallido();
error LoteAlreadyFinalized();
error CannotFailLoteInThisState();

// Compra
error KgSolicitadosExcedenSupply();
error MontoUSDCInsuficiente();

// Transfers
error TransferP2PNoPermitido();

// Burn / RedemptionManager
error OnlyRedemptionCanBurn();
error RedemptionManagerNotSet();
error RedemptionManagerAlreadySet();

// Reserva
error ReservaAlreadyReleased();
error MontoNetoAlreadyReleased();

// Reembolso
error ReembolsoYaEjecutado();
error CannotRefundBlockedAddress();
error CannotRefundRevokedAddress();
error BatchTooLarge();

// Pause (ADR-016)
error UnauthorizedPauseActor();
```

> **Removidos:** errores de QualityAttestation (FASE 2 — `confirmarCalidad` no existe en MVP).

### 4.10 Modifiers

El contrato real no usa modifiers custom para KYC/lote — los checks están inline en cada función siguiendo el patrón Checks-Effects-Interactions. Modifiers heredados que sí se usan:

- `onlyRole(ROLE)` — de `AccessControlDefaultAdminRules`
- `nonReentrant` — de `ReentrancyGuard`
- `whenNotPaused` — de `Pausable` (ERC1155Pausable propaga a `_update`)

> **Nota:** la validación KYC en mint se realiza en `_update()` via `identityRegistry.canMint(to)`, no en un modifier separado.

### 4.11 Function signatures

#### 4.11.1 Construcción y administración

```solidity
/// @notice Inicializa el contrato con dependencias agrupadas en InitParams.
/// @dev FIX M-08: admin asignado vía AccessControlDefaultAdminRules con delay de 3 días.
///      NOTA: labRegistry removido del MVP (FASE 2 — ADR-010).
/// @param p Struct InitParams con todos los parámetros de inicialización.
constructor(InitParams memory p) ERC1155(p.uri) AccessControlDefaultAdminRules(ADMIN_TRANSFER_DELAY, p.admin);

/// @notice Setea el RedemptionManager (one-time, post-deploy — dependencia circular).
/// @dev Solo DEFAULT_ADMIN_ROLE. Reverts si ya fue seteado (RedemptionManagerAlreadySet).
/// @param newRedemptionManager Dirección del RedemptionManager desplegado.
function setRedemptionManager(address newRedemptionManager) external;

/// @notice Pausa de emergencia. Bloquea iniciarRedencion y mints vía ERC1155Pausable._update.
/// @dev ADR-016: COMPLIANCE_OFFICER_ROLE OR DEFAULT_ADMIN_ROLE. Emite EmergencyPaused.
function pause() external;

/// @notice Despausa el contrato post-incidente.
/// @dev ADR-016: solo DEFAULT_ADMIN_ROLE. Emite EmergencyUnpaused.
function unpause() external;
```

#### 4.11.2 Ciclo de vida del lote

```solidity
/// @notice Crea un nuevo lote en estado PREVENTA.
/// @dev Solo ADMIN_ROLE.
/// @param loteId ID único del lote (también es el ERC-1155 tokenId).
/// @param kgEsperados Kilos totales esperados del lote.
/// @param precioPorTokenUSDC Precio fijo en USDC base units (6 decimales) por 1 token (= 0.5 kg).
/// @param fechaCosechaEstimada Unix timestamp estimado de cosecha.
/// @param origenGeografico Código de 2 bytes de origen geográfico.
/// @param productorSRL Wallet del productor SRL (no zero).
/// @param hashFSA Hash del fact-sheet del lote.
/// @param reservaBps Basis points (1500-2000) de reserva técnica.
/// @param variedadMonofloral Código de variedad monofloral (uint8).
/// @custom:security Valida reservaBps dentro de [RESERVA_TECNICA_BPS_MIN, RESERVA_TECNICA_BPS_MAX].
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

/// @notice Mintea tokens a un comprador tras pago confirmado y USDC transferido al contrato.
/// @dev Solo BACKEND_SIGNER_ROLE. nonReentrant + whenNotPaused.
///      Modelo escrow total: USDC debe estar en el contrato ANTES de llamar a comprar().
///      Acumula reservaTecnicaUSDC + montoNetoPendiente en el lote.
///      KYC validado en _update() via identityRegistry.canMint(comprador).
/// @param loteId Lote a comprar. Debe estar en PREVENTA.
/// @param cantidadTokens Tokens a mintear (1 token = 0.5 kg). No exceder kgEsperados en gramos (FIX H-02).
/// @param comprador Wallet del comprador.
/// @param montoUSDCPagado Monto USDC ya transferido al contrato.
/// @param paymentRefHash Hash del payment intent (audit trail, anti-replay off-chain).
function comprar(
    uint256 loteId,
    uint256 cantidadTokens,
    address comprador,
    uint256 montoUSDCPagado,
    bytes32 paymentRefHash
) external;

/// @notice Confirma la cosecha y transiciona a COSECHADO. Libera montoNeto al productor.
/// @dev Solo ORACLE_ROLE. nonReentrant. FIX H-01: libera montoNetoPendiente al productor SRL.
///      La reserva técnica permanece hasta liberarReservaTecnica().
/// @param loteId Lote. Debe estar en PREVENTA.
/// @param kgRealCosechado Kilos efectivamente cosechados.
/// @param hashSenasag Hash del certificado SENASAG.
/// @param hashAnalisisLab Hash del análisis lab estándar (HMF, humedad, diastasa).
/// @param hashActaCosecha Hash del acta de cosecha.
/// @param hashFotosApiario Hash de las fotos del apiario.
/// @param hashCertificadoOrigen Hash del certificado de origen.
/// @param tipoCertificado Tipo de certificado de origen (FORM_A, EUR_1, OTHER, NONE).
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

/// @notice Confirma almacenamiento y transiciona COSECHADO → ALMACENADO.
/// @dev Solo ORACLE_ROLE. En MVP no hay QUALITY_ATTESTED intermedio (ADR-010).
/// @param loteId Lote. Debe estar en COSECHADO.
/// @param hashContratoDeposito Hash del contrato de depósito.
/// @param almacenAutorizado Dirección del almacén autorizado.
function confirmarAlmacenamiento(
    uint256 loteId,
    bytes32 hashContratoDeposito,
    address almacenAutorizado
) external;

/// @notice Marca un lote como FALLIDO (estado terminal).
/// @dev Solo ORACLE_ROLE. Solo permitido desde PREVENTA o COSECHADO (FIX M-05).
///      Post-ALMACENADO requiere governance superior (reservado para futuro).
/// @param loteId Lote.
/// @param motivo String con motivo del fallo.
function marcarFallido(uint256 loteId, string calldata motivo) external;

/// @notice Ejecuta reembolso pro-rata para un batch de compradores de un lote FALLIDO.
/// @dev Solo ORACLE_ROLE. nonReentrant. Batch máximo MAX_REFUND_BATCH (100).
///      Pool disponible = montoNetoPendiente + reservaTecnicaUSDC - reservaTecnicaLiberada.
///      FIX H-01: reembolso 100% on-chain si el lote falla en PREVENTA (escrow total).
///      FIX M-06: bloquea reembolso a sancionados/frozen. FIX H-01: bloquea a KYC revocados.
///      Para lotes con más buyers, llamar múltiples veces con sub-arrays.
/// @param loteId Lote FALLIDO.
/// @param compradores Lista de wallets a reembolsar (max MAX_REFUND_BATCH).
function reembolsarLoteFallido(uint256 loteId, address[] calldata compradores) external;

/// @notice Marca el reembolso de un lote como completado.
/// @dev Solo ORACLE_ROLE. Llamar tras procesar todos los batches de reembolsarLoteFallido.
/// @param loteId Lote FALLIDO con reembolso procesado.
function finalizarReembolso(uint256 loteId) external;

/// @notice Quema tokens del comprador delegado por RedemptionManager (única vía permitida de burn).
/// @dev Solo callable por la dirección seteada en redemptionManager. No tiene whenNotPaused (ADR-016).
///      Actualiza kgRedimidos. Transiciona ALMACENADO → REDENCION_PARCIAL o → AGOTADO.
/// @param from Wallet del comprador (tokens se queman de su balance).
/// @param loteId ID del lote.
/// @param cantidad Tokens a quemar.
function burnForRedemption(address from, uint256 loteId, uint256 cantidad) external;
```

> **FASE 2 — removido del MVP:** `confirmarCalidad(loteId, QualityAttestation, bytes[])` — reservado para cuando LabRegistry esté disponible (ADR-010).

#### 4.11.3 Reserva técnica

```solidity
/// @notice Libera la reserva técnica al productor SRL (transfiere USDC from escrow).
/// @dev Solo TREASURY_SRL_ROLE. nonReentrant.
///      Permitido desde COSECHADO, ALMACENADO, REDENCION_PARCIAL o AGOTADO.
///      NO permitido en PREVENTA (cosecha no confirmada) ni FALLIDO (la reserva va a reembolso).
///      FIX CONFLICT-1: no requiere QUALITY_ATTESTED (estado removido del MVP).
/// @param loteId Lote.
function liberarReservaTecnica(uint256 loteId) external;

/// @notice Devuelve el monto de reserva técnica todavía no liberada.
/// @param loteId Lote.
/// @return Monto en USDC base units (reservaTecnicaUSDC - reservaTecnicaLiberada).
function reservaTecnicaActual(uint256 loteId) external view returns (uint256);
```

#### 4.11.4 Burn delegado para redención (Modelo Option B — Lock Acumulator)

> **Cambio arquitectónico respecto a la versión anterior de las specs:**
> El modelo original preveía transferencia de tokens al escrow del RM (`lockForRedemption`) y
> devolución en cancelación (`returnRedemptionTokens`). El modelo real es **Option B — Lock Acumulator**:
> los tokens permanecen en el wallet del comprador todo el tiempo. Solo se llama a
> `burnForRedemption` al completar la redención. `lockForRedemption`, `burnRedemptionTokens` y
> `returnRedemptionTokens` **NO existen** en el contrato.

Ver `burnForRedemption` en §4.11.2 y la explicación completa en §6.1 (RedemptionManager).

#### 4.11.5 View functions

```solidity
/// @notice Devuelve el struct completo del lote.
/// @param loteId Lote.
/// @return Struct LoteMiel.
function lotes(uint256 loteId) external view returns (LoteMiel memory);

/// @notice Devuelve kg disponibles para compra (no vendidos aún) en un lote.
/// @dev FIX H-02: calcula en gramos internamente, retorna kg redondeando hacia abajo.
/// @param loteId Lote.
/// @return Kilos disponibles para compra.
function kgDisponibles(uint256 loteId) external view returns (uint256);

/// @notice Devuelve la reserva técnica no liberada todavía.
/// @param loteId Lote.
/// @return Monto en USDC base units.
function reservaTecnicaActual(uint256 loteId) external view returns (uint256);

/// @notice Devuelve el total supply de tokens de un lote (override ERC1155Supply + IAssetVault).
/// @param id El loteId (= tokenId).
/// @return Total tokens en circulación para ese lote.
function totalSupply(uint256 id) external view returns (uint256);
```

> **Removidas:** `getLoteEstado`, `getQualityAttestation`, `isMonofloralCertified`, `getLoteIds`, `tokensDisponibles`, `getCompradoresLote` — no existen en el contrato real. La información de estado se obtiene de `lotes(loteId).estado`. La certificación monofloral es FASE 2.

### 4.12 Overrides de OpenZeppelin

#### 4.12.1 `_update` (núcleo del compliance hook)

```solidity
/// @notice Override que combina ERC1155Supply, ERC1155Pausable y el bloqueo P2P.
/// @dev Reglas (Modelo Option B — tokens nunca se transfieren al RM):
///      1. Mint (from == address(0)): permitido. Valida identityRegistry.canMint(to).
///      2. Burn (to == address(0)): permitido solo desde RedemptionManager vía burnForRedemption,
///         o internamente en reembolsarLoteFallido.
///      3. Cualquier otra transferencia P2P: BLOQUEADO → TransferP2PNoPermitido.
///      NO hay ruta de transfer hacia/desde RedemptionManager como escrow (Option B).
function _update(
    address from,
    address to,
    uint256[] memory ids,
    uint256[] memory values
) internal override(ERC1155, ERC1155Supply, ERC1155Pausable);
```

#### 4.12.2 `supportsInterface`

```solidity
/// @notice Indica interfaces ERC implementadas (ERC-1155 + AccessControlDefaultAdminRules).
/// @dev FIX M-08: override actualizado para incluir AccessControlDefaultAdminRules.
function supportsInterface(bytes4 interfaceId)
    public
    view
    override(ERC1155, AccessControlDefaultAdminRules)
    returns (bool);
```

### 4.13 Consideraciones de seguridad

1. **Reentrancy:**
   - Funciones que mueven USDC o mintean/queman tokens usan `nonReentrant`.
   - `reembolsarLoteFallido` sigue CEI estricto: checks → effects (_burn) → interactions (safeTransfer).

2. **Pause asymmetry (ADR-016):**
   - `pause()`: `COMPLIANCE_OFFICER_ROLE` OR `DEFAULT_ADMIN_ROLE` → defensa cruzada ante compromiso de un actor.
   - `unpause()`: solo `DEFAULT_ADMIN_ROLE` (Safe 2-de-3) → un compliance officer comprometido no puede deshacer el pause.
   - Emite `EmergencyPaused` / `EmergencyUnpaused` (además del evento Paused/Unpaused de OZ).
   - Error: `UnauthorizedPauseActor`.

3. **Access control (FIX M-08):**
   - `DEFAULT_ADMIN_ROLE` usa `AccessControlDefaultAdminRules` con delay de 3 días para transferencias.
   - `ADMIN_TRANSFER_DELAY = 3 days` — permite cancelar transferencias accidentales o maliciosas.

4. **Escrow total (FIX H-01):**
   - USDC del comprador ingresa al contrato en `comprar()`.
   - `montoNetoPendiente` se libera al productor en `confirmarCosecha()`.
   - Si el lote falla en PREVENTA: `montoNetoPendiente + reservaTecnicaUSDC` = 100% reembolsable on-chain.
   - Si el lote falla post-COSECHADO con montoNeto ya liberado: recuperación off-chain (documentar en runbook).

5. **Overmint protection (FIX H-02):**
   - `comprar()` valida en gramos (no kg) para evitar rounding que permitiría overmint.
   - `gramosYaVendidos + gramosSolicitados <= lote.kgEsperados * 1000`.

6. **Reembolso a addresses bloqueadas (FIX H-01, M-06):**
   - `reembolsarLoteFallido` rechaza sancionados (`CannotRefundBlockedAddress`) y KYC revocados (`CannotRefundRevokedAddress`). La recuperación de esos fondos es off-chain (decisión de compliance).

7. **Option B — no escrow de tokens:**
   - `lockForRedemption`, `burnRedemptionTokens`, `returnRedemptionTokens` NO existen.
   - Los tokens permanecen en el wallet del comprador hasta `burnForRedemption` en `completarRedencion`.
   - La única vía de burn es a través del `redemptionManager` configurado o internamente (reembolsos).

8. **DoS por batch:**
   - `reembolsarLoteFallido` cap a `MAX_REFUND_BATCH = 100`. Para lotes con más compradores, llamar múltiples veces y finalizar con `finalizarReembolso`.

9. **marcarFallido restringido (FIX M-05):**
   - Solo desde PREVENTA o COSECHADO. Post-ALMACENADO el producto físico existe; los riesgos requieren governance superior (reservado para versión futura).

10. **MEV en compras:**
    - Sin riesgo material: precio fijo, mints ejecutados en serie por el backend con nonce monotónico.

---

## 5. Contrato 2: `IdentityRegistry.sol`

### 5.1 Propósito

`IdentityRegistry` mantiene la whitelist on-chain de wallets verificadas (KYC), su tier, su jurisdicción, su estado (sancionado, congelado, expirado), y un hash externo (`externalRefHash`) que enlaza con el `applicantId` de Sumsub para reconstruir el linkage off-chain. Es consultado por `AssetVault` (mint, transfer-blocked-by-default) y `RedemptionManager` (iniciar redención requiere tier >= 2).

Diseñado como **bridge con Plume Arc**: en Plume Network, Plume Arc es la fuente nativa de verificación KYC; este contrato se sincroniza vía un backend signer que escucha eventos Arc y refleja decisiones aquí. Pero el contrato es **autónomo**: en Polygon (fase 6+) o en testnets sin Plume Arc, funciona standalone con el backend signer como única fuente.

El contrato **no almacena PII**: solo hashes y datos compatibles con regulación de privacidad (tier, jurisdicción ISO, timestamps, flags). El `externalRefHash` es un commitment criptográfico al `applicantId` Sumsub, recuperable solo conociendo el original (no rainbow-tableable porque incluye sal interna del backend).

### 5.2 Herencias OpenZeppelin (orden C3)

```
contract IdentityRegistry is
    AccessControlDefaultAdminRules,
    Pausable,
    IIdentityRegistry
```

> **FIX H-02 / FIX M-08:** IdentityRegistry SÍ incluye `Pausable` y `AccessControlDefaultAdminRules` (delay 3 días).
> El pause de IdentityRegistry afecta SOLO a los mutators KYC/compliance (`setKYC`, `revokeKYC`,
> `markSanctioned`, `unmarkSanctioned`, `freezeAddress`, `unfreezeAddress`) — las views (`canMint`,
> `canRedeem`, `isSanctioned`, etc.) NO se bloquean, así que AssetVault y RedemptionManager
> pueden seguir validando durante un pause de emergencia del registry.
>
> **Asimetría ADR-016:** `pause()` = COMPLIANCE_OFFICER_ROLE OR DEFAULT_ADMIN_ROLE.
> `unpause()` = solo DEFAULT_ADMIN_ROLE.

### 5.3 Roles definidos

| Rol | Identidad típica | Funciones que controla |
|---|---|---|
| `DEFAULT_ADMIN_ROLE` | Safe multi-sig 2-de-3 | Gestión de roles, `unpause`. Con delay 3 días (FIX M-08) |
| `BACKEND_SIGNER_ROLE` | Wallet del backend (AWS KMS / GCP KMS) | `setKYC`, `revokeKYC` |
| `COMPLIANCE_OFFICER_ROLE` | Hardware wallet del compliance officer (titular + suplente) | `markSanctioned`, `unmarkSanctioned`, `freezeAddress`, `unfreezeAddress`, `pause` |

> `ADMIN_ROLE`, `ORACLE_ROLE` y `TREASURY_SRL_ROLE` **no aplican** en IdentityRegistry.
> `pause()` es accesible por `COMPLIANCE_OFFICER_ROLE` OR `DEFAULT_ADMIN_ROLE` (ADR-016).

### 5.4 Constantes

```solidity
bytes32 public constant BACKEND_SIGNER_ROLE     = keccak256("BACKEND_SIGNER_ROLE");
bytes32 public constant COMPLIANCE_OFFICER_ROLE = keccak256("COMPLIANCE_OFFICER_ROLE");

/// @notice Delay para transferencias de DEFAULT_ADMIN_ROLE (FIX M-08).
uint48 public constant ADMIN_TRANSFER_DELAY = 3 days;
```

Referencia a `ComplianceConstants.MAX_KYC_TIER`, `MIN_KYC_TIER_PARA_COMPRAR`, `MIN_KYC_TIER_PARA_REDIMIR` sin redeclarar.

### 5.5 Structs

#### 5.5.1 `KYCData` (antes `IdentityData`)

```solidity
/// @notice Datos de KYC on-chain de una wallet.
/// @dev Storage packed:
///      slot 0: tier (1) + sanctioned (1) + frozen (1) + jurisdiction (2) +
///              expiresAt (8) + updatedAt (8) = 21 bytes
///      slot 1: sumsubApplicantHash (32)
struct KYCData {
    uint8  tier;                  // 0=none/revocado, 1=básico, 2=estándar, 3=reforzado EDD
    bool   sanctioned;
    bool   frozen;
    bytes2 jurisdiction;          // ISO 3166-1 alpha-2 (e.g. "BO", "DE", "US")
    uint64 expiresAt;             // unix timestamp de expiración KYC
    uint64 updatedAt;             // unix timestamp del último cambio
    bytes32 sumsubApplicantHash;  // hash del applicantId Sumsub (audit trail off-chain)
}
```

> **Renombrado:** `IdentityData` → `KYCData`. Campo `revokedAt` removido (revocación se maneja poniendo `tier = 0`). Campo `externalRefHash` renombrado a `sumsubApplicantHash` para claridad.

### 5.6 Enums

No requeridos (los flags son `bool`, el tier es `uint8`).

### 5.7 State variables

```solidity
/// @notice Storage de datos KYC por wallet.
mapping(address => KYCData) private _kyc;
```

> `plumeArcBridge` no existe en el contrato real (FASE 6+, fuera del MVP). El bridge se implementa como adapter separado.

### 5.8 Eventos

```solidity
/// @notice Emitido al setear o actualizar KYC de una cuenta.
/// @dev FIX M-03: actor indexed para forensics (qué backend signer hizo el cambio).
event KYCUpdated(
    address indexed user,
    address indexed actor,
    uint8 tier,
    uint64 expiresAt,
    bytes2 jurisdiction
);

/// @notice Emitido al marcar sancionado (FIX M-01: evidenceHash mandatorio).
event Sanctioned(
    address indexed user,
    address indexed actor,
    string reason,
    bytes32 evidenceHash,
    uint64 timestamp
);

/// @notice Emitido al desmarcar sancionado.
event Unsanctioned(address indexed user, address indexed actor, string reason);

/// @notice Emitido al congelar una cuenta (FIX M-01b: orderHash mandatorio).
event Frozen(address indexed user, address indexed actor, string regulatoryOrder, bytes32 orderHash);

/// @notice Emitido al descongelar.
event Unfrozen(address indexed user, address indexed actor, string reason);

/// @notice Emitido al revocar KYC.
event KYCRevoked(address indexed user, address indexed actor, string reason);

/// @notice Emitido al pausar de emergencia (FIX H-02 / ADR-016).
event EmergencyPaused(address indexed actor, uint64 timestamp);

/// @notice Emitido al despausar (FIX H-02 / ADR-016).
event EmergencyUnpaused(address indexed actor, uint64 timestamp);
```

> **Removido:** `PlumeArcBridgeUpdated` (bridge no existe en MVP).

### 5.9 Custom errors

```solidity
error InvalidTier();
error ExpiryInPast();
error AlreadySanctioned();
error NotSanctioned();
error AlreadyFrozen();
error NotFrozen();
error AlreadyRevoked();
error EmptyReason();
error ZeroAddressUser();
// FIX M-01: hash de evidencia mandatorio para sanciones
error InvalidEvidenceHash();
// FIX M-01b: hash de orden regulatoria mandatorio para freeze
error InvalidOrderHash();
// FIX M-04: tier=0 no se setea via setKYC (usar revokeKYC)
error TierZeroNotAllowed();
// FIX H-02: pause por actor sin rol adecuado
error UnauthorizedPauseActor();
```

### 5.10 Modifiers

El contrato real no usa modifiers custom. Modifiers heredados que sí se usan:

- `onlyRole(ROLE)` — de `AccessControlDefaultAdminRules`
- `whenNotPaused` — de `Pausable` (aplicado a mutators KYC/compliance)

> `onlySignerOrCompliance` y `onlyBridgeOrSigner` no existen; los checks de rol son inline o via `onlyRole`.

### 5.11 Function signatures

#### 5.11.1 Construcción

```solidity
/// @notice Inicializa con admin, backend signer y compliance officers.
/// @dev FIX M-08: admin asignado vía AccessControlDefaultAdminRules con delay de 3 días.
/// @param admin Dirección con DEFAULT_ADMIN_ROLE (Safe Wyoming 2-de-3).
/// @param backendSigner Wallet del backend (HSM-managed) que sincroniza KYC.
/// @param complianceOfficer Oficial de Cumplimiento titular.
/// @param complianceOfficerSuplente Oficial de Cumplimiento suplente.
constructor(
    address admin,
    address backendSigner,
    address complianceOfficer,
    address complianceOfficerSuplente
) AccessControlDefaultAdminRules(ADMIN_TRANSFER_DELAY, admin);
```

#### 5.11.2 Mutators

```solidity
/// @notice Setea o actualiza KYC de una cuenta (sincronización desde Sumsub).
/// @dev Solo BACKEND_SIGNER_ROLE. whenNotPaused.
///      FIX M-04: tier=0 no se acepta acá — usar revokeKYC para separar semánticamente.
/// @param user Wallet a actualizar.
/// @param tier 1-3 (no 0; usar revokeKYC para revocar).
/// @param expiresAt Unix timestamp de expiración del KYC.
/// @param jurisdiction ISO 3166-1 alpha-2.
/// @param sumsubApplicantHash Hash del applicantId Sumsub (audit trail off-chain).
function setKYC(
    address user,
    uint8 tier,
    uint64 expiresAt,
    bytes2 jurisdiction,
    bytes32 sumsubApplicantHash
) external;

/// @notice Revoca KYC (EDD failure, cuenta cierra). Resetea tier a 0.
/// @dev Solo BACKEND_SIGNER_ROLE. whenNotPaused.
function revokeKYC(address user, string calldata reason) external;

/// @notice Marca cuenta como sancionada.
/// @dev Solo COMPLIANCE_OFFICER_ROLE. whenNotPaused.
///      FIX M-01: evidenceHash mandatorio (no aceptamos sanciones sin documento de soporte).
///      FIX M-03: emite actor indexed para forensics.
/// @param user Wallet.
/// @param reason Motivo (e.g. "OFAC_SDN_match").
/// @param evidenceHash Hash del documento de evidencia.
function markSanctioned(address user, string calldata reason, bytes32 evidenceHash) external;

/// @notice Quita el flag sancionado (recurso, false-positive, etc.).
/// @dev Solo COMPLIANCE_OFFICER_ROLE. whenNotPaused.
function unmarkSanctioned(address user, string calldata reason) external;

/// @notice Congela cuenta por orden regulatoria (sin sanción formal).
/// @dev Solo COMPLIANCE_OFFICER_ROLE. whenNotPaused.
///      FIX M-01b: orderHash mandatorio (no aceptamos freeze sin orden judicial/regulatoria documentada).
/// @param user Wallet.
/// @param regulatoryOrder Descripción de la orden.
/// @param orderHash Hash del documento de la orden.
function freezeAddress(address user, string calldata regulatoryOrder, bytes32 orderHash) external;

/// @notice Descongela cuenta.
/// @dev Solo COMPLIANCE_OFFICER_ROLE. whenNotPaused.
function unfreezeAddress(address user, string calldata reason) external;

/// @notice Pausa de emergencia (scope limitado a mutators).
/// @dev FIX H-02 / ADR-016: COMPLIANCE_OFFICER_ROLE OR DEFAULT_ADMIN_ROLE.
///      Las views canMint/canRedeem/isSanctioned siguen funcionando durante el pause.
function pause() external;

/// @notice Despausa post-incidente.
/// @dev FIX H-02 / ADR-016: solo DEFAULT_ADMIN_ROLE.
function unpause() external;
```

#### 5.11.3 View functions / queries

```solidity
/// @notice Devuelve el tier actual de KYC del usuario.
function getTier(address user) external view returns (uint8);

/// @notice Devuelve true si el usuario está sancionado.
function isSanctioned(address user) external view returns (bool);

/// @notice Devuelve true si el usuario está congelado.
function isFrozen(address user) external view returns (bool);

/// @notice Devuelve true si el KYC del usuario está expirado.
function isExpired(address user) external view returns (bool);

/// @notice Devuelve true si el usuario puede recibir un mint (tier >= 1, no sancionado, no frozen, no expirado).
/// @dev Llamado por AssetVault._update() en mints. Views no bloqueadas por pause.
function canMint(address user) external view returns (bool);

/// @notice Devuelve true si el usuario puede iniciar una redención (tier >= 2, no sancionado, no frozen, no expirado).
/// @dev Llamado por RedemptionManager.iniciarRedencion(). Views no bloqueadas por pause.
function canRedeem(address user) external view returns (bool);

/// @notice Devuelve la jurisdicción ISO del usuario.
function getJurisdiction(address user) external view returns (bytes2);

/// @notice Devuelve el struct completo de datos KYC de un usuario.
function getKYCData(address user) external view returns (KYCData memory);
```

> **Removidas:** `checkCompliance`, `isCompliant`, `getIdentity` — no existen en el contrato real.
> El equivalente funcional son `canMint(user)` y `canRedeem(user)`, que ya combinan tier + sanctioned + frozen + expiry.

### 5.12 Overrides

No requiere overrides custom de OpenZeppelin. La combinación `AccessControlDefaultAdminRules + Pausable` no presenta conflictos C3.

### 5.13 Consideraciones de seguridad

1. **Centralización del backend signer:**
   - Si la wallet `BACKEND_SIGNER_ROLE` se compromete, atacante puede aprobar KYCs falsos. Mitigación: KMS, monitoreo de eventos, rotación periódica.

2. **Bridge Plume Arc:**
   - Si Plume Arc tiene incidente, el bridge puede propagar estado inválido. Mitigación: `unmarkSanctioned`/`unfreeze` solo por compliance officer (humano), independiente del bridge.

3. **Privacy / PII:**
   - El contrato no almacena PII directamente. `externalRefHash` es un commitment unidirectional.
   - **Cuidado:** la jurisdicción + tier + timestamp + dirección puede inferirse en patrones; documentar en privacy notice.

4. **Replay de operaciones:**
   - Cada operación es idempotente vía estado (e.g. `markSanctioned` revierte si ya sancionada). No requiere nonces.

5. **Expiry handling:**
   - `getTier` devuelve 0 si expirado. `checkCompliance` lo refleja con `reason = 5`.
   - El backend debe re-aprobar antes del expiry para evitar congelamiento de operación al usuario.

6. **Pause de emergencia (FIX H-02 / ADR-016):**
   - `pause()` bloquea solo mutators (setKYC, revokeKYC, markSanctioned, etc.). Las views `canMint` / `canRedeem` / `isSanctioned` / `isFrozen` siguen funcionando para no bloquear AssetVault y RedemptionManager.
   - Asimetría: `pause()` = COMPLIANCE_OFFICER_ROLE OR DEFAULT_ADMIN_ROLE; `unpause()` = solo DEFAULT_ADMIN_ROLE.

7. **Revocación semántica (FIX M-04):**
   - `setKYC` rechaza tier=0 (`TierZeroNotAllowed`). La revocación usa `revokeKYC` separado, diferenciando "nunca verificado" de "fue verificado y revocado". Re-aprobación requiere nueva llamada a `setKYC` con datos frescos.

---

## 6. Contrato 3: `RedemptionManager.sol`

### 6.1 Propósito

`RedemptionManager` encapsula el flujo de redención física en 2 fases (ADR-017):

1. **`iniciarRedencion`** — el comprador (tier >= 2) registra la intención de redimir tokens. Los tokens NO se transfieren. Se registra un lock lógico contable en `_tokensLockedFor[loteId][comprador]`. Invariante crítica: `_tokensLockedFor[loteId][buyer] <= IERC1155(assetVault).balanceOf(buyer, loteId)`.
2. **`confirmarExportacion`** — Oracle registra el DUE (INICIADA → EN_EXPORTACION). NO quema tokens aún.
3. **`completarRedencion`** — Oracle recibe BL/AWB. Quema tokens vía `assetVault.burnForRedemption` (EN_EXPORTACION → COMPLETADA).
4. (alternativa) **`cancelarRedencion`** — libera el lock contable sin quemar. INICIADA o EN_EXPORTACION → CANCELADA.

**Modelo Option B — Lock Acumulator:** los tokens permanecen en el wallet del comprador todo el tiempo. El lock es contable — `_tokensLockedFor` previene la doble-redencion sin requerir transfers al escrow. Las funciones `lockForRedemption`, `burnRedemptionTokens` y `returnRedemptionTokens` **NO existen**.

El contrato **no mueve USDC**.

### 6.2 Herencias OpenZeppelin (orden C3)

```
contract RedemptionManager is
    AccessControlDefaultAdminRules,
    ReentrancyGuard,
    Pausable,
    IRedemptionManager
```

- `AccessControlDefaultAdminRules` (FIX M-08): delay de 3 días para transferencias de DEFAULT_ADMIN_ROLE. Constante `ADMIN_TRANSFER_DELAY = 3 days`.
- `Pausable`: solo bloquea `iniciarRedencion` (whenNotPaused). `confirmarExportacion`, `completarRedencion` y `cancelarRedencion` NO usan whenNotPaused — las operaciones en curso deben poder resolverse durante un incidente (§6.13.8).
- `ReentrancyGuard`: `iniciarRedencion` y `completarRedencion` son nonReentrant (external call a AssetVault).

### 6.3 Roles definidos

| Rol | Identidad típica | Funciones que controla |
|---|---|---|
| `DEFAULT_ADMIN_ROLE` | Safe multi-sig 2-de-3 | Gestión de roles, `unpause`. Con delay 3 días (FIX M-08) |
| `COMPLIANCE_OFFICER_ROLE` | Compliance officer (titular + suplente) | `cancelarRedencion` siempre, `pause` (junto con DEFAULT_ADMIN_ROLE — ADR-016) |
| `ORACLE_ROLE` | Safe multi-sig 2-de-3 | `confirmarExportacion`, `completarRedencion`, `cancelarRedencion` siempre |

> `ADMIN_ROLE` y `BACKEND_SIGNER_ROLE` **no aplican** en RedemptionManager.
> `iniciarRedencion` es llamada directamente por el comprador (`msg.sender`) — no requiere rol.
> **ADR-016 pause asymmetry:** `pause()` = COMPLIANCE_OFFICER_ROLE OR DEFAULT_ADMIN_ROLE. `unpause()` = solo DEFAULT_ADMIN_ROLE.

### 6.4 Constantes

```solidity
bytes32 public constant ORACLE_ROLE             = keccak256("ORACLE_ROLE");
bytes32 public constant COMPLIANCE_OFFICER_ROLE = keccak256("COMPLIANCE_OFFICER_ROLE");

/// @notice Delay para transferencias de DEFAULT_ADMIN_ROLE (FIX M-08).
uint48 public constant ADMIN_TRANSFER_DELAY = 3 days;

/// @notice Longitud máxima del número DUE en caracteres.
uint256 public constant MAX_DUE_NUMERO_LENGTH = 64;

/// @notice Tiempo tras el cual el comprador puede self-cancelar una redención stuck (ADR-015).
/// @dev 60 días balancea export-time Bolivia→UE (30-45d + margen) con consumer protection.
///      Cierra findings RM-06 + RM-07 (HIGH) del audit.
uint256 public constant REDENCION_TIMEOUT = 60 days;
```

### 6.5 Enums

```solidity
/// @notice Estados del ciclo de redención.
/// @dev Transiciones válidas (ADR-017):
///      INICIADA → EN_EXPORTACION → COMPLETADA
///      INICIADA → CANCELADA (por Oracle, Compliance o buyer post-timeout)
///      EN_EXPORTACION → CANCELADA (por Oracle o Compliance — ADR-017 checkpoint operacional)
enum EstadoRedencion {
    INICIADA,         // 0 - lock contable registrado; tokens en wallet del comprador
    EN_EXPORTACION,   // 1 - DUE emitida; burn pendiente
    COMPLETADA,       // 2 - tokens quemados via burnForRedemption (terminal)
    CANCELADA         // 3 - lock liberado, sin burn (terminal)
}
```

### 6.6 Structs

#### 6.6.1 `Redencion`

```solidity
/// @notice Datos de una redención individual.
struct Redencion {
    address comprador;          // wallet del comprador (quien inicia la redención)
    uint256 loteId;
    uint256 cantidadTokens;
    bytes32 datosEnvioHash;     // hash de datos de envío (dirección, contacto, instrucciones)
    EstadoRedencion estado;
    string dueNumero;           // número DUE (Declaración Única de Exportación) — max 64 chars
    bytes32 hashBLAWB;          // hash del Bill of Lading o Air Waybill
    uint64 createdAt;
    uint64 completedAt;
    bytes32 cancelReason;       // motivo de cancelación (bytes32, no string)
}
```

> **Removido respecto a la versión anterior:** `redemptionId` (se almacena como clave del mapping, no en el struct), `hashDUE` (reemplazado por `dueNumero` string — ADR-017), `exportadaAt` / `canceladaAt` (consolidados en `completedAt`). `buyer` renombrado a `comprador`.
>
> **ADR-017:** `hashDUE` no existe. El número DUE se almacena como `string dueNumero` (número legible de aduana). El hash BL/AWB llega en `completarRedencion`.

### 6.7 State variables

```solidity
/// @notice Dirección de AssetVault (immutable).
IAssetVault public immutable assetVault;

/// @notice Dirección de IdentityRegistry (immutable).
IIdentityRegistry public immutable identityRegistry;

/// @notice Storage de redenciones por ID (privado, acceso via getRedencion).
mapping(uint256 => Redencion) private _redenciones;

/// @notice Próximo ID de redención a asignar (comienza en 1).
uint256 private _nextRedencionId;

/// @notice Acumulador de tokens lockeados lógicamente por loteId y comprador (Modelo Option B).
/// @dev Invariante: _tokensLockedFor[loteId][buyer] <= IERC1155(assetVault).balanceOf(buyer, loteId).
///      Incrementa en iniciarRedencion. Decrementa en completarRedencion / cancelarRedencion.
mapping(uint256 loteId => mapping(address buyer => uint256)) private _tokensLockedFor;
```

### 6.8 Eventos

```solidity
event RedencionIniciada(
    uint256 indexed redencionId,
    address indexed comprador,
    uint256 indexed loteId,
    uint256 cantidadTokens,
    bytes32 datosEnvioHash
);

/// @dev ADR-017: actor indexed para forensics (qué Safe signer registró el DUE).
event RedencionEnExportacion(
    uint256 indexed redencionId,
    address indexed actor,
    string dueNumero            // número DUE legible (max 64 chars); NO hashDUE
);

/// @dev ADR-017: actor indexed para forensics.
event RedencionCompletada(
    uint256 indexed redencionId,
    address indexed actor,
    bytes32 hashBLAWB
);

/// @dev actor indexed para forensics (Oracle, Compliance, o buyer post-timeout).
event RedencionCancelada(
    uint256 indexed redencionId,
    address indexed actor,
    bytes32 reason              // bytes32, no string
);

/// @notice Emitido al pausar de emergencia (ADR-016).
event EmergencyPaused(address indexed actor, uint64 timestamp);

/// @notice Emitido al despausar (ADR-016).
event EmergencyUnpaused(address indexed actor, uint64 timestamp);
```

### 6.9 Custom errors

```solidity
error ZeroAddress();
error CannotRedeem();               // identityRegistry.canRedeem devolvió false (tier, sancionado, frozen, expirado)
error LoteNotFound(uint256 loteId); // lote no existe (productorSRL == address(0))
error LoteNotInAlmacenado();        // lote no está en ALMACENADO ni REDENCION_PARCIAL
error CantidadCero();
error CantidadExcedeSupply();       // defensa-in-depth vs totalSupply (RM-19)
error BalanceInsuficiente();        // available balance (balance - locked) < cantidadTokens
error OnlyAuthorizedCanceler();     // no es Oracle, Compliance, ni buyer-after-timeout
error UnauthorizedPauseActor();     // pause() por caller sin rol adecuado (ADR-016)
error NotInExportacion();           // completarRedencion cuando estado != EN_EXPORTACION
error InvalidHash();                // datosEnvioHash o hashBLAWB == bytes32(0)
error RedencionNotIniciada();       // comprador == address(0) en la redencion
error RedencionAlreadyFinalized();  // estado ya es COMPLETADA o CANCELADA (o no es INICIADA para confirmar)
error EmptyDUE();
error DUENumeroTooLong();           // dueNumero.length > MAX_DUE_NUMERO_LENGTH (64)
error EmptyReason();                // reason == bytes32(0) en cancelarRedencion
```

### 6.10 Modifiers

El contrato real no usa modifiers custom para KYC/estado. Modifiers heredados que sí se usan:

- `onlyRole(ROLE)` — de `AccessControlDefaultAdminRules`
- `nonReentrant` — de `ReentrancyGuard` (en `iniciarRedencion`, `completarRedencion`, `cancelarRedencion`)
- `whenNotPaused` — de `Pausable` (solo en `iniciarRedencion`)

### 6.11 Function signatures

#### 6.11.1 Construcción

```solidity
/// @notice Inicializa con dependencias y roles operativos.
/// @dev FIX M-08: admin asignado vía AccessControlDefaultAdminRules con delay de 3 días.
/// @param admin DEFAULT_ADMIN_ROLE (Safe Wyoming 2-de-3).
/// @param oracleSafe Recibe ORACLE_ROLE.
/// @param complianceOfficer Recibe COMPLIANCE_OFFICER_ROLE.
/// @param complianceOfficerSuplente Recibe COMPLIANCE_OFFICER_ROLE.
/// @param _assetVault Dirección de AssetVault (immutable).
/// @param _identityRegistry Dirección de IdentityRegistry (immutable).
constructor(
    address admin,
    address oracleSafe,
    address complianceOfficer,
    address complianceOfficerSuplente,
    IAssetVault _assetVault,
    IIdentityRegistry _identityRegistry
) AccessControlDefaultAdminRules(ADMIN_TRANSFER_DELAY, admin);
```

#### 6.11.2 Mutators

```solidity
/// @notice Inicia una redención registrando un lock contable (Modelo Option B).
/// @dev nonReentrant + whenNotPaused. Llamado directamente por el comprador (msg.sender).
///      NO requiere BACKEND_SIGNER_ROLE — el comprador firma la tx directamente.
///      Checks: canRedeem(msg.sender), cantidadTokens > 0, datosEnvioHash != 0,
///              lote existe, lote en ALMACENADO o REDENCION_PARCIAL,
///              availableBalance >= cantidadTokens.
///      Effects: incrementa _tokensLockedFor[loteId][msg.sender] + crea Redencion INICIADA.
///      NO transfiere tokens (Modelo Option B).
/// @param loteId Lote a redimir. Debe estar en ALMACENADO o REDENCION_PARCIAL.
/// @param cantidadTokens Tokens a redimir. Debe ser > 0 y <= availableBalance(msg.sender, loteId).
/// @param datosEnvioHash Hash de los datos de envío.
/// @return redencionId ID asignado a la nueva redención.
function iniciarRedencion(
    uint256 loteId,
    uint256 cantidadTokens,
    bytes32 datosEnvioHash
) external returns (uint256 redencionId);

/// @notice Registra la emisión del DUE (fase 1 de 2 — ADR-017).
/// @dev Solo ORACLE_ROLE. NO usa whenNotPaused.
///      Transición INICIADA → EN_EXPORTACION. NO quema tokens todavía.
/// @param redencionId ID de la redención.
/// @param dueNumero Número DUE (Declaración Única de Exportación), max 64 chars.
function confirmarExportacion(uint256 redencionId, string calldata dueNumero) external;

/// @notice Completa la redención al recibir BL/AWB — quema tokens del comprador (fase 2 de 2 — ADR-017).
/// @dev Solo ORACLE_ROLE. nonReentrant. NO usa whenNotPaused.
///      Transición EN_EXPORTACION → COMPLETADA.
///      Decrementa _tokensLockedFor y llama assetVault.burnForRedemption(comprador, loteId, cantidad).
/// @param redencionId ID de la redención (debe estar en EN_EXPORTACION).
/// @param hashBLAWB Hash del Bill of Lading o Air Waybill.
function completarRedencion(uint256 redencionId, bytes32 hashBLAWB) external;

/// @notice Cancela una redención en curso, liberando el lock contable (ADR-015).
/// @dev nonReentrant. NO usa whenNotPaused. NO requiere onlyRole — access control inline:
///      - ORACLE_ROLE: siempre puede cancelar.
///      - COMPLIANCE_OFFICER_ROLE: siempre puede cancelar (motivos regulatorios).
///      - msg.sender == comprador && block.timestamp >= createdAt + REDENCION_TIMEOUT: escape valve (RM-06).
///      Cancellable desde INICIADA o EN_EXPORTACION (ADR-017).
///      Decrementa _tokensLockedFor. NO quema tokens.
/// @param redencionId ID.
/// @param reason Hash del motivo de cancelación (bytes32). No puede ser bytes32(0).
function cancelarRedencion(uint256 redencionId, bytes32 reason) external;

/// @notice Pausa de emergencia. Bloquea únicamente iniciarRedencion.
/// @dev ADR-016: COMPLIANCE_OFFICER_ROLE OR DEFAULT_ADMIN_ROLE. Emite EmergencyPaused.
///      confirmarExportacion, completarRedencion y cancelarRedencion NO se bloquean.
function pause() external;

/// @notice Despausa post-incidente.
/// @dev ADR-016: solo DEFAULT_ADMIN_ROLE. Emite EmergencyUnpaused.
function unpause() external;
```

#### 6.11.3 View functions

```solidity
/// @notice Devuelve el struct completo de una redención.
function getRedencion(uint256 redencionId) external view returns (Redencion memory);

/// @notice Devuelve el próximo ID de redención a asignar.
function getNextRedencionId() external view returns (uint256);

/// @notice Devuelve el balance disponible del comprador para nuevas redenciones.
/// @dev Calcula: balanceOf(buyer, loteId) - _tokensLockedFor[loteId][buyer].
/// @param buyer Wallet del comprador.
/// @param loteId ID del lote.
/// @return Tokens disponibles para iniciar nuevas redenciones.
function availableBalance(address buyer, uint256 loteId) external view returns (uint256);

/// @notice Devuelve la cantidad de tokens lockeados de un comprador para un lote.
/// @dev Valor > 0 mientras haya redenciones en estado INICIADA activas.
/// @param buyer Wallet del comprador.
/// @param loteId ID del lote.
/// @return Tokens actualmente lockeados.
function tokensLockedFor(address buyer, uint256 loteId) external view returns (uint256);
```

> **Removidas:** `getEstadoRedencion`, `getRedencionesByBuyer`, `getRedencionesByLote` — no existen en el contrato real. El estado se obtiene de `getRedencion(id).estado`.

### 6.12 Overrides

No requiere overrides custom (`AccessControlDefaultAdminRules + ReentrancyGuard + Pausable` no presenta conflictos C3).

### 6.13 Consideraciones de seguridad

1. **Reentrancy (Modelo Option B):**
   - `iniciarRedencion`: nonReentrant (aunque en Option B no hay external calls mutantes post-effects, se mantiene por defense-in-depth).
   - `completarRedencion`: nonReentrant + CEI estricto — decrementar _tokensLockedFor ANTES del burn (external call).
   - `cancelarRedencion`: nonReentrant por defense-in-depth (RM-14).

2. **Lock acumulator invariante:**
   - `_tokensLockedFor[loteId][buyer] <= IERC1155(assetVault).balanceOf(buyer, loteId)` garantizado en `iniciarRedencion`.
   - `availableBalance` expone el balance disponible para nuevas redenciones.

3. **State transitions:**
   - Transiciones validadas inline en cada mutator con errores específicos.
   - `cancelarRedencion` acepta INICIADA o EN_EXPORTACION (ADR-017: checkpoint operacional).

4. **Timeout escape valve (ADR-015 / RM-06+07):**
   - El comprador puede auto-cancelar tras `REDENCION_TIMEOUT = 60 días` si el Oracle Safe desaparece.
   - Protección para consumer ante lockout permanente del lock contable.

5. **Cancelación post-exportación (ADR-017):**
   - Permitida desde EN_EXPORTACION por Oracle o Compliance (si goods se detienen en aduana post-DUE).
   - El backend debe propagar la cancelación al sistema de tracking off-chain.

6. **No revalidar KYC en completar/cancelar:**
   - La validación KYC solo ocurre en `iniciarRedencion`. Un envío físico ya en curso no puede revertirse por pérdida de KYC posterior.

7. **Pause asymmetry (ADR-016):**
   - `pause()` bloquea solo `iniciarRedencion` (whenNotPaused).
   - `confirmarExportacion`, `completarRedencion` y `cancelarRedencion` NO usan whenNotPaused — las redenciones en curso deben poder resolverse durante un incidente.
   - `pause()` = COMPLIANCE_OFFICER_ROLE OR DEFAULT_ADMIN_ROLE.
   - `unpause()` = solo DEFAULT_ADMIN_ROLE.

8. **§6.13.8 — Funciones NO bloqueadas por pause:**
   - `confirmarExportacion`, `completarRedencion`, `cancelarRedencion`.
   - Diseño deliberado: el Oracle Safe es responsable de no confirmar exportaciones durante un incidente que afecte la cadena de custodia física.

---

## 7. FASE 2 — `LabRegistry.sol` (reservado, ADR-010)

> **NO ES PARTE DEL MVP.** LabRegistry y todo lo relativo a QualityAttestation (`confirmarCalidad`,
> el estado `QUALITY_ATTESTED`, la dependencia `ILabRegistry labRegistry` en AssetVault) están
> reservados para FASE 2. El contrato vive en `packages/contracts/src/phase2/` y NO se deployará
> junto con el MVP. Esta sección se mantiene como referencia de diseño para cuando se active.

### 7.1 Propósito (FASE 2)

`LabRegistry` mantendrá la whitelist de laboratorios certificados autorizados a firmar `QualityAttestation`s. Cada lab tiene una dirección de firma (clave pública ECDSA registrada on-chain), una jurisdicción ISO, especializaciones (palinología, NMR, C4, residuos), un hash de su acreditación documental y un flag `active`. Consultado por `AssetVault.confirmarCalidad` para validar (1) que cada lab está autorizado en su especialización y (2) que la firma sobre el digest del reporte es válida.

Política de la plataforma: mínimo 2 labs en whitelist al lanzamiento (recomendado 1 boliviano + 1 europeo: IBNORCA + Eurofins). Cada `QualityAttestation` debe ser firmada por al menos 2 labs (`MIN_LABS_PARA_ATTESTATION`), con tests independientes que se contrastan.

### 7.2 Herencias OpenZeppelin (orden C3)

```
contract LabRegistry is
    AccessControl,
    EIP712
```

- `EIP712` se incluye para construir el domain separator usado en la verificación de firmas estructuradas (más seguro y standards-compliant que firmar hashes raw).
- No incluye `Pausable`: las desactivaciones individuales (`deactivateLab`) cumplen el rol de pausa granular.

### 7.3 Roles definidos

| Rol | Identidad típica | Funciones que controla |
|---|---|---|
| `DEFAULT_ADMIN_ROLE` | Safe multi-sig 2-de-3 | Gestión de roles |
| `ADMIN_ROLE` | Safe multi-sig 2-de-3 | `addLab`, `updateLabSpecializations` |
| `COMPLIANCE_OFFICER_ROLE` | Compliance officer | `deactivateLab`, `reactivateLab` |

### 7.4 Constantes

```solidity
bytes32 public constant ADMIN_ROLE              = keccak256("ADMIN_ROLE");
bytes32 public constant COMPLIANCE_OFFICER_ROLE = keccak256("COMPLIANCE_OFFICER_ROLE");

// EIP-712 typehash para LabReport
bytes32 public constant LAB_REPORT_TYPEHASH = keccak256(
    "LabReport(uint256 loteId,bytes32 reportHash,uint64 testedAt,address lab)"
);
```

### 7.5 Enums

```solidity
/// @notice Especializaciones reconocidas para labs.
/// @dev Se usa en LabRegistry.isLabCertifiedFor.
enum Specialization {
    PALINOLOGIA,        // 0 - microscopía de polen
    NMR,                // 1 - spectroscopy
    C4_SUGAR,           // 2 - AOAC 998.12 (jarabe caña/maíz)
    PESTICIDAS,         // 3 - cromatografía residuos
    ANTIBIOTICOS,       // 4 - residuos veterinarios
    HMF_DIASTASA,       // 5 - frescura / procesamiento
    HUMEDAD,            // 6 - calidad estándar
    OTROS               // 7 - reservado para extensiones documentadas off-chain
}
```

### 7.6 Structs

#### 7.6.1 `Lab`

```solidity
/// @notice Datos de un laboratorio certificado.
/// @dev Storage layout:
///      slot 0 (packed): signerAddress (20) + jurisdiction (2) + active (1) +
///                       addedAt (8) + 1 byte padding = 31 bytes
///      slot 1:          deactivatedAt (8) + ...
///      slot 2:          nameHash (32)
///      slot 3:          accreditationHash (32)
///      slot 4+:         specializations[] dynamic array
struct Lab {
    address signerAddress;       // 20 bytes - clave pública del lab
    bytes2  jurisdiction;        // 2 bytes - ISO 3166-1 alpha-2
    bool    active;              // 1 byte
    uint64  addedAt;             // 8 bytes
    // 1 byte padding en slot 0
    uint64  deactivatedAt;       // 8 bytes (separado para readability)
    bytes32 nameHash;            // SHA-256 del nombre legal
    bytes32 accreditationHash;   // SHA-256 del paquete de credenciales (ISO 17025, etc.)
    Specialization[] specializations;
}
```

### 7.7 State variables

```solidity
/// @notice Storage de labs por signer address.
mapping(address signer => Lab) public labs;

/// @notice Lista de signers registrados (para enumeración).
address[] private _labSigners;

/// @notice Quick lookup: existencia de un signer.
mapping(address signer => bool) private _isRegistered;

/// @notice Mapping rápido para isLabCertifiedFor.
mapping(address signer => mapping(Specialization => bool)) private _certifiedFor;
```

### 7.8 Eventos

```solidity
event LabAdded(
    address indexed signerAddress,
    bytes2 jurisdiction,
    Specialization[] specializations,
    bytes32 nameHash,
    bytes32 accreditationHash
);

event LabDeactivated(address indexed signerAddress, string motivo);

event LabReactivated(address indexed signerAddress);

event LabSpecializationsUpdated(address indexed signerAddress, Specialization[] newSpecializations);
```

### 7.9 Custom errors

```solidity
error ZeroAddress();
error LabAlreadyRegistered(address signer);
error LabNotRegistered(address signer);
error LabAlreadyActive(address signer);
error LabAlreadyInactive(address signer);
error EmptySpecializations();
error InvalidJurisdiction(bytes2 jurisdiction);
error InvalidSignature();
```

### 7.10 Modifiers

```solidity
/// @notice Reverts si el lab no está registrado.
modifier labRegistered(address signer);

/// @notice Reverts si el lab no está activo (registrado y active == true).
modifier labActive(address signer);
```

### 7.11 Function signatures

#### 7.11.1 Construcción

```solidity
/// @notice Inicializa el contrato con EIP712 domain.
/// @param _name Nombre del dominio EIP-712 (e.g. "TokenizacionMielLabRegistry").
/// @param _version Versión del dominio (e.g. "1").
constructor(string memory _name, string memory _version);
```

#### 7.11.2 Mutators

```solidity
/// @notice Agrega un nuevo lab a la whitelist.
/// @dev Solo ADMIN_ROLE. Reverts si ya está registrado.
/// @param signerAddress Dirección de firma del lab (clave pública ECDSA).
/// @param jurisdiction ISO 3166-1 alpha-2.
/// @param specializations Array no vacío de especializaciones.
/// @param nameHash SHA-256 del nombre legal del lab.
/// @param accreditationHash SHA-256 del paquete de acreditación documental.
function addLab(
    address signerAddress,
    bytes2 jurisdiction,
    Specialization[] calldata specializations,
    bytes32 nameHash,
    bytes32 accreditationHash
) external;

/// @notice Desactiva un lab. No lo borra (mantiene audit trail).
/// @dev Solo COMPLIANCE_OFFICER_ROLE.
/// @param signerAddress Dirección del lab.
/// @param motivo Razón corta.
function deactivateLab(address signerAddress, string calldata motivo) external;

/// @notice Reactiva un lab previamente desactivado.
/// @dev Solo COMPLIANCE_OFFICER_ROLE.
function reactivateLab(address signerAddress) external;

/// @notice Actualiza las especializaciones de un lab (e.g. nueva acreditación).
/// @dev Solo ADMIN_ROLE. Reemplaza completamente el array.
function updateLabSpecializations(
    address signerAddress,
    Specialization[] calldata newSpecializations
) external;
```

#### 7.11.3 View functions

```solidity
/// @notice Devuelve los datos completos de un lab.
function getLab(address signerAddress) external view returns (Lab memory);

/// @notice Devuelve true si el lab está activo (registrado + active=true).
function isActive(address signerAddress) external view returns (bool);

/// @notice Devuelve true si el lab está certificado para una especialización dada.
function isLabCertifiedFor(address signerAddress, Specialization spec) external view returns (bool);

/// @notice Devuelve la lista de signers registrados (para enumeración off-chain).
function getAllLabs() external view returns (address[] memory);

/// @notice Verifica firma de un lab sobre un report.
/// @dev Construye el digest EIP-712 a partir de (loteId, reportHash, testedAt, lab) y verifica
///      que la firma corresponda a `lab.signerAddress`.
/// @param lab Dirección del signer esperado.
/// @param loteId Lote al que pertenece el report.
/// @param reportHash SHA-256 del reporte completo.
/// @param testedAt Unix timestamp del test.
/// @param signature ECDSA signature (65 bytes: r,s,v).
/// @return ok True si la firma es válida y proviene del signer registrado.
function verifyAttestationSignature(
    address lab,
    uint256 loteId,
    bytes32 reportHash,
    uint64 testedAt,
    bytes calldata signature
) external view returns (bool ok);

/// @notice Devuelve el digest EIP-712 que el lab debe firmar (utility para frontend / labs).
function getLabReportDigest(
    uint256 loteId,
    bytes32 reportHash,
    uint64 testedAt,
    address lab
) external view returns (bytes32);
```

### 7.12 Overrides

`EIP712` ya provee `_domainSeparatorV4()` y `_hashTypedDataV4()` internos; no requiere overrides custom.

### 7.13 Consideraciones de seguridad

1. **Signature replay:**
   - La verificación firma sobre `(loteId, reportHash, testedAt, lab)` + domain separator (EIP-712 contiene chainId + contract address). No es replayable cross-chain ni cross-contract.
   - Anti-replay dentro del mismo lote/lab se garantiza en `AssetVault.confirmarCalidad` (vía `_attestationConsumed`).

2. **Compromiso de clave de lab:**
   - Si la clave privada de un lab se compromete, el atacante puede firmar attestations falsas.
   - Mitigación: `deactivateLab` por compliance officer. Las attestations ya confirmadas on-chain quedan irreversibles, pero el lab no puede firmar nuevas.

3. **Especializaciones inconsistentes:**
   - Tests de calidad sin lab certificado para ellos rompen `confirmarCalidad`. La validación de pares (test ↔ lab) ocurre en `AssetVault` (no aquí), usando `isLabCertifiedFor`.

4. **Permisos solapados:**
   - `ADMIN_ROLE` puede actualizar specializations; `COMPLIANCE_OFFICER_ROLE` puede deactivar. Diseño deliberado: tracks separados (cambio operacional vs decisión disciplinaria).

5. **Granular pause vs global pause:**
   - El contrato no tiene `pause()` global. Para "pausar" un lab problemático, usar `deactivateLab`. Para detener el oráculo de calidad completo, pausar `AssetVault` (las funciones que consumen LabRegistry).

6. **Address reuse:**
   - Re-añadir un lab previamente removido (mismo `signerAddress`) revierte con `LabAlreadyRegistered`. Decisión: si un lab necesita re-incorporación, se usa `reactivateLab`. Si rota su clave, se registra una nueva entrada con nuevo signer.

7. **Cantidad mínima de labs:**
   - El contrato no enforce el mínimo `MIN_LABS_PARA_ATTESTATION` (eso vive en `AssetVault.confirmarCalidad`).

---

## 8. Interfaces (`I*.sol`)

Cada contrato expone su interfaz pública en un archivo separado `interfaces/I<Nombre>.sol` para que otros contratos (y los abis del frontend) consuman sin acoplarse a la implementación. Las interfaces declaran únicamente las funciones `external` (no las `public` que también son external por convención Solidity), los eventos y los errors.

### 8.1 `IAssetVault.sol`

Declara (MVP):
- `crearLote`, `comprar`, `confirmarCosecha`, `confirmarAlmacenamiento`, `marcarFallido`, `reembolsarLoteFallido`, `finalizarReembolso`
- `setRedemptionManager`, `burnForRedemption`
- `liberarReservaTecnica`
- `pause`, `unpause`
- Views: `lotes`, `kgDisponibles`, `reservaTecnicaActual`, `totalSupply`
- Eventos y errors (ver §4.8, §4.9)
- Enums `LoteEstado`, `TipoCertificadoOrigen` y struct `LoteMiel` declarados en la interfaz

> **FASE 2 removido:** `confirmarCalidad`, `lockForRedemption`, `burnRedemptionTokens`, `returnRedemptionTokens`, `QualityAttestation`.

### 8.2 `IIdentityRegistry.sol`

Declara (MVP):
- `setKYC`, `revokeKYC`, `markSanctioned`, `unmarkSanctioned`, `freezeAddress`, `unfreezeAddress`
- `pause`, `unpause`
- Views: `getTier`, `isSanctioned`, `isFrozen`, `isExpired`, `canMint`, `canRedeem`, `getJurisdiction`, `getKYCData`
- Eventos y errors (ver §5.8, §5.9)
- Struct `KYCData` declarado en la interfaz

> **Removidos:** `checkCompliance`, `isCompliant`, `getIdentity`, `setPlumeArcBridge`.

### 8.3 `IRedemptionManager.sol`

Declara (MVP):
- `iniciarRedencion` (sin parámetro buyer — es msg.sender)
- `confirmarExportacion`, `completarRedencion`, `cancelarRedencion`
- `pause`, `unpause`
- Views: `getRedencion`, `getNextRedencionId`, `availableBalance`, `tokensLockedFor`
- Constantes públicas: `MAX_DUE_NUMERO_LENGTH`, `REDENCION_TIMEOUT`
- Eventos y errors (ver §6.8, §6.9)
- Enum `EstadoRedencion` y struct `Redencion` declarados en la interfaz

> **Removidos:** `getEstadoRedencion`, `getRedencionesByBuyer`, `getRedencionesByLote`.

### 8.4 `ILabRegistry.sol` (FASE 2 — reservado, ADR-010)

> Reservado. No se genera ni deploya en MVP. Ver §7 para referencia de diseño.

---

## 9. Libraries

### 9.1 `ComplianceConstants.sol`

Ver sección 2. No contiene funciones; solo `constant` declarations consumidas por `AssetVault`, `IdentityRegistry`, `RedemptionManager`.

### 9.2 `DocumentHashes.sol`

Helpers puros para hashing y validación de documentos. Sin estado.

**Funciones internas:**

```solidity
/// @notice Verifica que un hash no sea zero (placeholder common error).
function requireNonZero(bytes32 hash) internal pure;

/// @notice Hashea (concatenación) de múltiples hashes documentales para audit trail compacto.
/// @dev Util para reembolsos pro-rata o snapshots multi-doc.
function combineHashes(bytes32[] memory hashes) internal pure returns (bytes32);

/// @notice Genera el commitment de un applicantId externo (Sumsub) con sal del backend.
/// @dev Solo se usa off-chain (el backend computa antes de llamar a setKYC).
///      Aquí solo definido como referencia.
function computeExternalRefHash(string memory applicantId, bytes32 salt) internal pure returns (bytes32);
```

### 9.3 `QualityRules.sol`

Helpers puros para lógica de calidad monofloral. Sin estado.

**Funciones internas:**

```solidity
/// @notice Computa si una QualityAttestation cumple los criterios de monofloral.
/// @dev Regla: pollenPct >= MIN_POLLEN_PERCENTAGE_MONOFLORAL (45) && nmrPassed && c4Passed && residuesPassed.
function isMonofloral(
    uint8 pollenPercentage,
    bool nmrPassed,
    bool c4Passed,
    bool residuesPassed
) internal pure returns (bool);

/// @notice Valida que el array de specializations cubra los tests reportados en la attestation.
/// @dev Helper consumido por AssetVault.confirmarCalidad para pre-validación.
function requiredSpecializationsForAttestation()
    internal
    pure
    returns (Specialization[] memory);
```

---

## 10. Decisiones derivadas y conflictos detectados

Esta sección recoge decisiones de diseño que ya están fijadas en estas specs pero que se desviaron levemente de la arquitectura, y conflictos que el implementador debe resolver con la guía propuesta antes de codear.

### 10.1 Decisiones derivadas (resueltas en estas specs)

| # | Decisión | Razón |
|---|---|---|
| D1 | El **loteId** es externo — el caller de `crearLote` elige el ID. No hay counter interno monotónico en AssetVault. | Permite coordinación off-chain del ID antes del deploy (align con base de datos y UI). |
| D2 | `TREASURY_SRL_ROLE` ejecuta **`liberarReservaTecnica` on-chain**, que transfiere USDC directamente desde el escrow del contrato. | Escrow total (FIX H-01): USDC vive en el contrato hasta liberación explícita. No hay movimiento off-chain. |
| D3 | `RedemptionManager` recibe las dependencias por constructor (`IAssetVault`, `IIdentityRegistry`). `AssetVault` recibe `redemptionManager` post-deploy vía `setRedemptionManager` (one-time, callable solo por DEFAULT_ADMIN_ROLE). **Opción B** (address inmutable one-time) sobre **Opción A** (rol dedicado). | Evita que accidentalmente se otorgue el rol a más de una dirección. |
| D4 | Los **structs y enums** se declaran directamente en las **interfaces** (`IAssetVault.sol`, `IIdentityRegistry.sol`, `IRedemptionManager.sol`), no en los contratos concretos. | Las interfaces son el contrato público; los tipos deben vivir ahí para que los consumidores no dependan de la implementación. |
| D5 | **EIP-712** se usa solo en `LabRegistry` (FASE 2). El MVP no lo usa. | Solo aporta donde hay firmas cross-party. |
| D6 | **Option B — Lock Acumulator**: tokens permanecen en el wallet del comprador. El lock es contable en `_tokensLockedFor`. El burn ocurre en `completarRedencion` vía `burnForRedemption`. | Mantiene el invariante "NUNCA P2P" de AssetVault sin excepción. Elimina complejidad de escrow + devolución de tokens. |
| D7 | **`ERC1155Pausable`** + **`Pausable`** en los 3 contratos. Asimetría ADR-016: `pause()` = COMPLIANCE_OFFICER_ROLE OR DEFAULT_ADMIN_ROLE; `unpause()` = solo DEFAULT_ADMIN_ROLE. | Defensa cruzada: si Compliance está comprometido, el Safe puede pausar igual. Unpause requiere decisión deliberada del Safe. |
| D8 | **URI base** recibida como parámetro en constructor. Sin URI per-lote en MVP. | Simplifica MVP. |
| D9 | **Reentrancy guards** en funciones que llaman contratos externos: AssetVault → USDC, AssetVault → IdentityRegistry, RedemptionManager → AssetVault. | Defense in depth. |
| D10 | **Compliance officer** implementado como dos wallets (titular + suplente) con `COMPLIANCE_OFFICER_ROLE`. No multi-sig dedicado. | Responsividad ante emergencias. Safe 2-de-3 cubre acciones críticas. |
| D11 | **ADR-017 2-phase export state machine**: `confirmarExportacion` (INICIADA→EN_EXPORTACION, NO burn) + `completarRedencion` (EN_EXPORTACION→COMPLETADA, burn). | Separar el registro del DUE del burn final, reflejando la realidad operacional: el DUE se emite días antes de que el shipment salga. |
| D12 | **ADR-015 timeout policy**: `REDENCION_TIMEOUT = 60 días`. El comprador puede auto-cancelar tras ese período si el Oracle no avanza. `cancelarRedencion` acepta INICIADA o EN_EXPORTACION. | Cierra RM-06 + RM-07 (HIGH): un Lock acumulator sin escape valve para el comprador es inaceptable en consumer protection. |

### 10.2 Conflicts detectados

**CONFLICT 1: `TREASURY_SRL_ROLE` on-chain vs off-chain. — RESUELTO**

> **Resolución implementada:** `TREASURY_SRL_ROLE` ejecuta `liberarReservaTecnica()` on-chain. El USDC vive en el contrato (escrow total, FIX H-01) y se transfiere directamente al productor SRL en esa llamada. No hay flujo off-chain. Ver D2 en §10.1.

**CONFLICT 2: cómo se cablea `RedemptionManager` ↔ `AssetVault`. — RESUELTO**

> **Resolución implementada:** Opción B — `setRedemptionManager(address)` callable una sola vez por DEFAULT_ADMIN_ROLE. `burnForRedemption` revierte con `RedemptionManagerNotSet` si no fue configurado, y con `OnlyRedemptionCanBurn` si el caller no es la dirección configurada. Ver D3 en §10.1.

**CONFLICT 3: storage layout de `QualityAttestation`. — FASE 2 (ADR-010)**

> No aplica en MVP. `QualityAttestation` y `LabRegistry` son FASE 2. Se retoma cuando LabRegistry se active.

**CONFLICT 4: `reembolsarLoteFallido` requiere USDC líquido en `AssetVault`. — RESUELTO**

> **Resolución implementada:** modelo escrow total (FIX H-01). El USDC del comprador ingresa al contrato en `comprar()`. Si el lote FALLA en PREVENTA, `montoNetoPendiente + reservaTecnicaUSDC` = 100% del pago queda en el contrato disponible para reembolso on-chain sin necesidad de fondear externamente.

**CONFLICT 5: jurisdicción ISO en `bytes2` vs `bytes3`. — RESUELTO**

> `bytes2` (ISO 3166-1 alpha-2) implementado y consistente en todos los contratos.

**CONFLICT 6: confirmación de calidad. — FASE 2 (ADR-010)**

> No aplica en MVP. Se retoma con `LabRegistry` en FASE 2.

**CONFLICT 7: blast radius de `BACKEND_SIGNER_ROLE`. — ABIERTO**

> Un único `BACKEND_SIGNER_ROLE` en MVP (compras + KYC). Separación en `MINTER_SIGNER` / `KYC_SIGNER` reservada para FASE 2. Rotación trimestral mínima documentada en runbook de operaciones.

**CONFLICT 8: revocación de KYC retroactiva. — RESUELTO**

> La redención se completa si el KYC se revoca después de `iniciarRedencion`. La validación KYC ocurre solo en `iniciarRedencion`. Ver §6.13 punto 6.

**CONFLICT 9: lab desactivado entre firma y tx. — FASE 2 (ADR-010)**

> No aplica en MVP. Se retoma con `confirmarCalidad` en FASE 2.

**CONFLICT 10: granularidad gramos/kilos/tokens. — RESUELTO (FIX H-02)**

> Kilos en parámetros de input; gramos internamente (FIX H-02). `crearLote` recibe `kgEsperados`; la conversión interna es `kgEsperados * 1000` gramos. `comprar` valida en gramos para evitar rounding que permitiría overmint.

---

**Fin del documento `CONTRACT-SPECS.md` v2.0**
**Reconciliado contra código real:** 2026-05-28
**ADRs incorporados:** ADR-010, ADR-015, ADR-016, ADR-017, FIX M-08, FIX H-01, FIX H-02, FIX M-01/01b/03/04/05/06