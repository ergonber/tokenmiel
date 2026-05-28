# Deploy Scripts (Gap 2) — Diseño

**Fecha:** 2026-05-28
**Autor:** Daniel Hidalgo Carrasco
**Estado:** Aprobado (diseño) — pendiente de plan de implementación
**Scope:** `packages/contracts/script/` (nuevo) + refactor de `packages/contracts/test/BaseTest.t.sol`

---

## 1. Contexto y objetivo

El **Gap 2** del handoff (`docs/SMART-CONTRACTS-HANDOFF.md`) es la ausencia de deploy scripts: `packages/contracts/script/` está vacío. No hay forma de desplegar los 3 contratos del MVP de manera reproducible.

El obstáculo de fondo es una **dependencia cíclica**:

- `RedemptionManager` recibe `AssetVault` como `immutable` en su constructor.
- `AssetVault` necesita la address de `RedemptionManager`, pero esa address no existe hasta que `RedemptionManager` se despliega.

La cadena se rompe con un setter post-deploy: `AssetVault.setRedemptionManager(rm)` (one-time, `onlyRole(DEFAULT_ADMIN_ROLE)`, revierte `RedemptionManagerAlreadySet` si se llama dos veces).

**Objetivo:** crear deploy scripts para los 3 contratos del MVP (`IdentityRegistry`, `AssetVault`, `RedemptionManager`), con el wiring (deploy en orden + ruptura del ciclo) factorizado en un módulo reutilizable que consuman **tanto el script como los integration tests del Gap 1** — eliminando duplicación de raíz.

**Decisión de orden (Gap 2 antes que Gap 1):** el `setUp()` de los tests y el deploy script comparten exactamente la misma necesidad de orquestación. Si ese wiring nace una sola vez, los integration tests del Gap 1 lo consumen sin reescribirlo.

---

## 2. Decisiones de diseño

| # | Decisión | Razón |
|---|----------|-------|
| 1 | **Lib agnóstica + perfiles por red** | Separa el invariante (orden de deploy + wiring) del variable (addresses, admin, USDC por entorno). La dependencia cíclica pasa a ser un parámetro de perfil, no un hardcode. |
| 2 | **`HelperConfig` en Solidity** | Config type-safe seleccionada por `block.chainid`, patrón idiomático de Foundry, testeable, sin archivos externos para correr. Secrets (private key, RPC) por env var. |
| 3 | **`abstract contract DeployCore`** (no `library`) | Heredado por el Script y por `BaseTest` refactorizado. Comparte el wiring exacto; el `broadcast`/`prank` lo pone cada consumidor. Las libraries con `new` quedan linkeadas y no pueden envolver `broadcast`/`prank`. |

---

## 3. Arquitectura y componentes

```
script/
  HelperConfig.s.sol   # NetworkConfig por block.chainid + MockUSDC en local
  DeployCore.sol       # abstract, neutral: _deployContracts(cfg) + _breakCycle(...)
  DeployPlume.s.sol    # is Script, DeployCore → run() con vm.startBroadcast()
test/
  BaseTest.t.sol           # REFACTOR: is Test, DeployCore → setUp() con vm.prank
  integration/Deploy.t.sol # NUEVO: testea el orquestador end-to-end
```

### 3.1 `HelperConfig.s.sol`

Fuente de los perfiles. Su corazón es la struct:

```solidity
struct NetworkConfig {
    address admin;                     // DEFAULT_ADMIN_ROLE (Safe 2-de-3 en mainnet)
    address adminOperator;             // ADMIN_ROLE
    address backendSigner;             // BACKEND_SIGNER_ROLE
    address complianceOfficer;         // COMPLIANCE_OFFICER_ROLE
    address complianceOfficerSuplente; // COMPLIANCE_OFFICER_ROLE
    address oracleSafe;                // ORACLE_ROLE
    address treasurySRL;               // TREASURY_SRL_ROLE
    address usdc;                      // payment token (MockUSDC en local)
    string  uri;                       // ERC-1155 metadata URI
    bool    executorIsAdmin;           // ¿el ejecutor puede romper el ciclo?
}
```

- `getConfig()` → selecciona la `NetworkConfig` por `block.chainid` (Plume / Plume testnet / Anvil local).
- `getOrCreateAnvilConfig()` → en local despliega `MockUSDC`, rellena `usdc`, y marca `executorIsAdmin = true`.

### 3.2 `DeployCore.sol`

`abstract contract` neutral (no extiende `Script` ni `Test`). Dos funciones `internal`:

```solidity
function _deployContracts(NetworkConfig memory cfg)
    internal returns (IdentityRegistry, AssetVault, RedemptionManager);

function _breakCycle(AssetVault av, address rm, NetworkConfig memory cfg) internal;
```

- `_deployContracts` hace los 3 `new` en orden: `IdentityRegistry` → `AssetVault` (con `redemptionManager` implícito en `address(0)`, ya que `InitParams` no lo incluye) → `RedemptionManager`.
- `_breakCycle` llama `setRedemptionManager` **solo si** `cfg.executorIsAdmin`; si no, hace `console2.log` de la calldata que el Safe debe firmar y NO ejecuta.

### 3.3 Consumidores

- `DeployPlume.s.sol` (`is Script, DeployCore`) → `run()` envuelve todo en `vm.startBroadcast`.
- `BaseTest.t.sol` (refactor: `is Test, DeployCore`) → `setUp()` arma config local y prankea `admin`. **Mismo wiring, cero duplicación.**

---

## 4. Flujo de deploy

El mismo `DeployCore`, dos contextos.

### 4.1 Script (`DeployPlume.run()`)

1. `getConfig()` resuelve `NetworkConfig` por `block.chainid`.
2. `vm.startBroadcast(deployerKey)` — key por env en testnet; KMS/hardware en mainnet (operacional).
3. `_deployContracts(cfg)` → los 3 `new` en orden, `AssetVault` con `redemptionManager` en `address(0)`.
4. `_breakCycle(av, rm, cfg)`:
   - `executorIsAdmin == true` → `av.setRedemptionManager(rm)` ejecuta (el broadcaster ES admin en ese perfil).
   - `false` → `console2.log` de `target` + `abi.encodeCall(AssetVault.setRedemptionManager, (rm))`; el deploy queda con **wiring pendiente** para que el Safe lo firme.
5. `stopBroadcast` → log de las 3 addresses (+ MockUSDC si aplica).

Output de addresses: arrancar con `console2.log` + los artifacts nativos de Foundry (`broadcast/*.json`). Un `deployments/<chainid>.json` legible queda como opción futura (YAGNI hasta que ops lo pida).

### 4.2 Test (`BaseTest.setUp()`)

1. Config local vía `getOrCreateAnvilConfig()` — usa las **mismas constantes de address** que el `setUp()` actual (`ADMIN`, `ORACLE_SAFE`, etc.), para no romper los 149 tests.
2. `_deployContracts(cfg)` — mismo código que el script.
3. `vm.prank(cfg.admin); _breakCycle(av, rm, cfg)` — un solo call externo con autoridad, así que `prank` simple alcanza.

---

## 5. Manejo de errores

Custom errors, fail-fast:

- `UnsupportedChainId(uint256)` — `getConfig()` no matchea ningún perfil.
- `MissingConfig(string field)` — alguna address crítica en `address(0)` en perfil non-local (evita regalar un rol al zero address).
- USDC `address(0)` en non-local → revert; en local lo despliega `getOrCreateAnvilConfig`.
- **`setRedemptionManager` doble:** NO se duplica guarda — `AssetVault` ya revierte `RedemptionManagerAlreadySet`. Se confía en el contrato (boundary cubierto).
- **`executorIsAdmin=true` con deployer no-admin:** el revert de `AccessControl` hace fallar el broadcast ruidosamente. Falla temprano y claro; no se agrega validación redundante.

Práctica: correr el script en dry-run (sin `--broadcast`) para simular antes de transmitir.

---

## 6. Testing

`test/integration/Deploy.t.sol` (nuevo):

- `test_deploy_wiresAllContracts` — ciclo roto (`av.redemptionManager() == rm`), roles asignados a los holders de la config, immutables correctos (`rm.assetVault() == av`, `av.usdc() == cfg.usdc`, etc.).
- `test_breakCycle_skipsWhenExecutorNotAdmin` — con `executorIsAdmin == false`, `av.redemptionManager()` queda en `address(0)` (wiring pendiente para el Safe).
- `test_getConfig_revertsOnUnsupportedChain` — `vm.chainId(999)` → revert `UnsupportedChainId`.
- `test_helperConfig_revertsOnMissingAddress` — perfil con address(0) → revert `MissingConfig`.

**Criterio de regresión clave:** los **149 tests existentes siguen verdes** tras refactorizar `BaseTest` — mismo wiring, solo factorizado, sin tocar addresses ni comportamiento.

Al escribir estos tests aplica el skill `solidity-testing`.

---

## 7. Supuestos y temas abiertos

- **Scope de contratos:** se despliegan los 3 del MVP. `src/adapters` y `src/libraries` se tratan como dependencias internas (no deploy independiente) salvo corrección.
- **chainids de Plume:** a confirmar contra la doc oficial de Plume al implementar — no se inventan números.
- **Output de addresses:** `console2.log` + broadcast artifacts nativos. `deployments/<chainid>.json` como opción futura.
- **Modelo Safe mainnet (`executorIsAdmin=false`):** el script emite la calldata pendiente; la firma multisig y el manejo del delay de 3 días de `AccessControlDefaultAdminRules` quedan para el playbook operacional de mainnet (fuera del scope de este diseño, pero el código ya lo soporta vía el flag).

---

## 8. Criterios de éxito

- `forge build` limpio.
- `DeployPlume` corre en dry-run (sin `--broadcast`) sin revertir para el perfil local.
- Los **149 tests existentes** siguen verdes tras el refactor de `BaseTest`.
- `integration/Deploy.t.sol` cubre **ambas ramas** de `_breakCycle` y los reverts de config.
- El coverage global no baja.

---

## 9. Referencias

- `docs/SMART-CONTRACTS-HANDOFF.md` — Gap 2 (§6)
- `packages/contracts/src/{AssetVault,IdentityRegistry,RedemptionManager}.sol`
- `packages/contracts/test/BaseTest.t.sol` — a refactorizar
- `packages/contracts/foundry.toml` — `[rpc_endpoints]`
