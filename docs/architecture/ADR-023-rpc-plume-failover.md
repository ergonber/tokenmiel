# ADR-023: RPC de Plume + failover (transport viem con `fallback()`)

**Status:** Accepted
**Date:** 2026-06-02
**Author:** Daniel Hidalgo Carrasco
**Tags:** rpc, plume, failover, viem, transport, fallback, backend-fase2, relayer, indexer, observability
**Resuelve:** OS-5.1 (ADR de RPC Plume + failover que bloquea el wiring a mainnet)
**Relacionado:** ADR-001 (multi-chain strategy), ADR-024 (Goldsky-en-Plume), CIS §1
**Supersedes:** N/A
**Superseded by:** N/A

---

## Context

El backend de Fase 2 (Bun + Hono + viem, `ARQUITECTURA-BACKEND-FASE2.md`) tiene una dependencia DURA del RPC de Plume en sus tres layers:

1. **Read path / read-vs-live (§1.2):** todo lo que es gate o decisión crítica se lee **LIVE** contra el nodo, NO del read model. Eso incluye `paused()` de los 3 contratos antes de `comprar`/`iniciarRedencion`, `canMint`/`canRedeem` (enforcement KYC on-chain), `balanceOf`/`availableBalance`/`tokensLockedFor` (balance pre-tx), `kgDisponibles(loteId)` y la hidratación de `lotes()` para los campos sin evento. Si el RPC cae, estas lecturas críticas se caen con él.
2. **Write path / relayer (§1.3):** el `RelayerService` hace `simulateContract` + `getTransactionCount(signer, 'pending')` para nonce, firma con KMS y emite la tx, después `waitForTransactionReceipt`. Una caída del RPC en medio del flujo deja el nonce sin reconciliar y la tx sin trackear.
3. **Reconciliación de nonce (§1.3):** la cola `relayer-hot` (concurrency=1) reconcilia `next_nonce` contra `getTransactionCount` y hace re-broadcast con gas-bump de tx atascadas. Sin RPC, el `NonceManager` queda ciego.

ADR-001 ya fijó la estrategia macro multi-chain: **Plume es la red primaria de las fases 1-7**, y en sus _Implementation notes_ dejó anotado **"RPC: Plume RPC oficial + provider redundante"** para Plume, reservando **"Alchemy (primario) + Infura (fallback)"** EXCLUSIVAMENTE para Polygon (fase 8+). El §0 de `ARQUITECTURA-BACKEND-FASE2.md` lo blinda como contradicción-a-evitar: _"asumir Polygon/Alchemy/Infura como RPC primario (la chain primaria es Plume)"_.

### El hueco que cierra

ADR-001 dejó **"provider redundante"** como un placeholder sin mecánica. El audit de cobertura de decisiones abiertas (OP-5 de la arquitectura de backend) lo listó como **OS-5.1 — bloqueante de producción**: no se puede wirear el backend a Plume mainnet sin definir, de forma formal y configurable:

- **Quién es el RPC primario** (URL + chainids exactos de Plume).
- **Cuál es la cadena de failover** y en qué orden.
- **Cómo se compone el transport de viem** para que una caída del primario NO frene reads live, envío de tx ni reconcile de nonce.
- **Qué env vars** gobiernan la configuración (sin hardcodear URLs fuera de `packages/chain`, CIS §1.1 Componente 3 — `rpcUrls inyectados por config/env`).

Hoy `packages/chain/src/clients` define `plumeTestnet`/`plumeMainnet` vía `defineChain` con los `rpcUrls` marcados como _"inyectados por config/env — ver ADR-RPC abierto"_. Este ADR ES ese ADR abierto.

---

## Decision

Se adopta un **transport viem `fallback()` con tres providers rankeados** para cada red de Plume, configurable por env var, e idéntico en estructura para `getPublicClient` (reads) y `getWalletClient` (writes, firma KMS).

### Mecánica

**1. Providers y orden de la cadena de failover:**

| Posición | Provider | Rol | chainid mainnet (98866) | chainid testnet (98867) |
|---|---|---|---|---|
| `[0]` primario | **Plume oficial** | RPC canónico de la red | `rpc.plume.org` | `testnet-rpc.plume.org` |
| `[1]` failover | **dRPC** (`drpc.org`) | redundancia multi-provider | endpoint Plume de dRPC | endpoint Plume de dRPC |
| `[2]` failover | **thirdweb** | redundancia adicional | endpoint Plume de thirdweb | endpoint Plume de thirdweb |

El primario es SIEMPRE el RPC oficial de Plume (es la fuente más fiel al estado canónico de la L2). dRPC y thirdweb son **redundancia de terceros** que materializan el "provider redundante" que ADR-001 dejó pendiente.

**2. Composición del transport (viem):**

```ts
// packages/chain/src/clients — esquema conceptual
transport: fallback(
  [
    http(PLUME_RPC_URL),            // [0] Plume oficial
    http(PLUME_RPC_URL_FALLBACK_DRPC), // [1] dRPC
    http(PLUME_RPC_URL_FALLBACK_THIRDWEB), // [2] thirdweb
  ],
  { rank: true, retryCount: 3 },
)
```

- **`rank: true`** — viem mide latencia/estabilidad de cada provider y reordena dinámicamente, así un primario lento se degrada de hecho sin intervención manual.
- **`retryCount`** — reintento por provider antes de pasar al siguiente de la lista.
- Una respuesta con error de transporte (timeout, 5xx, conexión caída) hace que viem **avance al próximo provider de la lista**, transparente para el caller. Un revert de contrato (custom error) NO es fallo de transporte: se propaga tal cual al `SolidityErrorDecoder` (§1.3).

**3. Configuración por env (sin hardcode fuera de `packages/chain`):**

| Env var | Contenido | Default si ausente |
|---|---|---|
| `PLUME_RPC_URL` | URL del primario (Plume oficial) | URL pública oficial por `CHAIN_ID` |
| `PLUME_RPC_URL_FALLBACK_DRPC` | URL de dRPC | omitir del array si vacía |
| `PLUME_RPC_URL_FALLBACK_THIRDWEB` | URL de thirdweb | omitir del array si vacía |

La red activa se resuelve por `CHAIN_ID` (CIS §1.1: `CHAIN_ID → DEPLOYMENTS[chainId] → resolveAddress`). Para mainnet `CHAIN_ID=98866`, para testnet `CHAIN_ID=98867`. Si una env var de failover está vacía, ese provider se omite del array `fallback()` (degradación graciosa: con solo el primario el sistema sigue funcionando, sin redundancia).

**4. Alcance Plume-only:**

Este ADR aplica **EXCLUSIVAMENTE a Plume** (98866/98867). **Polygon/Alchemy/Infura son fase 8+** (ADR-001 _Implementation notes_, Polygon) y NO se configuran acá. Cuando llegue la fase 8, la red Polygon tendrá su propio bloque de transport (Alchemy primario + Infura failover) en un ADR de cross-chain, sin tocar este.

### Por qué `fallback()` y no un solo `http()`

El layer de read live (§1.2) y el relayer (§1.3) NO toleran un single point of failure en el RPC: una caída del primario frenaría el gate `canMint`/`canRedeem`, el chequeo `paused()` pre-`comprar`, el balance pre-tx y la reconciliación de nonce. `fallback()` convierte esa caída en una degradación transparente (se sirve del siguiente provider) en vez de una caída del backend.

---

## Alternatives considered

### Alternativa A — Un solo RPC `http()` (Plume oficial, sin failover) (rechazada)

Configurar `transport: http(PLUME_RPC_URL)` apuntando solo al RPC oficial de Plume.

**Por qué se rechazó:**
- ❌ **Single point of failure** — una caída/rate-limit del RPC oficial frena TODOS los reads live críticos (`paused()`, `canMint`/`canRedeem`, balance pre-tx), el envío de tx y la reconciliación de nonce. El backend completo queda ciego ante la cadena.
- ❌ **Contradice ADR-001** — que explícitamente pidió "Plume RPC oficial **+ provider redundante**". Un solo provider no es redundante.
- ❌ **Sin escape ante incidente del proveedor** — si el endpoint oficial degrada, no hay alternativa automática; habría que redeployar/reconfigurar el backend a mano en medio del incidente.

### Alternativa B — Round-robin / balanceo manual entre providers (rechazada)

Implementar a mano la rotación de providers (load-balancer custom, contador, health-checks propios) en lugar de usar el primitivo de viem.

**Por qué se rechazó:**
- ❌ **Reinventa lo que viem ya da** — `fallback({ rank: true })` ya hace ranking por latencia/estabilidad, retry y avance automático. Un balanceador propio es superficie de bug nueva sin beneficio.
- ❌ **Acopla el código a infra de RPC** — el balanceo manual mete lógica de transporte en el dominio; con `fallback()` el transport queda declarativo y aislado en `packages/chain`.
- ❌ **No respeta la prioridad** — el round-robin trata a todos los providers como iguales; nosotros QUEREMOS al RPC oficial como primario (más fiel al estado canónico) y a los terceros como redundancia.

### Alternativa C — Gateway de terceros como primario (dRPC o thirdweb en `[0]`) (rechazada)

Poner un agregador de terceros como primario y el RPC oficial como failover.

**Por qué se rechazó:**
- ❌ **El oficial es la fuente más fiel** — para gates de compliance y balance pre-tx queremos el estado canónico de la L2; un agregador puede introducir lag/caché propios. El oficial debe ser `[0]`.
- ❌ **Contradice ADR-001** — que nombra "Plume RPC **oficial**" como base, con el redundante como complemento, no al revés.

### Alternativa D — Asumir el stack Polygon (Alchemy primario + Infura failover) para Plume (rechazada de plano)

**Por qué se rechazó:**
- ❌ **Contradicción explícita del §0** de `ARQUITECTURA-BACKEND-FASE2.md`: _"asumir Polygon/Alchemy/Infura como RPC primario (la chain primaria es Plume)"_. Alchemy/Infura son fase 8+ y para Polygon, NO para Plume.

---

## Consequences

### Positive

1. **Sin single point of failure en el RPC** — una caída del primario NO frena reads live (gates `canMint`/`canRedeem`, `paused()` pre-tx, balance pre-tx, `kgDisponibles`), ni el envío de tx, ni el reconcile de nonce. viem sirve del siguiente provider de forma transparente.
2. **Cierra OS-5.1, desbloquea el wiring a mainnet** — la decisión de RPC dejó de ser un placeholder de ADR-001 y queda formal y configurable, que era bloqueante de producción.
3. **Configurable por env, sin hardcode** — `PLUME_RPC_URL` + `PLUME_RPC_URL_FALLBACK_*` permiten rotar/cambiar providers sin recompilar; respeta CIS §1.1 (rpcUrls inyectados por config/env, addresses solo en `packages/chain`).
4. **Ranking dinámico gratis** — `rank: true` degrada un primario lento sin intervención humana; el backend siempre usa el provider más sano del momento.
5. **Degradación graciosa** — si las env de failover están vacías, el array se reduce al primario y el sistema sigue operando (sin redundancia), sin abortar el arranque.
6. **Aislado de cross-chain** — al ser Plume-only, la fase 8+ (Polygon/Alchemy/Infura) suma su propio bloque sin tocar este ADR.

### Negative

1. **Inconsistencia transitoria entre providers** — distintos RPCs pueden ir momentáneamente desincronizados de bloque (uno unos bloques atrás de otro). Mitigado por: (a) los gates críticos leen LIVE y toleran latencia de 1-2 bloques; (b) la finalidad/reorg se maneja en el read path (N-confirmaciones, ADR de finalidad abierto OS-5.5) y en Goldsky (ADR-024), NO en el transport; (c) el reconcile de nonce usa `getTransactionCount(signer, 'pending')` que es por-cuenta y converge.
2. **Dependencia de terceros (dRPC, thirdweb)** — agrega dos proveedores externos a monitorear. Mitigado: son failover, no primario; su caída no afecta el happy path, solo reduce la redundancia. El monitoreo de external deps (§1.4) puede sumar un health-check de cada provider.
3. **Costo/rate-limits de los failover** — dRPC y thirdweb pueden tener planes con límites. Aceptable: solo reciben tráfico cuando el primario degrada; en operación normal el grueso va al oficial.

### Neutral

1. **`rank` mueve el orden efectivo** — con `rank: true` el orden de la lista es una preferencia inicial, no un orden fijo; viem reordena por latencia. Es el comportamiento buscado, pero hay que tenerlo presente al leer logs (el provider que respondió puede no ser el `[0]`).
2. **Un revert NO es failover** — un custom error de Solidity (`NotKYCVerified`, `LoteNotInPreventa`, etc.) es una respuesta válida del nodo, no un fallo de transporte: NO dispara avance al siguiente provider, se propaga al `SolidityErrorDecoder` (§1.3). Esta distinción es intencional y debe mantenerse.
3. **El número de failovers es 2 por diseño** — primario + 2 redundantes. Sumar más providers es trivial (agregar `PLUME_RPC_URL_FALLBACK_N` al array), pero hoy 3 da redundancia suficiente para el MVP.

---

## Implementation notes

### Ubicación (CIS §1.1 Componente 3)

El transport vive en `packages/chain/src/clients`, donde `plumeTestnet`/`plumeMainnet` se definen vía `defineChain`. Los `rpcUrls` del `defineChain` y el `fallback([...])` de `getPublicClient`/`getWalletClient` se arman a partir de las env vars, resueltas por `CHAIN_ID`. **Prohibido hardcodear URLs de RPC fuera de `packages/chain`** (mismo principio que addresses en CIS §1.1).

### Composición concreta

```ts
// packages/chain/src/clients/transport.ts — esquema
import { fallback, http } from 'viem';

export function plumeTransport() {
  const urls = [
    process.env.PLUME_RPC_URL,
    process.env.PLUME_RPC_URL_FALLBACK_DRPC,
    process.env.PLUME_RPC_URL_FALLBACK_THIRDWEB,
  ].filter(Boolean) as string[];

  return fallback(
    urls.map((u) => http(u)),
    { rank: true, retryCount: 3 },
  );
}
```

- `getPublicClient(chainId)` (read-only, cacheado) y `getWalletClient(chainId)` (firma KMS via `KmsAccount`, NO clave privada — CIS §6.1) usan **el mismo** `plumeTransport()`. El failover protege por igual reads y writes.
- El `KmsAccount` (ADR de KMS abierto, OS-5.2) delega solo la firma; el envío de la tx firmada usa el transport con failover.

### Interacción con nonce y relayer (§1.3)

- La cola `relayer-hot` (concurrency=1) sigue serializando el stream del `BACKEND_SIGNER_ROLE`. El failover NO cambia la semántica de nonce: si el primario cae mientras hay una tx en vuelo, viem la reenvía vía el siguiente provider; el `NonceManager` reconcilia con `getTransactionCount(signer, 'pending')` (que es consistente por-cuenta entre providers).
- Re-broadcast con gas-bump (EIP-1559 ×1.25) de tx atascadas: NUNCA reusar nonce con otro payload (§1.3). El failover puede ayudar si el atasco era del provider, no de la red.

### Lo que este ADR NO decide

- **NO** decide finalidad/reorg — eso es **ADR-025** (finalidad/reorg en Plume). El transport NO maneja finalidad; eso vive en el read path y en Goldsky.
- **NO** decide Goldsky-en-Plume ni push-vs-polling — ese es **ADR-024** (OS-5.5). El indexer tiene su propia conexión a Plume, fuera de este transport (que es para el backend viem).
- **NO** decide KMS — eso es **ADR-022** (GCP Cloud KMS). El transport es agnóstico del account.
- **NO** aplica a Polygon — fase 8+ (Alchemy/Infura), ADR de cross-chain futuro.

---

## References

- `docs/architecture/ARQUITECTURA-BACKEND-FASE2.md` §1.1 (Componente 3 — viem chain + transport, rpcUrls por env), §1.2 (read-vs-live, reads live críticos), §1.3 (relayer, nonce, re-broadcast), §0 (contradicción-a-evitar: no asumir Polygon/Alchemy/Infura como RPC primario), OP-5 / OS-5.1 (este ADR)
- `docs/architecture/CIS-v1.md` §1 (chainids Plume: testnet 98867, mainnet 98866; addresses deployadas), §6.1 (custodia KMS del `BACKEND_SIGNER_ROLE`)
- ADR-001 (multi-chain strategy — "Plume RPC oficial + provider redundante" para Plume; "Alchemy primario + Infura fallback" SOLO Polygon fase 8+)
- ADR-024 (Goldsky-en-Plume — indexer con su propia conexión a Plume, fuera de este transport)
- viem `fallback()` transport (`rank`, `retryCount`) — primitivo de redundancia de RPC
