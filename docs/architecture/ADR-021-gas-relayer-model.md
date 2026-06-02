# ADR-021: Modelo de gas y relayer (BACKEND_SIGNER paga gas; B2C self-custody en el MVP)

**Status:** Accepted
**Date:** 2026-06-02
**Author:** Daniel Hidalgo Carrasco
**Tags:** relayer, gas, backend-signer, nonce, bullmq, leader-election, eip-1559, gasless, erc-2771, b2c, plume
**Resuelve:** OS-5.4 / OPEN-TOPIC "ADR-021 — Gas / relayer en Plume" (quién paga el gas, fondeo/rotación de la wallet operacional, política de nonce/gas-bump, modelo B2C)
**Relacionado:** CIS §6.1 (las 8 claves del deploy, custodia intended), ADR-020 (custodia HOT/COLD), ADR-022 (KMS concreto), ADR-015 (Timeout Policy — `cancelarRedencion` buyer-post-timeout), ADR-007 (backend stack: viem + BullMQ + Redis), ADR-012/ADR-016 (access control)
**Supersedes:** N/A
**Superseded by:** N/A

---

## Context

El backend de fase 2 tiene **un único punto que arma, firma y emite transacciones on-chain** (el write path / relayer descrito en `ARQUITECTURA-BACKEND-FASE2.md` §1.3). Todo lo demás es lectura. Ese write path tiene dos clases de actores muy distintas:

1. **`BACKEND_SIGNER_ROLE`** — el único rol que el backend firma por sí mismo, autónomamente, sin intervención humana: `AssetVault.comprar`, `IdentityRegistry.setKYC`, `IdentityRegistry.revokeKYC`. La custodia de esta clave es **GCP Cloud KMS** (ADR-022), NUNCA una clave privada en env de producción (CLAUDE.md §9, CIS §6.1).
2. **El comprador B2C** — `RedemptionManager.iniciarRedencion` la llama el **comprador con su propio wallet** (self-custody RainbowKit), NO el backend (CIS §3.3: la función es pública, sin rol; el `msg.sender` es el comprador). Lo mismo para el path `cancelarRedencion` buyer-post-timeout de ADR-015 (el comprador se auto-cancela pasados los 60 días si el Oracle desaparece).

### El hueco que cierra este ADR

La auditoría de cobertura de OPEN TOPICS del backend (`ARQUITECTURA-BACKEND-FASE2.md`, tabla final) marcó **ADR-021 con "Cero decisión documentada"** y lo clasificó como bloqueante de producción por dos razones operacionales concretas:

- **Lado backend:** si nadie define quién paga el gas y cómo se fondea/rota la wallet operacional, la wallet HOT se queda sin balance nativo y **se frena TODA la escritura** del sistema (no se mintea ninguna compra, no se sincroniza ningún KYC). Además, `BACKEND_SIGNER_ROLE` es **un solo address con un solo stream de nonce**: sin una política explícita de serialización, dos instancias de la API firmando en paralelo producen colisión de nonce, doble-gasto de gas, o —en el peor caso— **doble-mint** (la invariante de seguridad más cara del sistema).
- **Lado B2C:** el comprador self-custody podría **no tener gas nativo** en su wallet para disparar `iniciarRedencion` o el `cancelarRedencion` post-timeout. Si no se decide el modelo (paga el usuario vs gasless), la redención —el flujo que cierra el ciclo de negocio— queda con UX indefinida.

El CIS §6.1 ya **insinúa** la respuesta (la columna "Custodia mainnet intended" pone `BACKEND_SIGNER` en KMS y todo lo demás en Safe/hardware), y `ARQUITECTURA-BACKEND-FASE2.md` §1.3 ya describe la mecánica de `RelayerService`/`NonceManager`. Pero no existe un **invariante operacional formal** ni una decisión cerrada sobre el gas. Este ADR la formaliza. La decisión de qué claves son hot vs cold se formaliza por separado en ADR-020; acá se asume ese reparto y se decide **el modelo de gas** sobre él.

---

## Decision

Se adopta la **Vía A — `BACKEND_SIGNER` paga el gas con su propia wallet operacional (la misma clave GCP Cloud KMS)** para todas las transacciones que el backend firma autónomamente, y **self-custody B2C** (el usuario paga su propio gas) para las transacciones que dispara el comprador en el MVP.

### Vía A — Relayer HOT: el backend paga el gas

**Quién paga:** la wallet de `BACKEND_SIGNER_ROLE` paga el gas nativo de Plume de sus propias transacciones (`comprar`, `setKYC`, `revokeKYC`). No hay relayer de terceros ni paymaster: la wallet operacional ES la wallet que paga. La clave es la misma referencia KMS (ADR-022) — la wallet operacional no es una clave aparte, es la cuenta KMS de `BACKEND_SIGNER`.

**Serialización de nonce (corazón anti-doble-mint):** `BACKEND_SIGNER` es UN address con UN stream de nonce. La serialización se garantiza con dos capas combinadas:

1. **Cola BullMQ `relayer-hot` con `concurrency=1`** — todas las tx HOT pasan por una sola cola que procesa de a una. El `next_nonce` vive en la tabla `relayer_nonce` y se reconcilia contra `getTransactionCount(signer, 'pending')` (gap recovery).
2. **Leader-election** — como la API es **stateless y escala horizontalmente**, varias instancias podrían levantar workers de la cola. Solo **una instancia** debe firmar a la vez. Un lock distribuido (Redis-backed, el mismo Redis de Upstash que usa BullMQ) elige al leader; el resto de las instancias siguen sirviendo reads y encolando, pero **no procesan** la cola `relayer-hot`. Si el leader cae, otra instancia toma el lock y continúa el stream de nonce reconciliando contra la cadena.

**Idempotencia (segunda barrera anti-doble-mint):** antes de la cola, el endpoint aplica `Idempotency-Key` (para `comprar`, la clave natural es `paymentRefHash`). Tabla `relayer_idempotency` con `INSERT ... ON CONFLICT DO NOTHING`: si la key existía se devuelve el resultado previo, NUNCA se re-emite; misma key con payload distinto → 409. La confirmación de estado de dominio la da el **evento indexado por Goldsky**, no el receipt.

**Stuck tx → re-broadcast con gas-bump:** si una tx queda atascada (mempool sin minar), se **re-emite con el MISMO nonce** y un bump EIP-1559 de **×1.25** sobre `maxFeePerGas`/`maxPriorityFeePerGas`. **NUNCA se reusa un nonce con otro payload distinto** — re-broadcast es siempre la misma calldata, mismo nonce, solo sube el fee. Esto evita que un "reemplazo" accidental con otra calldata cause un doble efecto bajo el mismo nonce.

**Fondeo (MVP):** balance nativo de la wallet `BACKEND_SIGNER` **monitoreado + alerta + top-up manual**. Un job de monitoreo lee el balance nativo; al cruzar un umbral configurable dispara alerta a operaciones (Slack/Resend, vía `notifications/`); el top-up lo hace un humano manualmente. Auto-funding desde tesorería, rotación automática de wallet, y multi-wallet pooling quedan **fuera del MVP**.

### B2C — Self-custody en el MVP

**`iniciarRedencion` (comprador) y `cancelarRedencion` buyer-post-timeout (ADR-015):** las firma **el usuario con su propio wallet** (self-custody RainbowKit). **El usuario paga su propio gas.** El backend NO relaya estas transacciones; solo expone un **endpoint de PRE-VALIDACIÓN de lectura** (`canRedeem`, `balanceOf`, `availableBalance` vs lock) para que el frontend muestre un preview antes de que el usuario firme. No hay endpoint de escritura para estas dos funciones.

**Gasless como fast-follow, NO en el MVP:** la opción gasless (meta-transacciones ERC-2771 con un trusted forwarder, o un paymaster ERC-4337) mejora la UX del comprador retail (no necesita gas nativo de Plume para redimir), pero agrega un componente nuevo que mantener y fondear, y —en el caso ERC-2771— **requeriría modificar los contratos** para soportar `_msgSender()` vía forwarder, lo cual choca con la inmutabilidad de ADR-003 sobre los 3 contratos ya code-frozen. Por eso queda explícitamente **como fast-follow post-MVP**, no como parte del MVP.

---

## Alternatives considered

### Vía B — Relayer de terceros / servicio de relay externo (Gelato, Biconomy, OZ Defender) (rechazada para el MVP)

Delegar el envío de tx HOT a un relayer-as-a-service que gestiona nonce, gas-bump y fondeo por nosotros.

**Por qué se rechazó:**
- ❌ **Dependencia de un tercero en el path crítico de escritura** — si el relayer externo cae o cambia su API, se frena el minteo y la sync de KYC. Para un protocolo RWA con compliance crítico, es una superficie de terceros inaceptable en el MVP.
- ❌ **Custodia de firma poco clara** — varios de estos servicios esperan tener la clave o un mecanismo de delegación que rompe el invariante "la firma de `BACKEND_SIGNER` vive en KMS y no sale de ahí" (ADR-022).
- ❌ **Soporte en Plume incierto** — Plume es una L2 EVM RWA-focused relativamente nueva; el soporte de estos relayers no está garantizado, vs nuestra propia wallet que solo necesita un RPC.
- ✅ Se reconsidera post-MVP si el volumen justifica externalizar la operación de la wallet.

### Vía C — Gasless B2C en el MVP (ERC-4337 paymaster o ERC-2771 meta-tx) (rechazada para el MVP)

Que el backend (o un paymaster) patrocine el gas del comprador en `iniciarRedencion`/`cancelarRedencion` para que el usuario no necesite gas nativo.

**Por qué se rechazó (para el MVP):**
- ❌ **ERC-2771 requiere tocar los contratos** — soportar meta-tx vía trusted forwarder implica que `RedemptionManager` resuelva el `msg.sender` real vía `_msgSender()` del forwarder. Los 3 contratos están code-frozen e inmutables (ADR-003); agregar esto es un cambio de superficie + re-auditoría que no entra en el MVP.
- ❌ **ERC-4337 / paymaster agrega infraestructura nueva** — un paymaster es un contrato más que deployar, fondear, monitorear y proteger contra abuso (alguien podría drenar el patrocinio). Más superficie operacional sin beneficio bloqueante para el MVP.
- ❌ **No es bloqueante** — el comprador self-custody RainbowKit ya tiene un wallet; conseguir gas nativo de Plume es fricción tolerable para el primer círculo de usuarios del MVP.
- ✅ Queda como **fast-follow** explícito cuando el retail masivo lo justifique (preferible vía ERC-2771 con un nuevo contrato forwarder externo que NO toque los 3 existentes, o ERC-4337 si se migra a smart accounts).

### Vía D — Multi-wallet HOT pool con auto-funding (rechazada para el MVP)

Varias wallets `BACKEND_SIGNER` rotando, con re-fondeo automático desde tesorería, para paralelizar el throughput de minteo y eliminar el top-up manual.

**Por qué se rechazó:**
- ❌ **Multiplica los holders de un rol crítico** — más wallets HOT = más superficie de compromiso (cada una es una clave KMS que puede mintear). Contradice la dirección de ADR-020 (minimizar lo hot).
- ❌ **Auto-funding agrega un path de movimiento de fondos automático** — desde tesorería hacia wallets operacionales sin firma humana, otra superficie de ataque.
- ❌ **El throughput del MVP no lo justifica** — el volumen de compras inicial (miel monofloral premium, lotes acotados) se sirve sobrado con un solo signer serializado.
- ✅ Se reconsidera si el throughput de minteo se vuelve un cuello de botella real.

---

## Consequences

### Positive

1. **Cero dependencia de terceros en el write path** — la wallet `BACKEND_SIGNER` (KMS) firma y paga su propio gas. No hay relayer externo que pueda caerse o cambiar de API en el path crítico de minteo/KYC.
2. **Doble-mint imposible por construcción** — la combinación cola `relayer-hot` `concurrency=1` + leader-election (un solo firmante aunque la API escale) + idempotencia por `paymentRefHash` garantiza un único stream de nonce ordenado. La invariante anti-doble-gasto/anti-doble-mint vive en infraestructura, no en confianza.
3. **Stuck tx recuperables sin riesgo** — el re-broadcast mismo-nonce + gas-bump ×1.25 destraba tx atascadas; la regla "NUNCA reusar nonce con otro payload" elimina la clase de bug de reemplazo accidental con efecto distinto.
4. **B2C simple y sin custodia** — el comprador firma con su wallet; el backend no toca la firma del usuario ni custodia gas para él. Menos superficie, menos responsabilidad legal sobre fondos del usuario en el MVP.
5. **Inmutabilidad de los contratos preservada (ADR-003)** — al NO meter gasless ERC-2771 en el MVP, no se toca ninguno de los 3 contratos code-frozen.
6. **Camino de evolución claro** — gasless queda formalizado como fast-follow con la vía preferida (forwarder externo o ERC-4337) sin reabrir la decisión.

### Negative

1. **Single signer = límite de throughput** — un solo `BACKEND_SIGNER` serializado pone un techo al ritmo de minteo (una tx confirmada por nonce a la vez). Mitigado por: el volumen del MVP es bajo; si se vuelve cuello de botella, Vía D (multi-wallet pool) es la evolución natural.
2. **Top-up manual = riesgo operacional de "se acabó el gas"** — si nadie atiende la alerta de balance bajo, la wallet se queda sin gas y se frena toda la escritura. Mitigado por: monitoreo de balance + alerta a operaciones con umbral configurable; runbook que define el SLA de respuesta al top-up. Auto-funding queda como evolución.
3. **Fricción de gas para el comprador B2C** — el usuario retail necesita conseguir gas nativo de Plume para redimir/cancelar. Mitigado por: documentación/onboarding del comprador; gasless como fast-follow si la fricción mata conversión.
4. **Leader-election es estado distribuido que hay que operar bien** — un lock mal liberado podría dejar la cola `relayer-hot` sin procesar (ningún leader) o, peor, con dos leaders. Mitigado por: lock con TTL/renovación sobre el Redis ya existente (Upstash), reconciliación de nonce contra `getTransactionCount('pending')` al tomar el lock, y la cola `concurrency=1` como segunda barrera.

### Neutral

1. **La wallet operacional ES la clave de `BACKEND_SIGNER`** — no hay separación entre "wallet que firma el rol" y "wallet que paga gas"; son la misma cuenta KMS. Esto simplifica el MVP (una sola cuenta que monitorear), pero significa que el balance nativo de esa cuenta es parte del costo operacional del rol.
2. **Decisión acoplada a ADR-020 y ADR-022** — este ADR asume el reparto hot/cold de ADR-020 (`BACKEND_SIGNER` es el único hot) y el shape de firma KMS de ADR-022. Si alguno de esos cambia, revisar acá.
3. **El gas-bump ×1.25 es un valor inicial configurable** — el factor de bump y el umbral de "stuck" se calibran con datos reales de la mempool de Plume; no es un parámetro de diseño congelado.

---

## Implementation notes

Implementación en el backend Bun + Hono + Drizzle + viem (`apps/api`), dentro del write path descrito en `ARQUITECTURA-BACKEND-FASE2.md` §1.3 (OP-3 / OS-3.x).

### `RelayerService` (Vía A — HOT)

`writeContract` vía un `walletClient` construido con un **`KmsAccount` custom de viem** (`getWalletClient(chainId)`): el `signTransaction`/`sign` delega a un adapter KMS (ADR-022), **nunca materializa la clave privada en memoria**. El flujo happy-path: (1) resolver `walletClient` KMS → (2) **pre-flight reads** (para `comprar`: `lotes(loteId).estado==PREVENTA`, `kgDisponibles` en gramos cubre, `canMint(comprador)`, `paused()==false`, USDC ya transferido al contrato) → falla = 4xx ANTES de tocar nonce/gas → (3) `simulateContract` para capturar el custom error y mapearlo a HTTP → (4) nonce + idempotencia → (5) firma + envío → (6) tracking de `tx_hash` + `waitForTransactionReceipt` (el estado de dominio lo confirma el evento Goldsky, no el receipt).

### `NonceManager` + leader-election

- Cola **BullMQ `relayer-hot` `concurrency=1`** (OS-3.2). `next_nonce` en `relayer_nonce`, reconciliado contra `getTransactionCount(signer, 'pending')`.
- **Leader-election** vía lock distribuido en Redis (Upstash, el mismo que respalda BullMQ): solo el leader corre el worker de `relayer-hot`. Lock con TTL + renovación; al adquirirlo, reconciliar nonce contra la cadena antes de procesar.
- **Política de re-broadcast/gas-bump:** detectar stuck (sin minar tras N bloques/tiempo), re-emitir con MISMO nonce + EIP-1559 ×1.25, NUNCA otra calldata bajo el mismo nonce. Gap recovery vía el job de reconciliación.

### Persistencia (Drizzle)

Tablas del write path (migraciones Drizzle, OS-3.3/OS-3.5):
- `relayer_idempotency(idempotency_key PK, endpoint, request_hash, status, tx_hash, result, created_at)` — `paymentRefHash` como key natural de `comprar`.
- `relayer_nonce` — `next_nonce` por signer.
- `relayer_tx(id, idempotency_key, endpoint, contract_name, function_name, via [HOT|COLD], signer_or_safe, calldata, nonce, tx_hash, status, revert_error, created_by_admin, created_at, mined_at)` + escritura al `audit_log` append-only (hash chain).

### Monitoreo de fondeo (MVP)

Job BullMQ que lee el **balance nativo** de la wallet `BACKEND_SIGNER` (`getBalance` vía `getPublicClient`); al cruzar un umbral configurable, alerta a operaciones vía `notifications/` (Slack/Resend). Top-up manual. Sin auto-funding en el MVP.

### B2C (sin relayer)

`iniciarRedencion` y `cancelarRedencion` buyer-post-timeout **no tienen endpoint de escritura** — las firma el usuario (self-custody RainbowKit, paga su gas). El backend expone solo un endpoint de **PRE-VALIDACIÓN de lectura**: `canRedeem(msg.sender)`, `balanceOf`, y `availableBalance` vs `tokensLockedFor` (CIS §4.3) para el preview del frontend.

---

## References

- `docs/architecture/CIS-v1.md` §6.1 (las 8 claves del deploy; `BACKEND_SIGNER` en KMS, resto en Safe/hardware) y §3.3 (`iniciarRedencion`/`cancelarRedencion` públicas, sin rol — las firma el comprador)
- `docs/architecture/ARQUITECTURA-BACKEND-FASE2.md` §1.3 (write path: `RelayerService` Vía A HOT / Vía B COLD, `NonceManager`, idempotencia, re-broadcast/gas-bump), tabla de OPEN TOPICS (ADR-021 "Cero decisión documentada"), OP-3, OS-3.1–OS-3.5, OS-5.4
- ADR-020 (Custodia HOT/COLD — formaliza que `BACKEND_SIGNER` es el ÚNICO rol hot; este ADR decide el gas sobre ese reparto)
- ADR-022 (KMS = GCP Cloud KMS — define el shape del `KmsAccount` y el formato de `BACKEND_SIGNER_KMS_KEY_ID`)
- ADR-015 (Timeout Policy — el path `cancelarRedencion` buyer-post-timeout que el comprador firma self-custody)
- ADR-007 (backend stack — viem 2.x, BullMQ + Redis/Upstash)
- ADR-003 (4 contratos inmutables sin proxy — por qué gasless ERC-2771 in-contract no entra en el MVP)
- ADR-012 / ADR-016 (access control y asimetría de pause — contexto de roles)
