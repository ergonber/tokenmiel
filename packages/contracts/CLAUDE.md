# CLAUDE.md — packages/contracts (smart contracts Solidity)

> Reglas obligatorias para cualquier agente que trabaje con smart contracts Solidity. Scope acotado: SOLO archivos en `packages/contracts/`.

---

## 1. Scope

**Lo que SÍ podés tocar en este scope:**
- `packages/contracts/src/**` — código Solidity de los contratos
- `packages/contracts/test/**` — tests Foundry
- `packages/contracts/script/**` — deployment scripts (`*.s.sol`)
- `packages/contracts/foundry.toml`, `remappings.txt`
- `packages/contracts/package.json`
- `packages/abis/` — outputs generados (wagmi generate)
- `docs/architecture/ADR-*.md` — para crear nuevos ADRs si cambia arquitectura

**Lo que NO podés tocar:**
- `apps/web/**`, `apps/api/**` — otras áreas
- `packages/db/**`, `packages/shared/**`, `packages/ui/**`
- `ARQUITECTURA-TECNICA-MVP.md`, `CONTRACT-SPECS.md`, `TEST-SPECS.md` (sin ADR)

---

## 2. Stack

- **Solidity:** 0.8.24+ (fijo `0.8.24`, no caret)
- **Framework:** Foundry (forge, cast, anvil)
- **Librería base:** OpenZeppelin Contracts v5.x
- **EVM target:** `paris` (compatibilidad Plume + Polygon)
- **Optimizer:** `enabled = true`, `runs = 200`

---

## 3. Skills relevantes (invocar antes de trabajar)

- `solidity-testing` — **AUTO-INVOKE** antes de escribir o modificar tests `.t.sol`
- `solidity-security` — antes de modificar contratos productivos
- `foundry-solidity` — comandos forge/cast/anvil
- `web3-testing` — patrones de testing avanzados (mainnet fork, etc.)
- `account-abstraction` — si tocás Plume Smart Wallets

---

## 4. Archivos críticos a leer ANTES de cualquier cambio

**Orden recomendado:**
1. `/Users/firrton/Desktop/tokenización/CLAUDE.md` (raíz, reglas globales del proyecto)
2. **Este archivo** (CLAUDE.md de área)
3. **`docs/architecture/CONTRACT-SPECS.md`** (source of truth para signatures, structs, errors, events)
4. **`docs/architecture/TEST-SPECS.md`** (TDD-first: tests primero)
5. **`docs/architecture/ADR-001-multi-chain-strategy.md`** (Plume + Polygon)
6. **`docs/architecture/ADR-002-erc-1155.md`** (token standard)
7. **`docs/architecture/ADR-003-4-contracts-immutable.md`** (arquitectura contratos)
8. **`docs/architecture/ADR-004-oracle-design.md`** (Safe + Chainlink PoR)
9. **`docs/architecture/ADR-005-lab-registry-quality-oracle.md`** (oráculo de calidad)
10. **`ARQUITECTURA-TECNICA-MVP.md`** secciones 6, 7, 7B, 9

---

## 5. Convenciones Solidity

### Naming
- Contratos / interfaces / libraries: `PascalCase` (`AssetVault`, `IIdentityRegistry`)
- Funciones públicas/external del dominio: `camelCase` rioplatense (`comprar`, `confirmarCosecha`, `iniciarRedencion`)
- Funciones OpenZeppelin (heredadas): inglés (`grantRole`, `pause`)
- Funciones internas/private: prefijo `_` (`_validateKYC`, `_releaseReserva`)
- State variables públicas: `camelCase` sin prefijo
- State variables privadas: `_camelCase`
- Constantes / immutables: `SCREAMING_SNAKE_CASE`
- Structs: `PascalCase` (`LoteMiel`, `QualityAttestation`)
- Enums: `PascalCase` con valores `SCREAMING_SNAKE_CASE`
- Eventos: `PascalCase` (`LoteComprado`, `CosechaConfirmada`)
- Errores custom: `PascalCase` (`NotKYCVerified`, `AddressSanctioned`)

### Estructura de archivo
```solidity
// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

// 1. Imports OpenZeppelin
// 2. Imports de proyecto
// 3. Interfaces
// 4. Libraries
// 5. Errors
// 6. Contract

contract AssetVault is ERC1155, ERC1155Supply, ERC1155Pausable, AccessControl, ReentrancyGuard {
    // 1. Type declarations (using ... for ...)
    // 2. State variables
    //    - Constants
    //    - Immutables
    //    - Mappings
    //    - Structs (instances)
    // 3. Events
    // 4. Errors
    // 5. Modifiers
    // 6. Constructor
    // 7. External functions
    // 8. Public functions
    // 9. Internal functions
    // 10. Private functions
    // 11. View / pure functions
    // 12. Override functions (OpenZeppelin)
}
```

### Reglas estrictas
- **Custom errors obligatorios** (gas-efficient): NUNCA `require(condition, "string")` ni `revert("string")`.
- **NatSpec completo** en cada función externa/pública:
  ```solidity
  /// @notice Descripción para el usuario final
  /// @dev Detalles técnicos para desarrolladores
  /// @param paramName descripción del parámetro
  /// @return descripción del valor retornado
  /// @custom:security consideraciones de seguridad relevantes
  ```
- **Storage packing**: ordenar campos de struct para minimizar slots ocupados.
- **Roles via OpenZeppelin AccessControl** — sin admin único hardcoded.
- **Sin proxy / sin upgradeability** — contratos inmutables.
- **Sin `tx.origin`** — usar `msg.sender`.
- **Sin `block.timestamp` para randomness** o decisiones críticas.
- **Sin inline assembly** sin auditoría explícita y ADR.
- **Checks-Effects-Interactions** estricto para prevenir reentrancy.
- **External calls** envueltos en `nonReentrant` modifier cuando aplique.
- **SafeERC20** para transferencias de USDC.

---

## 6. TDD workflow obligatorio

**Red → Green → Refactor.** NO se acepta código sin tests previos.

### Orden de trabajo
1. **Read** `CONTRACT-SPECS.md` para la signature
2. **Read** `TEST-SPECS.md` para los test cases requeridos
3. **Write** los tests (`.t.sol`) que fallan inicialmente (RED)
4. **Write** la implementación mínima que hace pasar los tests (GREEN)
5. **Refactor** si necesario, manteniendo tests verdes
6. **Verify** coverage 100% líneas/branches en el archivo
7. **Document** NatSpec + actualizar ADR si la implementación reveló decisión nueva

### Coverage no negociable
- Líneas: 100%
- Branches: 100%
- Funciones: 100%

### Fuzz testing
- ≥ 10,000 runs por test fuzz
- Variables: precios, kg, balances, percentages

### Invariant testing
- ≥ 50,000 runs, depth 100
- Invariantes documentados (ver TEST-SPECS.md)

---

## 7. Comandos forge comunes

```bash
# Compilación
forge build
forge build --sizes                          # tamaño contratos (límite 24576 bytes)

# Tests
forge test -vvv                              # verbose (logs)
forge test --match-contract AssetVaultTest
forge test --match-test test_comprar
forge test --fuzz-runs 10000 -vv
forge test --invariant-runs 50000 --invariant-depth 100

# Coverage
forge coverage --report summary
forge coverage --report lcov

# Format y lint
forge fmt
forge fmt --check                            # CI mode

# Análisis estático
slither .                                    # security analysis
slither . --print human-summary

# Gas
forge snapshot                               # snapshot de gas
forge snapshot --diff                        # comparar con snapshot anterior

# Anvil (testnet local)
anvil --fork-url $PLUME_RPC_URL              # fork de Plume

# Scripts deployment
forge script script/DeployPlume.s.sol \
  --rpc-url $PLUME_RPC_URL \
  --broadcast \
  --verify \
  --etherscan-api-key $PLUME_EXPLORER_API_KEY
```

---

## 8. Lo que NO debe hacer en esta área

- ❌ Agregar upgradeability (UUPS, Transparent, Diamond) — contratos son **inmutables** (ADR-003)
- ❌ Usar string reverts (`require(x, "error")`, `revert("error")`) — siempre custom errors
- ❌ Inline assembly sin auditoría externa explícita y ADR
- ❌ Usar `tx.origin` — siempre `msg.sender`
- ❌ Usar `block.timestamp` para randomness o decisiones críticas
- ❌ Permitir transferencias P2P del token — override `_update()` debe revertir
- ❌ Mintear tokens sin validar KYC (`canMint` en IdentityRegistry)
- ❌ Burnear tokens fuera del flujo `RedemptionManager`
- ❌ Liberar reserva técnica antes de `confirmarCosecha`
- ❌ Aceptar attestations de calidad de labs no whitelisted en `LabRegistry`
- ❌ Permitir un solo lab para QualityAttestation (mínimo 2 independientes)
- ❌ Hardcodear addresses de OpenZeppelin o protocolos externos en código (usar constructor params o constants documentadas)
- ❌ Deployar a mainnet sin auditoría externa completada
- ❌ Modificar `CONTRACT-SPECS.md` sin ADR previo
- ❌ Saltarse `slither .` antes de commit a `main`
- ❌ Commitear `out/`, `cache/`, `broadcast/` (en `.gitignore`)
- ❌ Confiar en oracle/multi-sig sin documentar las direcciones en ADR

---

## 9. Convenciones de tests Foundry

### Naming
```
test_<context>_<scenario>_<expectedOutcome>()
testFuzz_<context>_<property>(<params>)
invariant_<property>()
test_RevertWhen_<context>_<scenario>()
```

### Estructura básica (Arrange-Act-Assert)
```solidity
function test_comprar_HappyPath_MintCorrectAmount() public {
    // Arrange
    _setupKYC(buyer, 1);
    uint256 cantidad = 10;

    // Act
    vm.prank(backendSigner);
    assetVault.comprar(loteId, cantidad, buyer, montoUSDC, paymentRefHash);

    // Assert
    assertEq(assetVault.balanceOf(buyer, loteId), cantidad);
    // ... más assertions
}
```

### Setup helpers
- `BaseTest.t.sol` con setup compartido (deploy contratos, mock USDC, KYC base)
- Funciones helper privadas: `_setupKYC()`, `_createLote()`, etc.
- Mocks de OpenZeppelin: `MockERC20` para USDC

### Forking tests (para integración con Plume real)
```solidity
function setUp() public {
    plumeFork = vm.createSelectFork(vm.envString("PLUME_RPC_URL"));
}
```

---

## 10. Workflow loop dentro del área

Cada cambio en `packages/contracts/`:

1. **Build:**
   - Leer/escribir test en `test/`
   - Escribir implementación en `src/`
   - `forge build`
2. **Test:**
   - `forge test -vvv` (todos pasan)
   - `forge test --fuzz-runs 10000` (fuzz tests pasan)
   - `forge coverage --report summary` (100% mantenido)
3. **Document:**
   - NatSpec actualizado
   - ADR si cambio arquitectónico
   - README de contrato si crítico
4. **Review:**
   - `slither .` sin issues high
   - `forge snapshot --diff` (gas no creció sin razón)
   - Si tocó lógica crítica: invocar `solidity-security` skill

---

## 11. Integraciones externas (precaución especial)

### OpenZeppelin v5
- Usar **siempre** `5.x` (verificar `package.json` / `remappings.txt`)
- NUNCA copy-paste de internet — instalar via `forge install OpenZeppelin/openzeppelin-contracts`

### Chainlink (PoR feeds)
- Solo lectura de feeds (no escritura)
- Address del feed configurado en deployment script
- Validar `latestRoundData().updatedAt` no esté stale

### Plume Arc (KYC bridge)
- Adapter en `packages/contracts/src/adapters/PlumeArcAdapter.sol`
- Lectura de estado KYC nativo de Plume
- Fallback a `IdentityRegistry.sol` custom

---

**Última actualización:** 2026-05-19
**Aplicabilidad:** todos los archivos bajo `packages/contracts/**` y `packages/abis/**`
