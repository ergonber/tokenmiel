# Deep Security Audit — IdentityRegistry.sol

**Auditor:** Subagente A (opus)
**Date:** 2026-05-22
**Scope:** `packages/contracts/src/IdentityRegistry.sol` v0.1.0
**Author of contract:** Dany Hidalgo F.
**Lines audited:** 193 (incl. blank lines + NatSpec); ~120 effective LOC
**Compiler:** solc 0.8.24 (paris EVM, optimizer 200 runs)
**Dependencies reviewed:** `IIdentityRegistry`, `ComplianceConstants`, OpenZeppelin `AccessControl` v5
**Consumers in scope:** `AssetVault.sol`, `RedemptionManager.sol`

---

## Resumen ejecutivo

`IdentityRegistry` es el **gatekeeper KYC del sistema completo**. Cualquier vulnerabilidad acá compromete el cumplimiento regulatorio (OFAC, AMLD) y permite bypass del control de elegibilidad de compradores y redentores. La auditoría profunda cubrió las 12 categorías solicitadas, comparando el código actual con CONTRACT-SPECS §5 (que es la spec autoritativa pero más amplia que la implementación MVP actual).

**Veredicto general:** la implementación es **considerablemente más simple que la spec original** (no implementa `revokedAt`, `externalRefHash`, `plumeArcBridge`, `checkCompliance`, `isCompliant`, ni la verificación de jurisdicción ISO 3166-1). Esto reduce la superficie de ataque pero deja al contrato con **gaps regulatorios serios y dependencias operacionales fuera de banda**. El núcleo del gating (`canMint`, `canRedeem`) está correctamente implementado y la integración con `AssetVault._update` y `RedemptionManager.iniciarRedencion` funciona como gatekeeping efectivo.

Sin embargo, esta auditoría **identifica 21 findings**, entre ellos:

- **2 High** (revocación parcialmente inefectiva post-compra + ausencia total de pause/emergencia regulatoria)
- **8 Medium** (rate limiting ausente, evidenceHash no validado, sin distinción titular/suplente compliance, transición de estado ambigua tier=0, jurisdicción sin validar, riesgo lockout admin, etc.)
- **6 Low** (gas griefing por strings ilimitados, eventos sin timestamp en algunos casos, etc.)
- **5 Informational**

**Acción crítica antes de mainnet:**

1. **H-01** (revocación inefectiva sobre tokens ya minteados) — definir política: ¿`revokeKYC` debe gatillar también `frozen=true` para impedir redención posterior? Hoy un buyer revocado conserva sus tokens y, si `expiresAt > now`, **puede seguir redimiendo**.
2. **H-02** (sin pause de emergencia) — divergencia con AssetVault. Si el bridge Sumsub se compromete y BACKEND_SIGNER aprueba 10k KYCs falsos, no hay forma de detener la hemorragia salvo revocar manualmente cada wallet o pausar AssetVault. **Decisión arquitectónica requerida.**
3. **M-02 / M-03** (rate limiting ausente + evidenceHash no validado) — explotable si BACKEND_SIGNER o un COMPLIANCE_OFFICER se compromete.

---

## Findings (clasificados por severidad)

### 🔴 Critical

Sin findings de severidad crítica explotables hoy.

> **Nota:** la ausencia de `Critical` no significa "sin riesgo". Significa que **no hay un vector explotable autónomo desde el contrato actual sin compromiso de un rol**. Sin embargo, varios findings High convergen en escenarios donde un compromiso parcial escala a daño regulatorio masivo.

---

### 🟠 High

#### H-01 (NUEVO) — `revokeKYC` no impide redención futura ni P2P (no existe P2P, pero sí redención), y deja tokens líquidos

**Severidad:** High
**Archivo:** `IdentityRegistry.sol:81-90` (`revokeKYC`)
**Categoría:** State integrity + Defensive programming
**Estado:** vigente.

**Descripción:**

`revokeKYC` setea `tier = 0` y `updatedAt`, pero **NO toca**:

- `expiresAt` → permanece > 0 hasta que expire por timestamp
- `sanctioned` → permanece `false` (correcto si la revocación no es por sanción)
- `frozen` → permanece `false`

El gatekeeping en `canMint` y `canRedeem` (líneas 171-181) requiere:

```solidity
return data.tier >= MIN_KYC_TIER_PARA_* && !data.sanctioned && !data.frozen
    && data.expiresAt > block.timestamp;
```

Después de `revokeKYC`, `tier == 0 < MIN_KYC_TIER_PARA_*` → `canMint` y `canRedeem` devuelven `false`. **Esto bloquea NUEVAS compras/redenciones.** Correcto.

**El problema:** los **tokens ya minteados quedan en la wallet del buyer revocado**. Como AssetVault bloquea P2P en `_update`, el buyer no puede transferirlos a otra address; pero **puede llamar `RedemptionManager.iniciarRedencion`**... espera, eso también requiere `canRedeem` → bloqueado.

**Revisión más fina:** `RedemptionManager.iniciarRedencion:83` valida `canRedeem(msg.sender)`. Con `tier == 0`, devuelve `false`. Por lo tanto, **la redención sí queda bloqueada después de revoke**. Eso es bueno.

**Pero el escenario real explotable es:**

1. Alice tiene tier 2, compra 100 tokens del lote X.
2. BACKEND_SIGNER llama `revokeKYC(alice, "EDD failure")`. `tier → 0`.
3. Alice ya tiene tokens. AssetVault bloquea transfer P2P. RedemptionManager bloquea redención.
4. **Pero los tokens siguen contando como circulating supply.** Si el lote pasa a FALLIDO, `reembolsarLoteFallido` chequea `isSanctioned(buyer)` y `isFrozen(buyer)` (líneas 368-369 en AssetVault), pero **NO chequea `getTier(buyer) == 0`**.
5. Por lo tanto, **Alice (KYC revocado) recibe USDC en el reembolso**.

Esto puede ser intencional (el reembolso es un derecho de propiedad, no una compra), pero **regulatoriamente es ambiguo**: si el revoke fue por EDD failure por suspicion de lavado, ¿se le debe devolver el dinero? Probablemente sí (es su capital), pero **se debe documentar la política y eventualmente integrar `frozen=true` o `sanctioned=true` para casos críticos**.

**Caso peor:** si `revokeKYC` se llama por **error operacional** (e.g., wallet de Alice marcada por mistake), Alice no puede operar pero conserva sus tokens. **No hay forma directa de "re-aprobar"** salvo llamar `setKYC` nuevamente. Esto está OK, pero la spec original (CONTRACT-SPECS §5.13.7) menciona `revokedAt` como audit trail, que **no se implementa**. Sin ese campo, no se puede distinguir "nunca tuvo KYC" de "tuvo y le revocaron".

**PoC del impacto regulatorio:**

```
1. Alice tier=2, compra 1000 tokens. Pagó 100k USDC.
2. Sumsub detecta señales de fraude en patrón de pago de Alice (no es OFAC, no es congelamiento judicial — es EDD failure).
3. Backend llama revokeKYC(alice, "EDD failure por patrón de pagos sospechosos").
4. Alice queda con tier=0. NO puede comprar ni redimir.
5. Lote X cosecha falla. ORACLE marca FALLIDO.
6. ORACLE llama reembolsarLoteFallido([alice]).
7. isSanctioned(alice) = false. isFrozen(alice) = false. ⇒ Reembolso procede.
8. Alice recibe USDC. Compliance officer: "¿debíamos devolverle el dinero a alguien con EDD failure?"
```

**Mitigación propuesta:**

Opción A (recomendada): introducir un flag `revoked` separado, y agregarlo al gating de `canRedeem`. Permite distinguir tier=0-nunca-tuvo de revoked-explícito:

```solidity
struct KYCData {
    uint8 tier;
    bool sanctioned;
    bool frozen;
    bool revoked;            // NUEVO
    bytes2 jurisdiction;
    uint64 expiresAt;
    uint64 updatedAt;
    uint64 revokedAt;        // NUEVO (audit trail)
    bytes32 sumsubApplicantHash;
}

function revokeKYC(address user, string calldata reason) external onlyRole(BACKEND_SIGNER_ROLE) {
    if (user == address(0)) revert ZeroAddressUser();
    if (bytes(reason).length == 0) revert EmptyReason();
    if (_kyc[user].revoked) revert AlreadyRevoked();

    _kyc[user].tier = 0;
    _kyc[user].revoked = true;
    _kyc[user].revokedAt = uint64(block.timestamp);
    _kyc[user].updatedAt = uint64(block.timestamp);

    emit KYCRevoked(user, reason);
}
```

Y agregar a `AssetVault.reembolsarLoteFallido` el check de `revoked` (junto con `sanctioned` y `frozen`).

Opción B (más simple, pero más rígida): forzar que `revokeKYC` setee también `frozen = true`, asegurando que `canRedeem` y eventualmente el reembolso (con M-06 mitigation activo en AssetVault) bloqueen al buyer. Documentar que "revoke = freeze permanente".

**Acción requerida:** decisión de producto + compliance. La política de "qué pasa con buyers KYC-revocados y sus tokens" debe documentarse explícitamente en ADR antes de mainnet.

---

#### H-02 (NUEVO) — Sin función `pause()` ni mecanismo de circuit breaker

**Severidad:** High
**Archivo:** `IdentityRegistry.sol` (completo)
**Categoría:** Compromiso de claves + Defensa contra DoS
**Estado:** vigente (decisión arquitectónica documentada en CONTRACT-SPECS §5.13.6 pero **cuestionable**).

**Descripción:**

CONTRACT-SPECS §5.13.6 dice:

> "Sin `pause`: Diseño deliberado. Para detener emisiones de tokens ante incidente, pausar `AssetVault` (no este contrato)."

**Razonamiento de la spec:** un pause en `IdentityRegistry` haría que `canMint`/`canRedeem` reverten en los consumidores, freezeando el sistema entero.

**Por qué este razonamiento es insuficiente:**

1. **Pausar AssetVault NO detiene un escenario donde el atacante tiene `BACKEND_SIGNER_ROLE` y está spammeando `setKYC`/`markSanctioned`** para corromper el registro mismo. El attacker puede aprobar 10,000 KYCs falsos antes de que los humanos noten. Después, cuando se "unpause" AssetVault, esos KYCs falsos siguen vigentes.

2. **El bridge Sumsub puede tener un incidente** (Sumsub comprometido off-chain, replay de eventos malformados, etc.) y el BACKEND_SIGNER (que ejecuta legítimamente) propagaría estado corrupto. No hay forma de detener la propagación sin revocar el rol (que requiere DEFAULT_ADMIN_ROLE Safe).

3. **Pause en IdentityRegistry no necesita bloquear views.** Un pause podría afectar SOLO los mutators (`setKYC`, `markSanctioned`, etc.), dejando los views (`canMint`, `canRedeem`) funcionando. Esto preservaría la operación del sistema mientras se detiene la ingesta de nuevos KYCs.

**Comparación con AssetVault:** AssetVault SÍ tiene `pause()` (línea 452-455). RedemptionManager también (línea 148). **IdentityRegistry es el único contrato del sistema sin circuit breaker.** Esto es inconsistente y peligroso.

**PoC del escenario:**

```
T=0: BACKEND_SIGNER HSM es comprometida (vector: ataque a AWS KMS, supply chain, etc.).
T=1: Attacker llama setKYC para 10,000 wallets nuevas con tier=3, expiresAt=lejano.
T=2: Esas 10,000 wallets compran tokens (vía un wallet propio que el attacker tiene en el frontend coordinado).
T=3: Humanos detectan a las 2 horas. Necesitan revocar 10,000 wallets una por una (no hay batch revoke).
T=4: Mientras tanto, el sistema sigue minteando porque AssetVault no puede saber cuáles son las wallets fraudulentas.

Mitigación inadecuada: pausar AssetVault detiene NUEVAS compras pero no rolling back los mints ya ejecutados.
```

Con un pause en IdentityRegistry que solo afecte mutators:

```
T=3: COMPLIANCE_OFFICER llama IdentityRegistry.pause().
T=3.1: setKYC, markSanctioned, freeze, etc. revierten. Las views siguen funcionando.
T=3.2: AssetVault sigue operativo para usuarios legítimos.
T=3.3: Humanos investigan, revocan rol BACKEND_SIGNER, rotan HSM, hacen batch revoke offline-prepared.
T=4: unpause.
```

**Mitigación propuesta:**

Agregar `Pausable` mixin con scope limitado a mutators:

```solidity
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

contract IdentityRegistry is AccessControl, Pausable, IIdentityRegistry {
    // ...

    function pause() external onlyRole(COMPLIANCE_OFFICER_ROLE) {
        _pause();
        emit RegistryPaused(msg.sender, uint64(block.timestamp));
    }

    function unpause() external onlyRole(COMPLIANCE_OFFICER_ROLE) {
        _unpause();
        emit RegistryUnpaused(msg.sender, uint64(block.timestamp));
    }

    function setKYC(...) external onlyRole(BACKEND_SIGNER_ROLE) whenNotPaused {
        // ...
    }
    function revokeKYC(...) external onlyRole(BACKEND_SIGNER_ROLE) whenNotPaused { /* ... */ }
    function markSanctioned(...) external onlyRole(COMPLIANCE_OFFICER_ROLE) whenNotPaused { /* ... */ }
    // ... etc
}
```

**Importante:** las funciones de unmark/unfreeze **NO deben tener `whenNotPaused`**: durante un pause, debemos PODER descongelar / desmarcar manualmente. Lo que se bloquea son las operaciones de INGESTA de nuevo estado, no las de remediación.

**Acción requerida:** ADR explícito sobre la decisión final (pause sí/no, scope, qué roles pueden invocarlo). Recomendación firme: **agregar pause con scope limitado** antes de mainnet.

---

### 🟡 Medium

#### M-01 (NUEVO) — `markSanctioned` acepta `evidenceHash = bytes32(0)`

**Severidad:** Medium (regulatorio)
**Archivo:** `IdentityRegistry.sol:95-107`
**Categoría:** Validación de inputs + Eventos / audit trail

**Descripción:**

La función valida `reason.length > 0` pero **no valida `evidenceHash != bytes32(0)`**. Un compliance officer (titular o suplente) puede sancionar una address sin proveer evidencia.

```solidity
function markSanctioned(address user, string calldata reason, bytes32 evidenceHash)
    external
    onlyRole(COMPLIANCE_OFFICER_ROLE)
{
    if (user == address(0)) revert ZeroAddressUser();
    if (bytes(reason).length == 0) revert EmptyReason();
    if (_kyc[user].sanctioned) revert AlreadySanctioned();
    // ↑ falta: if (evidenceHash == bytes32(0)) revert EmptyEvidenceHash();
    // ...
}
```

**Impacto regulatorio:** una sanción OFAC sin evidence hash **no es legalmente trazable**. El audit trail on-chain pierde valor probatorio. Si en una disputa legal alguien argumenta "marcaron mi address sin evidencia", el contrato no protege a la empresa.

Comparación con `freezeAddress` (línea 122): exactamente el mismo problema — `orderHash` no se valida contra `bytes32(0)`.

**Mitigación propuesta:**

```solidity
error EmptyEvidenceHash();
error EmptyOrderHash();

function markSanctioned(address user, string calldata reason, bytes32 evidenceHash)
    external onlyRole(COMPLIANCE_OFFICER_ROLE)
{
    if (user == address(0)) revert ZeroAddressUser();
    if (bytes(reason).length == 0) revert EmptyReason();
    if (evidenceHash == bytes32(0)) revert EmptyEvidenceHash();
    if (_kyc[user].sanctioned) revert AlreadySanctioned();
    // ...
}

function freezeAddress(address user, string calldata regulatoryOrder, bytes32 orderHash)
    external onlyRole(COMPLIANCE_OFFICER_ROLE)
{
    if (user == address(0)) revert ZeroAddressUser();
    if (bytes(regulatoryOrder).length == 0) revert EmptyReason();
    if (orderHash == bytes32(0)) revert EmptyOrderHash();
    if (_kyc[user].frozen) revert AlreadyFrozen();
    // ...
}
```

**Acción requerida:** fix obligatorio antes de mainnet. Compliance officer (legal) debe firmar off con la decisión.

---

#### M-02 (NUEVO) — Ausencia total de rate limiting / volume cap

**Severidad:** Medium
**Archivo:** `IdentityRegistry.sol` (completo)
**Categoría:** Compromiso de claves + Defensa contra DoS

**Descripción:**

Ninguna función tiene rate limiting. Un BACKEND_SIGNER comprometido puede:

- Llamar `setKYC` 10,000 veces en un bloque (limitado solo por gas/block size). Cada llamada cuesta ~50k gas (1 SSTORE + 1 evento), así que en un bloque de 30M gas → ~600 wallets aprobadas. En 100 bloques (20 min en Plume con block time ~12s) → 60,000 wallets KYC tier 3.
- Esto **NO** sería detectado por límites on-chain. Solo por monitoring off-chain (Goldsky alerts).

Un COMPLIANCE_OFFICER comprometido puede:

- Llamar `markSanctioned` masivamente → DoS de usuarios legítimos (todos sus tokens quedan inutilizables hasta unmark, que requiere el MISMO COMPLIANCE_OFFICER_ROLE → si el rol comprometido es el único, no hay rescate).
- Llamar `freezeAddress` masivamente → mismo impacto.

**Spec dice (§5.13.1):**

> "Si la wallet `BACKEND_SIGNER_ROLE` se compromete, atacante puede aprobar KYCs falsos. Mitigación: KMS, monitoreo de eventos, rotación periódica."

**El monitoreo es reactivo.** Para una mitigación proactiva en contrato:

**Mitigación propuesta:**

Opción A: rate limit per-block (gas-cheap, simple):

```solidity
uint8 public constant MAX_OPS_PER_BLOCK = 50;
mapping(uint256 blockNum => uint8) private _opsThisBlock;

error RateLimitExceeded();

modifier rateLimited() {
    if (_opsThisBlock[block.number] >= MAX_OPS_PER_BLOCK) revert RateLimitExceeded();
    _opsThisBlock[block.number]++;
    _;
}

function setKYC(...) external onlyRole(BACKEND_SIGNER_ROLE) rateLimited { /* ... */ }
// ... etc
```

Opción B: rate limit per-role per-day (más sofisticado, más gas):

```solidity
mapping(address signer => mapping(uint64 day => uint16 count)) private _dailyOps;
uint16 public constant MAX_OPS_PER_DAY = 1000;

modifier dailyRateLimited(address signer) {
    uint64 today = uint64(block.timestamp / 1 days);
    if (_dailyOps[signer][today] >= MAX_OPS_PER_DAY) revert RateLimitExceeded();
    _dailyOps[signer][today]++;
    _;
}
```

Opción C (más simple aún): si pause se implementa (H-02), confiar en monitoring off-chain + pause manual rápido. Esto es la dirección que el proyecto parece estar tomando.

**Acción recomendada:** combinar pause (H-02) + monitoring riguroso. Rate limiting on-chain agrega complejidad y limita operación legítima si hay legítimas oleadas (ej. campaña de marketing genera 1000 KYC en una hora).

---

#### M-03 (NUEVO) — Doble superficie de ataque por dos COMPLIANCE_OFFICER_ROLE (titular + suplente OR)

**Severidad:** Medium
**Archivo:** `IdentityRegistry.sol:52-53` (constructor) + uso del rol en todas las funciones de compliance
**Categoría:** Access Control

**Descripción:**

El constructor otorga `COMPLIANCE_OFFICER_ROLE` a DOS addresses distintas (titular + suplente):

```solidity
_grantRole(COMPLIANCE_OFFICER_ROLE, complianceOfficer);
_grantRole(COMPLIANCE_OFFICER_ROLE, complianceOfficerSuplente);
```

OpenZeppelin AccessControl es un sistema OR: **cualquier holder del rol** puede ejecutar las funciones. Esto significa:

- **Defensa en profundidad:** si el titular pierde la wallet, el suplente puede actuar. ✅
- **Doble superficie de ataque:** comprometer el suplente equivale a comprometer al titular. **2 hardware wallets para auditar y proteger, no una.** ❌

Esto **no es necesariamente un bug**, pero **es una decisión que debe ser explícita en un ADR**. Hoy no lo es.

**Escenarios problemáticos:**

1. El suplente es típicamente menos vigilado (es backup). Si su hardware wallet se daña/extravía y el titular no lo nota, el atacante físico que lo encuentre puede usarlo.

2. Si titular y suplente actúan **en simultáneo con decisiones contradictorias** (titular sancionó, suplente desanciona inmediatamente), **el último gana** sin warning. **No hay log de quién hizo qué cambio** (excepto la transacción on-chain, pero el evento solo emite `user, reason` — no `msg.sender`).

**Issue específico de eventos:** `Sanctioned(address indexed user, string reason, bytes32 evidenceHash, uint64 timestamp)` **no indexa `msg.sender`**. Si titular y suplente se contradicen, off-chain queremos saber QUIÉN ejecutó la última acción. El indexed `user` lo tenemos, pero no el actor.

**Mitigación propuesta:**

Opción A: separar en dos roles distintos `COMPLIANCE_OFFICER_TITULAR_ROLE` y `COMPLIANCE_OFFICER_SUPLENTE_ROLE`, con el suplente solo activo en escenarios documentados (e.g., requiere también `EMERGENCY_ROLE` co-firma):

```solidity
bytes32 public constant COMPLIANCE_OFFICER_TITULAR_ROLE = keccak256("COMPLIANCE_OFFICER_TITULAR_ROLE");
bytes32 public constant COMPLIANCE_OFFICER_SUPLENTE_ROLE = keccak256("COMPLIANCE_OFFICER_SUPLENTE_ROLE");

modifier onlyComplianceOfficer() {
    if (!hasRole(COMPLIANCE_OFFICER_TITULAR_ROLE, msg.sender)
        && !hasRole(COMPLIANCE_OFFICER_SUPLENTE_ROLE, msg.sender)) {
        revert AccessControlUnauthorizedAccount(msg.sender, COMPLIANCE_OFFICER_TITULAR_ROLE);
    }
    _;
}
```

Opción B (más simple y efectiva): mantener el rol único pero **agregar `msg.sender` indexed a todos los eventos de compliance**:

```solidity
event Sanctioned(address indexed user, address indexed actor, string reason, bytes32 evidenceHash, uint64 timestamp);
event Unsanctioned(address indexed user, address indexed actor, string reason);
event Frozen(address indexed user, address indexed actor, string regulatoryOrder, bytes32 orderHash);
event Unfrozen(address indexed user, address indexed actor, string reason);
event KYCRevoked(address indexed user, address indexed actor, string reason);
```

Esto permite forensics post-incidente: "¿Quién marcó a alice como sancionada?".

**Acción requerida:** decisión documentada + (al mínimo) agregar `msg.sender` indexed a los eventos.

---

#### M-04 (NUEVO) — `setKYC` permite `tier = 0` sin warning (ambigüedad semántica)

**Severidad:** Medium
**Archivo:** `IdentityRegistry.sol:59-78` (`setKYC`)
**Categoría:** State integrity + Validación de inputs

**Descripción:**

La validación es `if (tier > MAX_KYC_TIER) revert InvalidTier();`. **Por lo tanto, `tier = 0` es válido.**

`tier = 0` en `MIN_KYC_TIER_PARA_COMPRAR = 1` significa "no puede operar". Si BACKEND_SIGNER llama `setKYC(alice, 0, ...)`:

- `data.tier = 0`
- `data.expiresAt = expiresAt`
- ... otros campos populated

**Esto equivale a un "soft revoke" silencioso**, pero:

1. No emite `KYCRevoked` (emite `KYCUpdated` con tier=0).
2. No setea `revokedAt` (no existe el campo).
3. Si después se llama `setKYC(alice, 2, ...)`, la wallet vuelve a tier 2 sin trace de que tuvo tier 0 en el medio.
4. Si después se llama `revokeKYC(alice, "razón")`, **revierte con `AlreadyRevoked`** porque `_kyc[user].tier == 0`.

Este último punto es relevante: **`revokeKYC` requiere `tier != 0`**. Pero si `setKYC` la dejó en tier 0, ya está "revocada" según `revokeKYC`. Esto es ambiguo y confunde dos conceptos: "nunca tuvo KYC" vs "fue revocada explícitamente".

**Mitigación propuesta:**

Opción A: forzar `tier >= MIN_KYC_TIER` en `setKYC` (no permitir tier=0 vía setKYC; la única forma de bajar a 0 sería `revokeKYC`):

```solidity
function setKYC(...) external onlyRole(BACKEND_SIGNER_ROLE) {
    if (user == address(0)) revert ZeroAddressUser();
    if (tier == 0 || tier > MAX_KYC_TIER) revert InvalidTier();
    if (expiresAt <= block.timestamp) revert ExpiryInPast();
    // ...
}
```

Opción B (recomendada en H-01): introducir el flag `revoked` separado del tier. Tier representa "nivel de verificación"; revoked es "estado del usuario". Esto desambigüa completamente.

**Acción requerida:** elegir Opción A o B + actualizar tests. Opción A es 1 línea; Opción B implica refactor.

---

#### M-05 (NUEVO) — `jurisdiction: bytes2` no se valida contra ISO 3166-1 alpha-2

**Severidad:** Medium (regulatorio)
**Archivo:** `IdentityRegistry.sol:63, 74` (`setKYC`)
**Categoría:** Validación de inputs

**Descripción:**

`jurisdiction` se acepta como `bytes2` (e.g. `"BO"`, `"DE"`, `"US"`) sin validar que sea ISO 3166-1 alpha-2 válido. BACKEND_SIGNER puede pasar `0x0000`, `0xFFFF`, o cualquier valor arbitrario.

**Impacto:**

1. **Compliance offshore:** algunos países están restringidos (sanciones por jurisdicción — North Korea, Iran, etc.). Si BACKEND_SIGNER (legítimamente o no) pasa `bytes2("KP")` para una wallet, el contrato lo acepta. **No hay enforcement de lista de jurisdicciones permitidas.**

2. **Quality data:** off-chain analytics que usan `getJurisdiction()` pueden filtrar incorrectamente si los códigos son arbitrarios.

3. **Empty jurisdiction:** `bytes2(0)` es válido. `KYCData.jurisdiction == bytes2(0)` es un estado ambiguo (nunca verificada? código nulo?).

**Mitigación propuesta:**

Opción A: validar contra una whitelist mutable de jurisdicciones permitidas:

```solidity
mapping(bytes2 jurisdictionCode => bool allowed) public allowedJurisdictions;

function setAllowedJurisdiction(bytes2 code, bool allowed)
    external onlyRole(COMPLIANCE_OFFICER_ROLE)
{
    allowedJurisdictions[code] = allowed;
    emit JurisdictionWhitelistUpdated(code, allowed);
}

function setKYC(...) {
    // ...
    if (!allowedJurisdictions[jurisdiction]) revert UnsupportedJurisdiction(jurisdiction);
    // ...
}
```

Opción B (más simple): validar solo que `jurisdiction != bytes2(0)`:

```solidity
if (jurisdiction == bytes2(0)) revert InvalidJurisdiction();
```

Opción C: aceptar como está (responsabilidad del BACKEND_SIGNER de pasar códigos correctos). Documentar en NatSpec que el contrato es agnóstico.

**Recomendación:** Opción A es robusta y permite ajustes regulatorios futuros (e.g., bloquear Belarus después de sanciones nuevas) sin redeploy. Es overhead aceptable.

**Acción requerida:** decisión de compliance team. Si el modelo legal requiere control de jurisdicciones, Opción A obligatoria.

---

#### M-06 (NUEVO) — `reason` y `regulatoryOrder` strings sin límite de longitud (gas griefing)

**Severidad:** Medium (gas / DoS)
**Archivo:** `IdentityRegistry.sol:81, 95, 110, 122, 137`
**Categoría:** Defensa contra DoS

**Descripción:**

Todas las funciones que aceptan strings (`revokeKYC`, `markSanctioned`, `unmarkSanctioned`, `freezeAddress`, `unfreezeAddress`) **no tienen límite de longitud**. Un actor con el rol puede pasar un string de 1MB → consumo masivo de gas, hash del evento gigante, posible OOG en indexers off-chain (Goldsky tiene límites de payload).

```solidity
function markSanctioned(address user, string calldata reason, bytes32 evidenceHash) ...
```

`calldata` no se copia (eso es bueno) pero **se incluye en el evento `emit Sanctioned(user, reason, evidenceHash, ...)`**. Los eventos sí pagan gas por longitud del payload (~8 gas per byte).

**Impacto:**

- Un actor comprometido con el rol puede inflar drásticamente los costos de eventos. **No es exploit directo** (el caller paga, no la víctima), pero degrada UX y dificulta indexing.
- En el bloque, el límite de calldata es alto (~128KB en Ethereum, similar en Plume). Un evento con 100KB de `reason` consume ~800,000 gas en el evento. **Posible pero costoso.**

**Mitigación propuesta:**

```solidity
uint256 public constant MAX_REASON_LENGTH = 256;
error ReasonTooLong();

function markSanctioned(address user, string calldata reason, bytes32 evidenceHash) ... {
    if (bytes(reason).length == 0) revert EmptyReason();
    if (bytes(reason).length > MAX_REASON_LENGTH) revert ReasonTooLong();
    // ...
}
// ... aplicar a todas las funciones con strings
```

256 bytes es generoso para una razón legal estructurada ("OFAC SDN Match #12345 dated 2026-05-22"). Para evidencia detallada, usar el `evidenceHash` / `orderHash` (32 bytes apuntando a IPFS/Arweave).

**Acción recomendada:** agregar límite. No es crítico pero es low-effort buenas prácticas.

---

#### M-07 (NUEVO) — `setKYC` sobreescribe sin warning: pérdida de audit trail in-contract

**Severidad:** Medium
**Archivo:** `IdentityRegistry.sol:65-78` (`setKYC`)
**Categoría:** State integrity + Eventos

**Descripción:**

Si BACKEND_SIGNER llama `setKYC(alice, 2, expiry1, "BO", hash1)`, y luego `setKYC(alice, 3, expiry2, "DE", hash2)`:

- El primer estado es **silenciosamente sobreescrito** en storage.
- El evento `KYCUpdated` se emite ambas veces, así que el audit trail OFF-CHAIN (eventos) preserva ambas versiones.
- **Pero on-chain, solo el último estado es queryable**. No hay "history" inline.

Eso es estándar y aceptable. **El issue es más sutil:**

1. `sanctioned`, `frozen` **NO se tocan** en `setKYC`. Esto es **correcto** (la spec dice "los flags se manejan en sus propias funciones"). Pero si BACKEND_SIGNER actualiza el KYC de alguien sancionado, el evento `KYCUpdated` se emite sin reportar que está sancionada. **Indexer que procesa solo `KYCUpdated` pierde el contexto crítico.**

2. **No hay un check defensivo de "no setear KYC para alguien sancionado/frozen"**. Si BACKEND_SIGNER es comprometido, puede llamar `setKYC(sancionada, tier=3, ...)` y mantener la sanción intacta. **canMint sigue devolviendo false (por `!data.sanctioned`)**, así que no hay exploit directo, pero **hay un evento engañoso que sugiere que la wallet fue re-verificada cuando todavía está bloqueada**.

3. **Si tier=0 es el estado "no KYC", y `setKYC` puede setear cualquier tier (M-04), entonces puede silenciosamente "des-revocar" una wallet revocada sin emitir `KYCRevoked` reverso o "KYCRestored":**

   ```
   T=0: tier=2 (active)
   T=1: revokeKYC → tier=0
   T=2: setKYC(tier=2, ...) → tier=2 (active again)
   ```

   Entre T=1 y T=2 no hay evento explícito de "restoration" — solo `KYCUpdated` con tier=2. Off-chain hay que correlacionar con el evento previo `KYCRevoked` para entender.

**Mitigación propuesta:**

Opción A: agregar check defensivo:

```solidity
function setKYC(...) external onlyRole(BACKEND_SIGNER_ROLE) {
    // ...
    KYCData storage data = _kyc[user];
    if (data.sanctioned) revert CannotSetKYCWhileSanctioned();
    if (data.frozen) revert CannotSetKYCWhileFrozen();
    // (revoked si se implementa H-01)
    if (data.tier == 0 && data.updatedAt > 0) {
        // user was previously revoked; emit explicit event
        emit KYCRestored(user, tier);
    }
    // ...
}
```

Opción B (más simple): documentar la decisión + asegurar que el evento `KYCUpdated` incluye los flags actuales:

```solidity
event KYCUpdated(
    address indexed user,
    uint8 tier,
    uint64 expiresAt,
    bytes2 jurisdiction,
    bool sanctioned,    // NUEVO
    bool frozen         // NUEVO
);
```

Esto permite a indexers reconstruir el estado completo desde un solo evento.

**Acción requerida:** Opción B es low-effort y reduce confusión off-chain. Recomendado.

---

#### M-08 (NUEVO) — Riesgo de admin lockout: `DEFAULT_ADMIN_ROLE` puede renunciar sin restricciones

**Severidad:** Medium
**Archivo:** Hereda de OpenZeppelin `AccessControl` (`renounceRole`)
**Categoría:** Patrones de checks no implementados + Access Control

**Descripción:**

OpenZeppelin v5 `AccessControl` expone `renounceRole(role, account)` con la única restricción `require(account == msg.sender)`. Esto significa:

1. Si el único holder de `DEFAULT_ADMIN_ROLE` (Safe 2-de-3) renuncia accidentalmente o por mistake:
   - **El contrato queda sin admin para siempre.**
   - **Nadie puede grant/revoke ningún rol.**
   - **Los roles existentes siguen funcionando** (BACKEND_SIGNER puede seguir actualizando KYC, COMPLIANCE_OFFICER puede seguir sancionando), pero **no se puede rotar claves comprometidas**.

2. Esto es un **footgun conocido** y OZ v5 introdujo `AccessControlDefaultAdminRules` que mitiga este caso (con delay para cambios de DEFAULT_ADMIN).

**Verificación en el código:** el contrato hereda `AccessControl` (NO `AccessControlDefaultAdminRules`):

```solidity
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
contract IdentityRegistry is AccessControl, IIdentityRegistry { ... }
```

**Esto deja al contrato expuesto al lockout.**

**Mitigación propuesta:**

Opción A (preferida): migrar a `AccessControlDefaultAdminRules`:

```solidity
import {AccessControlDefaultAdminRules} from "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";
contract IdentityRegistry is AccessControlDefaultAdminRules, IIdentityRegistry {
    constructor(...)
        AccessControlDefaultAdminRules(
            3 days,           // delay para cambios de DEFAULT_ADMIN_ROLE
            admin             // initial admin
        )
    {
        // grant otros roles...
    }
}
```

Esto agrega un delay de 3 días para cualquier cambio de `DEFAULT_ADMIN_ROLE`, permitiendo cancelar transferencias accidentales o maliciosas.

Opción B: override `renounceRole` para impedir renuncia del único admin:

```solidity
function renounceRole(bytes32 role, address account) public override {
    if (role == DEFAULT_ADMIN_ROLE && getRoleMemberCount(DEFAULT_ADMIN_ROLE) == 1) {
        revert CannotRenounceLastAdmin();
    }
    super.renounceRole(role, account);
}
```

Pero esto requiere también `AccessControlEnumerable` para tener `getRoleMemberCount`. Mejor ir con Opción A.

**Acción requerida:** evaluar migración a `AccessControlDefaultAdminRules` antes de mainnet. **El proyecto debería estar usando esto en TODOS los contratos** — AssetVault y RedemptionManager tienen el mismo issue.

---

### 🟢 Low

#### L-01 (NUEVO) — `Sanctioned` event emite `timestamp` redundantemente

**Severidad:** Low
**Archivo:** `IdentityRegistry.sol:106`

**Descripción:**

```solidity
emit Sanctioned(user, reason, evidenceHash, uint64(block.timestamp));
```

`block.timestamp` ya está disponible en el block header de cada transacción. Indexers (Goldsky, The Graph) lo proveen automáticamente. **Incluir `timestamp` en el evento es redundante** y desperdicia ~600 gas por evento.

**Comparación:** `Frozen`, `Unfrozen`, `Unsanctioned`, `KYCRevoked` **no incluyen `timestamp`** (correcto). `Sanctioned` es el único que lo hace — inconsistencia.

**Mitigación propuesta:**

```solidity
event Sanctioned(address indexed user, string reason, bytes32 evidenceHash);

emit Sanctioned(user, reason, evidenceHash);
```

**Acción:** trivial; aplicar en próximo refactor.

---

#### L-02 (NUEVO) — `KYCData` storage layout no es óptimo (1 slot extra)

**Severidad:** Low (gas)
**Archivo:** `IIdentityRegistry.sol:12-20`

**Descripción:**

Layout actual:

```solidity
struct KYCData {
    uint8 tier;              // 1 byte
    bool sanctioned;         // 1 byte
    bool frozen;             // 1 byte
    bytes2 jurisdiction;     // 2 bytes
    uint64 expiresAt;        // 8 bytes
    uint64 updatedAt;        // 8 bytes  → 21 bytes en slot 0
    bytes32 sumsubApplicantHash;  // 32 bytes en slot 1
}
```

**Análisis:**

- `tier (1) + sanctioned (1) + frozen (1) + jurisdiction (2) + expiresAt (8) + updatedAt (8) = 21 bytes`. Sí, **entra en slot 0** (32 bytes disponibles). ✅
- `sumsubApplicantHash` ocupa slot 1 completo. ✅

**Total: 2 slots.** Esto está bien empacado. ✅

**Sin embargo**, si en H-01 se agrega `bool revoked` + `uint64 revokedAt`:

- Slot 0: `tier (1) + sanctioned (1) + frozen (1) + revoked (1) + jurisdiction (2) + expiresAt (8) + updatedAt (8) + revokedAt (8) = 30 bytes`. Aún entra. ✅

Mantener bytes consecutivos en el slot 0 antes de mover a slot 1.

**Recomendación:** documentar layout actual en el NatSpec del struct (parcialmente hecho en líneas 9-11 del interface, mejorar):

```solidity
/// @dev Storage layout:
///   slot 0: tier (1) + sanctioned (1) + frozen (1) + jurisdiction (2)
///         + expiresAt (8) + updatedAt (8) = 21 bytes used, 11 bytes free
///   slot 1: sumsubApplicantHash (32) = full slot
struct KYCData { ... }
```

**Verificaciones positivas en packing:** ya está óptimo.

---

#### L-03 (NUEVO) — `getKYCData` devuelve struct completo: gas + privacy leak

**Severidad:** Low
**Archivo:** `IdentityRegistry.sol:190-192`

**Descripción:**

`getKYCData` devuelve el struct completo (sumsubApplicantHash incluido). El hash es un commitment, no debería ser un secret, pero:

1. **Cualquier address puede leer el `sumsubApplicantHash` de cualquier user.** Esto es **público on-chain** (Etherscan, RPC). El hash en sí no revela PII directamente, pero si Sumsub usa un applicantId predecible o si el backend usa un sal débil, **rainbow attack puede correlacionar hash → applicantId Sumsub → identidad real**.

2. **Gas:** retornar un struct completo cuando solo se necesita un campo es ineficiente.

**Mitigación propuesta:**

Opción A: restringir `getKYCData` a roles autorizados:

```solidity
function getKYCData(address user)
    external view returns (KYCData memory)
{
    if (!hasRole(BACKEND_SIGNER_ROLE, msg.sender)
        && !hasRole(COMPLIANCE_OFFICER_ROLE, msg.sender)
        && !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)
        && msg.sender != user)
    {
        revert UnauthorizedAccess();
    }
    return _kyc[user];
}
```

**Pero:** AssetVault y RedemptionManager hacen llamadas view sin tener el rol BACKEND_SIGNER. **Acceso restringido rompería integraciones.**

Opción B (más práctica): eliminar el `sumsubApplicantHash` del retorno de `getKYCData` y crear una función separada:

```solidity
function getKYCData(address user) external view returns (
    uint8 tier, bool sanctioned, bool frozen, bytes2 jurisdiction,
    uint64 expiresAt, uint64 updatedAt
) {
    KYCData storage d = _kyc[user];
    return (d.tier, d.sanctioned, d.frozen, d.jurisdiction, d.expiresAt, d.updatedAt);
}

function getSumsubApplicantHash(address user)
    external view returns (bytes32)
{
    if (!hasRole(BACKEND_SIGNER_ROLE, msg.sender)
        && !hasRole(COMPLIANCE_OFFICER_ROLE, msg.sender))
    {
        revert UnauthorizedAccess();
    }
    return _kyc[user].sumsubApplicantHash;
}
```

Opción C: aceptar como está si el sumsubApplicantHash es público por diseño (revisar con compliance).

**Acción requerida:** decisión con compliance/legal sobre la sensibilidad del sumsubApplicantHash. Mientras tanto, documentar la decisión en NatSpec.

---

#### L-04 (NUEVO) — `isExpired` usa `<=` mientras `canMint` usa `>`: asimetría sutil

**Severidad:** Low
**Archivo:** `IdentityRegistry.sol:167, 174, 181`

**Descripción:**

```solidity
function isExpired(address user) external view returns (bool) {
    return _kyc[user].expiresAt <= block.timestamp;
}

function canMint(address user) external view returns (bool) {
    // ...
    && data.expiresAt > block.timestamp;
}
```

**Coherencia:** `isExpired == true` ⇔ `expiresAt <= now` ⇔ `not (expiresAt > now)`. ✅ Las dos funciones son consistentes (negación una de otra).

**Casos extremos:**

- Si `expiresAt == block.timestamp` exactamente: `isExpired = true`, `canMint = false`. ✅ Consistente.
- Si `expiresAt == 0` (default value for unset): `isExpired = true`, `canMint = false`. ✅ Consistente.

**Conclusión:** matemáticamente correcto. **Pero** la spec original (CONTRACT-SPECS §5.13.5) dice:

> "`getTier` devuelve 0 si expirado."

En el código, `getTier` NO devuelve 0 si expirado — devuelve el tier almacenado:

```solidity
function getTier(address user) external view returns (uint8) {
    return _kyc[user].tier;
}
```

**Inconsistencia con la spec.** No es necesariamente bug (los consumidores usan `canMint`/`canRedeem` que sí incluyen expiry), pero off-chain consumers que llaman `getTier` pueden creer que la wallet está activa cuando está expirada.

**Mitigación propuesta:**

```solidity
function getTier(address user) external view returns (uint8) {
    KYCData storage d = _kyc[user];
    if (d.expiresAt <= block.timestamp) return 0;
    return d.tier;
}
```

O alternativamente agregar `getEffectiveTier` que sí respeta expiry, y dejar `getTier` como raw.

**Acción:** decisión menor. Si se mantiene como está, documentar en NatSpec que `getTier` NO respeta expiry y usuarios deben checkear con `isExpired` separadamente.

---

#### L-05 (NUEVO) — `expiresAt = uint64.max` permite expiry efectivamente infinito sin warning

**Severidad:** Low
**Archivo:** `IdentityRegistry.sol:68` (`setKYC`)

**Descripción:**

`uint64.max = 18446744073709551615` ≈ año 584,554,051,223 (eón geológico). Si BACKEND_SIGNER pasa `expiresAt = type(uint64).max`, la wallet nunca expira en práctica.

**Esto puede ser intencional** (KYC "permanente" para institucionales), o un **bug operacional** (backend pasa accidentalmente un valor inflado).

**Mitigación propuesta:**

```solidity
uint64 public constant MAX_KYC_VALIDITY = 5 * 365 days; // 5 años

function setKYC(...) external onlyRole(BACKEND_SIGNER_ROLE) {
    // ...
    if (expiresAt <= block.timestamp) revert ExpiryInPast();
    if (expiresAt > block.timestamp + MAX_KYC_VALIDITY) revert ExpiryTooFar();
    // ...
}
```

5 años cubre el caso de KYC institucional Tier 3 con renovación bianual sin overshoot peligroso.

**Acción:** decisión con compliance. La regulación AML típicamente requiere re-verificación cada 1-3 años. Un cap de 5 años es conservador.

---

#### L-06 (NUEVO) — Eventos `Unsanctioned` y `Unfrozen` no incluyen `evidenceHash` reverso

**Severidad:** Low
**Archivo:** `IdentityRegistry.sol:118, 145`

**Descripción:**

Al sancionar, se requiere `evidenceHash` (e.g., PDF de OFAC list match). Al **DESsancionar**, solo se requiere `reason: string`. No hay `unsanctionEvidenceHash` ni `judicialOrderHash` para el caso de descongelamiento por orden judicial revocada.

**Impacto regulatorio:** un desmarcado de sanción debería tener tanto rigor probatorio como el marcado. Hoy un compliance officer puede unmark sin proveer documentación.

**Mitigación propuesta:**

```solidity
event Unsanctioned(address indexed user, string reason, bytes32 reverseEvidenceHash);
event Unfrozen(address indexed user, string reason, bytes32 reverseOrderHash);

function unmarkSanctioned(address user, string calldata reason, bytes32 reverseEvidenceHash) ...
function unfreezeAddress(address user, string calldata reason, bytes32 reverseOrderHash) ...
```

**Acción:** decisión con legal/compliance sobre el rigor probatorio. Aplicar si la política lo requiere.

---

### 🔵 Informational

#### I-01 (NUEVO) — Licencia BUSL-1.1 placeholder

**Archivo:** `IdentityRegistry.sol:1`, `IIdentityRegistry.sol:1`

Igual que en AssetVault audit previo. La licencia final debe definirse antes de freeze pre-auditoría.

---

#### I-02 (NUEVO) — Naming inconsistente con AssetVault: `ZeroAddressUser` vs `ZeroAddress`

**Archivo:** `IdentityRegistry.sol:32` vs `AssetVault.sol:55`

AssetVault usa `ZeroAddress`. IdentityRegistry usa `ZeroAddressUser`. Trivial pero inconsistente.

**Recomendación:** unificar a `ZeroAddress` (más corto, más genérico). El campo `address user` ya da contexto en el revert.

---

#### I-03 (NUEVO) — Falta `getTimeUntilExpiry` view helper

**Archivo:** `IdentityRegistry.sol` (completo)

Para UX off-chain (frontend), sería útil:

```solidity
function getTimeUntilExpiry(address user) external view returns (uint64) {
    uint64 expiry = _kyc[user].expiresAt;
    if (expiry <= block.timestamp) return 0;
    return expiry - uint64(block.timestamp);
}
```

Permite mostrar "tu KYC expira en X días" en el frontend sin doble llamada.

---

#### I-04 (NUEVO) — `getJurisdiction` retorna `bytes2(0)` para wallets sin KYC

**Archivo:** `IdentityRegistry.sol:185-187`

Sin warning ni revert. Si el frontend llama `getJurisdiction(0xRandom)` recibe `bytes2(0)`. Esto es Solidity default; consumers deben validar primero con `getTier > 0`.

**Recomendación:** documentar en NatSpec:

```solidity
/// @notice Retorna la jurisdicción ISO 3166-1 alpha-2 del usuario.
/// @dev Si el usuario no tiene KYC registrado, retorna bytes2(0).
///      Los consumers DEBEN validar primero con `getTier > 0`.
function getJurisdiction(address user) external view returns (bytes2);
```

---

#### I-05 (NUEVO) — Constructor no separa role grants por subgrupos claros

**Archivo:** `IdentityRegistry.sol:39-54`

Funcionalmente correcto. Estilísticamente, podría agruparse mejor con comentarios:

```solidity
constructor(
    address admin,
    address backendSigner,
    address complianceOfficer,
    address complianceOfficerSuplente
) {
    // Validate inputs
    if (admin == address(0)) revert ZeroAddressUser();
    if (backendSigner == address(0)) revert ZeroAddressUser();
    if (complianceOfficer == address(0)) revert ZeroAddressUser();
    if (complianceOfficerSuplente == address(0)) revert ZeroAddressUser();

    // Super-admin (Safe multi-sig)
    _grantRole(DEFAULT_ADMIN_ROLE, admin);

    // KYC sync (HSM-managed)
    _grantRole(BACKEND_SIGNER_ROLE, backendSigner);

    // Compliance officers (hardware wallets)
    _grantRole(COMPLIANCE_OFFICER_ROLE, complianceOfficer);
    _grantRole(COMPLIANCE_OFFICER_ROLE, complianceOfficerSuplente);
}
```

Trivial; refactor cosmético.

---

## Verificaciones positivas

Lo que está bien implementado y agrega confianza:

1. **OpenZeppelin AccessControl v5** correctamente heredado. No hay auto-grant al deployer (OZ v5 ya lo arregló).

2. **Custom errors gas-efficient** (no `require(x, "string")`). Cumple regla del proyecto.

3. **NatSpec presente** en todas las funciones (vía `@inheritdoc IIdentityRegistry`). El NatSpec full está en la interface.

4. **Storage layout empacado correctamente** en `KYCData` — 21 bytes en slot 0, 32 bytes en slot 1. **Verificado óptimo para el set actual de campos.**

5. **Validación de `address(0)`** en TODAS las funciones que reciben `address user`. ✅

6. **Idempotencia / guards** correctos: `AlreadySanctioned`, `NotSanctioned`, `AlreadyFrozen`, `NotFrozen`, `AlreadyRevoked` previenen estado inconsistente y operaciones duplicadas.

7. **Separación de roles correcta:**
   - BACKEND_SIGNER → sync de Sumsub (`setKYC`, `revokeKYC`).
   - COMPLIANCE_OFFICER → acciones regulatorias (`markSanctioned`, `freezeAddress`, etc.).
   - DEFAULT_ADMIN → solo grant/revoke. **No tiene atajos para modificar KYC.** ✅

8. **`canMint` y `canRedeem` son views correctos** (no side effects, leen storage). Consumers (AssetVault, RedemptionManager) los llaman directamente sin riesgo de reentrancy ni state mutation.

9. **No `tx.origin`** en ninguna parte. ✅

10. **No `block.timestamp` para randomness o decisiones críticas.** Solo para audit timestamps. ✅

11. **No inline assembly.** ✅

12. **No `delegatecall`.** ✅

13. **`expiresAt > block.timestamp` strict** en `canMint`/`canRedeem`: una wallet que expira exactamente AHORA no puede operar. Estricto pero correcto.

14. **`tier > MAX_KYC_TIER` revert**: previene seteo de tier inválido. ✅ (pero ver M-04 sobre tier=0).

15. **`expiresAt <= block.timestamp` revert** en `setKYC`: previene seteo de KYC ya expirado. ✅

16. **`reason.length == 0` revert** en todas las funciones de compliance: forzar trazabilidad mínima. ✅ (pero ver M-06 sobre longitud máxima).

17. **Inmutabilidad del contrato:** sin proxy, sin upgradeability. Cumple ADR-003. ✅

18. **Modular consumer pattern:** consumers (AssetVault, RedemptionManager) usan la interface `IIdentityRegistry`, no la implementación concreta. Permite testing con mocks y, en teoría, futuro replacement. ✅

19. **No funciones públicas/external sin role check** que deberían tenerlo. Todas las funciones de mutación están correctamente gatekeeped.

20. **`getKYCData` retorna struct memory copy**, no storage reference. Seguro contra mutación inadvertida en consumers.

---

## Verificaciones específicas solicitadas por categoría

### Categoría 1: Access Control

- **Cada función externa tiene modifier correcto:** ✅ (verificado línea por línea).
- **Roles con poderes excesivos:** `BACKEND_SIGNER_ROLE` tiene poder de aprobar KYCs masivamente sin rate limiting (M-02). `COMPLIANCE_OFFICER_ROLE` tiene poder de sancionar/freezar masivamente sin rate limiting (M-02).
- **`DEFAULT_ADMIN_ROLE` sin restricciones:** ✅ Es Safe multi-sig, riesgo controlado. **PERO** ver M-08 sobre admin lockout.
- **Constructor previene mistakes:** ✅ Valida address(0) en los 4 parámetros.
- **Funciones públicas/externas sin role check:** los views NO tienen role check (correcto, son de lectura pública). Las mutators TODAS tienen role check ✅.

### Categoría 2: State integrity

- **Caminos para estado inconsistente:**
  - Una address puede ser sanctioned=true + frozen=true simultáneamente. **Aceptable o problemático?** ACEPTABLE: representan dos restricciones complementarias. Ver categoría sanción vs freeze más abajo.
  - Una address puede tener tier=0 + expiresAt > 0 (revocada explícitamente, expiry no tocada). Ambiguo (M-04).
  - Una address puede tener tier > 0 + expiresAt < block.timestamp (KYC expirado). Esto es correcto: el flag de expiry actúa como veto en canMint/canRedeem.
- **`tier > MAX_KYC_TIER` pasarse:** NO. Validado en `setKYC` (línea 67). ✅
- **`expiresAt = 0`:** trata como "siempre expirado" (porque `0 <= block.timestamp` siempre). Consistente con `isExpired` y `canMint`. ✅
- **`setKYC` múltiples veces:** sobreescribe sin warning. Aceptable pero ver M-07.
- **`revokeKYC` setea tier=0 sin tocar otros:** intencional, pero ver H-01 sobre los tokens minteados pre-revoke.

### Categoría 3: Race conditions y front-running

- **Frontrun `markSanctioned`:** AssetVault.comprar() es `onlyRole(BACKEND_SIGNER)`, no público. Backend ejecuta serialmente. **Frontrun no viable desde usuarios.**
- **`setKYC` y `markSanctioned` mismo bloque:** **orden importa.** Si en el mismo bloque BACKEND_SIGNER setea KYC tier 3 + un COMPLIANCE_OFFICER sanciona, el orden de las txs determina el estado final. Block builder (Plume sequencer en testnet) determina el orden — no hay garantía. **Para escenarios de race, los humanos deben coordinar off-chain.** Documentar en runbook.
- **Double-spending de KYC:** setear → comprar → revoke → setear de nuevo:
  - T=0: tier=2. T=1: comprar 100 tokens. T=2: revokeKYC (tier=0). T=3: setKYC tier=2 nuevamente.
  - Entre T=2 y T=3: tokens ya en la wallet, pero `canMint`/`canRedeem` bloqueado. Después de T=3, `canRedeem` vuelve a `true`.
  - **Esto NO es bug, es feature** (re-aprobación después de fix de KYC). Pero abre superficie a abuso si BACKEND_SIGNER es comprometido (ver H-01, M-02).

### Categoría 4: Validación de inputs

- **`tier` validado 0-3:** parcial. `tier > MAX_KYC_TIER` revert, pero `tier == 0` aceptado. Ver M-04.
- **`jurisdiction: bytes2`:** NO validado. Ver M-05.
- **`expiresAt` muy lejano:** NO validado contra cap. Ver L-05.
- **`sumsubApplicantHash == bytes32(0)`:** ACEPTADO. Esto puede significar "no Sumsub linkage" para casos sin Sumsub (e.g., institucional KYB manual). Documentar como permitido.
- **`reason` y `regulatoryOrder` longitud:** NO validada. Ver M-06.

### Categoría 5: Eventos y audit trail

- **Cada cambio crítico emite evento:** ✅. `KYCUpdated`, `Sanctioned`, `Unsanctioned`, `Frozen`, `Unfrozen`, `KYCRevoked`.
- **Indexed apropiados:** parcial. `user` siempre indexed. Pero `msg.sender` NO indexed (ver M-03).
- **Información para reconstruir estado off-chain:** parcial. `KYCUpdated` emite tier/expiresAt/jurisdiction pero NO sanctioned/frozen (ver M-07). Indexer debe mantener su propio state machine.
- **Cambios silenciosos en código:** los flags sanctioned/frozen NO emiten evento si `setKYC` "los preserva" (porque no los toca). **OK por construcción.**
- **`markSanctioned` valida `evidenceHash`:** NO. Ver M-01.

### Categoría 6: Compromiso de claves

- **BACKEND_SIGNER comprometido:** spam de KYC fraudulentos. **No hay rate limiting** (M-02). **No hay pause** (H-02). Mitigación actual: monitoring off-chain + revocar rol manualmente (requiere DEFAULT_ADMIN Safe).
- **COMPLIANCE_OFFICER comprometido (cualquiera de los dos):** sanción/freezing masivo o desmarcado de sanciones legítimas. **Mismo problema sin rate limit / pause.**
- **DEFAULT_ADMIN comprometido (Safe 2-de-3):** game over (puede grant/revoke todo). Requiere 2 de 3 hardware wallets físicos.

### Categoría 7: Defensa contra DoS

- **`setKYC` spam:** posible. Caller paga gas pero satura indexer. Ver M-02.
- **`markSanctioned` con `reason` larga:** posible gas griefing. Ver M-06.
- **Límite de cuántas direcciones sancionar:** ninguno. **Aceptable** (storage no bounded; cada sanción es 1 SSTORE).

### Categoría 8: Integración con consumidores

- **`canMint` / `canRedeem` views correctos:** ✅. Sin side effects.
- **`getTier`, `isSanctioned`, `isFrozen` consistentes con canMint/canRedeem:** parcialmente. `getTier` NO respeta expiry (L-04). Las otras dos son consistentes.
- **Si IdentityRegistry tiene bug, impacto en AssetVault:** mint inválido o mint negado falsamente. RedemptionManager: redención bloqueada o aprobada incorrectamente. **El gating funciona; el riesgo está en la calidad de los datos, no en la lógica.**
- **Llamadas via interface:** ✅. `AssetVault.identityRegistry` es `IIdentityRegistry`. `RedemptionManager.identityRegistry` también.

### Categoría 9: Mejoras de gas (preliminares)

- **Reads redundantes:** mínimos. `canMint` y `canRedeem` cada uno hace 1 read del struct storage (vía `KYCData storage data = _kyc[user];`), luego accede a 4 campos en el mismo slot. **Óptimo.**
- **Storage layout `KYCData`:** óptimo (L-02). 2 slots usados, 11 bytes libres en slot 0 para futuros campos (revoked, revokedAt — H-01).

### Categoría 10: Defensive programming

- **`address(0)` validada:** ✅ en TODAS las funciones de mutación.
- **`tier = 0` en setKYC:** ACEPTADO. Ver M-04.
- **Salir de sanctioned/frozen sin COMPLIANCE_OFFICER:** NO ES POSIBLE. ✅ ✅

### Categoría 11: Compatibilidad con flujos de upgrade

- **Migración a v2:** los eventos preservan history off-chain. Sin función de "import batch" — cada KYC debe re-setearse manualmente. **Aceptable para MVP**, doloroso a escala.
- **Funciones de import en batch:** ausentes. Decisión deliberada para reducir superficie de ataque. ✅

### Categoría 12: Patrones de checks no implementados

- **`renounceRole`:** estándar OZ, sin protección contra lockout. Ver M-08.
- **`pause`/`unpause`:** ausentes. Ver H-02.
- **Admin lockout:** posible. Ver M-08.

---

## Recomendaciones priorizadas (top 10 acciones)

1. **H-02 (fix obligatorio antes de mainnet):** agregar `Pausable` mixin con scope limitado a mutators. ADR explícito para documentar la decisión.

2. **H-01 (decisión de producto + fix):** definir política de revocación post-compra. Recomendación: agregar flag `revoked` separado + actualizar `AssetVault.reembolsarLoteFallido` para considerarlo.

3. **M-08 (fix antes de mainnet):** migrar a `AccessControlDefaultAdminRules` para prevenir admin lockout. Aplicar también a AssetVault y RedemptionManager.

4. **M-01 (fix obligatorio):** validar `evidenceHash != bytes32(0)` en `markSanctioned` y `orderHash != bytes32(0)` en `freezeAddress`.

5. **M-03 (fix mínimo):** agregar `address indexed actor` a TODOS los eventos de compliance para forensics post-incidente.

6. **M-04 (decisión + fix):** prohibir `tier = 0` en `setKYC` (la única vía a 0 es `revokeKYC`).

7. **M-05 (decisión con compliance):** validar `jurisdiction` contra whitelist mutable o al menos `!= bytes2(0)`.

8. **M-07 (fix simple):** incluir `sanctioned` y `frozen` en el evento `KYCUpdated` para evitar pérdida de contexto off-chain.

9. **M-06 (low effort):** agregar `MAX_REASON_LENGTH = 256` y validar en todas las funciones con strings.

10. **L-04 (decisión):** alinear `getTier` con la spec original (devolver 0 si expirado) O documentar explícitamente que no lo hace.

---

## Recomendaciones sobre infraestructura

(Cosas que no son del contrato pero impactan seguridad)

### 1. HSM / KMS para BACKEND_SIGNER

- **AWS KMS o GCP KMS** con políticas IAM restrictivas: solo el backend principal puede firmar.
- **Rotación automática mensual** del key version.
- **Audit logs persistidos en S3/GCS con retención de 7 años** (regulatorio).
- **Multi-region failover** para evitar single point of failure.

### 2. Hardware wallets para COMPLIANCE_OFFICER (titular + suplente)

- **Ledger Nano X** o equivalente. NUNCA hot wallets.
- **PIN + passphrase**, almacenamiento físico en sitios distintos (titular en oficina, suplente en domicilio o caja fuerte).
- **Procedure documentado**: el suplente solo actúa con autorización explícita del titular en condiciones excepcionales (vacaciones, indisponibilidad).
- **No usar la misma seed phrase** en ambos. Wallets completamente independientes.

### 3. Safe multi-sig para DEFAULT_ADMIN_ROLE

- **3-de-5** preferible a 2-de-3 (más resistente a comprometido único + permite cambio de membership sin downtime).
- **Signers separados geográficamente** y operacionalmente (no todos los cofundadores en la misma jurisdicción).
- **Procedimiento de rotación** documentado (cada 12 meses, cambiar al menos 1 signer).

### 4. Monitoring off-chain

- **Goldsky / The Graph** indexando todos los eventos.
- **Alertas Slack/PagerDuty** para:
  - `KYCUpdated` rate > 100/hora → posible compromiso de BACKEND_SIGNER.
  - `Sanctioned` o `Frozen` rate > 10/hora → posible compromiso de COMPLIANCE_OFFICER.
  - Cualquier `RoleGranted` o `RoleRevoked` en `DEFAULT_ADMIN_ROLE`.
- **Dashboard de health:** total wallets KYC tier 1/2/3, sancionadas, frozen, expirando próximamente.

### 5. Disaster recovery

- **Runbook documentado** para escenarios:
  - "BACKEND_SIGNER comprometido": revoke rol, rotar HSM key, grant a nueva wallet.
  - "COMPLIANCE_OFFICER comprometido": revoke rol, grant a nueva hardware wallet.
  - "DEFAULT_ADMIN Safe comprometido": situación crítica; mitigación posible solo con AccessControlDefaultAdminRules + 3-day delay para cambios (M-08).
- **Backup de seeds** en bóveda física (no Cloud, no digital).

### 6. Coordinación con bridge Sumsub

- **Webhook signature validation** estricto (HMAC SHA-256).
- **Replay protection** off-chain: cada applicantId Sumsub procesado debe registrarse en DB con flag de "processed".
- **Reconciliación diaria** entre Sumsub records y eventos `KYCUpdated` on-chain. Discrepancias generan alerta.

---

## Comparación vs AssetVault audit profundo

| Aspecto | AssetVault | IdentityRegistry |
|---|---|---|
| LOC | ~310 efectivos | ~120 efectivos |
| Findings High | 3 (H-01, H-02, H-03) | 2 (H-01, H-02) |
| Findings Medium | 8 | 8 |
| Findings Low | 6 | 6 |
| Findings Informational | 9 | 5 |
| Custom errors | ✅ | ✅ |
| `nonReentrant` | ✅ donde aplica | N/A (no mueve valor) |
| Pause | ✅ | ❌ (H-02) |
| `AccessControlDefaultAdminRules` | ❌ | ❌ (M-08) |
| Multi-sig admin | Recomendado | Recomendado |
| Storage packing | ✅ | ✅ |

**Conclusión comparativa:** IdentityRegistry es **más simple y tiene menos superficie**, pero su rol crítico como gatekeeper amplifica el impacto de cualquier finding. La ausencia de `pause` es la diferencia arquitectónica más importante con AssetVault y debe corregirse.

---

## Resumen para auditoría externa (Sherlock/Trail of Bits)

Antes de auditoría externa, **bloquear releases** hasta resolver:

- **H-01** (política de revocación post-compra) — decisión + implementación
- **H-02** (pause / circuit breaker) — implementación
- **M-01** (validar evidenceHash/orderHash) — fix obligatorio
- **M-03** (msg.sender indexed en eventos) — fix obligatorio para forensics
- **M-04** (tier=0 ambiguo) — decisión + fix
- **M-08** (admin lockout) — migrar a AccessControlDefaultAdminRules
- **M-05** (jurisdicción) — decisión con compliance

Resoluciones recomendadas en próximo iteration cycle:

- M-02 (rate limiting) — si pause se implementa, opcional
- M-06 (max reason length) — low effort
- M-07 (KYCUpdated incluir flags) — low effort

Tests adicionales requeridos:

- 100% coverage líneas/branches en IdentityRegistry.
- Fuzz tests sobre `setKYC` con `tier` arbitrario, `expiresAt` arbitrario, `jurisdiction` arbitraria.
- Invariant: "una address `sanctioned == true` SIEMPRE tiene `canMint() == false` y `canRedeem() == false`".
- Invariant: "una address `frozen == true` SIEMPRE tiene `canMint() == false` y `canRedeem() == false`".
- Invariant: "una address con `expiresAt <= block.timestamp` SIEMPRE tiene `canMint() == false` y `canRedeem() == false`".
- Test de integración: revokeKYC → comprar (revierte) → reembolsarLoteFallido (procesa? ver H-01).

---

**Última actualización:** 2026-05-22
**Auditor:** Subagente A (opus) | Deep audit IdentityRegistry.sol v0.1.0
**Estado:** findings comunicados al orquestador. Requiere aprobación de Dany F. para priorizar fixes.
