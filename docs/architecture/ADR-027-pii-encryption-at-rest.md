# ADR-027: Cifrado de PII at-rest (applicants) con envelope encryption AES-256-GCM sobre GCP Cloud KMS

**Status:** Accepted
**Date:** 2026-06-02
**Author:** Daniel Hidalgo Carrasco
**Tags:** pii, encryption, at-rest, applicants, sumsub, kyc, envelope-encryption, aes-256-gcm, gcp-kms, dek-kek, defense-in-depth, no-pii-on-chain
**Resuelve:** Cómo se cifra concretamente la PII de la tabla `applicants` (el "PII cifrada en DB" que el backend ya declara pero no especifica)
**Relacionado:** ADR-022 (GCP Cloud KMS como infra de llaves del backend), ADR-026 (RLS sobre las tablas con PII), ADR-007 (stack backend: Bun+Hono+Drizzle+Postgres/Supabase), ADR-011 (jurisdicción validada off-chain), CIS §9 (authority boundary — NO PII on-chain, solo `sumsubApplicantHash`), CLAUDE.md §9 (seguridad operacional)
**Supersedes:** N/A
**Superseded by:** N/A

---

## Context

La tabla `applicants` es el **único repositorio de PII del sistema** y la **fuente de verdad ÚNICA** de la evidencia KYC de Sumsub (CIS §9, matriz source-of-truth del backend, fila "Evidencia KYC"). Guarda nombre, número de documento de identidad y dirección de cada inversor verificado. On-chain **NUNCA** viaja PII: lo único que llega a `IdentityRegistry` es el `sumsubApplicantHash` (un `bytes32` determinístico, NO el id de Sumsub en claro), por decisión explícita del authority boundary del CIS §9 y del flujo `ResolveKYCDecision` (ARQUITECTURA-BACKEND-FASE2 §, item KYC). La frontera está bien trazada del lado de la cadena.

El hueco está del lado de la DB. La arquitectura de backend (fase 2) ya **declara** que `applicants` lleva "PII cifrada en DB, hash en cadena" (matriz source-of-truth) y el checklist de implementación pide crear la tabla `applicants` (PII cifrada) — pero **NUNCA especifica el mecanismo de cifrado**: ni el algoritmo, ni dónde viven las llaves, ni la granularidad, ni cómo se descifra en runtime. Ese "cifrada" sin especificar es exactamente el gap que detecta el audit de cobertura de seguridad: una afirmación de control sin diseño que la respalde no es un control.

Las restricciones heredadas que acotan la solución:

- **CLAUDE.md §9 — seguridad operacional:** "Llaves operativas viven en HSM (AWS KMS / GCP KMS) o hardware wallets. NUNCA en env vars de producción". "No PII en logs". La regla de llaves aplica también a las llaves de cifrado de datos, no solo a las de firma de transacciones.
- **ADR-022 — GCP Cloud KMS:** la decisión de KMS concreto del backend (resuelta a favor de GCP Cloud KMS) ya provee infra de llaves gestionadas para el `BACKEND_SIGNER` (firma). Reusar esa misma infra para cifrado evita introducir un segundo proveedor de llaves.
- **ADR-026 — RLS:** Row-Level Security limita **qué filas** puede leer cada rol de Postgres, pero NO protege el **contenido** de una fila si esta se exfiltra (dump robado, backup filtrado, credencial de DB comprometida, insider con `SELECT`). RLS y cifrado at-rest atacan vectores distintos.
- **Stack (ADR-007):** Bun + Hono + Drizzle ORM sobre PostgreSQL 16+ (Supabase). El cifrado debe encajar en la capa de aplicación (Drizzle), no depender de features propietarios que aten al proveedor.

El gap concreto a cerrar: definir **cómo** se cifra la PII de `applicants` de forma que (1) las llaves nunca toquen la DB ni el env, (2) la rotación de llaves no obligue a re-cifrar todos los registros, (3) el cifrado complemente — no reemplace — a RLS, y (4) se preserve la invariante "NUNCA PII on-chain" del CIS §9.

---

## Decision

La PII de la tabla `applicants` (nombre, documento, dirección, y cualquier columna que contenga evidencia Sumsub identificable) se cifra **a nivel de aplicación** con **AES-256-GCM** usando **envelope encryption**: una **DEK** (Data Encryption Key) por registro/columna cifrada, y esa DEK envuelta (cifrada) por una **KEK** (Key Encryption Key) que vive y nunca sale de **GCP Cloud KMS** (la misma infra de ADR-022). Las llaves de cifrado **nunca viven en la DB ni en variables de entorno**. El cifrado complementa RLS (ADR-026) como **defensa en profundidad**: RLS limita el acceso por fila; el cifrado protege el contenido aunque la fila se exfiltre. On-chain sigue yendo **únicamente** el `sumsubApplicantHash` (`bytes32` determinístico) — esta decisión NO toca el authority boundary del CIS §9.

### Mecánica

**1. Modelo de llaves (envelope, dos niveles):**

- **KEK** — vive en GCP Cloud KMS (keyring + cryptoKey dedicados a PII, separados de la cryptoKey de firma del `BACKEND_SIGNER` de ADR-022). El material de la KEK **nunca se exporta**: GCP KMS solo expone `encrypt`/`decrypt` sobre payloads pequeños (la DEK). Soporta rotación de versión sin re-cifrar los datos (solo se re-envuelven las DEKs en background).
- **DEK** — AES-256, generada con CSPRNG **por registro** (una DEK por fila de `applicants`). La DEK en claro vive **solo en memoria del proceso backend** durante la operación de cifrado/descifrado; en reposo se persiste **únicamente su forma envuelta** (`encrypted_dek` = `KMS.encrypt(KEK, DEK)`).

**2. Esquema de columnas (Drizzle/Postgres):**

Cada campo PII se persiste como ciphertext binario, no como texto plano. La tabla `applicants` guarda, por registro:

- `encrypted_dek` (`bytea`) — la DEK envuelta por la KEK de GCP KMS.
- `kek_version` (`text`) — la versión de la cryptoKey de GCP KMS usada para envolver la DEK (habilita rotación + descifrado de registros viejos).
- Por columna PII (ej. `nombre_ciphertext`, `documento_ciphertext`, `direccion_ciphertext`, todas `bytea`): `nonce` (12 bytes, único por operación) ‖ `ciphertext` ‖ `auth_tag` (GCM tag de 16 bytes). El AAD del GCM liga el ciphertext al `applicantId` para prevenir swapping de ciphertexts entre filas.
- `sumsubApplicantHash` (`bytea`/`char(66)`) — **en claro**: es el `bytes32` determinístico que va on-chain; NO es PII y se usa como join key contra `kyc_mirror` y los eventos `KYCUpdated`. No se cifra.

**3. Flujo de cifrado (escritura, en `application` al persistir evidencia Sumsub):**

```
1. genDEK()                       → DEK aleatoria AES-256 (CSPRNG, en memoria)
2. KMS.encrypt(KEK, DEK)          → encrypted_dek + kek_version   (llamada a GCP KMS)
3. por cada campo PII:
     nonce = random(12)
     AES-256-GCM.encrypt(DEK, nonce, plaintext, AAD=applicantId)
       → ciphertext + auth_tag
4. persistir { encrypted_dek, kek_version, *_ciphertext } vía Drizzle
5. zeroize(DEK)                   → borra la DEK en claro de memoria
```

**4. Flujo de descifrado (lectura, bajo demanda y auditada):**

```
1. leer { encrypted_dek, kek_version, *_ciphertext } (fila ya filtrada por RLS de ADR-026)
2. KMS.decrypt(KEK[kek_version], encrypted_dek) → DEK en memoria   (llamada a GCP KMS)
3. AES-256-GCM.decrypt(DEK, nonce, ciphertext, auth_tag, AAD=applicantId)
     → plaintext  (si el auth_tag no valida → revert: tampering/corrupción)
4. usar plaintext en memoria; zeroize(DEK) al terminar
```

El descifrado **nunca** es masivo ni de fondo: se hace por registro, bajo un caso de uso explícito de compliance, y se registra en `audit_log` (append-only, hash chain, **sin volcar la PII descifrada** — solo `applicantId` + actor + motivo).

### Por qué dos capas (KEK/DEK) y no cifrar todo con la KEK directamente

Cifrar cada campo llamando a GCP KMS directamente sería 1 round-trip de red por campo por operación (latencia + costo + límite de tamaño de payload de KMS). Con envelope, GCP KMS solo cifra/descifra la DEK (un blob chico); el cifrado simétrico bruto de la PII lo hace el backend localmente con AES-256-GCM (rápido, sin límite de tamaño). Y la **rotación de la KEK no obliga a re-cifrar la PII**: basta re-envolver las DEKs (`decrypt` con la versión vieja → `encrypt` con la nueva), operación barata sobre blobs pequeños.

---

## Alternatives considered

### Opción A — Supabase Vault (pgsodium / Transparent Column Encryption) (rechazada)

Usar la extensión `pgsodium` / Supabase Vault para cifrar columnas dentro de Postgres, con las llaves gestionadas por el server key de pgsodium.

**Por qué se rechazó:**
- ❌ **La llave raíz vive en/junto a la DB** — pgsodium deriva las llaves de un server secret que, en el modelo gestionado, es accesible al motor Postgres. Eso viola CLAUDE.md §9 ("llaves NUNCA en el env de prod" y, por extensión, fuera del perímetro de la DB) y debilita la defensa en profundidad: si se compromete el host de la DB, se compromete también la capacidad de descifrar.
- ❌ **Atadura al proveedor** — acopla el cifrado al runtime de Supabase/pgsodium; una migración futura de Postgres o un re-deploy a otra infra obligaría a re-cifrar todo. El stack (ADR-007) trata a Supabase como Postgres gestionado, no como plataforma de cifrado.
- ❌ **No reusa la infra de llaves ya decidida** — ADR-022 ya estableció GCP Cloud KMS para el backend. Meter un segundo gestor de llaves (pgsodium) fragmenta la gobernanza de llaves, las políticas de rotación y el audit trail.
- ❌ **Separación de poderes débil** — quien tiene acceso administrativo a la DB tendría también la capacidad de descifrar. Con KEK en GCP KMS, descifrar exige además permisos IAM sobre la cryptoKey, separados del acceso a la DB.

Evaluada seriamente porque es la opción de menor fricción operativa dentro de Supabase; se rechaza porque el modelo de amenaza central es justamente "la DB/su backup se exfiltra", y pgsodium no protege bien contra eso.

### Opción B — Solo RLS, sin cifrado de contenido (rechazada)

Confiar únicamente en Row-Level Security (ADR-026) para proteger la PII, sin cifrar el contenido.

**Por qué se rechazó:**
- ❌ **RLS no protege contenido exfiltrado** — RLS enforcea el acceso en el plano de consultas autorizadas del motor. No protege contra dump de disco, backup robado, snapshot filtrado, o una credencial de DB con privilegios que evada/desactive políticas. En todos esos casos la PII queda en claro.
- ❌ **Un solo control = sin defensa en profundidad** — la PII es el activo más sensible (documento de identidad, dirección). Un único punto de falla sobre el activo más crítico es inaceptable.

### Opción C — Cifrado directo con la KEK de GCP KMS (sin DEK) (rechazada)

Cifrar cada campo PII llamando directamente a `GCP KMS.encrypt(KEK, plaintext)`, sin DEK intermedia.

**Por qué se rechazó:**
- ❌ **Latencia y costo por campo** — un round-trip de red a GCP KMS por cada campo y cada operación de lectura/escritura. Insostenible para el volumen de onboarding (CIS §5.2 marca `KYCUpdated` como evento de alto volumen).
- ❌ **Límite de tamaño de payload de KMS** — GCP KMS está pensado para cifrar blobs pequeños (llaves), no payloads arbitrarios.
- ❌ **Rotación cara** — rotar la KEK obligaría a re-cifrar TODA la PII directamente contra KMS, en vez de solo re-envolver DEKs pequeñas.

---

## Consequences

### Positive

1. **Defensa en profundidad real** — RLS (ADR-026) limita el acceso por fila; el cifrado at-rest protege el contenido aunque la fila se exfiltre. Dos controles ortogonales sobre el activo más sensible: un atacante necesita comprometer la DB **y** obtener permisos IAM sobre la KEK de GCP KMS.
2. **Llaves fuera de la DB y del env** — la KEK nunca sale de GCP Cloud KMS; la DEK solo vive en memoria del proceso durante la operación. Cumple CLAUDE.md §9 al pie. Quien dumpea la DB obtiene solo ciphertext + DEKs envueltas inútiles sin la KEK.
3. **Rotación barata** — rotar la KEK re-envuelve DEKs (blobs chicos), sin re-cifrar la PII. `kek_version` por registro permite descifrar datos viejos durante la transición.
4. **Reusa la infra de ADR-022** — un solo proveedor de llaves (GCP Cloud KMS) para firma y cifrado: gobernanza, IAM, rotación y audit trail unificados.
5. **Integridad además de confidencialidad** — GCM provee authentication tag: un ciphertext manipulado falla el descifrado (no devuelve basura silenciosa). El AAD ligado al `applicantId` previene swapping de ciphertexts entre filas.
6. **Authority boundary intacto** — esta decisión es 100% off-chain. On-chain sigue yendo solo el `sumsubApplicantHash` (`bytes32` determinístico). El CIS §9 ("NUNCA PII on-chain") queda preservado sin cambios.
7. **Portabilidad** — el cifrado vive en la capa de aplicación (Drizzle + AES-256-GCM + adapter GCP KMS), no atado a un feature propietario de Postgres. Migrar de Supabase a otro Postgres no obliga a re-cifrar.

### Negative

1. **Latencia de descifrado por llamada a KMS** — cada lectura de PII implica un `KMS.decrypt` de la DEK (round-trip de red). Mitigado por: (a) las lecturas de PII son raras y bajo caso de uso de compliance, no en el hot path de `comprar`/`setKYC` (que usan `sumsubApplicantHash` en claro como join key, no la PII); (b) opción de cache de DEK en memoria con TTL corto si un flujo lo exige, decidido caso por caso.
2. **Las columnas PII cifradas NO son consultables** — no se puede `WHERE nombre LIKE ...` ni indexar sobre el plaintext. Mitigado: las búsquedas/joins operativos se hacen sobre `sumsubApplicantHash` (en claro, no PII) y sobre el `wallet`/`applicantId`; los campos PII solo se descifran ya teniendo la fila localizada.
3. **Dependencia operacional de GCP Cloud KMS** — si GCP KMS no está disponible, no se puede cifrar (escritura de onboarding bloqueada) ni descifrar (lectura de compliance bloqueada). Mitigado por la disponibilidad gestionada de KMS y por que los flujos críticos on-chain NO dependen de descifrar PII (van por `sumsubApplicantHash`).
4. **Complejidad de implementación** — manejo de nonces únicos, zeroize de DEK en memoria, AAD por registro, versionado de KEK. Es código de seguridad sensible que exige review manual obligatorio (CLAUDE.md §5, paso review para cambios de secrets/KMS).

### Neutral

1. **`sumsubApplicantHash` permanece en claro** — es intencional: NO es PII (es un `bytes32` determinístico, el mismo que va on-chain) y es la join key contra `kyc_mirror`/eventos. Cifrarlo rompería los joins y la correlación con la cadena sin ganar nada.
2. **El audit trail de descifrados es append-only sin PII** — cada descifrado registra `applicantId` + actor + motivo en `audit_log` (hash chain de CLAUDE.md §9), nunca el plaintext. Esto es coherente con "No PII en logs".
3. **Granularidad DEK-por-registro vs DEK-por-columna** — se adopta una DEK por registro (todas las columnas PII de una fila comparten DEK, con nonce distinto por columna). Una DEK por columna daría aislamiento mayor a costo de más blobs envueltos; la asimetría es intencional y puede revisarse si un campo (ej. documento) exige aislamiento criptográfico extra.

---

## Implementation notes

### Ubicación en el backend (Bun + Hono + Drizzle, hexagonal)

- **Puerto de dominio:** una interfaz `PiiCipher` (`encryptField` / `decryptField`) en la capa `domain`/`application` del módulo de identidad, agnóstica del proveedor.
- **Adapter de infraestructura:** `GcpKmsEnvelopeCipher` en `infrastructure/crypto/`, que (a) llama a GCP Cloud KMS (`encrypt`/`decrypt` de la KEK, vía el SDK de GCP con auth por service account / workload identity — NUNCA clave en env, consistente con el `KmsAccount` de firma de ADR-022), (b) hace el AES-256-GCM local con el módulo `crypto` de Bun/WebCrypto. Reusa el mismo cliente/credenciales de GCP KMS que el adapter de firma del `BACKEND_SIGNER`.
- **Schema Drizzle:** la tabla `applicants` define las columnas `encrypted_dek bytea`, `kek_version text`, y los `*_ciphertext bytea` por campo PII; `sumsubApplicantHash` en claro como índice/join key. Migración con `drizzle-kit`.
- **Caso de uso:** `ResolveKYCDecision` (ARQUITECTURA-BACKEND-FASE2) persiste la evidencia Sumsub cifrada y deriva el `sumsubApplicantHash` en claro para `setKYC`. La PII cruda **nunca** se loguea (pino, sin PII) ni se pasa a viem/on-chain.

### Invariantes a verificar (tests)

```
1. Ningún campo PII se persiste en claro: el round-trip encrypt→DB→decrypt devuelve el original,
   pero un SELECT crudo de la columna devuelve bytea ilegible (ni nombre ni documento aparecen).
2. La KEK nunca se materializa fuera de GCP KMS: el adapter solo recibe ciphertext de DEK; no hay path
   que exporte material de la KEK.
3. AAD = applicantId: descifrar un ciphertext con el applicantId equivocado falla el auth_tag (anti-swap).
4. Tampering del ciphertext o del auth_tag → decrypt revierte (no plaintext corrupto silencioso).
5. NUNCA PII on-chain: el único dato que sale hacia IdentityRegistry es sumsubApplicantHash (bytes32).
6. Sin PII en audit_log ni en logs (pino): se verifica que el descifrado registra solo applicantId+actor+motivo.
```

### Rotación de KEK (runbook)

Rotar la versión de la cryptoKey en GCP KMS; un job de background re-envuelve las DEKs (`decrypt` con `kek_version` vieja → `encrypt` con la nueva → actualiza `encrypted_dek` + `kek_version`). La PII (los `*_ciphertext`) **no se toca**. Registros con `kek_version` vieja siguen siendo descifrables hasta que el job los migre.

### Review obligatorio

Por tocar PII + KMS, este cambio cae bajo CLAUDE.md §5 (paso review: "Secrets / KMS / auth → review manual obligatorio") y §9. El PR de implementación exige review manual de seguridad, no solo CI verde.

---

## References

- `docs/architecture/ARQUITECTURA-BACKEND-FASE2.md` (matriz source-of-truth, fila "Evidencia KYC (Sumsub applicant)" → "PII cifrada en DB, hash en cadena"; checklist: tabla `applicants` PII cifrada; `ResolveKYCDecision` deriva `sumsubApplicantHash` sin PII on-chain)
- `docs/architecture/CIS-v1.md` §9 (authority boundary — NO PII on-chain, solo `sumsubApplicantHash`) y matriz source-of-truth (Evidencia KYC = fuente de verdad única off-chain)
- `CLAUDE.md` §9 (seguridad operacional: llaves en KMS, NUNCA en env; No PII en logs) y §5 (loop review obligatorio para secrets/KMS/auth)
- ADR-022 (GCP Cloud KMS como infra de llaves del backend — KEK reusa esta infra)
- ADR-026 (RLS sobre las tablas con PII — el cifrado at-rest es su complemento, defensa en profundidad)
- ADR-007 (stack backend: Bun + Hono + Drizzle ORM + PostgreSQL/Supabase + viem)
- ADR-011 (jurisdicción validada off-chain — el backend ya es la fuente de datos KYC sensibles)
