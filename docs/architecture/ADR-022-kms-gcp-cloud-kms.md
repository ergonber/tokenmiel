# ADR-022: Proveedor de KMS = GCP Cloud KMS (clave asimétrica secp256k1 para el BACKEND_SIGNER)

**Status:** Accepted
**Date:** 2026-06-02
**Author:** Daniel Hidalgo Carrasco
**Tags:** kms, gcp-cloud-kms, backend-signer, secp256k1, viem, custom-account, hot-relayer, secrets, irys
**Resuelve:** OS-5.2 (KMS concreto AWS vs GCP), desbloquea OS-3.1 / OS-1.3 (shape de `KmsAccount` + formato de `BACKEND_SIGNER_KMS_KEY_ID`)
**Relacionado:** CIS §6.1 (las 8 claves del deploy — `BACKEND_SIGNER_ROLE` = KMS AWS/GCP), CIS §17.2 (gestión de secretos: "AWS o GCP", OR sin resolver), ADR-020 (Custodia HOT/COLD — `BACKEND_SIGNER_ROLE` es el único rol hot), ADR-021 (Modelo de gas/relayer — la wallet HOT firma y paga gas), CLAUDE.md §9 (seguridad operacional: llaves en HSM/KMS, NO en env de prod)
**Supersedes:** N/A
**Superseded by:** N/A

---

## Context

El backend del MVP tiene exactamente **un** rol que firma transacciones de forma autónoma: `BACKEND_SIGNER_ROLE` (ADR-020). Es el relayer HOT que ejecuta `AssetVault.comprar`, `IdentityRegistry.setKYC` e `IdentityRegistry.revokeKYC` (CIS §6.1, §3; ARQUITECTURA-BACKEND-FASE2 §"RelayerService Vía A"). La regla de seguridad operacional es categórica: **la clave privada de ese signer NUNCA vive en una env var de producción ni se materializa en memoria** (CLAUDE.md §9; CIS §17.2). La clave reside en un KMS y el backend solo guarda una **referencia** (`BACKEND_SIGNER_KMS_KEY_ID`); cada firma es una llamada remota a la API del KMS.

El gap concreto que cierra este ADR proviene del audit de cobertura de la arquitectura de Fase 2 (ARQUITECTURA-BACKEND-FASE2, ítem 43 / OS-5.2): tanto el CIS §17.2 como el §6.1 dicen literalmente **"AWS o GCP"** — un `OR` sin resolver. Mientras ese `OR` quede abierto:

1. No se puede definir el **shape concreto de `KmsAccount`**, el custom account de viem que delega `signTransaction`/`sign` al KMS (OS-3.1, OS-1.3). Cada proveedor expone una API de firma distinta (nombres de operación, formato de request/response, forma de recuperar la clave pública).
2. No se puede fijar el **formato de `BACKEND_SIGNER_KMS_KEY_ID`** (ni el de `IRYS_FUNDING_WALLET_KMS_KEY_ID`, que sigue la misma política de custodia para fondear los uploads a Arweave/Irys). AWS usa ARNs; GCP usa nombres de recurso jerárquicos. El bootstrap fail-fast del backend (CIS §2 — pin de integridad; ARQUITECTURA-BACKEND-FASE2 §"bootstrap") necesita parsear ese identificador para resolver la cuenta antes de aceptar tráfico.
3. Queda bloqueado el camino de escritura completo (OP-3): sin un proveedor concreto no se implementa el `RelayerService` ni el manejo de nonce/gas-bump del único stream HOT.

Restricción técnica común a ambos proveedores: Ethereum/Plume usa firmas **ECDSA sobre la curva secp256k1**. Tanto AWS KMS como GCP Cloud KMS soportan claves asimétricas secp256k1 para firma, así que la decisión **no** está forzada por capacidad criptográfica — es una decisión de proveedor.

---

## Decision

El `BACKEND_SIGNER` usa **GCP Cloud KMS** con una **clave asimétrica de propósito `ASYMMETRIC_SIGN` y algoritmo `EC_SIGN_SECP256K1_SHA256`**.

El `KmsAccount` —un **custom account de viem**— delega `signTransaction` y `sign` a Cloud KMS vía la API de firma asimétrica (`AsymmetricSign`). La **clave privada NUNCA se materializa**: no aparece en memoria del proceso ni en ninguna env var. El backend solo conoce la referencia a la versión de la clave.

### Cambio de formato del identificador de clave

`BACKEND_SIGNER_KMS_KEY_ID` pasa de formato **ARN de AWS** al formato de **nombre de recurso de GCP**:

```
projects/PROJECT/locations/LOCATION/keyRings/RING/cryptoKeys/KEY/cryptoKeyVersions/VERSION
```

El identificador apunta a una **versión concreta** (`cryptoKeyVersions/VERSION`), no a la `cryptoKey` "lógica": la firma y la recuperación de la clave pública operan sobre una versión específica, y atar el signer a una versión explícita evita ambigüedad cuando se rote la clave (la rotación crea una versión nueva y se actualiza la env var deliberadamente).

El **mismo cambio de formato aplica a `IRYS_FUNDING_WALLET_KMS_KEY_ID`** (la wallet que fondea los uploads permanentes a Arweave vía Irys): misma política de custodia, mismo proveedor, mismo formato de recurso GCP.

### Mecánica del `KmsAccount` (custom account de viem)

1. **Bootstrap — derivar address desde la KMS key:** GCP Cloud KMS firma pero **no entrega la dirección Ethereum**. Al arranque, el backend llama `GetPublicKey` sobre la versión de clave, parsea la clave pública secp256k1 (DER/SPKI → punto sin comprimir de 64 bytes) y deriva la `address` como `keccak256(pubkey)[12:]`. Esa address debe coincidir con `BACKEND_SIGNER_ADDR` del deploy (CIS §6.1); si no coincide, el bootstrap **falla rápido** (fail-fast), igual que el pin de integridad de ABIs/bytecode (CIS §2).
2. **Firma — delegación remota:** para `signTransaction` (y `sign`), viem arma el digest de la transacción (EIP-1559 sobre Plume) y el `KmsAccount` invoca `AsymmetricSign` con ese hash. Cloud KMS devuelve la firma DER `(r, s)`; el adapter la normaliza a `(r, s, v)` de Ethereum: aplica **low-`s` malleability fix** (si `s > n/2`, `s = n - s`) y **recupera `v`** comparando la address derivada de cada candidato de recuperación contra la address conocida del bootstrap.
3. **Cero clave en memoria:** el `KmsAccount` solo guarda la `address` derivada y la referencia a la versión de clave. No existe ningún `privateKey` en el objeto cuenta ni en el `walletClient` que lo envuelve.

---

## Alternatives considered

### AWS KMS (rechazada)

El otro lado del `OR` de CIS §17.2 / §6.1. Soporta claves asimétricas secp256k1 (`SignatureAlgorithm = ECDSA_SHA_256`), la API `Sign`/`GetPublicKey` es equivalente en capacidad, y existe ecosistema maduro de adapters secp256k1↔Ethereum.

**Por qué se rechazó:**
- ❌ **Preferencia del equipo** — la decisión operacional es estandarizar la infraestructura de claves en GCP. Ambos proveedores son técnicamente equivalentes para secp256k1, así que la elección se resuelve por preferencia, no por capacidad.
- ⚠️ Tradeoff aceptado: alinear a un solo proveedor de cloud KMS reduce la superficie operativa (un solo IAM, un solo modelo de auditoría/rotación), a costa de la atadura que se documenta en Consequences.

### Materializar la clave privada en una env var / secret manager y firmar local (rechazada de plano)

Cargar la clave privada del signer en un `Secret` y firmar en proceso con viem `privateKeyToAccount`.

**Por qué se rechazó:**
- ❌ **Viola CLAUDE.md §9 y CIS §17.2** — la regla es explícita: NO clave privada en env de prod; las llaves operativas viven en HSM/KMS. Esta opción está prohibida por política de seguridad, no es un tradeoff abierto.
- ❌ **Amplía la superficie de compromiso** — cualquier lectura del entorno del proceso (dump, log, exfiltración) expone la clave que controla el mint y el KYC on-chain.

---

## Consequences

### Positive

1. **Cierra el `OR` de CIS §17.2 / §6.1** — el shape de `KmsAccount` y el formato de `BACKEND_SIGNER_KMS_KEY_ID` quedan definidos; se desbloquean OS-1.3 (`getWalletClient`) y OS-3.1 (`RelayerService` + `KmsAccount`).
2. **La clave privada NUNCA se materializa** — cumple CLAUDE.md §9 al pie: el secreto que controla `comprar`/`setKYC`/`revokeKYC` vive solo en Cloud KMS; el proceso nunca lo ve.
3. **Auditoría y rotación nativas** — Cloud KMS registra cada `AsymmetricSign` en Cloud Audit Logs, y la rotación de clave es una versión nueva + actualización deliberada de la env var (el identificador ya apunta a una versión concreta).
4. **Un solo proveedor para todo el signing operacional** — `BACKEND_SIGNER` e `IRYS_FUNDING_WALLET` comparten proveedor, IAM y formato de recurso: menos modelos de seguridad que mantener.
5. **Encaja con la arquitectura de Fase 2** — el `KmsAccount` se inserta sin fricción en `getWalletClient(chainId)` (ARQUITECTURA-BACKEND-FASE2 §"Componente 3"), que ya estaba diseñado para un custom account sin clave privada.

### Negative

1. **Atadura a GCP** — cambiar de proveedor implica reescribir el adapter de firma (API `AsymmetricSign`/`GetPublicKey`), re-emitir las claves y migrar el formato de los `*_KMS_KEY_ID`. Mitigado parcialmente: el `KmsAccount` se aísla detrás de la interfaz de cuenta de viem, así que el blast radius queda contenido al adapter.
2. **Latencia de firma remota** — cada firma es un round-trip de red a Cloud KMS. Como el HOT relayer es un único stream serializado (cola BullMQ `relayer-hot` concurrency=1, ARQUITECTURA-BACKEND-FASE2 §"Nonce"), la latencia de firma entra en la ruta crítica de cada tx (mint/KYC) y debe contemplarse en timeouts y backoff del gas-bump (ADR-021).
3. **Hay que recuperar la public key/address al bootstrap** — GCP firma pero no entrega la address; el backend debe llamar `GetPublicKey`, derivar la address y validarla contra `BACKEND_SIGNER_ADDR` antes de aceptar tráfico. Un mismatch debe ser fail-fast (no degradar a "sin signer").
4. **Recuperación de `v` y low-`s` a mano** — Cloud KMS devuelve DER `(r, s)` sin el `v` de Ethereum ni garantía de low-`s`. El adapter DEBE normalizar `s` y recuperar `v` por comparación de address; un bug acá produce firmas inválidas o rechazadas por la red.

### Neutral

1. **secp256k1 no era el factor decisivo** — ambos proveedores lo soportan; la decisión es de proveedor (preferencia del equipo), no de curva.
2. **El formato del identificador deja de ser ARN** — todo código, doc, `.env.example` y test que asumiera ARN de AWS para `BACKEND_SIGNER_KMS_KEY_ID` / `IRYS_FUNDING_WALLET_KMS_KEY_ID` debe migrar al nombre de recurso GCP. Es un cambio mecánico pero transversal.
3. **No altera el authority boundary** — tener la clave en GCP KMS no cambia qué puede hacer el `BACKEND_SIGNER_ROLE`: el gate sigue siendo on-chain (CIS §9; si el destinatario no pasa `canMint`, `comprar` revierte `NotKYCVerified` en `_update`, ADR-020).

---

## Implementation notes

Backend Bun + Hono + viem (ARQUITECTURA-BACKEND-FASE2, OS-1.3 / OS-3.1):

- **`KmsAccount` (custom viem account):** módulo en `apps/api/src/modules/.../shared/infrastructure/on-chain/`. Implementa la interfaz `Account` de viem con `signTransaction` y `sign` delegando al adapter de Cloud KMS (`AsymmetricSign`). No expone `signMessage`/`signTypedData` salvo que un caso de uso lo requiera; el MVP solo necesita firmar transacciones. El objeto cuenta guarda `{ address, keyVersionResourceName }`, **nunca** una clave privada.
- **Adapter de Cloud KMS:** cliente del SDK de GCP KMS (instalado vía `pnpm`, NUNCA `npm` — CLAUDE.md global). Dos operaciones: `getPublicKey(keyVersion)` (bootstrap) y `asymmetricSign(keyVersion, digest)` (firma). La normalización DER→`(r,s,v)` + low-`s` vive acá, aislada del resto del backend.
- **Bootstrap fail-fast:** en el arranque, `getWalletClient(chainId)` resuelve el `KmsAccount`, deriva la address vía `getPublicKey` y la compara con `BACKEND_SIGNER_ADDR` (resuelto desde `packages/chain`). Mismatch → abortar el arranque, alineado con el pin de integridad de ABIs/bytecode (CIS §2).
- **Validación de config (Zod):** `BACKEND_SIGNER_KMS_KEY_ID` e `IRYS_FUNDING_WALLET_KMS_KEY_ID` se validan en el esquema de env con un patrón que matchee `projects/.../cryptoKeyVersions/...` (input validation obligatoria en backend, CLAUDE.md raíz §4). Un valor con formato ARN debe fallar la validación en el arranque, no en la primera firma.
- **Integración con el `RelayerService` (Vía A HOT, OS-3.1):** el `walletClient` resuelto con `KmsAccount` se usa para `simulateContract` → `writeContract` sobre `comprar`/`setKYC`/`revokeKYC`. La latencia de firma KMS entra en la ruta de la cola `relayer-hot` (concurrency=1); el manejo de nonce/gas-bump y la idempotencia siguen ADR-021. El path COLD (Safe 2-de-3) NO usa `KmsAccount`: arma calldata, no firma (ADR-020).
- **`IRYS_FUNDING_WALLET`:** misma construcción de `KmsAccount` apuntando a `IRYS_FUNDING_WALLET_KMS_KEY_ID`, usada por el módulo de storage para firmar el fondeo de uploads permanentes a Arweave vía Irys. No participa del relayer on-chain de los 3 contratos del MVP.
- **Secretos:** ni `BACKEND_SIGNER_KMS_KEY_ID` ni `IRYS_FUNDING_WALLET_KMS_KEY_ID` son secretos (son referencias a recursos, no claves); aun así NO se commitean valores de prod (`.env*` fuera de git, CLAUDE.md raíz §4/§8). El secreto real es la credencial IAM de GCP del proceso, gestionada por el secret manager del hosting (Railway/Fly.io, ARQUITECTURA-BACKEND-FASE2 §18.1).

---

## References

- CIS §6.1 (las 8 claves del deploy — `BACKEND_SIGNER_ROLE` = "KMS (AWS/GCP), NO clave privada en env de prod")
- CIS §17.2 (gestión de secretos — backend signer en "AWS o GCP", el `OR` que este ADR resuelve)
- CIS §9 (authority boundary — el gate de KYC es on-chain; tener el rol no implica poder mintear sin `canMint`)
- ARQUITECTURA-BACKEND-FASE2 §"Componente 3 — viem chain + transport" (`getWalletClient` con custom account sin clave privada, OS-1.3)
- ARQUITECTURA-BACKEND-FASE2 §"RelayerService" + OS-3.1 (Vía A HOT firma KMS; `KmsAccount` custom de viem; nonce/idempotencia)
- ARQUITECTURA-BACKEND-FASE2 ítem 43 / OS-5.2 (ADR-022 — KMS concreto + shape de `KmsAccount`, el gap que cierra este ADR)
- ADR-020 (Custodia HOT/COLD — `BACKEND_SIGNER_ROLE` es el único rol hot que firma autónomamente; todo lo demás es cold vía Safe/hardware)
- ADR-021 (Modelo de gas/relayer — la wallet HOT firma vía KMS y paga gas; nonce/gas-bump)
- CLAUDE.md §9 (seguridad operacional — llaves operativas en HSM/KMS, backend signer como referencia KMS, NO clave privada en env de prod)
