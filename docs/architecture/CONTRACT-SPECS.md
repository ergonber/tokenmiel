# Smart Contract Specifications (v1.0)

> Specs detalladas de los 4 smart contracts del MVP de tokenización de RWA agrícola.
> Derivado de `ARQUITECTURA-TECNICA-MVP.md` v2.0 (Decisiones 5, 6, 7, 7B, sección 9).
> **Este documento NO contiene implementación**: solo signatures, NatSpec, structs, errors y eventos.
> Sirve como input directo para subagentes de implementación (Foundry) y tests.

---

## Tabla de contenidos

1. [Convenciones globales](#1-convenciones-globales)
2. [Constantes globales (`ComplianceConstants.sol`)](#2-constantes-globales-complianceconstantssol)
3. [Errores globales reutilizables](#3-errores-globales-reutilizables)
4. [Contrato 1: `AssetVault.sol`](#4-contrato-1-assetvaultsol)
5. [Contrato 2: `IdentityRegistry.sol`](#5-contrato-2-identityregistrysol)
6. [Contrato 3: `RedemptionManager.sol`](#6-contrato-3-redemptionmanagersol)
7. [Contrato 4: `LabRegistry.sol`](#7-contrato-4-labregistrysol)
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

- **Sin proxies** (sin UUPS, sin Transparent, sin Diamond). Los 4 contratos son inmutables.
- **`Pausable`** se usa para `pause()` de emergencia en `AssetVault` y `RedemptionManager`. `IdentityRegistry` y `LabRegistry` no se pausan (su pause crearía dead-locks; en su lugar se desactivan registros individualmente).

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

`AssetVault` es el **contrato principal del MVP**. Implementa el estándar ERC-1155 donde cada `tokenId` representa un lote (`LoteMiel`), con balance = cantidad de tokens (0.5 kg cada uno) propiedad de cada wallet. Mantiene el ciclo de vida completo del lote (PREVENTA → COSECHADO → QUALITY_ATTESTED → ALMACENADO → REDENCION_PARCIAL / AGOTADO / FALLIDO), embebe la reserva técnica (15-20% del USDC prepagado retenido como buffer operacional), embebe el compliance hook (override de `_update` que prohibe transferencias P2P) y embebe el oráculo de calidad (`QualityAttestation` populated por `confirmarCalidad`).

El contrato **no maneja USDC directamente** durante la compra: el backend (`BACKEND_SIGNER_ROLE`) ya recibió el pago off-chain (Stripe/MoonPay/Ramp/SEPA) y llama a `comprar()` para mintear los tokens al wallet del comprador. La reserva técnica se entiende como un **registro contable** dentro del struct `LoteMiel`; el USDC físico vive en wallets operativas Safe Wyoming. La liberación de la reserva al productor SRL la dispara `confirmarCosecha`, ejecutada por `ORACLE_ROLE` (Safe multi-firma 2-de-3) que también dispara la transferencia USDC desde la wallet `TREASURY_SRL_ROLE` controlada externamente.

### 4.2 Herencias OpenZeppelin (orden C3)

```
contract AssetVault is
    ERC1155,
    ERC1155Supply,
    ERC1155Pausable,
    AccessControl,
    ReentrancyGuard
```

**Notas C3 linearization:**
- `ERC1155Supply` debe ir antes de `ERC1155Pausable` para que el `_update` chain compute supply correctamente antes del pause check.
- `AccessControl` después de los ERC1155 mixins para que `supportsInterface` se resuelva correctamente.
- `ReentrancyGuard` al final (no afecta linearization, solo modifier).
- **Override obligatorio de `_update`** para combinar `ERC1155Supply._update` + `ERC1155Pausable._update` + el bloqueo de transfers P2P custom.
- **Override obligatorio de `supportsInterface`** para combinar `ERC1155.supportsInterface` + `AccessControl.supportsInterface`.

### 4.3 Roles definidos

| Rol | Identidad típica | Funciones que controla |
|---|---|---|
| `DEFAULT_ADMIN_ROLE` | Safe multi-sig 2-de-3 (cofundadores) | `grantRole`, `revokeRole`. Bootstrap inicial |
| `ADMIN_ROLE` | Safe multi-sig 2-de-3 | `crearLote`, gestión URI |
| `BACKEND_SIGNER_ROLE` | Wallet del backend (AWS KMS / GCP KMS) | `comprar` (mint tras pago confirmado off-chain) |
| `COMPLIANCE_OFFICER_ROLE` | Compliance officer (hardware wallet) | `pause`, `unpause`, congelamiento de lotes individuales |
| `ORACLE_ROLE` | Safe multi-sig 2-de-3 | `confirmarCosecha`, `confirmarCalidad`, `confirmarAlmacenamiento`, `marcarFallido`, `reembolsarLoteFallido` |
| `TREASURY_SRL_ROLE` | Hardware wallet del tesorero designado | Recipient externo del USDC liberado. **No ejecuta funciones en el contrato**; figura para auditoría off-chain. Documentado pero **no necesario como rol on-chain** (CONFLICT: ver sección 10) |

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
/// @dev Transiciones permitidas:
///      PREVENTA → COSECHADO → QUALITY_ATTESTED → ALMACENADO
///                                                 ├→ REDENCION_PARCIAL → AGOTADO
///                                                 └→ AGOTADO
///      Desde cualquiera (excepto AGOTADO y FALLIDO) → FALLIDO.
///      AGOTADO y FALLIDO son terminales (no se vuelve atrás).
enum LoteEstado {
    PREVENTA,            // 0 - inicial, recibe compras
    COSECHADO,           // 1 - cosecha confirmada con hash SENASAG
    QUALITY_ATTESTED,    // 2 - palinología + NMR confirmados por labs
    ALMACENADO,          // 3 - contrato depósito firmado
    REDENCION_PARCIAL,   // 4 - redenciones en curso
    AGOTADO,             // 5 - todo redimido (terminal)
    FALLIDO              // 6 - terminal, reembolso pro-rata
}
```

### 4.6 Structs

#### 4.6.1 `QualityAttestation` (anidado en `LoteMiel`)

```solidity
/// @notice Attestation de calidad firmada por 2+ labs certificados.
/// @dev Storage layout (slot por slot, dado que mezcla dynamic types):
///      slot N:    labAddresses (dynamic array header)
///      slot N+1:  pollenSpecies (2 bytes) + pollenPercentage (1) + nmrPassed (1) +
///                 c4Passed (1) + residuesPassed (1) + isMonofloralCertified (1) +
///                 testedAt (8) -> fits in 14 bytes packed
///      slot N+2:  fullReportHashes (dynamic array header)
///      Los arrays dinámicos consumen un slot por su length + heap separado para data.
struct QualityAttestation {
    address[] labAddresses;          // labs que firmaron la attestation
    bytes2    pollenSpecies;         // código botánico (ISO o convención interna). e.g. "RM" para Romero
    uint8     pollenPercentage;      // 0-100, real (no normalizado)
    bool      nmrPassed;             // detección adulteración con jarabes
    bool      c4Passed;              // detección adulteración con C4 sugars (AOAC 998.12)
    bool      residuesPassed;        // pesticidas/antibióticos dentro de límites UE MRL
    bool      isMonofloralCertified; // computed: pollenPct >= 45 && nmrPassed && c4Passed && residuesPassed
    uint64    testedAt;              // unix timestamp del cierre de attestation
    bytes32[] fullReportHashes;      // un hash por reporte completo (orden = labAddresses)
}
```

**Razón del orden:** los `bool` + `uint8` + `bytes2` + `uint64` se empacan en un único slot (14 bytes usados de 32). Arrays dinámicos al inicio/final no afectan el packing del bloque escalar central.

#### 4.6.2 `LoteMiel`

```solidity
/// @notice Estado completo de un lote de miel tokenizado.
/// @dev Storage layout pensado para minimizar slots de campos escalares.
///      slot 0:  loteId (32)                              -> 1 slot
///      slot 1:  productor (20) + estado (1) + reservaBps (2) + reservaReleased (1) + ... padding
///      slot 2:  kgEsperados (32)                         -> 1 slot
///      slot 3:  kgCosechadosReal (32)                    -> 1 slot
///      slot 4:  kgRedimidos (32)                         -> 1 slot
///      slot 5:  precioUSDCPorToken (32)                  -> 1 slot
///      slot 6:  reservaTecnicaUSDCInicial (32)
///      slot 7:  reservaTecnicaUSDCDisponible (32)
///      slot 8:  hashFSA (32)
///      slot 9:  hashSenasag (32)
///      slot 10: hashAnalisisLab (32)
///      slot 11: hashContratoDeposito (32)
///      slot 12: createdAt (8) + cosechadoAt (8) + qualityAttestedAt (8) + almacenadoAt (8)
///      slot 13: qualityAttestation (struct anidado consume sus propios slots)
struct LoteMiel {
    // ---- slot 0 ----
    uint256 loteId;                       // ID único, también es el ERC-1155 tokenId

    // ---- slot 1 (packed) ----
    address productor;                    // 20 bytes - wallet del apicultor productor
    LoteEstado estado;                    // 1 byte (enum stored as uint8)
    uint16     reservaTecnicaBps;         // 2 bytes - bps de reserva técnica (1500-2000)
    bool       reservaTecnicaReleased;    // 1 byte - true cuando se liberó al productor
    // 8 bytes restantes libres en slot 1

    // ---- slot 2 ----
    uint256 kgEsperadosTotal;             // kg totales planeados (gramos = kg * 1000)
    // ---- slot 3 ----
    uint256 kgCosechadoReal;              // kg confirmados en cosecha
    // ---- slot 4 ----
    uint256 kgRedimidos;                  // kg ya redimidos (entregados)

    // ---- slot 5 ----
    uint256 precioUSDCPorToken;           // precio fijo en USDC base units (6 decimales) por token
    // ---- slot 6 ----
    uint256 reservaTecnicaUSDCInicial;    // monto total reservado, en USDC base units
    // ---- slot 7 ----
    uint256 reservaTecnicaUSDCDisponible; // monto remanente (para reembolsos pro-rata si FALLIDO)

    // ---- slots 8-11 ----
    bytes32 hashFSA;                      // hash del fact-sheet del lote (creación)
    bytes32 hashSenasag;                  // hash certificado cosecha SENASAG
    bytes32 hashAnalisisLab;              // hash del análisis estándar (HMF, humedad, diastasa)
    bytes32 hashContratoDeposito;         // hash del contrato de depósito firmado

    // ---- slot 12 (packed timestamps) ----
    uint64 createdAt;
    uint64 cosechadoAt;
    uint64 qualityAttestedAt;
    uint64 almacenadoAt;

    // ---- slot 13+ ----
    QualityAttestation qualityAttestation; // sub-struct, consume slots adicionales
}
```

**Notas de packing:**
- Slot 1 podría empaquetar también un `uint64 createdAt` si interesa reducir 1 slot más, pero priorizo legibilidad agrupando timestamps en slot 12.
- `bytes32` no se puede empacar con nada menor.
- `qualityAttestation` permanece al final para no romper el packing escalar previo.

### 4.7 State variables

```solidity
/// @notice Dirección del contrato IdentityRegistry consultado para enforcement KYC.
IIdentityRegistry public immutable identityRegistry;

/// @notice Dirección del contrato LabRegistry consultado para verificar firmas de attestation.
ILabRegistry public immutable labRegistry;

/// @notice Dirección del token USDC en la chain de despliegue.
/// @dev Inmutable. El contrato no maneja USDC directamente excepto para reembolsos en FALLIDO.
IERC20 public immutable usdc;

/// @notice Storage de los lotes indexados por loteId.
mapping(uint256 loteId => LoteMiel) private _lotes;

/// @notice Lista de loteIds existentes para enumeración off-chain (no usar para iteración on-chain).
uint256[] private _loteIds;

/// @notice Contador monotónico para asignar loteId.
uint256 public nextLoteId;

/// @notice URI metadata por lote (sobreescribe la base de ERC-1155).
mapping(uint256 loteId => string) private _loteURI;

/// @notice Para reembolsos pro-rata en FALLIDO: lista de compradores conocidos por lote.
/// @dev Mantenida vía hook en `_update` cuando se mintea por primera vez a una nueva address.
mapping(uint256 loteId => address[]) private _compradoresPorLote;

/// @notice Evita duplicar addresses en `_compradoresPorLote`.
mapping(uint256 loteId => mapping(address => bool)) private _esCompradorRegistrado;

/// @notice Marca de attestation hashes ya consumidos (evita replay de firmas).
mapping(bytes32 attestationDigest => bool consumed) private _attestationConsumed;
```

### 4.8 Eventos

```solidity
/// @notice Emitido al crear un nuevo lote en estado PREVENTA.
event LoteCreado(
    uint256 indexed loteId,
    address indexed productor,
    uint256 kgEsperadosTotal,
    uint256 precioUSDCPorToken,
    uint16  reservaTecnicaBps,
    bytes32 hashFSA
);

/// @notice Emitido tras una compra exitosa (mint).
event LoteComprado(
    uint256 indexed loteId,
    address indexed buyer,
    uint256 cantidadTokens,
    uint256 amountUSDC,
    bytes32 paymentRefHash
);

/// @notice Emitido al confirmar cosecha por el oráculo Safe multi-firma.
event CosechaConfirmada(
    uint256 indexed loteId,
    uint256 kgCosechadoReal,
    bytes32 hashSenasag,
    bytes32 hashAnalisisLab
);

/// @notice Emitido al confirmar attestation de calidad multi-lab.
event CalidadConfirmada(
    uint256 indexed loteId,
    address[] labAddresses,
    bytes2 pollenSpecies,
    uint8 pollenPercentage,
    bool isMonofloralCertified
);

/// @notice Emitido al confirmar almacenamiento (contrato de depósito firmado).
event AlmacenamientoConfirmado(
    uint256 indexed loteId,
    bytes32 hashContratoDeposito
);

/// @notice Emitido al marcar un lote como FALLIDO.
event LoteFallido(
    uint256 indexed loteId,
    string motivo,
    bytes32 hashEvidencia
);

/// @notice Emitido cuando se libera la reserva técnica al productor.
event ReservaTecnicaLiberada(
    uint256 indexed loteId,
    address indexed productor,
    uint256 montoUSDC
);

/// @notice Emitido durante reembolso pro-rata por lote fallido.
event ReembolsoEjecutado(
    uint256 indexed loteId,
    address indexed buyer,
    uint256 tokensQuemados,
    uint256 amountUSDCDevuelto
);

/// @notice Emitido cuando RedemptionManager solicita burn de tokens en escrow.
event TokensRedimidos(
    uint256 indexed loteId,
    address indexed buyer,
    uint256 cantidadTokens
);

/// @notice Emitido al cambiar la URI metadata de un lote.
event LoteURIUpdated(uint256 indexed loteId, string newURI);
```

### 4.9 Custom errors

```solidity
// Identity / KYC
error NotKYCVerified(address account);
error InsufficientKYCTier(address account, uint8 currentTier, uint8 requiredTier);
error AddressSanctioned(address account);
error AddressFrozen(address account);

// Lote
error LoteNotFound(uint256 loteId);
error InvalidLoteState(uint256 loteId, LoteEstado current, LoteEstado required);
error InvalidStateTransition(LoteEstado from, LoteEstado to);
error LoteCreationInvalidProductor();
error LoteCreationInvalidGramos();
error LoteCreationInvalidPrecio();
error LoteCreationInvalidReserva(uint16 bps);

// Compra
error InsufficientStock(uint256 loteId, uint256 requested, uint256 available);
error PaymentRefAlreadyUsed(bytes32 paymentRefHash);

// Transfers
error TransferP2PNoPermitido(address from, address to);

// Reserva
error ReservaTecnicaAlreadyReleased(uint256 loteId);

// Quality
error InsufficientLabsForAttestation(uint8 provided, uint8 required);
error LabNotCertified(address lab);
error InvalidAttestationSignature(address lab);
error AttestationAlreadyConsumed(bytes32 digest);
error AttestationSignaturesLengthMismatch(uint256 labs, uint256 sigs);

// Reembolso
error ReembolsoCompradorIndexInvalido(uint256 idx, uint256 max);
error ReembolsoUSDCInsuficiente(uint256 needed, uint256 available);
```

### 4.10 Modifiers

```solidity
/// @notice Reverts si el account no tiene KYC tier >= MIN_KYC_TIER_PARA_COMPRAR.
modifier onlyKYCVerified(address account);

/// @notice Reverts si el account no tiene el tier mínimo requerido.
modifier onlyTier(address account, uint8 minTier);

/// @notice Reverts si el account está marcado sancionado en IdentityRegistry.
modifier notSanctioned(address account);

/// @notice Reverts si el account está marcado frozen en IdentityRegistry.
modifier notFrozen(address account);

/// @notice Reverts si el lote no está en el estado esperado.
modifier loteInState(uint256 loteId, LoteEstado required);

/// @notice Reverts si el lote no existe.
modifier loteExists(uint256 loteId);
```

> **Nota de implementación:** `onlyKYCVerified` y `onlyTier` se implementan como llamada a `identityRegistry.checkCompliance(...)` para centralizar el chequeo.

### 4.11 Function signatures

#### 4.11.1 Construcción y administración

```solidity
/// @notice Inicializa el contrato con dependencias inmutables.
/// @dev El deployer recibe DEFAULT_ADMIN_ROLE inicial; deberá transferirlo al Safe inmediatamente
///      via `grantRole(DEFAULT_ADMIN_ROLE, safe)` + `renounceRole(...)`.
/// @param _identityRegistry Dirección de IdentityRegistry desplegado previamente.
/// @param _labRegistry Dirección de LabRegistry desplegado previamente.
/// @param _usdc Dirección de USDC en la chain.
/// @param _baseURI URI base ERC-1155 (formato `https://api.dominio/lotes/{id}.json`).
constructor(
    IIdentityRegistry _identityRegistry,
    ILabRegistry _labRegistry,
    IERC20 _usdc,
    string memory _baseURI
);

/// @notice Pausa el contrato. Bloquea mint, burn, comprar y todas las funciones de oráculo.
/// @dev Solo COMPLIANCE_OFFICER_ROLE.
/// @custom:security Patrón de mitigación de emergencia. No tiene timelock por diseño (ver ARQUITECTURA-TECNICA-MVP §6.3).
function pause() external;

/// @notice Despausa el contrato.
/// @dev Solo COMPLIANCE_OFFICER_ROLE.
function unpause() external;

/// @notice Actualiza la URI metadata específica de un lote (sobreescribe la base).
/// @dev Solo ADMIN_ROLE.
/// @param loteId ID del lote.
/// @param newURI Nueva URI completa.
function setLoteURI(uint256 loteId, string calldata newURI) external;

/// @notice Devuelve la URI metadata de un token siguiendo la lógica ERC-1155.
/// @dev Override de ERC1155.uri. Consulta `_loteURI[id]` y cae a la base si no hay override.
function uri(uint256 id) public view override returns (string memory);
```

#### 4.11.2 Ciclo de vida del lote

```solidity
/// @notice Crea un nuevo lote en estado PREVENTA.
/// @dev Solo ADMIN_ROLE. Asigna `loteId = nextLoteId++`. La reserva técnica se calcula al primer mint (no aquí).
/// @param productor Wallet del apicultor productor (no zero, debe estar KYC tier >= 1).
/// @param kgEsperadosTotal Kilos totales esperados del lote (gramos = kg * 1000).
/// @param precioUSDCPorToken Precio fijo en USDC base units (6 decimales) por 1 token (= 0.5 kg).
/// @param reservaTecnicaBps Basis points (1500-2000) que se reservan del USDC prepago.
/// @param hashFSA SHA-256 del fact-sheet del lote.
/// @return loteId ID asignado al nuevo lote.
/// @custom:security Valida `reservaTecnicaBps` dentro de [RESERVA_TECNICA_BPS_MIN, RESERVA_TECNICA_BPS_MAX].
function crearLote(
    address productor,
    uint256 kgEsperadosTotal,
    uint256 precioUSDCPorToken,
    uint16 reservaTecnicaBps,
    bytes32 hashFSA
) external returns (uint256 loteId);

/// @notice Mintea tokens a un comprador tras pago confirmado off-chain.
/// @dev Solo BACKEND_SIGNER_ROLE. nonReentrant + whenNotPaused.
///      No transfiere USDC: el pago ya ocurrió en el provider (Stripe/MoonPay/Ramp/SEPA);
///      el backend respalda con `paymentRefHash` (hash del intent + provider txid) para auditoría.
///      Acumula `reservaTecnicaUSDCInicial` y `reservaTecnicaUSDCDisponible` proporcionalmente.
/// @param loteId Lote a comprar. Debe estar en PREVENTA.
/// @param buyer Wallet del comprador. Debe pasar KYC tier >= 1 y no estar sanctioned/frozen.
/// @param cantidadTokens Tokens a mintear (1 token = 0.5 kg). No exceder kgEsperadosTotal en gramos.
/// @param paymentRefHash Hash único del payment intent (anti-replay y audit trail).
function comprar(
    uint256 loteId,
    address buyer,
    uint256 cantidadTokens,
    bytes32 paymentRefHash
) external;

/// @notice Confirma la cosecha y transiciona el lote a COSECHADO.
/// @dev Solo ORACLE_ROLE (Safe multi-firma). Libera la reserva técnica al productor (marca released).
///      Si `kgCosechadoReal < kgEsperadosTotal`, el delta queda registrado para gestión off-chain
///      (no impacta tokens minteados, que son por preventa).
/// @param loteId Lote a confirmar.
/// @param kgCosechadoReal Kilos efectivamente cosechados (en kg, conversion interna a gramos opcional).
/// @param hashSenasag SHA-256 del certificado SENASAG.
/// @param hashAnalisisLab SHA-256 del análisis lab estándar (HMF, humedad, diastasa).
function confirmarCosecha(
    uint256 loteId,
    uint256 kgCosechadoReal,
    bytes32 hashSenasag,
    bytes32 hashAnalisisLab
) external;

/// @notice Confirma la attestation de calidad multi-lab y transiciona a QUALITY_ATTESTED.
/// @dev Solo ORACLE_ROLE. Valida:
///      1. Lote en estado COSECHADO.
///      2. `attestation.labAddresses.length >= MIN_LABS_PARA_ATTESTATION` (2).
///      3. `attestation.labAddresses.length == labSignatures.length == fullReportHashes.length`.
///      4. Cada lab está activo + certificado para los tests relevantes (vía LabRegistry).
///      5. Cada firma es válida sobre el digest del reporte correspondiente (ECDSA).
///      6. El digest no fue consumido previamente (`_attestationConsumed[digest]`).
///      7. Computa `isMonofloralCertified` y guarda en el lote.
/// @param loteId Lote.
/// @param attestation Struct completo (sin `isMonofloralCertified`: lo computa el contrato y sobreescribe).
/// @param labSignatures Una firma ECDSA por cada lab, sobre el reportHash correspondiente.
/// @custom:security Anti-replay vía `_attestationConsumed` indexado por keccak256 del digest combinado.
function confirmarCalidad(
    uint256 loteId,
    QualityAttestation calldata attestation,
    bytes[] calldata labSignatures
) external;

/// @notice Confirma almacenamiento (contrato de depósito firmado) y transiciona a ALMACENADO.
/// @dev Solo ORACLE_ROLE. Requiere lote en QUALITY_ATTESTED.
/// @param loteId Lote.
/// @param hashContratoDeposito SHA-256 del contrato de depósito.
function confirmarAlmacenamiento(uint256 loteId, bytes32 hashContratoDeposito) external;

/// @notice Marca un lote como FALLIDO (estado terminal de excepción).
/// @dev Solo ORACLE_ROLE. Permite reembolso pro-rata posterior vía `reembolsarLoteFallido`.
///      Permite transición desde cualquier estado no terminal.
/// @param loteId Lote.
/// @param motivo String corto (e.g. "clima", "robo", "contaminacion"). Indexado off-chain.
/// @param hashEvidencia SHA-256 del paquete de evidencia del fallo.
function marcarFallido(uint256 loteId, string calldata motivo, bytes32 hashEvidencia) external;

/// @notice Ejecuta reembolso pro-rata para compradores específicos de un lote FALLIDO.
/// @dev Solo ORACLE_ROLE. nonReentrant.
///      Quema los tokens de cada `buyer` listado y transfiere USDC pro-rata desde `reservaTecnicaUSDCDisponible`
///      + balance del contrato (este último depende de funding externo via wallet TREASURY_SRL_ROLE).
///      Procesa en batches para evitar gas limits; el caller debe iterar si la lista es larga.
/// @param loteId Lote FALLIDO.
/// @param compradores Lista de wallets a reembolsar (no duplicados; sub-conjunto de `_compradoresPorLote`).
/// @custom:security Validar que `_esCompradorRegistrado[loteId][buyer]` evita reembolso a non-buyers.
function reembolsarLoteFallido(uint256 loteId, address[] calldata compradores) external;
```

#### 4.11.3 Reserva técnica

```solidity
/// @notice Libera la reserva técnica al productor (marca released; no transfiere USDC).
/// @dev Llamada interna desde `confirmarCosecha`. El movimiento real del USDC al productor
///      ocurre fuera del contrato (wallet operativa Safe Wyoming → wallet productor).
///      Emite `ReservaTecnicaLiberada` para audit trail on-chain.
/// @param loteId Lote.
function _liberarReservaTecnica(uint256 loteId) internal;

/// @notice Devuelve el monto de reserva técnica todavía disponible para reembolsos.
/// @param loteId Lote.
/// @return montoUSDC Monto en USDC base units.
function reservaDisponible(uint256 loteId) external view returns (uint256 montoUSDC);
```

#### 4.11.4 Hooks de redención (acoplados a RedemptionManager)

```solidity
/// @notice Transfiere tokens del comprador al escrow gestionado por RedemptionManager.
/// @dev Solo callable por RedemptionManager (controlado vía AccessControl o address dedicada).
///      No quema: la quema ocurre en `burnRedemptionTokens` cuando se confirma la exportación.
///      Bloqueado durante pause.
/// @param loteId Lote.
/// @param buyer Wallet del comprador.
/// @param cantidad Tokens.
function lockForRedemption(uint256 loteId, address buyer, uint256 cantidad) external;

/// @notice Quema tokens del escrow de RedemptionManager.
/// @dev Solo callable por RedemptionManager. Marca lote como REDENCION_PARCIAL o AGOTADO.
/// @param loteId Lote.
/// @param cantidad Tokens a quemar.
function burnRedemptionTokens(uint256 loteId, uint256 cantidad) external;

/// @notice Devuelve tokens del escrow al buyer si la redención es cancelada.
/// @dev Solo callable por RedemptionManager.
function returnRedemptionTokens(uint256 loteId, address buyer, uint256 cantidad) external;
```

> **Nota de diseño:** la dirección de `RedemptionManager` se registra en `AssetVault` vía constructor (immutable) o vía rol dedicado `REDEMPTION_MANAGER_ROLE` configurado por `DEFAULT_ADMIN_ROLE` post-deploy. CONFLICT: ver sección 10.

#### 4.11.5 View functions

```solidity
/// @notice Devuelve el struct completo del lote.
/// @param loteId Lote.
/// @return lote Struct LoteMiel.
function getLote(uint256 loteId) external view returns (LoteMiel memory lote);

/// @notice Devuelve el estado actual del lote.
function getLoteEstado(uint256 loteId) external view returns (LoteEstado);

/// @notice Devuelve la attestation de calidad de un lote.
function getQualityAttestation(uint256 loteId) external view returns (QualityAttestation memory);

/// @notice Devuelve si un lote está certificado monofloral.
function isMonofloralCertified(uint256 loteId) external view returns (bool);

/// @notice Devuelve la lista de loteIds creados (paginar off-chain).
function getLoteIds() external view returns (uint256[] memory);

/// @notice Devuelve la cantidad de tokens disponibles (no minted aún) para un lote en PREVENTA.
/// @dev Calcula como: (kgEsperadosTotal / GRAMOS_POR_TOKEN gramos) - totalSupply(loteId).
function tokensDisponibles(uint256 loteId) external view returns (uint256);

/// @notice Devuelve la lista de compradores registrados de un lote (para reembolsos).
/// @dev Acceso restringido a ORACLE_ROLE y COMPLIANCE_OFFICER_ROLE para privacidad.
function getCompradoresLote(uint256 loteId) external view returns (address[] memory);
```

### 4.12 Overrides de OpenZeppelin

#### 4.12.1 `_update` (núcleo del compliance hook)

```solidity
/// @notice Override que combina ERC1155Supply, ERC1155Pausable y el bloqueo P2P.
/// @dev Reglas:
///      1. Permitir mint (from == address(0)).
///      2. Permitir burn (to == address(0)).
///      3. Permitir transfer hacia/desde la dirección autorizada de RedemptionManager
///         (la lógica de redención mueve tokens al escrow y luego los quema).
///      4. Permitir transfer hacia/desde el propio contrato si el caller tiene COMPLIANCE_OFFICER_ROLE
///         (reservado para casos de remediación forzada documentada).
///      5. Cualquier otra transferencia (P2P entre usuarios) revierte con TransferP2PNoPermitido.
///      6. Validar compliance del `to` en cualquier mint: KYC tier >= 1, no sancionado, no frozen.
///      7. Mantener `_compradoresPorLote` actualizado en mints.
function _update(
    address from,
    address to,
    uint256[] memory ids,
    uint256[] memory values
) internal override(ERC1155, ERC1155Supply, ERC1155Pausable);
```

#### 4.12.2 `supportsInterface`

```solidity
/// @notice Indica interfaces ERC implementadas (ERC-1155 + AccessControl).
function supportsInterface(bytes4 interfaceId)
    public
    view
    override(ERC1155, AccessControl)
    returns (bool);
```

### 4.13 Consideraciones de seguridad

1. **Reentrancy:**
   - Funciones que pueden gatillar callbacks ERC1155 (mint, burn) usan `nonReentrant`.
   - `reembolsarLoteFallido` mueve USDC (external call a USDC contract) → `nonReentrant` obligatorio + checks-effects-interactions.

2. **Signature replay attacks (QualityAttestation):**
   - Cada attestation tiene un `digest` derivado del hash del struct + loteId + chainId + dirección del contrato.
   - `_attestationConsumed[digest] = true` antes de cualquier validación (effects-first dentro del límite seguro).

3. **Access control gaps:**
   - `DEFAULT_ADMIN_ROLE` debe transferirse al Safe inmediatamente post-deploy.
   - `BACKEND_SIGNER_ROLE` controla mints: si se compromete, atacante puede mintear sin pago. Mitigación: rotación periódica, alertas de mints anómalos en Goldsky, capacity caps off-chain.

4. **Integer overflow:**
   - Solidity 0.8.24 protege por defecto.
   - `kgCosechadoReal * GRAMOS_POR_KILO` no debe overflowar para lotes de tamaño realista (max ~10⁹ kg sigue dentro de uint256).

5. **DoS por arrays:**
   - `_compradoresPorLote` y `_loteIds` son potencialmente grandes; ninguna función itera sobre ellos on-chain salvo `reembolsarLoteFallido` que recibe la lista por calldata (controlable en tamaño por el caller).
   - View functions devuelven arrays; el caller debe paginar off-chain.

6. **Compliance hook bypass:**
   - El override de `_update` es la única superficie de transfer. ERC1155 no expone otras rutas de movimiento.

7. **Pausabilidad sin timelock:**
   - Diseño deliberado: emergencias requieren respuesta inmediata. El abuso del pause queda contenido por el Safe 2-de-3 que controla `COMPLIANCE_OFFICER_ROLE` post-deploy.

8. **Locking permanente:**
   - Si la dirección de `RedemptionManager` está mal configurada, los tokens en escrow quedan locked. Mitigación: tests E2E del flujo de redención antes de mainnet + recuperación vía `pause` + migración v2.

9. **Frontrunning de `confirmarCalidad`:**
   - El proceso requiere firmas pre-coordinadas por el Safe; no hay frontrun económico viable.

10. **MEV en compras:**
    - Sin riesgo material: el precio está fijo por `precioUSDCPorToken`, no hay arbitrage on-chain. El stock de tokens se atribuye en orden de llegada de la tx del backend; el backend ejecuta en serie con nonce monotónico → no hay race entre compradores on-chain.

---

## 5. Contrato 2: `IdentityRegistry.sol`

### 5.1 Propósito

`IdentityRegistry` mantiene la whitelist on-chain de wallets verificadas (KYC), su tier, su jurisdicción, su estado (sancionado, congelado, expirado), y un hash externo (`externalRefHash`) que enlaza con el `applicantId` de Sumsub para reconstruir el linkage off-chain. Es consultado por `AssetVault` (mint, transfer-blocked-by-default) y `RedemptionManager` (iniciar redención requiere tier >= 2).

Diseñado como **bridge con Plume Arc**: en Plume Network, Plume Arc es la fuente nativa de verificación KYC; este contrato se sincroniza vía un backend signer que escucha eventos Arc y refleja decisiones aquí. Pero el contrato es **autónomo**: en Polygon (fase 6+) o en testnets sin Plume Arc, funciona standalone con el backend signer como única fuente.

El contrato **no almacena PII**: solo hashes y datos compatibles con regulación de privacidad (tier, jurisdicción ISO, timestamps, flags). El `externalRefHash` es un commitment criptográfico al `applicantId` Sumsub, recuperable solo conociendo el original (no rainbow-tableable porque incluye sal interna del backend).

### 5.2 Herencias OpenZeppelin (orden C3)

```
contract IdentityRegistry is
    AccessControl
```

> **Nota:** intencionalmente NO incluye `Pausable`. Pausar `IdentityRegistry` dejaría a `AssetVault` sin poder validar mints, congelando el sistema completo. El control de emergencia es a nivel `AssetVault.pause()` y desactivaciones puntuales (`freeze`).

### 5.3 Roles definidos

| Rol | Identidad típica | Funciones que controla |
|---|---|---|
| `DEFAULT_ADMIN_ROLE` | Safe multi-sig 2-de-3 | Gestión de roles |
| `ADMIN_ROLE` | Safe multi-sig 2-de-3 | Configuración general (set Plume Arc bridge address) |
| `BACKEND_SIGNER_ROLE` | Wallet del backend (AWS KMS / GCP KMS) | `setKYC`, `markSanctioned`, `unmarkSanctioned`, `freeze`, `unfreeze`, `revokeKYC` |
| `COMPLIANCE_OFFICER_ROLE` | Hardware wallet del compliance officer | `markSanctioned`, `unmarkSanctioned`, `freeze`, `unfreeze` (redundante con backend para emergencia) |

> `ORACLE_ROLE` y `TREASURY_SRL_ROLE` **no aplican** aquí.

### 5.4 Constantes

```solidity
bytes32 public constant ADMIN_ROLE              = keccak256("ADMIN_ROLE");
bytes32 public constant BACKEND_SIGNER_ROLE     = keccak256("BACKEND_SIGNER_ROLE");
bytes32 public constant COMPLIANCE_OFFICER_ROLE = keccak256("COMPLIANCE_OFFICER_ROLE");
```

Re-export de `ComplianceConstants.TIER_*` y `MIN_KYC_TIER_*` (sin redeclarar).

### 5.5 Structs

#### 5.5.1 `IdentityData`

```solidity
/// @notice Datos de identidad on-chain de una wallet.
/// @dev Storage layout:
///      slot 0 (packed): tier (1) + sanctioned (1) + frozen (1) + jurisdiction (2) +
///                       expiresAt (8) + updatedAt (8) + revokedAt (8) = 29 bytes packed
///      slot 1:         externalRefHash (32)
struct IdentityData {
    uint8  tier;             // 0=none, 1, 2, 3
    bool   sanctioned;
    bool   frozen;
    bytes2 jurisdiction;     // ISO 3166-1 alpha-2 (e.g. "BO", "DE", "US")
    uint64 expiresAt;        // unix timestamp; 0 = no expiry
    uint64 updatedAt;        // unix timestamp del último cambio
    uint64 revokedAt;        // unix timestamp si fue revocado; 0 si activo
    bytes32 externalRefHash; // commitment del applicantId Sumsub (con sal del backend)
}
```

### 5.6 Enums

No requeridos (los flags son `bool`, el tier es `uint8`).

### 5.7 State variables

```solidity
/// @notice Storage de identidades por wallet.
mapping(address account => IdentityData) public identities;

/// @notice Dirección del bridge a Plume Arc (zero si no aplica).
/// @dev Permite a la dirección bridgear actualizaciones desde Arc al registro.
///      Controlada con BACKEND_SIGNER_ROLE para mantener single source flow.
address public plumeArcBridge;
```

### 5.8 Eventos

```solidity
/// @notice Emitido al setear o actualizar KYC de una cuenta.
event KYCUpdated(
    address indexed account,
    uint8 tier,
    bytes2 jurisdiction,
    uint64 expiresAt,
    bytes32 externalRefHash
);

/// @notice Emitido al marcar sancionado.
event Sanctioned(address indexed account, string listSource);

/// @notice Emitido al desmarcar sancionado.
event Unsanctioned(address indexed account);

/// @notice Emitido al congelar una cuenta (sin sanción, e.g. fraude pendiente investigación).
event Frozen(address indexed account, string motivo);

/// @notice Emitido al descongelar.
event Unfrozen(address indexed account);

/// @notice Emitido al revocar KYC (cuenta cierra, EDD failure, etc.).
event KYCRevoked(address indexed account, string motivo);

/// @notice Emitido al setear/cambiar el bridge a Plume Arc.
event PlumeArcBridgeUpdated(address indexed previousBridge, address indexed newBridge);
```

### 5.9 Custom errors

```solidity
error ZeroAddress();
error InvalidTier(uint8 tier);
error InvalidJurisdiction(bytes2 jurisdiction);
error IdentityNotFound(address account);
error IdentityAlreadySanctioned(address account);
error IdentityNotSanctioned(address account);
error IdentityAlreadyFrozen(address account);
error IdentityNotFrozen(address account);
error IdentityAlreadyRevoked(address account);
error UnauthorizedBridge(address caller);
```

### 5.10 Modifiers

```solidity
/// @notice Permite que tanto BACKEND_SIGNER_ROLE como COMPLIANCE_OFFICER_ROLE invoquen la función.
modifier onlySignerOrCompliance();

/// @notice Permite que el caller sea el plumeArcBridge configurado o BACKEND_SIGNER_ROLE.
modifier onlyBridgeOrSigner();
```

### 5.11 Function signatures

#### 5.11.1 Construcción

```solidity
/// @notice Inicializa con el deployer como DEFAULT_ADMIN_ROLE temporal.
/// @dev El deployer debe transferir DEFAULT_ADMIN_ROLE al Safe post-deploy.
constructor();
```

#### 5.11.2 Mutators

```solidity
/// @notice Setea o actualiza KYC de una cuenta.
/// @dev Solo BACKEND_SIGNER_ROLE o bridge Plume Arc. Sobreescribe campos no-flag (sanctioned, frozen no se tocan aquí).
///      `revokedAt` se resetea a 0 si la cuenta es re-aprobada después de un revoke.
/// @param account Wallet a actualizar.
/// @param tier 0-3.
/// @param jurisdiction ISO 3166-1 alpha-2.
/// @param expiresAt Unix timestamp; 0 = sin expiry.
/// @param externalRefHash Hash del applicantId Sumsub.
function setKYC(
    address account,
    uint8 tier,
    bytes2 jurisdiction,
    uint64 expiresAt,
    bytes32 externalRefHash
) external;

/// @notice Marca cuenta como sancionada.
/// @dev Solo BACKEND_SIGNER_ROLE o COMPLIANCE_OFFICER_ROLE.
/// @param account Wallet.
/// @param listSource Identificador de la lista que gatilló (e.g. "OFAC_SDN", "UN_CONSOLIDATED").
function markSanctioned(address account, string calldata listSource) external;

/// @notice Quita el flag sancionado (recurso, false-positive, etc.).
/// @dev Solo COMPLIANCE_OFFICER_ROLE (decisión humana, no automatizada).
function unmarkSanctioned(address account) external;

/// @notice Congela cuenta (no permite mint/transfer, sin sanción formal).
/// @dev Solo BACKEND_SIGNER_ROLE o COMPLIANCE_OFFICER_ROLE.
/// @param account Wallet.
/// @param motivo String corto (e.g. "fraude_investigacion", "edd_pending").
function freeze(address account, string calldata motivo) external;

/// @notice Descongela.
/// @dev Solo COMPLIANCE_OFFICER_ROLE.
function unfreeze(address account) external;

/// @notice Revoca KYC (cuenta cierra o EDD failure permanente).
/// @dev Solo COMPLIANCE_OFFICER_ROLE. Resetea tier a 0 y marca revokedAt.
function revokeKYC(address account, string calldata motivo) external;

/// @notice Setea o actualiza el bridge a Plume Arc.
/// @dev Solo ADMIN_ROLE. Pasar address(0) desactiva el bridge.
function setPlumeArcBridge(address newBridge) external;
```

#### 5.11.3 View functions / queries

```solidity
/// @notice Devuelve los datos de identidad de una cuenta.
function getIdentity(address account) external view returns (IdentityData memory);

/// @notice Devuelve el tier actual de KYC (0 si no registrada o expirada).
/// @dev Si `expiresAt > 0 && block.timestamp > expiresAt` devuelve 0.
function getTier(address account) external view returns (uint8);

/// @notice Helper combinado: verifica si una cuenta puede operar para un mínimo tier.
/// @dev Reverts con error específico (no devuelve bool). Usar para enforcement directo.
/// @param account Wallet.
/// @param minTier Tier mínimo requerido.
function checkCompliance(address account, uint8 minTier) external view;

/// @notice Versión non-reverting de checkCompliance (para uso off-chain o branching).
/// @return ok True si pasa todas las checks.
/// @return reason Código numérico del fallo (0=ok, 1=no kyc, 2=tier insuficiente, 3=sancionado, 4=frozen, 5=expirado, 6=revoked).
function isCompliant(address account, uint8 minTier)
    external
    view
    returns (bool ok, uint8 reason);

/// @notice Devuelve true si la cuenta está sancionada.
function isSanctioned(address account) external view returns (bool);

/// @notice Devuelve true si la cuenta está congelada.
function isFrozen(address account) external view returns (bool);
```

### 5.12 Overrides

No requiere overrides custom de OpenZeppelin (solo hereda `AccessControl`).

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

6. **Sin `pause`:**
   - Diseño deliberado. Para detener emisiones de tokens ante incidente, pausar `AssetVault` (no este contrato).

7. **Revocación irreversible parcial:**
   - `revokeKYC` resetea tier a 0; re-aprobación posterior requiere nueva llamada `setKYC` con datos frescos. `revokedAt` queda como audit trail.

---

## 6. Contrato 3: `RedemptionManager.sol`

### 6.1 Propósito

`RedemptionManager` encapsula el flujo de redención física: el usuario solicita retirar miel física, sus tokens quedan en escrow (transferidos al contrato vía `AssetVault.lockForRedemption`), el operador SRL coordina la exportación off-chain (Aduana, DUE, BL/AWB), y al confirmar la exportación el oráculo Safe gatilla la quema definitiva (`AssetVault.burnRedemptionTokens`). Si la redención se cancela antes de la quema, los tokens regresan al usuario (`AssetVault.returnRedemptionTokens`).

El contrato mantiene el estado de cada redención (`Redencion`) con sus hashes documentales (datos de envío, DUE, BL/AWB) para audit trail on-chain. **No mueve USDC** (los tokens son la única unidad de valor en este flujo; el comprador ya pagó al mint).

### 6.2 Herencias OpenZeppelin (orden C3)

```
contract RedemptionManager is
    AccessControl,
    Pausable,
    ReentrancyGuard
```

- `Pausable` se incluye para detener nuevas redenciones ante incidente (e.g. discrepancia entre estado on-chain y stock físico). Las redenciones ya iniciadas pueden ser canceladas manualmente o esperar el unpause.
- `ReentrancyGuard` por las llamadas a `AssetVault` (external calls).

### 6.3 Roles definidos

| Rol | Identidad típica | Funciones que controla |
|---|---|---|
| `DEFAULT_ADMIN_ROLE` | Safe multi-sig 2-de-3 | Gestión de roles |
| `ADMIN_ROLE` | Safe multi-sig 2-de-3 | Configuración general |
| `BACKEND_SIGNER_ROLE` | Wallet backend | `iniciarRedencion` (en nombre del usuario, signed UX) |
| `COMPLIANCE_OFFICER_ROLE` | Compliance officer | `pause`, `unpause`, `cancelarRedencion` por compliance |
| `ORACLE_ROLE` | Safe multi-sig 2-de-3 | `confirmarExportacion`, `cancelarRedencion` por logística |

### 6.4 Constantes

```solidity
bytes32 public constant ADMIN_ROLE              = keccak256("ADMIN_ROLE");
bytes32 public constant BACKEND_SIGNER_ROLE     = keccak256("BACKEND_SIGNER_ROLE");
bytes32 public constant COMPLIANCE_OFFICER_ROLE = keccak256("COMPLIANCE_OFFICER_ROLE");
bytes32 public constant ORACLE_ROLE             = keccak256("ORACLE_ROLE");
```

### 6.5 Enums

```solidity
/// @notice Estados de una redención.
/// @dev Transiciones válidas:
///      INICIADA → EN_EXPORTACION → COMPLETADA
///      INICIADA → CANCELADA
///      EN_EXPORTACION → CANCELADA (excepcionalmente, por compliance officer)
enum EstadoRedencion {
    INICIADA,         // 0 - tokens en escrow
    EN_EXPORTACION,   // 1 - DUE emitida
    COMPLETADA,       // 2 - tokens quemados (terminal)
    CANCELADA         // 3 - tokens devueltos (terminal)
}
```

### 6.6 Structs

#### 6.6.1 `Redencion`

```solidity
/// @notice Datos de una redención individual.
/// @dev Storage layout:
///      slot 0:  redemptionId (32)
///      slot 1:  loteId (32)
///      slot 2 (packed): buyer (20) + estado (1) + ... padding
///      slot 3:  cantidadTokens (32)
///      slot 4:  hashDatosEnvio (32)
///      slot 5:  hashDUE (32)
///      slot 6:  hashBLAWB (32)
///      slot 7 (packed): iniciadaAt (8) + exportadaAt (8) + completadaAt (8) + canceladaAt (8) = 32 bytes
struct Redencion {
    uint256 redemptionId;
    uint256 loteId;
    address buyer;             // 20 bytes
    EstadoRedencion estado;    // 1 byte
    // 11 bytes libres en slot 2
    uint256 cantidadTokens;
    bytes32 hashDatosEnvio;
    bytes32 hashDUE;
    bytes32 hashBLAWB;
    uint64 iniciadaAt;
    uint64 exportadaAt;
    uint64 completadaAt;
    uint64 canceladaAt;
}
```

### 6.7 State variables

```solidity
/// @notice Dirección de AssetVault (immutable).
IAssetVault public immutable assetVault;

/// @notice Dirección de IdentityRegistry (immutable).
IIdentityRegistry public immutable identityRegistry;

/// @notice Storage de redenciones por ID.
mapping(uint256 redemptionId => Redencion) public redenciones;

/// @notice Lista de redemptionIds por buyer (para enumeración off-chain).
mapping(address buyer => uint256[]) private _redencionesPorBuyer;

/// @notice Lista de redemptionIds por lote (para enumeración off-chain).
mapping(uint256 loteId => uint256[]) private _redencionesPorLote;

/// @notice Counter monotónico.
uint256 public nextRedemptionId;
```

### 6.8 Eventos

```solidity
event RedencionIniciada(
    uint256 indexed redemptionId,
    uint256 indexed loteId,
    address indexed buyer,
    uint256 cantidadTokens,
    bytes32 hashDatosEnvio
);

event RedencionEnExportacion(
    uint256 indexed redemptionId,
    string dueNumero,           // referencia legible Aduana
    bytes32 hashDUE
);

event RedencionCompletada(
    uint256 indexed redemptionId,
    bytes32 hashBLAWB
);

event RedencionCancelada(
    uint256 indexed redemptionId,
    string motivo
);
```

### 6.9 Custom errors

```solidity
error ZeroAddress();
error ZeroAmount();
error RedencionNotFound(uint256 redemptionId);
error InvalidRedencionState(uint256 redemptionId, EstadoRedencion current, EstadoRedencion required);
error InvalidStateTransition(EstadoRedencion from, EstadoRedencion to);
error InsufficientTokenBalance(address buyer, uint256 loteId, uint256 needed, uint256 available);
error LoteNotRedeemable(uint256 loteId); // lote no está en ALMACENADO/REDENCION_PARCIAL
error NotKYCVerified(address account);
error InsufficientKYCTier(address account, uint8 currentTier, uint8 requiredTier);
error AddressSanctioned(address account);
error AddressFrozen(address account);
error CallerNotRedemptionOwner(address caller, address owner);
```

### 6.10 Modifiers

```solidity
/// @notice Reverts si el buyer no es tier >= 2.
modifier onlyTierForRedemption(address buyer);

/// @notice Reverts si la redención no existe.
modifier redencionExists(uint256 redemptionId);

/// @notice Reverts si la redención no está en el estado requerido.
modifier redencionInState(uint256 redemptionId, EstadoRedencion required);
```

### 6.11 Function signatures

#### 6.11.1 Construcción

```solidity
/// @notice Inicializa con AssetVault e IdentityRegistry.
/// @param _assetVault Dirección de AssetVault.
/// @param _identityRegistry Dirección de IdentityRegistry.
constructor(IAssetVault _assetVault, IIdentityRegistry _identityRegistry);
```

#### 6.11.2 Mutators

```solidity
/// @notice Inicia una redención. Transfiere tokens al escrow (AssetVault.lockForRedemption).
/// @dev nonReentrant + whenNotPaused. Solo BACKEND_SIGNER_ROLE (UX abstraída: el backend firma en nombre del user
///      tras validar todos los checks en API).
///      Reglas:
///      - Lote en estado ALMACENADO o REDENCION_PARCIAL.
///      - buyer KYC tier >= 2, no sancionado, no frozen.
///      - buyer tiene balance suficiente del loteId en AssetVault.
///      - cantidadTokens > 0.
/// @param loteId Lote a redimir.
/// @param buyer Wallet del comprador.
/// @param cantidadTokens Tokens a redimir.
/// @param hashDatosEnvio SHA-256 de los datos de envío (dirección, contacto, instrucciones).
/// @return redemptionId ID asignado.
function iniciarRedencion(
    uint256 loteId,
    address buyer,
    uint256 cantidadTokens,
    bytes32 hashDatosEnvio
) external returns (uint256 redemptionId);

/// @notice Confirma que la exportación está en curso (DUE emitida).
/// @dev Solo ORACLE_ROLE. Transición INICIADA → EN_EXPORTACION.
/// @param redemptionId ID de la redención.
/// @param dueNumero Referencia legible de Aduana (para audit trail human-readable).
/// @param hashDUE SHA-256 del documento DUE.
function confirmarExportacion(
    uint256 redemptionId,
    string calldata dueNumero,
    bytes32 hashDUE
) external;

/// @notice Confirma entrega final. Quema los tokens en escrow definitivamente.
/// @dev Solo ORACLE_ROLE. nonReentrant. Transición EN_EXPORTACION → COMPLETADA.
///      Llama a AssetVault.burnRedemptionTokens.
/// @param redemptionId ID.
/// @param hashBLAWB SHA-256 del Bill of Lading / Airway Bill.
function completarRedencion(uint256 redemptionId, bytes32 hashBLAWB) external;

/// @notice Cancela una redención y devuelve los tokens al buyer.
/// @dev Solo ORACLE_ROLE o COMPLIANCE_OFFICER_ROLE. nonReentrant.
///      Transición INICIADA → CANCELADA (común).
///      Transición EN_EXPORTACION → CANCELADA (excepcional, requiere documentar motivo).
///      Llama a AssetVault.returnRedemptionTokens.
/// @param redemptionId ID.
/// @param motivo String corto.
function cancelarRedencion(uint256 redemptionId, string calldata motivo) external;

/// @notice Pausa nuevas redenciones (las en curso continúan via oracle).
function pause() external;

/// @notice Despausa.
function unpause() external;
```

#### 6.11.3 View functions

```solidity
/// @notice Devuelve los datos completos de una redención.
function getRedencion(uint256 redemptionId) external view returns (Redencion memory);

/// @notice Devuelve el estado de una redención.
function getEstadoRedencion(uint256 redemptionId) external view returns (EstadoRedencion);

/// @notice Devuelve la lista de redemptionIds de un buyer.
function getRedencionesByBuyer(address buyer) external view returns (uint256[] memory);

/// @notice Devuelve la lista de redemptionIds de un lote.
function getRedencionesByLote(uint256 loteId) external view returns (uint256[] memory);
```

### 6.12 Overrides

No requiere overrides custom (combinación `AccessControl + Pausable + ReentrancyGuard` no presenta conflictos C3).

### 6.13 Consideraciones de seguridad

1. **Reentrancy:** `iniciarRedencion`, `completarRedencion`, `cancelarRedencion` llaman a `AssetVault` (external). `nonReentrant` + checks-effects-interactions.

2. **Escrow consistency:**
   - El contrato delega el balance ERC-1155 a `AssetVault` (no es self-custody). La integridad depende de que `AssetVault.lockForRedemption` solo sea callable por este contrato.
   - **Invariant:** `sum(redenciones[id].cantidadTokens for INICIADA/EN_EXPORTACION) == AssetVault.balanceOf(address(this), loteId)` para cada loteId.

3. **State transitions:** Validar transición exacta en cada mutator. Tests de invariantes en Foundry para cubrir transiciones inválidas.

4. **DoS por buyer/lote arrays:**
   - `_redencionesPorBuyer` y `_redencionesPorLote` solo se appendean (nunca iteran on-chain).

5. **Cancelación post-exportación:**
   - Permitida pero costosa (logísticamente). Caller debe documentar via `motivo`. El backend debe propagar la cancelación al sistema de tracking off-chain.

6. **Validación KYC en cancelar/completar:**
   - **No revalidar KYC** en `completarRedencion` o `cancelarRedencion`. Si el usuario perdió KYC entre el inicio y el final, la operación debe seguir (ya no se puede revertir el envío físico). El compliance officer puede congelar la cuenta receptora si aplica, pero no bloquear la finalización.

7. **Race condition compra vs redención:**
   - El balance del usuario en AssetVault se valida en `iniciarRedencion` antes del `lockForRedemption`. Si entre validación y lock el balance cambia (no debería en práctica porque no hay P2P), la llamada falla en `lockForRedemption`.

8. **Pausabilidad:**
   - Pausar bloquea solo `iniciarRedencion`. `completarRedencion` y `cancelarRedencion` siempre disponibles para el oracle (necesarias para resolver redenciones en curso ante incidente).

---

## 7. Contrato 4: `LabRegistry.sol`

### 7.1 Propósito

`LabRegistry` mantiene la whitelist de laboratorios certificados autorizados a firmar `QualityAttestation`s. Cada lab tiene una dirección de firma (clave pública ECDSA registrada on-chain), una jurisdicción ISO, especializaciones (palinología, NMR, C4, residuos), un hash de su acreditación documental y un flag `active`. Consultado por `AssetVault.confirmarCalidad` para validar (1) que cada lab está autorizado en su especialización y (2) que la firma sobre el digest del reporte es válida.

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

Declara:
- `crearLote`, `comprar`, `confirmarCosecha`, `confirmarCalidad`, `confirmarAlmacenamiento`, `marcarFallido`, `reembolsarLoteFallido`
- `lockForRedemption`, `burnRedemptionTokens`, `returnRedemptionTokens`
- `getLote`, `getLoteEstado`, `getQualityAttestation`, `isMonofloralCertified`, `tokensDisponibles`
- Todos los eventos públicos
- Errors documentados en sección 4.9
- Re-export del enum `LoteEstado` y del struct `LoteMiel`, `QualityAttestation`

> **Patrón:** los structs y enums se declaran en el contrato concreto y la interfaz los **re-importa** vía `import { LoteEstado, LoteMiel, QualityAttestation } from "../AssetVault.sol";` o se declaran en un archivo separado `types/AssetVaultTypes.sol` (preferido para limpieza). CONFLICT: ver sección 10.

### 8.2 `IIdentityRegistry.sol`

Declara:
- `setKYC`, `markSanctioned`, `unmarkSanctioned`, `freeze`, `unfreeze`, `revokeKYC`, `setPlumeArcBridge`
- `getIdentity`, `getTier`, `checkCompliance`, `isCompliant`, `isSanctioned`, `isFrozen`
- Eventos
- Errors
- Re-export del struct `IdentityData`

### 8.3 `IRedemptionManager.sol`

Declara:
- `iniciarRedencion`, `confirmarExportacion`, `completarRedencion`, `cancelarRedencion`, `pause`, `unpause`
- `getRedencion`, `getEstadoRedencion`, `getRedencionesByBuyer`, `getRedencionesByLote`
- Eventos
- Errors
- Re-export del enum `EstadoRedencion` y del struct `Redencion`

### 8.4 `ILabRegistry.sol`

Declara:
- `addLab`, `deactivateLab`, `reactivateLab`, `updateLabSpecializations`
- `getLab`, `isActive`, `isLabCertifiedFor`, `getAllLabs`, `verifyAttestationSignature`, `getLabReportDigest`
- Eventos
- Errors
- Re-export del enum `Specialization` y del struct `Lab`

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
| D1 | El **contador `nextLoteId`** es global en `AssetVault` (no por asset type). Asset = miel (único en MVP), por lo que el espacio de IDs es compartido. | Simplifica el sistema en MVP. Multi-asset queda fuera de scope. |
| D2 | `TREASURY_SRL_ROLE` se **declara como rol on-chain pero no se asigna ninguna función mutator on-chain**. Existe para audit trail (eventos pueden indexar la dirección) y para futuras extensiones. | El movimiento real de USDC al productor ocurre off-chain (Safe Wyoming → wallet productor). On-chain solo emitimos `ReservaTecnicaLiberada`. |
| D3 | `RedemptionManager` recibe la dirección de `AssetVault` por **constructor inmutable**. `AssetVault` también recibe `RedemptionManager` post-deploy via rol dedicado `REDEMPTION_MANAGER_ROLE` controlado por `DEFAULT_ADMIN_ROLE`. | Romper el ciclo de dependencia: AssetVault se deploya primero, luego RedemptionManager con ref a AssetVault, luego AssetVault.grantRole(REDEMPTION_MANAGER_ROLE, redemptionManager). |
| D4 | Los **structs y enums** se declaran en el archivo del contrato concreto (`AssetVault.sol`, `RedemptionManager.sol`, `LabRegistry.sol`) y las interfaces los **re-importan** vía `import { Type } from "../Contract.sol"`. | Evita duplicación; mantiene single source of truth. Alternativa archivo `types/*.sol` queda como opción de refactor si la auditoría la sugiere. |
| D5 | **EIP-712** se usa solo en `LabRegistry` para firmas estructuradas de labs. `AssetVault.comprar` no requiere firma del buyer porque el backend ya firmó la tx (BACKEND_SIGNER_ROLE). | Mantener footprint de firma criptográfica donde aporta seguridad real (verificación cross-party). |
| D6 | El **digest anti-replay** de attestations se computa como `keccak256(abi.encode(loteId, attestation.labAddresses, attestation.fullReportHashes, attestation.testedAt, address(this), block.chainid))`. | Garantiza unicidad por lote, set de labs, set de reportes, contrato y chain. Inmune a replay cross-chain/cross-contract. |
| D7 | **`ERC1155Pausable`** se incluye en herencia. `pause()` bloquea ALL operaciones (mints, burns, transfers internos hacia RedemptionManager). `RedemptionManager.pause()` solo bloquea `iniciarRedencion`. | Granularidad útil: ante incidente solo en exportaciones, pausar RedemptionManager. Ante incidente sistémico, pausar AssetVault. |
| D8 | **Sin URI base hardcoded**. El constructor recibe `_baseURI` como parámetro. | Permite cambiar dominio sin redeploy (vía `setLoteURI` per-lote) y deploys de test independientes. |
| D9 | **Reentrancy guards** en cualquier función que llame contratos externos: AssetVault → USDC, AssetVault → IdentityRegistry, AssetVault → LabRegistry, RedemptionManager → AssetVault. | Defense in depth + zero perf cost relevante. |
| D10 | **Compliance officer** es un único actor humano (hardware wallet), no multi-sig dedicado. Justificación: las acciones reversibles (`unmarkSanctioned`, `unfreeze`) requieren responsividad. El Safe 2-de-3 cubre las acciones críticas (`grantRole`, `confirmarCalidad`, etc.). | Trade-off velocidad vs descentralización; documentado. |

### 10.2 Conflicts detectados (requieren decisión humana antes de implementar)

**CONFLICT 1: `TREASURY_SRL_ROLE` on-chain vs off-chain.**

> En arquitectura v2.0, sección 9.1, se menciona el rol como existente on-chain. Sin embargo, en sección 23.3 flujo, "tx liberarReservaTecnica() desde wallet TREASURY_SRL_ROLE" sugiere que la wallet ejecuta una tx custom **fuera del contrato** (movimiento USDC directo en wallet operativa, no llamada a contract function).
>
> **Propuesta de resolución:** declarar el rol en `AssetVault` pero **sin asignar funciones mutator**. El rol queda como anchor de auditoría (la dirección se emite en eventos cuando aplica), y el movimiento USDC ocurre off-chain en wallet operativa. Si en V2 surge la necesidad de mover USDC on-chain, el rol ya está; basta agregar la función.
>
> **Acción:** confirmar con el responsable de tesorería que el flujo USDC al productor SRL es 100% off-chain.

**CONFLICT 2: cómo se cablea `RedemptionManager` ↔ `AssetVault`.**

> Dos opciones razonables:
>
> **(A) Rol dedicado en AssetVault:** `REDEMPTION_MANAGER_ROLE` que solo el RedemptionManager puede ostentar. Asignado post-deploy.
>
> **(B) Address inmutable en AssetVault:** parámetro de constructor `redemptionManager` que se setea con un setter `setRedemptionManager` callable solo una vez por `DEFAULT_ADMIN_ROLE`.
>
> **Propuesta de resolución:** opción (A). Pros: usa el mecanismo AccessControl ya presente, no introduce flag custom one-time. Contras: requiere disciplina operacional de no asignar el rol a más de una address.
>
> **Acción:** confirmar opción (A); las specs asumen (A) por defecto.

**CONFLICT 3: storage layout de `QualityAttestation` con arrays dinámicos.**

> Tener `address[] labAddresses` y `bytes32[] fullReportHashes` como **mismo length** se enforce en runtime pero no en estructura. Implica gas costoso en SSTORE/SLOAD al populate.
>
> **Propuesta de resolución:** mantener el diseño con arrays (es la forma natural y el costo es razonable: ~2 labs típicamente). Si en futuras versiones se decide compactar, evaluar struct con `Lab[2] labs` fija (downside: no extensible).
>
> **Acción:** validar gas cost en testnet con 2 y con 5 labs. Si excede 250k gas, considerar compactación.

**CONFLICT 4: `reembolsarLoteFallido` requiere USDC líquido en `AssetVault`.**

> El contrato `AssetVault` no recibe USDC en `comprar` (todos los pagos son off-chain). Pero `reembolsarLoteFallido` debe transferir USDC pro-rata. ¿De dónde sale el USDC?
>
> **Propuesta de resolución:** la wallet operativa Safe Wyoming debe **prefondear** el contrato con USDC antes de invocar `reembolsarLoteFallido`. El monto = `reservaTecnicaUSDCDisponible[loteId] + suma de payments retenidos del lote`. Backend calcula este monto vía Goldsky + audit log; el Safe transfiere USDC al contrato; oracle ejecuta `reembolsarLoteFallido`.
>
> Alternativamente: usar `IERC20.transferFrom` desde Safe operativo en cada reembolso (requiere allowance previa). Más complejo pero evita parking USDC en el contrato.
>
> **Acción:** confirmar flujo con tesorería. Las specs documentan ambas vías como aceptables; la implementación elige basada en preferencia operacional.

**CONFLICT 5: jurisdicción ISO en `bytes2` vs `bytes3`.**

> ISO 3166-1 alpha-2 usa 2 caracteres. ISO 3166-1 alpha-3 usa 3 (Bolivia = "BO" alpha-2, "BOL" alpha-3). La arquitectura usa `bytes2` consistentemente, pero algunos sistemas legales prefieren alpha-3 para no confundir con códigos comerciales.
>
> **Propuesta de resolución:** mantener `bytes2` (alpha-2) consistente con la arquitectura v2.0. Documentar en un comentario que es ISO 3166-1 alpha-2.
>
> **Acción:** sin cambio. Confirmar con compliance que alpha-2 es suficiente.

**CONFLICT 6: confirmación de calidad — ¿una sola firma de Safe o firmas individuales de cada lab + Safe?**

> El flujo descrito en §7B.4 indica:
> 1. Cada lab firma su reporte off-chain (firmas ECDSA del lab).
> 2. Backend valida firmas.
> 3. Safe multi-sig firma la **transacción** `confirmarCalidad`.
>
> Pero la signature `confirmarCalidad(loteId, attestation, labSignatures[])` exige que las firmas de cada lab sean parámetros explícitos.
>
> **Propuesta de resolución (ya en specs):** la transacción la ejecuta `ORACLE_ROLE` (Safe), pero pasa las `labSignatures[]` como parámetro. El contrato valida cada firma contra `LabRegistry.verifyAttestationSignature`. Esto da **doble validación criptográfica**: cada lab firma su reporte; el Safe firma la tx que las agrega.
>
> **Acción:** sin cambio.

**CONFLICT 7: cuántas wallets distintas tienen `BACKEND_SIGNER_ROLE`.**

> Si una sola wallet KMS firma todas las txs (compras, KYC, redenciones), el blast radius de un compromiso es total.
>
> **Propuesta de resolución:** un único `BACKEND_SIGNER_ROLE` en MVP por simplicidad operacional. Plan de fase 2: separar en `MINTER_SIGNER`, `KYC_SIGNER`, `REDEMPTION_SIGNER` con wallets independientes. ADR pendiente.
>
> **Acción:** documentar en runbook de operaciones que la wallet es high-value; rotación trimestral mínima.

**CONFLICT 8: revocación de KYC retroactiva.**

> Si una wallet pasa de tier 2 a revocada después de iniciar una redención (estado `EN_EXPORTACION`), ¿la redención se completa o se cancela?
>
> **Propuesta de resolución (ya en specs §6.13 punto 6):** la redención se completa. La revocación de KYC posterior no debe revertir un envío físico ya en curso. El compliance officer puede tomar acciones adicionales off-chain (informe a autoridad, devolución física, etc.) pero la tx on-chain se completa.
>
> **Acción:** sin cambio. Documentar en runbook de compliance.

**CONFLICT 9: oracle execution de `confirmarCalidad` requiere el array de `labAddresses`. ¿Y si el lab firmó pero ya fue desactivado entre la firma y la tx?**

> **Propuesta de resolución:** validar en `confirmarCalidad` que cada lab esté activo **en el momento de la tx**. Si un lab fue desactivado, la attestation falla y debe re-emitirse con un lab activo alternativo.
>
> **Acción:** sin cambio. Documentar en runbook de calidad.

**CONFLICT 10: granularidad — gramos vs kilos vs tokens en parámetros públicos.**

> `crearLote` recibe `kgEsperadosTotal` en kilos enteros. `confirmarCosecha` recibe `kgCosechadoReal` en kilos enteros. `tokensDisponibles` devuelve tokens (0.5 kg cada uno).
>
> **Propuesta de resolución:** mantener kilos en parámetros de input (más legible humanamente), pero **convertir internamente a gramos** usando `GRAMOS_POR_KILO`. La conversión `tokens ↔ gramos` usa `GRAMOS_POR_TOKEN = 500`. Documentar en cada función con `@dev`.
>
> **Acción:** sin cambio. Confirmar que ningún caller pasa fracciones de kilo (requeriría cambiar el tipo a algo más fino, e.g. centigramos).

---

**Fin del documento `CONTRACT-SPECS.md` v1.0**