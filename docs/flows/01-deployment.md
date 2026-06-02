# Flow 01: Deployment of 4 Contracts + Role Bootstrap

> **⚠️ MVP RECONCILIATION (2026-05-28):** This document describes the original **4-contract** design including `LabRegistry`. The **current MVP deploys only 3 contracts** — `IdentityRegistry`, `AssetVault`, `RedemptionManager` — because **`LabRegistry` is deferred to phase 2** (`phase2/`, ADR-010). The real deploy script is **`script/DeployPlume.s.sol`** (`deploy()` + `getConfig()` per `block.chainid` + `run()`), and `AssetVault.InitParams` has **no `labRegistry` field**. Step 2 (LabRegistry deploy) and Step 6 (SeedLabs) below do NOT apply to the MVP; the real deploy order is `IdentityRegistry → AssetVault → RedemptionManager → setRedemptionManager`. The rest (roles, governance, verification, error cases) stays a valid reference.

## Executive Summary

This flow covers the one-time deployment of the four immutable smart contracts that make up the tokenization platform, in the correct dependency order, followed by the configuration of roles and the wiring of circular dependencies (`AssetVault` ↔ `RedemptionManager`). The entire deployment must be executed in a single coordinated session; the deployer EOA only holds roles during the deployment window and must surrender them to the Safe multi-sig before the session ends.

This is executed once at mainnet launch. On testnets, it is repeated as needed during development.

---

## Actors Involved

- **🤖 Deployer EOA** — Temporary deployer wallet (hardware wallet). Holds gas. Surrenders all roles at end of session.
- **🔐 Safe Wyoming (DEFAULT_ADMIN)** — Gnosis Safe 2-of-3 at `SAFE_ADMIN_ADDR`. Receives `DEFAULT_ADMIN_ROLE` on all four contracts.
- **🔐 Safe Operator (ADMIN_ROLE)** — Gnosis Safe 2-of-3 at `SAFE_OPERATOR_ADDR`. Receives `ADMIN_ROLE` on `AssetVault` and `LabRegistry`.
- **🤖 Backend Signer** — HSM-backed EOA at `BACKEND_SIGNER_ADDR`. Receives `BACKEND_SIGNER_ROLE`.
- **⚖️ Compliance Officer** — Hardware wallet at `COMPLIANCE_ADDR`. Receives `COMPLIANCE_OFFICER_ROLE`.
- **⚖️ Compliance Suplente** — Hardware wallet at `COMPLIANCE_SUPLENTE_ADDR`. Receives `COMPLIANCE_OFFICER_ROLE`.
- **🔐 Oracle Safe** — Gnosis Safe 2-of-3 at `ORACLE_SAFE_ADDR`. Receives `ORACLE_ROLE`.
- **🏢 Treasury SRL** — Hardware wallet at `TREASURY_SRL_ADDR`. Receives `TREASURY_SRL_ROLE`.

---

## Pre-conditions

- Plume Mainnet RPC available and stable.
- Deployer EOA funded with native gas token (PLUME).
- USDC contract address on Plume confirmed (`USDC_ADDR`).
- All Safe multi-sig wallets configured with correct signers and threshold 2-of-3.
- `DeployPlume.s.sol` and `SeedLabs.s.sol` deployment scripts written, reviewed, and tested on Plume Testnet.
- At least 2 labs registered on testnet and ready to seed on mainnet (IBNORCA + Eurofins).
- Security audit completed and all High/Medium findings resolved.

---

## Sequence Diagram

```
Deployer  --> Chain       : forge script DeployPlume.s.sol --broadcast

--- Step 1: Deploy IdentityRegistry ---
Deployer  --> Chain       : new IdentityRegistry(admin, backendSigner, compliance, complianceSuplente)
Chain     --> IR          : constructor() grants roles
IR        ~~> (no event)  : AccessControl roles granted silently

--- Step 2: Deploy LabRegistry ---
Deployer  --> Chain       : new LabRegistry(admin, adminOperator, compliance, complianceSuplente)
Chain     --> LR          : constructor() grants roles
LR        ~~> (no event)  : AccessControl roles granted silently

--- Step 3: Deploy AssetVault ---
Deployer  --> Chain       : new AssetVault(InitParams{admin, adminOp, backendSigner, compliance,
                                complianceSuplente, oracleSafe, treasurySRL,
                                usdc, identityRegistry, labRegistry, uri})
Chain     --> AV          : constructor() validates all non-zero, grants roles
AV        ~~> (no event)  : AccessControl roles granted silently

--- Step 4: Deploy RedemptionManager ---
Deployer  --> Chain       : new RedemptionManager(admin, oracleSafe, compliance,
                                complianceSuplente, assetVault, identityRegistry)
Chain     --> RM          : constructor() validates, grants roles
RM        ~~> (no event)  : AccessControl roles granted silently

--- Step 5: Wire circular dependency ---
Deployer  --> AV          : setRedemptionManager(redemptionManager)   [DEFAULT_ADMIN_ROLE]
AV        --> AV          : redemptionManager = address(RM)
AV        --> AV          : (one-time set, RedemptionManagerAlreadySet guard active)

--- Step 6: Seed LabRegistry ---
Deployer  --> LR          : addLab(IBNORCA_SIGNER, nameHash, "BO", [PALINOLOGIA,NMR,C4_SUGAR,PESTICIDAS], accreditationHash)  [ADMIN_ROLE]
LR        ~~> LabAdded    : LabAdded(IBNORCA_SIGNER, "BO", [...specs], accreditationHash)

Deployer  --> LR          : addLab(EUROFINS_SIGNER, nameHash, "DE", [PALINOLOGIA,NMR,C4_SUGAR,PESTICIDAS,ANTIBIOTICOS], accreditationHash)  [ADMIN_ROLE]
LR        ~~> LabAdded    : LabAdded(EUROFINS_SIGNER, "DE", [...specs], accreditationHash)

--- Step 7: Verify on explorer ---
Deployer  --> PlumeExplorer : verify IdentityRegistry, LabRegistry, AssetVault, RedemptionManager

--- Step 8: Renounce deployer roles (if any were auto-granted) ---
NOTE: OpenZeppelin v5 does NOT auto-grant DEFAULT_ADMIN_ROLE to msg.sender.
      The constructor receives explicit 'admin' param.
      Deployer EOA holds NO roles if it was not passed as a constructor param.
      VERIFY this before proceeding.
      If deployer EOA received any role, revoke via Safe in same tx batch.
```

---

## Detailed Steps

### Step 1 — Deploy IdentityRegistry

- **Actor:** Deployer EOA
- **Function called:** `new IdentityRegistry(admin, backendSigner, complianceOfficer, complianceOfficerSuplente)`
- **Validations in constructor:**
  - All four addresses are non-zero (reverts `ZeroAddressUser()`)
- **State changes:**
  - `DEFAULT_ADMIN_ROLE` → `SAFE_ADMIN_ADDR`
  - `BACKEND_SIGNER_ROLE` → `BACKEND_SIGNER_ADDR`
  - `COMPLIANCE_OFFICER_ROLE` → `COMPLIANCE_ADDR` and `COMPLIANCE_SUPLENTE_ADDR`
- **Events emitted:** none (AccessControl role grants are silent in OZ v5 unless explicitly emitted)
- **Gas estimated:** ~800k

**Dependency:** must be deployed before `AssetVault` and `RedemptionManager`, which take its address as an immutable parameter.

---

### Step 2 — Deploy LabRegistry

- **Actor:** Deployer EOA
- **Function called:** `new LabRegistry(admin, adminOperator, complianceOfficer, complianceOfficerSuplente)`
- **Validations in constructor:**
  - All four addresses are non-zero (reverts `ZeroAddress()`)
- **State changes:**
  - `DEFAULT_ADMIN_ROLE` → `SAFE_ADMIN_ADDR`
  - `ADMIN_ROLE` → `SAFE_OPERATOR_ADDR`
  - `COMPLIANCE_OFFICER_ROLE` → `COMPLIANCE_ADDR` and `COMPLIANCE_SUPLENTE_ADDR`
- **Gas estimated:** ~900k

**Dependency:** must be deployed before `AssetVault`.

---

### Step 3 — Deploy AssetVault

- **Actor:** Deployer EOA
- **Function called:** `new AssetVault(InitParams{...})`
- **Validations in constructor:**
  - All 10 address fields are non-zero (reverts `ZeroAddress()`)
- **State changes:**
  - `DEFAULT_ADMIN_ROLE` → `SAFE_ADMIN_ADDR`
  - `ADMIN_ROLE` → `SAFE_OPERATOR_ADDR`
  - `BACKEND_SIGNER_ROLE` → `BACKEND_SIGNER_ADDR`
  - `COMPLIANCE_OFFICER_ROLE` → `COMPLIANCE_ADDR` and `COMPLIANCE_SUPLENTE_ADDR`
  - `ORACLE_ROLE` → `ORACLE_SAFE_ADDR`
  - `TREASURY_SRL_ROLE` → `TREASURY_SRL_ADDR`
  - `usdc` (immutable) → `USDC_ADDR`
  - `identityRegistry` (immutable) → `IR_ADDR`
  - `labRegistry` (immutable) → `LR_ADDR`
  - `redemptionManager` → `address(0)` (not set yet — circular dep)
- **Gas estimated:** ~3.5M

**Note:** `redemptionManager` starts as `address(0)`. Any call to `burnForRedemption` before `setRedemptionManager` is called will correctly revert with `OnlyRedemptionCanBurn()` (because `msg.sender != address(0)` in EVM is always true for valid transactions).

---

### Step 4 — Deploy RedemptionManager

- **Actor:** Deployer EOA
- **Function called:** `new RedemptionManager(admin, oracleSafe, complianceOfficer, complianceOfficerSuplente, assetVault, identityRegistry)`
- **Validations in constructor:**
  - All six addresses are non-zero (reverts `ZeroAddress()`)
- **State changes:**
  - `DEFAULT_ADMIN_ROLE` → `SAFE_ADMIN_ADDR`
  - `ORACLE_ROLE` → `ORACLE_SAFE_ADDR`
  - `COMPLIANCE_OFFICER_ROLE` → `COMPLIANCE_ADDR` and `COMPLIANCE_SUPLENTE_ADDR`
  - `assetVault` (immutable) → `AV_ADDR`
  - `identityRegistry` (immutable) → `IR_ADDR`
  - `_nextRedencionId` → `1`
- **Gas estimated:** ~1.2M

---

### Step 5 — Wire Circular Dependency

- **Actor:** Deployer EOA (or Safe if it already holds `DEFAULT_ADMIN_ROLE`)
- **Function called:** `AssetVault.setRedemptionManager(RM_ADDR)` — `onlyRole(DEFAULT_ADMIN_ROLE)`
- **Validations:**
  - `_redemptionManager != address(0)` → reverts `ZeroAddress()`
  - `redemptionManager == address(0)` (not already set) → reverts `RedemptionManagerAlreadySet()`
- **State changes:**
  - `redemptionManager` → `RM_ADDR`
- **Gas estimated:** ~45k

This is the critical one-time wiring step. After this call, `burnForRedemption` is callable only by `RM_ADDR`.

---

### Step 6 — Seed LabRegistry

For each lab (IBNORCA at launch, Eurofins at launch):

- **Actor:** Deployer EOA or Safe Operator (`ADMIN_ROLE`)
- **Function called:** `LabRegistry.addLab(signerAddress, nameHash, jurisdiction, specializations[], accreditationHash)`
- **Validations:**
  - `signerAddress != address(0)` → reverts `ZeroAddress()`
  - `specializations.length > 0` → reverts `EmptySpecializations()`
  - Lab not already registered → reverts `LabAlreadyExists()`
- **State changes:**
  - `_labs[signerAddress]` populated with all fields, `active = true`
- **Events emitted:** `LabAdded(signerAddress, jurisdiction, specializations, accreditationHash)`
- **Gas estimated:** ~120k per lab

---

### Step 7 — Verify Contracts on Explorer

```bash
forge verify-contract $IR_ADDR  IdentityRegistry  --chain-id $PLUME_CHAIN_ID --etherscan-api-key $API_KEY
forge verify-contract $LR_ADDR  LabRegistry       --chain-id $PLUME_CHAIN_ID --etherscan-api-key $API_KEY
forge verify-contract $AV_ADDR  AssetVault        --chain-id $PLUME_CHAIN_ID --etherscan-api-key $API_KEY
forge verify-contract $RM_ADDR  RedemptionManager --chain-id $PLUME_CHAIN_ID --etherscan-api-key $API_KEY
```

Verification allows public audit and enables ABI lookup on Plume Explorer.

---

### Step 8 — Role Verification (Post-deploy Checklist)

```bash
# Verify deployer EOA holds NO roles (OZ v5 does not auto-grant to msg.sender)
cast call $AV_ADDR "hasRole(bytes32,address)" $(cast keccak "DEFAULT_ADMIN_ROLE") $DEPLOYER
# Expected: false

# Verify Safe holds DEFAULT_ADMIN_ROLE
cast call $AV_ADDR "hasRole(bytes32,address)" $(cast keccak "DEFAULT_ADMIN_ROLE") $SAFE_ADMIN
# Expected: true
```

---

## Post-conditions

- Four immutable contracts deployed and verified on Plume Explorer.
- `AssetVault.redemptionManager` set to `RedemptionManager` address (one-time, irreversible).
- All roles assigned to their intended multisig/hardware wallets.
- Two labs active in `LabRegistry` (IBNORCA + Eurofins at minimum).
- Deployer EOA holds zero roles.
- Backend environment variables updated:
  - `ASSET_VAULT_ADDRESS`
  - `IDENTITY_REGISTRY_ADDRESS`
  - `LAB_REGISTRY_ADDRESS`
  - `REDEMPTION_MANAGER_ADDRESS`

---

## Error Cases

| Cause | Result | Reverts with |
|-------|--------|-------------|
| Any address param is `address(0)` | Deploy fails | `ZeroAddress()` |
| `setRedemptionManager` called twice | Second call fails | `RedemptionManagerAlreadySet()` |
| `addLab` with same signerAddress twice | Second call fails | `LabAlreadyExists()` |
| Deployer runs out of PLUME gas | Partial deploy — restart from failed contract | VM out-of-gas |

---

## Concrete Numeric Example

```
Chain:           Plume Mainnet (chainId: 98866)
USDC address:    0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48 (placeholder)
Safe Admin:      0x111...Safe  (2-of-3: Alice Ledger X, Bob Ledger X, Carlos Ledger X)
Oracle Safe:     0x222...Safe  (2-of-3: same three cofounders)
Backend Signer:  0x333...KMS   (AWS KMS-managed EOA)
Compliance:      0x444...Ledger
IBNORCA signer:  0x555...Lab   (lab's dedicated signing EOA, Bolivia)
Eurofins signer: 0x666...Lab   (lab's dedicated signing EOA, Germany)

Deployment gas total: ~6.5M gas ≈ USD 3.25 at Plume gas prices
Session time: ~15 minutes including Safe confirmations
```

---

## Dependency Diagram

```
IdentityRegistry  (no deps)
LabRegistry       (no deps)
         |              |
         v              v
        AssetVault ----+
             |
             v
       RedemptionManager
             |
     (wired back via setRedemptionManager)
             |
             v
        AssetVault.redemptionManager = RM address
```

The deploy order must strictly follow: IR → LR → AV → RM → setRedemptionManager.

Cross-reference: See `05-redemption-export.md` for how `burnForRedemption` uses this wiring at runtime.
