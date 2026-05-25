# Propuesta: Plataforma de Tokenización de Miel Monofloral Boliviana para Exportación Premium

## Marco Técnico-Legal Integrado

---

**Autor:** Daniel Hidalgo Carrasco.
**Fecha:** 16 de mayo de 2026
**Versión:** 1.0
**Estado:** Borrador para revisión y presentación institucional

---

## Tabla de contenidos

1. [Resumen ejecutivo](#1-resumen-ejecutivo)
2. [Contexto del proyecto](#2-contexto-del-proyecto)
3. [Naturaleza jurídica del token](#3-naturaleza-jurídica-del-token)
4. [Marco legal aplicable](#4-marco-legal-aplicable)
5. [Estructura societaria propuesta](#5-estructura-societaria-propuesta)
6. [Arquitectura técnica de alto nivel](#6-arquitectura-técnica-de-alto-nivel)
7. [Bridge legal-código: tabla maestra](#7-bridge-legal-código-tabla-maestra)
8. [Smart contracts: descripción funcional](#8-smart-contracts-descripción-funcional)
9. [Backend de cumplimiento (compliance)](#9-backend-de-cumplimiento-compliance)
10. [Flujos operativos end-to-end](#10-flujos-operativos-end-to-end)
11. [Plan de implementación](#11-plan-de-implementación)
12. [Riesgos y mitigaciones](#12-riesgos-y-mitigaciones)
13. [Conflictos legales pendientes de validación](#13-conflictos-legales-pendientes-de-validación)
14. [Próximos pasos institucionales](#14-próximos-pasos-institucionales)
15. [Glosario técnico-legal](#15-glosario-técnico-legal)
16. [Referencias normativas](#16-referencias-normativas)

---

## 1. Resumen ejecutivo

La presente propuesta describe el diseño técnico-legal de una plataforma de **tokenización de miel monofloral boliviana** destinada a la exportación premium al mercado europeo, bajo un modelo de **pre-venta con redención física**.

**El modelo de negocio en una línea:** un comprador europeo paga hoy y recibe un *token* digital que representa una cantidad específica de miel (0.5 kg por token) de un lote identificado. Cuando se produce y certifica la cosecha, el comprador redime el token y recibe la miel exportada físicamente.

La plataforma se estructura sobre **dos pilares simultáneos**:

1. **Pilar jurídico:** cumplimiento estricto del marco normativo boliviano (RD BCB 082/2024, D.S. 5384/2025, Circular ASFI 885/2025, RA UIF 19/2025, Ley 1489, reglamentos SENASAG, Ley 470) e internacional aplicable (Wyoming Digital Asset Act 2019, MiCA UE).

2. **Pilar técnico:** infraestructura blockchain pública (Polygon PoS), contratos inteligentes auditables (Solidity, ERC-1155), KYC tiered con verificación biométrica (Sumsub), oráculo humano multi-firma (Safe 2-de-3), preservación documental inmutable (Arweave), reportería automatizada para UIF Bolivia y cadena de custodia digital para SENASAG.

**Lo que diferencia esta propuesta** de otras iniciativas de tokenización agrícola en América Latina es la **trazabilidad bidireccional**: cada token está respaldado por un contrato forward (FSA) entre dos entidades societarias claramente delimitadas, y cada hito del ciclo productivo (cosecha, análisis físico-químico, almacenamiento, exportación) queda registrado de forma inmutable, simultáneamente, en una base de datos auditable (PostgreSQL), en almacenamiento permanente (Arweave) y en la blockchain pública.

**Tipo de instrumento legal:** *commodity token* con respaldo en contrato forward. Explícitamente **NO es un valor mobiliario**. Esta clasificación —desarrollada en la sección 3— sustrae al proyecto del régimen del Libro XIV de la propuesta de Reglamento Normativo del Mercado de Valores (Propuesta Cerda, mayo 2026), evitando la obligación de constituirse como Operador de Plataforma de Tokenización (OPT) ante ASFI, sin perjuicio del cumplimiento estricto del marco PSAV ante UIF Bolivia.

**Audiencia objetivo del MVP:** modelo **híbrido B2B + B2C** desde el primer día. Comprador europeo profesional (importadores boutique, distribuidores de specialty food, chefs Michelin, hoteles boutique) y consumidor final europeo entusiasta del producto gourmet con conciencia ambiental.

**Plazo de implementación:** 10 a 12 meses desde aprobación hasta soft launch con primer lote piloto.

---

## 2. Contexto del proyecto

### 2.1 La oportunidad de mercado

Bolivia posee variedades de miel monofloral de altísimo valor en el mercado europeo de *specialty food*: miel de romero, miel de banda, miel de eucalipto y mieles de altura andina son productos diferenciados por su origen geográfico (terroir), su perfil organoléptico único y su producción artesanal a pequeña escala.

El precio promedio al consumidor final europeo de miel monofloral certificada de origen oscila entre **USD 60 y USD 100 por kilogramo**. El precio al productor boliviano se sitúa en USD 15 a USD 25 por kilogramo. Existe un margen considerable que actualmente capturan intermediarios y distribuidores tradicionales.

La tokenización con pre-venta permite:

- **Al productor apícola:** financiamiento anticipado de la cosecha sin endeudamiento bancario, reduciendo el riesgo financiero del ciclo productivo.
- **Al comprador europeo:** acceso directo a productores certificados con trazabilidad criptográfica completa, eliminando intermediarios y reduciendo el precio final.
- **A Bolivia como país exportador:** posicionamiento de producto premium de origen con infraestructura tecnológica moderna y cumplimiento regulatorio demostrable.

### 2.2 El modelo de negocio

El ciclo completo de cada lote tokenizado atraviesa **tres momentos jurídicamente distintos**:

**Momento 1: Pre-venta (token = promesa contractual de entrega).** El comprador europeo paga el precio del token. Recibe en su billetera digital un token que representa un derecho contractual contra la Wyoming LLC (emisora), respaldado por un Forward Sale Agreement con la SRL Bolivia (productora). Una fracción del 15% al 20% del monto pagado se retiene como reserva técnica.

**Momento 2: Post-cosecha (token = certificado digital de depósito).** Una vez producida y certificada la cosecha, el token cambia de naturaleza: ya no representa una promesa futura sino un certificado de existencia y depósito de mercadería identificada. Esta transición se materializa en la blockchain mediante una transacción firmada por un oráculo humano (multi-firma 2-de-3) que publica los hashes de los certificados sanitarios (SENASAG), los análisis físico-químicos de laboratorio independiente, el acta de cosecha y el contrato con el almacén general de depósito autorizado.

**Momento 3: Redención (token = título de propiedad sobre miel exportada).** El comprador inicia la redención. La SRL Bolivia genera la Declaración Única de Exportación (DUE) ante la Aduana Nacional y coordina la logística internacional con un courier autorizado. Una vez confirmada la salida por aduana, el token se quema (burn) en la blockchain y el comprador recibe la miel físicamente acompañada de los certificados originales escaneados y el tracking del envío.

### 2.3 Beneficiarios directos e indirectos

| Actor | Beneficio |
|---|---|
| Apicultores bolivianos | Financiamiento anticipado, precio justo, acceso a mercado internacional sin intermediarios |
| Comunidades rurales productoras | Generación de ingresos sostenidos en zonas de baja densidad económica |
| Exportadores intermedios | Transparencia operativa que reduce costos de auditoría y certificación |
| Compradores europeos | Trazabilidad criptográfica, autenticidad verificable, precio competitivo |
| Estado boliviano | Recaudación tributaria por exportaciones, posicionamiento país en RWA agrícola |
| SENASAG | Demanda regulada y documentada de certificados, ingreso predecible |

---

## 3. Naturaleza jurídica del token

Esta sección es **la pieza fundamental** de toda la propuesta, porque determina qué marco regulatorio aplica y cuál no aplica.

### 3.1 Clasificación: commodity token con Forward Sale Agreement

El token emitido por la plataforma se clasifica jurídicamente como **commodity token con respaldo contractual en un Forward Sale Agreement (FSA) bilateral**.

**Definición operativa:** el token es la representación digital de un derecho contractual a recibir, en una fecha futura aproximada, una cantidad determinada y específica de un producto físico (miel monofloral de un lote identificado), tras el cumplimiento de los hitos productivos y certificatorios establecidos en el contrato forward subyacente.

### 3.2 Por qué NO es un valor mobiliario

La distinción es crítica. Un valor mobiliario, conforme a la Ley 1834 del Mercado de Valores boliviana, presenta al menos una de las siguientes características:

- Representa una fracción del capital social de una entidad (acciones)
- Representa un crédito contra el emisor con flujo de pagos calendarizado (bonos)
- Otorga derechos económicos vinculados al desempeño financiero del emisor (cuotas de fondos)
- Otorga derechos de voto sobre la administración del emisor

**Ninguna de estas características está presente en el token aquí propuesto.** El token:

- No representa capital de ninguna entidad
- No genera intereses ni rendimientos calendarizados
- No vincula su valor al desempeño financiero del emisor (su valor está vinculado a la existencia física de un kilogramo específico de miel)
- No otorga derechos políticos sobre ninguna sociedad

El token es **funcionalmente equivalente a un certificado de depósito** o a un *warrant* de entrega física, instrumentos plenamente regulados por la legislación comercial boliviana (Código de Comercio) y no por la Ley del Mercado de Valores.

### 3.3 Implicaciones de la clasificación

Esta clasificación produce consecuencias jurídicas concretas:

**No aplica:**

- Libro XIV del Reglamento Normativo del Mercado de Valores (Propuesta Cerda, mayo 2026), que regula valores mobiliarios tokenizados
- Obligación de constituirse como Operador de Plataforma de Tokenización (OPT) ante ASFI
- Capital mínimo de USD 500,000 exigido a los OPT
- Auditoría obligatoria de smart contracts por auditor acreditado ASFI
- Registro espejo en la Entidad de Depósito de Valores (EDV)

**Sí aplica:**

- D.S. 5384/2025: si la entidad que opera comercialmente la plataforma es boliviana, debe constituirse como Empresa de Tecnología Financiera (ETF). **Esta obligación se mitiga estructuralmente** mediante la operación de la plataforma desde la Wyoming LLC (ver sección 5).
- RA UIF 19/2025: cualquier entidad que custodie, transfiera o intermedie activos virtuales comercialmente es Sujeto Obligado ante UIF. La SRL Bolivia es PSAV (Proveedor de Servicios de Activos Virtuales) registrado.
- Ley 1489 (Exportaciones), reglamentos SENASAG, Ley 470 (Almacenes Generales de Depósito): aplicables al ciclo físico del producto.
- Wyoming Digital Asset Act 2019: para la LLC emisora.
- MiCA (UE) 2023/1114: probablemente NO aplica como Asset-Referenced Token (ART) ni Electronic Money Token (EMT), dado que el respaldo es un bien físico específico (no una canasta de activos ni una moneda fiduciaria). Sin embargo, la directiva europea de protección al consumidor sí aplica al B2C, incluyendo derecho de retracto de 14 días.

---

## 4. Marco legal aplicable

### 4.1 Normativa boliviana

**Resolución Directiva BCB 082/2024 (25 junio 2024)**
Levantó la prohibición absoluta de uso de activos virtuales en Bolivia. Habilita el uso de Instrumentos Electrónicos de Pago (IEP) autorizados por ASFI para comprar y vender activos virtuales. El boliviano (Bs) sigue siendo única moneda de curso legal, pero el activo virtual es legal como medio de intercambio para transacciones acotadas.

> *Implicación práctica:* La plataforma puede legalmente recibir pagos en USDC desde el exterior y convertirlos a bolivianos vía IEP autorizados cuando sea operacionalmente necesario.

**Decreto Supremo 5384 (7 mayo 2025)**
Crea el régimen de Empresas de Tecnología Financiera (ETF). Si una entidad boliviana opera comercialmente una plataforma blockchain con activos tokenizados, está obligada a constituirse como ETF. Capital mínimo y requisitos definidos por la Circular ASFI 885/2025.

> *Mitigación estructural:* Wyoming LLC opera la plataforma técnica. SRL Bolivia opera la producción y exportación física. La obligación de ETF se evita porque la entidad operadora de plataforma no es boliviana.

**Circular ASFI 885/2025 (3 julio 2025)**
Reglamento operativo de las ETF. Establece el plazo de adecuación al 31 de diciembre de 2025 (vencido). Habilita el Entorno Controlado de Pruebas (ECP) como vía simplificada para entidades nuevas. Exige certificación ISO 27001, cumplimiento de los Anexos 7 y 8 de ciberseguridad y reporte de incidentes de seguridad en un plazo máximo de 4 horas.

> *Estrategia adoptada:* en el MVP no se aplica al ECP. Se evalúa la aplicación entre los meses 6 y 12 según volumen operativo, presencia de clientes bolivianos o señales regulatorias.

**Resolución Administrativa UIF 19/2025 (16 abril 2025)**
Designa a los Proveedores de Servicios de Activos Virtuales (PSAV) como Sujetos Obligados ante la Unidad de Investigaciones Financieras. Obligaciones:

- Registro previo ante UIF
- Conocimiento del cliente (KYC) de todos los compradores
- Manual de Prevención de Lavado de Ganancias Ilícitas, Financiamiento del Terrorismo y de la Proliferación de Armas de Destrucción Masiva (LGI/FT/FPADM)
- Oficial de Cumplimiento titular y suplente designados
- Reporte mensual de operaciones en formato PSAV
- Reporte inmediato de operaciones sospechosas (ROS) sin avisar al cliente
- Reporte sistemático anual
- Conservación de registros durante diez años

> *Cumplimiento adoptado:* la SRL Bolivia se registra como PSAV ante UIF. Toda la infraestructura técnica está diseñada para producir automáticamente los reportes exigidos en el formato requerido por UIF.

**Ley 1489 (Exportaciones) y reglamentos SENASAG**
La miel exportable requiere:

- Registro SENASAG como establecimiento procesador de productos apícolas
- Certificado sanitario por cada lote exportado
- Análisis físico-químico (humedad, hidroximetilfurfural HMF, diastasa) por laboratorio acreditado
- Certificado de origen para preferencias arancelarias (Formulario A o EUR.1 para la Unión Europea)
- Declaración Única de Exportación (DUE) ante Aduana Nacional

> *Integración técnica:* todos los certificados son escaneados, hasheados mediante SHA-256 y almacenados permanentemente en Arweave. Los hashes se publican en la blockchain en el momento de la confirmación de cosecha o exportación. La cadena de custodia documental queda criptográficamente verificable de forma perpetua.

**Ley 470 (Almacenes Generales de Depósito)**
Regula los almacenes autorizados donde puede depositarse mercadería con respaldo legal ejecutable. El contrato de depósito con el almacén autorizado es uno de los hitos documentales obligatorios del ciclo productivo.

### 4.2 Normativa extranjera relevante

**Wyoming Digital Asset Act (2019)**
El estado de Wyoming reconoce los activos digitales como propiedad y permite a sus entidades (LLC, DAO LLC) emitir y custodiar activos digitales con respaldo legal claro. La Wyoming LLC emisora se acoge a este marco.

**Markets in Crypto-Assets Regulation (MiCA) — Reglamento UE 2023/1114**
Entró en vigor en enero de 2025. Los commodity tokens con respaldo en bienes físicos específicos probablemente no califican como Asset-Referenced Tokens (ART) ni Electronic Money Tokens (EMT). Para venta a consumidores europeos retail, aplica también la Directiva 2011/83/UE de derechos de los consumidores, incluyendo derecho de retracto de 14 días para compras a distancia. **Este punto requiere validación explícita con abogado europeo experto antes del lanzamiento B2C UE.**

### 4.3 Síntesis del marco normativo

| Norma | Aplicabilidad | Sujeto obligado | Tratamiento técnico |
|---|---|---|---|
| RD BCB 082/2024 | Aplica | Cualquier intermediario | Recepción legal de USDC, conversión vía IEP |
| D.S. 5384/2025 | NO aplica (mitigado por estructura) | Entidades bolivianas operadoras | Wyoming LLC opera plataforma |
| Circular ASFI 885/2025 | No aplica en MVP | ETFs | Reservado para evaluación mes 6-12 |
| RA UIF 19/2025 | Aplica plenamente | SRL Bolivia (PSAV) | KYC + reportes + Oficial Cumplimiento |
| Ley 1489 + SENASAG | Aplica plenamente | SRL Bolivia (exportadora) | Documentación + hashes on-chain |
| Ley 470 | Aplica | Almacén autorizado contratado | Hash de contrato de depósito on-chain |
| Wyoming Digital Asset Act | Aplica | Wyoming LLC | Constitución según marco Wyoming |
| MiCA | Pendiente validación | Wyoming LLC + agente UE | Diseño con retracto 14d B2C |

---

## 5. Estructura societaria propuesta

La estructura societaria es **la pieza clave** que articula el cumplimiento legal con la operación técnica.

### 5.1 Las dos entidades

**SRL Bolivia (productora-exportadora)**
- Razón social: por definir, sociedad de responsabilidad limitada constituida en Bolivia.
- Roles operativos:
  - Contratación de apicultores y gestión de relaciones con productores rurales
  - Registro vigente ante SENASAG como establecimiento procesador de productos apícolas
  - Realización física de cosechas, análisis de laboratorio, almacenamiento y exportación
  - Generación de DUE, facturas comerciales, packing list, certificados de origen
  - Cumplimiento PSAV ante UIF Bolivia: Oficial de Cumplimiento, manual LGI/FT/FPADM, reportes mensuales, ROS, reporte sistemático anual, conservación 10 años
  - Banking local para operaciones bolivianas (salarios, proveedores, apicultores)

**Wyoming LLC (emisora-operadora de plataforma)**
- Razón social: por definir, Limited Liability Company constituida en Wyoming, EE.UU.
- Roles operativos:
  - Emisión de los tokens en la blockchain
  - Custodia de USDC recibido de compradores
  - Operación técnica de la plataforma (smart contracts, frontend, backend)
  - Hosting bajo jurisdicción Wyoming/EE.UU.
  - Contratación de auditores de smart contracts
  - Banking principal en banco EE.UU. (Mercury, Relay, Bank of America Business)
  - Cumplimiento Wyoming Digital Asset Act 2019 y, si el volumen lo amerita, registro FinCEN MSB

### 5.2 El vínculo: Forward Sale Agreement back-to-back

Las dos entidades están vinculadas operativamente por un **Forward Sale Agreement (FSA) bilateral por cada lote**. Este contrato establece:

- La SRL Bolivia se compromete a entregar X kilogramos de miel de la variedad Y, del apiario Z, para una fecha aproximada T
- La Wyoming LLC paga por anticipado un porcentaje del precio total (80% a 85%), reteniendo entre 15% y 20% como reserva técnica
- La reserva técnica se libera a la SRL únicamente al producirse y certificarse la cosecha
- Si la cosecha falla (clima, enfermedad, robo), la reserva técnica se devuelve íntegramente a los tenedores de tokens, junto con el monto principal proporcional

**Cada FSA específico se firma digitalmente, se almacena permanentemente en Arweave, su hash SHA-256 se publica en la blockchain en el campo `hashFSA` del struct `LoteMiel`.** De esta forma, cualquier persona puede verificar que el contrato firmado existe y no ha sido modificado.

### 5.3 Servicios técnicos cruzados

La Wyoming LLC presta servicios técnicos a la SRL Bolivia bajo un Master Services Agreement separado, que incluye:

- Hosting de la plataforma técnica
- Procesamiento de datos personales de compradores extranjeros por cuenta de la PSAV (SRL)
- API de oráculo para confirmar hitos productivos en la blockchain
- Generación de reportes operativos exportables por la SRL hacia UIF

Esta arquitectura permite que **la SRL cumpla con sus obligaciones PSAV** disponiendo de la información necesaria (provista por la LLC bajo SLA contractual), sin asumir directamente la operación de la plataforma técnica.

---

## 6. Arquitectura técnica de alto nivel

### 6.1 Decisiones arquitectónicas clave

A continuación se sintetizan las ocho decisiones arquitectónicas que determinan toda la implementación. Cada decisión fue tomada tras evaluación de alternativas con sus respectivos trade-offs.

| # | Decisión | Resolución |
|---|---|---|
| D1 | Audiencia objetivo MVP | Híbrido B2B + B2C simultáneo desde el día 1 |
| D2 | Modelo de circulación del token | Solo primario (sin mercado secundario P2P) |
| D3 | Granularidad del token | 1 token equivale exactamente a 0.5 kg de miel |
| D4 | Estándar y arquitectura de contratos | ERC-1155 más tres contratos inmutables (sin proxy) |
| D5 | Estrategia regulatoria de arranque | Híbrido escalonado: commodity puro con compliance UIF, evaluación ECP en meses 6-12 |
| D6 | Red blockchain | Polygon PoS mainnet |
| D7 | Stack backend y diseño del oráculo | Bun + Hono + PostgreSQL + Safe multi-sig 2-de-3 |
| D8 | Estructura de repositorios | Monorepo con Turborepo y pnpm workspaces |

### 6.2 Stack tecnológico consolidado

| Capa | Tecnología | Justificación |
|---|---|---|
| Red blockchain | Polygon PoS mainnet | Precedente regional en RWA agrícola (AgroToken, Mercado Bitcoin), USDC nativo de Circle, reconocimiento institucional europeo, gas predecible |
| Lenguaje contratos | Solidity 0.8.24+ con OpenZeppelin v5 | Estándar de industria, máxima cobertura de auditoría |
| Estándar de token | ERC-1155 (multi-token semi-fungible) | Eficiencia de gas, soporte multi-lote en un solo contrato |
| Framework de tests | Foundry (Forge, Cast, Anvil) | Tests rápidos, fuzzing nativo, invariant testing |
| Frontend | Next.js 15 App Router con TypeScript | SEO, SSR, ecosistema maduro |
| Conexión wallet | RainbowKit + wagmi | UX limpia, soporta múltiples wallets |
| Backend API | Bun runtime + Hono framework | Performance, DX moderno, edge-ready |
| ORM | Drizzle | Type-safety end-to-end con TypeScript |
| Base de datos | PostgreSQL (Supabase o Neon) | ACID, indispensable para compliance UIF |
| Cache y queues | Redis (Upstash) | Jobs asíncronos, rate limiting |
| Indexer blockchain | Goldsky subgraph | Eventos on-chain accesibles vía API GraphQL |
| Oráculo | Safe multi-firma 2-de-3 (Gnosis Safe) | Decisiones humanas firmadas, simplicidad legal |
| Autenticación admin | Clerk | Auth con 2FA out-of-the-box |
| KYC | Sumsub (Individual + Business) | Cobertura LATAM + Europa, webhooks, EDD |
| Pagos B2B | Stripe + transferencia SWIFT manual | Cobertura institucional internacional |
| Pagos B2C | MoonPay + Ramp Network | SEPA + tarjeta crédito en Europa |
| Almacenamiento legal | Arweave (vía Bundlr/Irys) | Permanencia perpetua para evidencia legal |
| Almacenamiento operacional | Cloudflare R2 | Acceso rápido, costo competitivo |
| Email transaccional | Resend | DX moderno |
| Monitoring errores | Sentry | Estándar de industria |
| Monitoring uptime | Better Stack | Mejor UX que Datadog para equipo pequeño |
| Analítica | Plausible | GDPR-compliant, privacy-first |
| CI/CD | GitHub Actions | Estándar |
| Hosting frontend | Vercel | Optimizado para Next.js |
| Hosting backend | Railway o Fly.io | Edge deployment, simplicidad operativa |

### 6.3 Diagrama de capas

```
┌──────────────────────────────────────────────────────────────────┐
│  USUARIOS                                                        │
│  Comprador B2C europeo (entusiasta gourmet)                      │
│  Comprador B2B (importador boutique, hotel, chef)                │
│  Administrador interno (SRL/LLC)                                 │
│  Oficial de Cumplimiento UIF                                     │
│  Firmantes del oráculo (3 cofundadores con Ledger)               │
└──────────────────────────────────────────────────────────────────┘
                            ▲ ▼
┌──────────────────────────────────────────────────────────────────┐
│  CAPA DE PRESENTACIÓN                                            │
│  Next.js 15 + RainbowKit + wagmi + shadcn/ui                     │
│  • Catálogo público                                              │
│  • Flujo de compra B2C / B2B                                     │
│  • Dashboard de redención                                        │
│  • Panel admin (compliance + oráculo)                            │
└──────────────────────────────────────────────────────────────────┘
                            ▲ ▼
┌──────────────────────────────────────────────────────────────────┐
│  CAPA DE APLICACIÓN (BACKEND)                                    │
│  Bun + Hono + TypeScript + Drizzle                               │
│  Módulos:                                                        │
│  • compliance/kyc-sync                                           │
│  • compliance/screening (OFAC, ONU, UE, UIF Bolivia)             │
│  • compliance/uif-reports                                        │
│  • compliance/ros-monitor                                        │
│  • compliance/document-vault (Arweave)                           │
│  • compliance/audit-log                                          │
│  • compliance/oracle-dashboard                                   │
│  • payments (Stripe + SWIFT + MoonPay + Ramp)                    │
│  • lots/reserve-technical                                        │
└──────────────────────────────────────────────────────────────────┘
                            ▲ ▼
┌─────────────────────┐    ┌─────────────────────────────────────┐
│ CAPA DE DATOS       │    │  CAPA BLOCKCHAIN                    │
│ PostgreSQL          │    │  Polygon PoS                        │
│ Redis               │    │  • MielVault.sol (ERC-1155)         │
│ Cloudflare R2       │    │  • KYCRegistry.sol                  │
│ Arweave             │    │  • RedemptionManager.sol            │
│ (10 años conserv.)  │    │  Indexer: Goldsky                   │
└─────────────────────┘    │  Oracle: Safe 2-de-3                │
                           └─────────────────────────────────────┘
                                          ▲ ▼
                           ┌─────────────────────────────────────┐
                           │  INTEGRACIONES EXTERNAS             │
                           │  Sumsub (KYC)                       │
                           │  Stripe, MoonPay, Ramp (pagos)      │
                           │  OFAC, ONU, UE, UIF Bolivia (listas)│
                           │  Chainalysis (screening blockchain) │
                           │  Aduana Nacional (DUE)              │
                           │  Couriers (DHL, FedEx) (BL/AWB)     │
                           │  SENASAG (certificados sanitarios)  │
                           └─────────────────────────────────────┘
```

---

## 7. Bridge legal-código: tabla maestra

Esta es la sección **central** del documento. Aquí se muestra cómo cada requisito legal específico se materializa en una función concreta del código.

| Norma boliviana | Requisito legal | Implementación técnica | Ubicación (path) | Evidencia auditable |
|---|---|---|---|---|
| RD BCB 082/2024 | Activos virtuales como medio de pago legal | Recepción de USDC y conversión vía IEP autorizado | `apps/api/src/modules/payments/` | Tabla `payments` + evento `LoteComprado` |
| D.S. 5384/2025 | ETF si la SRL opera plataforma | Wyoming LLC es `owner()` de los contratos; SRL no opera plataforma | `MielVault.sol` (AccessControl) | Eventos `RoleGranted` on-chain |
| Circular ASFI 885/2025 | ECP como vía simplificada | No aplicada en MVP; flag `ASFI_ECP_ENABLED=false` reservado | `libraries/ComplianceConstants.sol` | Tabla `compliance_decisions` con minutas |
| RA UIF 19/2025 — KYC tiered | Conocimiento del cliente en tres niveles | `KYCRegistry.setKYC()` sincronizado desde Sumsub vía webhook | `KYCRegistry.sol` + `compliance/kyc-sync/` | Evento `KYCUpdated` + tabla `audit_log_kyc` |
| RA UIF — Oficial Cumplimiento | Designación titular y suplente ante UIF | Rol `COMPLIANCE_OFFICER_ROLE` con dos direcciones autorizadas | `KYCRegistry.sol`, `MielVault.sol` | Eventos `RoleGranted/RoleRevoked` |
| RA UIF — Manual LGI/FT/FPADM | Manual aprobado de prevención | Hash SHA-256 del PDF en constante `COMPLIANCE_MANUAL_HASH` | `ComplianceConstants.sol` | PDF en Arweave + tabla `legal_documents` |
| RA UIF — Reportes mensuales PSAV | Formato PSAV mensual a UIF | Generador automático XML + PDF, cron día 5 mes siguiente | `compliance/uif-reports/` | Tabla `uif_monthly_reports` + Arweave snapshot |
| RA UIF — ROS sin avisar cliente | Reporte operaciones sospechosas sin notificar | `ros-monitor/` con `ros-isolation.guard.ts` que garantiza no-notify | `compliance/ros-monitor/` | Tabla `ros_queue` (acceso restringido por RBAC) |
| RA UIF — Conservación 10 años | Retención de registros una década | Triple almacenamiento: PostgreSQL + Cloudflare R2 + snapshots Arweave firmados mensualmente | `compliance/audit-log/monthly-snapshot.scheduler.ts` | Hash mensual en blockchain |
| Ley 1489 + SENASAG | Certificado sanitario y análisis físico-químico por lote | Campos `hashSenasag`, `hashAnalisisLab` en struct `LoteMiel` | `MielVault.sol` | Evento `CosechaConfirmada` + PDFs en Arweave |
| Ley 1489 — Certificado de origen UE | Formulario A o EUR.1 por lote exportado | Campo `hashCertificadoOrigen` y `tipoCertificadoOrigen` | `MielVault.sol` | Evento + URI Arweave |
| Ley 470 — Almacenes de Depósito | Contrato con almacén autorizado | Campo `hashContratoDeposito` y transición de estado a `ALMACENADO` | `MielVault.confirmarAlmacenamiento()` | Evento `AlmacenamientoConfirmado` |
| Wyoming Digital Asset Act 2019 | Reconocimiento de activos digitales como propiedad | Owner del contrato = Safe Wyoming; disclosure en Términos y Condiciones | Off-chain (TyC) + on-chain owner | Hash de TyC en tabla `legal_documents` |
| FSA — Reserva técnica 15-20% | Retención de fondos hasta confirmación de cosecha | Constante `RESERVA_TECNICA_BPS` (1500-2000) + función `liberarReservaTecnica()` | `MielVault.sol` | Evento `ReservaTecnicaLiberada` |
| FSA — Reembolso pro-rata si lote falla | Devolución íntegra a compradores | Función `reembolsarLoteFallido(loteId, address[])` con transfer USDC batch | `MielVault.sol` | Evento `ReembolsoEjecutado` |
| MiCA — Derecho retracto 14 días B2C | Posibilidad de cancelar compra dentro de 14 días | Módulo `refunds/withdrawal-right.ts` con delay del mint on-chain para B2C UE | `apps/api/src/modules/refunds/` | Tabla `withdrawal_holds` |
| Restricción solo primario (no P2P) | El token no se puede transferir entre tenedores | Override de `_update()` en `MielVault` permite solo mint y burn | `MielVault.sol` | Revert `TransferP2PNoPermitido` |

**Cómo leer esta tabla:** cada fila identifica una obligación legal específica, una función técnica concreta que la implementa, el archivo donde vive el código y la evidencia auditable que produce. Un auditor de UIF, ASFI, SENASAG o cualquier inspector puede recorrer esta tabla y verificar que cada obligación tiene su contraparte técnica.

---

## 8. Smart contracts: descripción funcional

Esta sección describe los tres contratos inteligentes que residen en la blockchain. No reproduce el código fuente; describe **qué hace cada contrato y por qué**.

### 8.1 `MielVault.sol`

**Propósito:** contrato principal del sistema. Almacena los lotes de miel, gestiona la pre-venta, retiene la reserva técnica y orquesta las transiciones de estado del ciclo productivo.

**Cumple el estándar:** ERC-1155 (token multi-fungible). Cada lote es un *token ID* distinto. La cantidad de tokens de un lote es el doble del peso esperado en kilogramos (porque 1 token = 0.5 kg).

**Estructura de datos de un lote (struct `LoteMiel`):**

- `kgEsperados`: capacidad estimada del apiario
- `kgCosechadosReal`: cantidad efectivamente producida
- `kgRedimidos`: acumulado entregado físicamente
- `precioPorTokenUSDC`: precio unitario al momento de la compra
- `reservaTecnicaUSDC`: monto retenido vivo en el contrato
- `reservaTecnicaLiberada`: tracking de liberación a la SRL
- `fechaCosechaEstimada`
- `estado` (enumeración): PREVENTA, COSECHADO, ALMACENADO, REDENCION_PARCIAL, AGOTADO, FALLIDO
- `origenGeografico`: código ISO con identificación del departamento boliviano
- `reservaBps`: porcentaje de reserva configurado (1500 a 2000 basis points)
- `productorSRL`: wallet de la SRL Bolivia destinataria de fondos
- `variedadMonofloral`: enum off-chain (romero, banda, eucalipto, otras)
- `tipoCertificadoOrigen`: Form A o EUR.1
- `motivoFallo`: descripción si el lote es marcado como FALLIDO
- **Siete hashes legales (cada uno SHA-256 de 32 bytes):**
  - `hashFSA`: Forward Sale Agreement firmado
  - `hashSenasag`: certificado sanitario SENASAG
  - `hashAnalisisLab`: análisis físico-químico de laboratorio
  - `hashContratoDeposito`: contrato con almacén general de depósito
  - `hashCertificadoOrigen`: Formulario A o EUR.1
  - `hashActaCosecha`: acta firmada de cosecha
  - `hashFotosApiario`: fotografías georeferenciadas del apiario

**Roles definidos (OpenZeppelin AccessControl):**

| Rol | Asignado a | Función |
|---|---|---|
| `DEFAULT_ADMIN_ROLE` | Safe Wyoming 2-de-3 | Administración general |
| `ADMIN_ROLE` | Safe Wyoming 2-de-3 | Creación de lotes |
| `BACKEND_SIGNER_ROLE` | Wallet del backend (HSM AWS/GCP KMS) | Mint post-confirmación de pago |
| `COMPLIANCE_OFFICER_ROLE` | Titular + suplente UIF | Pause de emergencia + freeze de direcciones |
| `ORACLE_ROLE` | Safe 2-de-3 (3 cofundadores con Ledger) | Confirmar cosecha, almacenamiento, exportación y fallo |
| `TREASURY_SRL_ROLE` | Wallet SRL Bolivia | Solicitar liberación de reserva técnica |

**Funciones principales (descripción funcional):**

- `crearLote(...)`: el administrador define un nuevo lote en estado PREVENTA. Especifica capacidad estimada, precio, fecha esperada de cosecha, productor SRL destinatario y porcentaje de reserva técnica.
- `comprar(...)`: el backend, tras confirmar el pago en fiat o cripto, mintea tokens al comprador. La función valida que el comprador tenga KYC vigente (tier 1 o superior), no esté sancionado, no esté congelado por orden regulatoria y que el lote tenga capacidad disponible. Retiene automáticamente el porcentaje de reserva técnica.
- `confirmarCosecha(...)`: el oráculo (Safe 2-de-3) firma una transacción que registra la cantidad real cosechada y los hashes de los certificados sanitarios, análisis de laboratorio, acta de cosecha y certificado de origen. El estado transiciona de PREVENTA a COSECHADO.
- `confirmarAlmacenamiento(...)`: el oráculo registra el hash del contrato con el almacén general autorizado y la dirección del almacén. Estado transiciona a ALMACENADO.
- `marcarFallido(...)`: el oráculo registra que el lote no podrá cumplirse (clima, enfermedad, robo). Habilita el reembolso pro-rata.
- `liberarReservaTecnica(...)`: una vez confirmada la cosecha, la SRL puede solicitar la liberación del porcentaje retenido. Transfiere USDC al wallet de la SRL.
- `reembolsarLoteFallido(...)`: el oráculo ejecuta un reembolso por lotes (batch transfer) a todos los compradores del lote. Quema los tokens correspondientes.
- `pause()` / `unpause()`: el Oficial de Cumplimiento puede pausar el contrato en emergencia regulatoria (orden de UIF, ASFI, etc.).

**Control crítico: bloqueo del mercado secundario.** El contrato sobrescribe la función interna `_update()` de ERC-1155 para revertir cualquier transferencia que no sea mint (creación) o burn (destrucción). Esto significa que un comprador A no puede transferir el token a un comprador B aunque ambos estén verificados. El token solo puede crearse (al comprar) o destruirse (al redimir). **Esta restricción es la que garantiza que el token no se recategorice legalmente como instrumento financiero.**

**Eventos para audit trail UIF:**

`LoteCreado`, `LoteComprado`, `CosechaConfirmada`, `AlmacenamientoConfirmado`, `LoteFallido`, `ReservaTecnicaLiberada`, `ReembolsoEjecutado`, `EmergencyPaused`, `EmergencyUnpaused`.

Cada uno de estos eventos es inmutable en la blockchain y constituye prueba criptográfica de la acción ejecutada. Los reportes UIF mensuales se generan parcialmente a partir de estos eventos.

### 8.2 `KYCRegistry.sol`

**Propósito:** mantiene la lista blanca on-chain de direcciones verificadas para operar con el sistema. Es consultado por `MielVault` en cada compra y por `RedemptionManager` en cada redención.

**Estructura de datos por dirección (struct `KYCData`):**

- `tier`: 0 (sin verificación), 1 (básico), 2 (estándar), 3 (reforzado)
- `sanctioned`: marcador de inclusión en listas de sanciones
- `frozen`: marcador de congelamiento por orden regulatoria
- `jurisdiction`: código ISO 3166-1 alpha-2 del país de residencia declarado
- `expiresAt`: fecha de vencimiento de la verificación (renovación anual)
- `updatedAt`: timestamp de última actualización
- `sumsubApplicantHash`: hash del applicant ID en Sumsub para vinculación off-chain

**Roles:**

- `BACKEND_SIGNER_ROLE`: sincroniza los cambios provenientes de Sumsub vía webhook
- `COMPLIANCE_OFFICER_ROLE`: ejecuta marcas de sanción y congelamiento manuales

**Funciones principales:**

- `setKYC(...)`: actualiza el registro de una dirección tras verificación Sumsub
- `markSanctioned(...)` / `unmarkSanctioned(...)`: marca o desmarca por hit en lista de sanciones
- `freezeAddress(...)` / `unfreezeAddress(...)`: congelamiento por orden regulatoria explícita
- `revokeKYC(...)`: revoca verificación expirada o inválida
- `canMint(addr)`: función de lectura que combina todas las validaciones para autorizar mint
- `canRedeem(addr)`: análoga, requiere tier 2 o superior

**Lógica de autorización de mint:**

Un usuario puede comprar tokens si y solo si: tiene tier 1 o superior, no está sancionado, no está congelado y su verificación KYC no ha expirado.

**Lógica de autorización de redención:**

Un usuario puede iniciar una redención física si y solo si: tiene tier 2 o superior (mayor exigencia de identificación para retiro físico internacional), no está sancionado, no está congelado y su verificación KYC no ha expirado.

### 8.3 `RedemptionManager.sol`

**Propósito:** gestiona el proceso de redención física desde que el comprador la inicia hasta que la exportación es confirmada por la aduana.

**Estructura de datos por redención (struct `Redencion`):**

- `comprador`: dirección del comprador
- `loteId`: lote del que se redime
- `cantidadTokens`: cuántos medios-kilos
- `datosEnvioHash`: hash del bloque de datos de envío (dirección, courier preferido, instrucciones)
- `estado`: INICIADA, EN_EXPORTACION, COMPLETADA, CANCELADA
- `dueNumero`: número de Declaración Única de Exportación emitida
- `hashBLAWB`: hash del Bill of Lading o Air Waybill del courier
- `createdAt`, `completedAt`, `cancelReason`

**Funciones principales:**

- `iniciarRedencion(...)`: el comprador, con tier 2 o superior, bloquea sus tokens en escrow del contrato. Los tokens no se queman aún; quedan congelados.
- `confirmarExportacion(...)`: el oráculo, tras verificar la emisión real de la DUE y del BL/AWB, ejecuta el burn definitivo de los tokens.
- `cancelarRedencion(...)`: si la aduana rechaza la exportación o el comprador desiste antes de la confirmación, el oráculo libera los tokens al comprador.

---

## 9. Backend de cumplimiento (compliance)

El backend organiza la lógica de cumplimiento en módulos especializados. Cada módulo tiene un propósito legal específico.

### 9.1 Módulo `kyc-sync` (sincronización KYC)

**Responsabilidades:**

- Recibir webhooks de Sumsub al completarse la verificación de un usuario (Individual o Business)
- Validar la firma criptográfica del webhook (HMAC SHA-256)
- Mapear el resultado de Sumsub (GREEN/YELLOW/RED) al tier correspondiente (1, 2 o 3)
- Llamar a `KYCRegistry.setKYC()` con la wallet del backend para sincronizar on-chain
- Mantener cola de revisión manual para casos ambiguos (review queue)
- Logging append-only en tabla `audit_log_kyc`

**Política de tiers:**

- **Tier 1 (compras hasta USD 1,000/mes):** verificación documental simple (documento de identidad + selfie con detección de vida)
- **Tier 2 (USD 1,000 a USD 15,000/mes):** Tier 1 + comprobante de domicilio reciente + screening enhanced
- **Tier 3 (más de USD 15,000/mes o empresa):** Tier 2 + Enhanced Due Diligence (entrevista + declaración de fuente de fondos) + screening reforzado contra todas las listas

### 9.2 Módulo `screening` (cribado de sancionados)

**Responsabilidades:**

- Ejecutar cribado nocturno contra cinco listas oficiales:
  - OFAC SDN List (Departamento del Tesoro de EE.UU.)
  - ONU Consolidated List
  - EU Consolidated List
  - Lista UIF Bolivia (PEPs nacionales y reportados)
  - Chainalysis API (screening blockchain, opcional)
- En caso de hit, ejecutar `KYCRegistry.markSanctioned()` automáticamente
- Notificar al Oficial de Cumplimiento por Slack, email y PagerDuty (alta severidad)
- Registrar cada match en `audit_log_screening`

### 9.3 Módulo `uif-reports` (reportes UIF)

**Responsabilidades:**

- Generar el reporte mensual de operaciones en formato PSAV (XML + PDF) según especificación UIF Bolivia
- Programar la generación automática para el día 5 del mes siguiente a las 06:00 hora boliviana
- Segregar las operaciones por tier (1, 2, 3)
- Generar el reporte sistemático anual el 15 de enero de cada año
- Almacenar copias en Cloudflare R2 (acceso operativo) y snapshot firmado en Arweave (permanencia legal)
- Notificar al Oficial de Cumplimiento titular vía email para revisión y envío manual a UIF
- Conservar el reporte y todos sus datos fuente durante 10 años

### 9.4 Módulo `ros-monitor` (operaciones sospechosas)

**Responsabilidades:**

- Monitorear continuamente las operaciones aplicando reglas declarativas:
  - Operaciones que exceden el tope del tier sin solicitud de upgrade
  - Patrones de fraccionamiento (múltiples compras pequeñas para evadir thresholds)
  - Compras desde IPs de jurisdicciones sancionadas
  - Compras desde direcciones blockchain con historial de mixing o darknet
  - Velocidad anormal de progresión (de 0 a USD 50,000 en 7 días)
- Encolar los matches en `ros_queue` para revisión humana
- **Garantía crítica del módulo:** `ros-isolation.guard.ts` asegura que ningún canal de notificación (email, push, in-app) llegue al usuario afectado. Esta es una obligación expresa de RA UIF 19/2025.
- Workflow de revisión: archivar / reportar a UIF / bloquear dirección

### 9.5 Módulo `document-vault` (bóveda documental)

**Responsabilidades:**

- Recibir uploads de documentos legales (FSA, certificados SENASAG, análisis de laboratorio, contratos de depósito, certificados de origen, actas de cosecha, fotos del apiario, BL/AWB)
- Calcular hash SHA-256 del documento antes del upload
- Subir el documento a Arweave a través de Bundlr/Irys (permanencia perpetua)
- Realizar backup paralelo en Cloudflare R2 (acceso rápido sin pasar por gateway Arweave)
- Verificar la integridad mediante readback post-upload (descargar de Arweave, re-hashear, comparar)
- Mantener catálogo en tabla `legal_documents` con URI Arweave, key R2, hash SHA-256, tipo de documento, lote asociado, firmantes y timestamp

### 9.6 Módulo `audit-log` (registro de auditoría)

**Responsabilidades:**

- Mantener tabla append-only `audit_log` que registra toda acción ejecutada en el sistema
- Aplicar política PostgreSQL que revoca permisos de UPDATE y DELETE a todos los roles excepto un rol de administrador de backups específico
- Implementar hash chain: cada nueva fila contiene el hash de la fila anterior, formando una cadena criptográfica que detecta cualquier intento de manipulación retroactiva
- Programar snapshot mensual del audit_log completo a Arweave, con publicación del hash root en la blockchain (timestamping inmutable)

### 9.7 Módulo `oracle-dashboard` (panel del oráculo)

**Responsabilidades:**

- Proveer interfaz para los firmantes del Safe multi-firma cuando deben confirmar cosecha, almacenamiento, exportación o fallo
- Recibir documentos del operador SRL, calcular hashes y preparar la transacción Safe pre-firmada
- Notificar a los tres firmantes vía Slack DM, email y PagerDuty
- Mantener tracking del estado de cada transacción (pendiente, firmas N de 2, ejecutada, fallida)
- Recibir webhooks del Safe Transaction Service para actualización automática del estado

### 9.8 Módulo `refunds/withdrawal-right` (retracto MiCA 14 días)

**Responsabilidades:**

- Para compradores B2C residentes en la Unión Europea, mantener el "token" como crédito off-chain durante los primeros 14 días desde la compra
- En la `pending_withdrawal_holds` table mantener el monto pagado y la fecha de expiración del derecho de retracto
- Permitir al comprador cancelar la compra y recibir reembolso íntegro en cualquier momento dentro de la ventana de 14 días
- Si el comprador renuncia expresamente al derecho con firma electrónica, ejecutar mint on-chain inmediato
- Al día 15, ejecutar mint on-chain automáticamente si no hubo cancelación

### 9.9 Módulo `lots/reserve-technical` (reserva técnica)

**Responsabilidades:**

- Calcular el monto exacto de reserva técnica por compra (entre 15% y 20% del precio total)
- Trackear en `lot_reserve_tracking` el monto retenido y liberado por lote
- Escuchar el evento on-chain `CosechaConfirmada` y, automáticamente, preparar la transacción `liberarReservaTecnica()` desde la wallet con rol TREASURY_SRL_ROLE
- En caso de fallo del lote, coordinar la transacción de reembolso pro-rata

---

## 10. Flujos operativos end-to-end

### 10.1 Flujo de compra B2C (consumidor europeo)

1. El comprador navega al catálogo público y selecciona un lote disponible.
2. Crea cuenta con email y completa el flujo KYC tier 1 en Sumsub (documento de identidad, selfie con detección de vida).
3. Sumsub completa la verificación. Webhook al backend. `KYCRegistry.setKYC` se ejecuta on-chain.
4. El comprador elige cantidad de tokens y método de pago. Para B2C europeo, MoonPay o Ramp Network procesan el pago con tarjeta o transferencia SEPA, convirtiendo a USDC en Polygon.
5. El backend confirma la recepción del USDC en la wallet operativa.
6. **Si el comprador es residente UE:** se crea un `withdrawal_hold` por 14 días. El comprador ve en su panel el estado "Período de retracto activo hasta el [fecha]".
7. **Al expirar el plazo o tras renuncia expresa:** el backend ejecuta `MielVault.comprar()`. El comprador recibe los tokens en su wallet.
8. El comprador ve en su panel "Mis lotes" la cantidad de medios-kilos poseídos por lote y el estado de cada lote.

### 10.2 Flujo de compra B2B (importador profesional)

1. El comprador empresarial inicia onboarding empresarial en el sitio.
2. Completa KYC Sumsub Business: certificado de constitución, beneficiarios finales, screening reforzado contra listas, declaración de fuente de fondos.
3. El Oficial de Cumplimiento revisa el caso manualmente y autoriza tier 3.
4. El comprador acuerda términos con el equipo comercial: cantidad de tokens, precio, plazo de pago.
5. La SRL Bolivia emite factura de exportación a la entidad del comprador.
6. El comprador realiza transferencia SWIFT a la cuenta de Wyoming LLC.
7. Confirmada la recepción del wire, el backend ejecuta `MielVault.comprar()` con el monto correspondiente.
8. El comprador recibe los tokens en su wallet (configurada típicamente como Safe multi-firma del importador).
9. El comprador puede agregar la operación a su contabilidad como inventario en tránsito.

### 10.3 Flujo de confirmación de cosecha

1. El apicultor reporta cosecha completada a la SRL Bolivia.
2. SENASAG inspecciona y emite certificado sanitario del lote.
3. Laboratorio acreditado realiza análisis físico-químico (humedad, HMF, diastasa) y emite informe.
4. El operador de la SRL sube los siguientes documentos al panel admin:
   - Certificado SENASAG (PDF)
   - Análisis físico-químico (PDF)
   - Acta de cosecha firmada (PDF)
   - Fotografías georeferenciadas del apiario
   - Certificado de origen (Formulario A o EUR.1)
5. El módulo `document-vault` calcula los hashes SHA-256 y sube los archivos a Arweave.
6. El módulo `oracle-dashboard` prepara una transacción `confirmarCosecha(loteId, kgReal, hashSenasag, hashAnalisisLab, hashActaCosecha, hashFotos, hashCertOrigen, tipoCertOrigen)` y la envía al Safe multi-firma.
7. Los tres firmantes reciben notificación. Dos de ellos revisan los documentos en la interfaz del Safe y firman con su Ledger.
8. Al alcanzar dos firmas, la transacción se ejecuta on-chain.
9. El lote transiciona a estado COSECHADO. Se emite evento `CosechaConfirmada` con todos los hashes.
10. El módulo `reserve-technical` detecta el evento y prepara automáticamente la liberación de la reserva técnica al wallet de la SRL.

### 10.4 Flujo de redención y exportación

1. El comprador, desde su panel, selecciona "Redimir" e indica cantidad de medios-kilos.
2. Completa formulario con datos de envío (dirección de entrega, courier preferido, instrucciones especiales).
3. Si su KYC es tier 2 o superior y el lote está en estado ALMACENADO, se ejecuta `RedemptionManager.iniciarRedencion()`. Los tokens del comprador quedan bloqueados (escrow) sin quemarse aún.
4. La SRL Bolivia recibe la orden de exportación. Coordina con el almacén el retiro de los frascos correspondientes.
5. La SRL prepara la documentación: factura comercial, packing list, certificado de origen, copias del certificado SENASAG.
6. La SRL genera la DUE ante la Aduana Nacional.
7. La SRL contrata al courier (DHL, FedEx u otro). El courier emite el Bill of Lading (BL) o Air Waybill (AWB).
8. Una vez confirmada la salida por aduana, el operador SRL sube el BL/AWB al sistema.
9. El módulo `oracle-dashboard` prepara `confirmarExportacion(redencionId, dueNumero, hashBLAWB)`. El Safe firma.
10. La transacción se ejecuta: los tokens del comprador se queman definitivamente. Se emite evento `RedencionCompletada`.
11. El comprador recibe email con tracking del envío y todos los certificados originales escaneados.

### 10.5 Flujo de reporte UIF mensual

1. El día 5 del mes siguiente a las 06:00 hora boliviana, el cron `monthly-report.scheduler` se dispara.
2. Se ejecutan queries SQL sobre las tablas `payments`, `mints`, `redemptions`, `kyc_users` para extraer todas las operaciones del mes.
3. Las operaciones se segregan por tier (1, 2, 3) y se calculan totales.
4. El `psav-generator` produce el reporte en formato XML y PDF según la especificación UIF Bolivia.
5. Se realiza upload a Cloudflare R2 (acceso operacional).
6. Se realiza upload paralelo a Arweave (snapshot permanente firmado por la wallet del backend).
7. Se crea fila en `uif_monthly_reports` con todos los metadatos.
8. Se envía notificación al Oficial de Cumplimiento con link a la interfaz de revisión.
9. El Oficial de Cumplimiento revisa el reporte, lo descarga en formato firmable y lo envía manualmente a UIF a través de los canales oficiales.
10. Al recibir acuse de UIF, el Oficial marca el reporte como `sent_to_uif` y carga el número de acuse.

---

## 11. Plan de implementación

### 11.1 Fases del proyecto

**Fase 0 — Pre-código (semanas 1 a 4)**
- Constitución de SRL Bolivia
- Constitución de Wyoming LLC
- Apertura de cuentas bancarias (Wyoming + Bolivia)
- Identificación y contratación de 1 a 2 apicultores con miel monofloral validada
- Inicio del registro SENASAG
- Redacción del template del Forward Sale Agreement con abogado comercial
- Identificación del almacén general de depósito candidato
- Decisión y contratación del proveedor KYC (Sumsub recomendado)
- **Resolución de los tres conflictos legales identificados en sección 13** con abogados especializados
- Validación con tres a cinco compradores potenciales europeos mediante entrevistas

**Fase 1 — MVP smart contracts (semanas 5 a 7)**
- Setup del monorepo (Turborepo + pnpm workspaces)
- Implementación de `ComplianceConstants.sol`
- Implementación de `KYCRegistry.sol` con tests Foundry al 100% de cobertura
- Implementación de `MielVault.sol` con tests unit, fuzz e invariant
- Implementación de `RedemptionManager.sol` con tests
- Deploy en testnet Polygon Amoy
- Ejecución de los siete escenarios E2E de verificación

**Fase 2 — Backend de compliance (semanas 8 a 10)**
- Setup Bun + Hono + PostgreSQL + Drizzle
- Módulo `kyc-sync` con webhook Sumsub
- Módulo `screening` con job nightly OFAC/ONU/UE
- Módulo `document-vault` con integración Arweave
- Módulo `audit-log` append-only con hash chain
- Módulo `oracle-dashboard` con integración Safe

**Fase 3 — Backend operativo (semanas 11 a 13)**
- Módulo `payments` (Stripe + SWIFT + MoonPay + Ramp)
- Módulo `lots/reserve-technical`
- Módulo `refunds/withdrawal-right` (MiCA 14 días)
- Módulo `uif-reports` con generador PSAV
- Módulo `ros-monitor` con reglas declarativas

**Fase 4 — Frontend (semanas 14 a 16)**
- Setup Next.js 15 con RainbowKit y wagmi
- Catálogo público de lotes
- Flujo de compra B2C y B2B
- Panel del comprador
- Panel admin con dashboard del oráculo

**Fase 5 — Auditoría y mainnet (semanas 17 a 19)**
- Auditoría externa (Trail of Bits, Sherlock contest o Quantstamp): USD 4,000 a USD 15,000
- Resolución de findings
- Deploy en Polygon mainnet
- Configuración de wallets operativas Safe

**Fase 6 — Lanzamiento controlado (semanas 20 a 23)**
- Onboarding del primer lote piloto (50 a 100 kg, una variedad)
- Soft launch con 5 a 10 compradores beta invitados
- Primera redención real end-to-end (cosecha → exportación → entrega física al comprador europeo)
- Iteración basada en feedback
- Lanzamiento abierto

### 11.2 Cronograma resumido

| Fase | Duración | Hito principal |
|---|---|---|
| 0. Pre-código | 4 semanas | Estructura legal + apicultores firmados |
| 1. Smart contracts | 3 semanas | Tests al 100%, deploy Amoy |
| 2. Backend compliance | 3 semanas | KYC sync + screening + audit operativos |
| 3. Backend operativo | 3 semanas | Pagos + reportes UIF funcionando |
| 4. Frontend | 3 semanas | Flujos B2C y B2B navegables |
| 5. Auditoría y mainnet | 3 semanas | Contratos auditados y deployados en Polygon |
| 6. Lanzamiento | 4 semanas | Primera redención física exitosa |

**Total: 23 semanas (aproximadamente 6 meses) hasta primer comprador real. Lanzamiento amplio en el mes 7.**


---

## 12. Riesgos y mitigaciones

A continuación se identifican los doce riesgos técnicos y operativos más relevantes del bridge legal-código, con sus mitigaciones.

| Riesgo | Descripción | Mitigación |
|---|---|---|
| R1 | Desincronización entre Sumsub off-chain y `KYCRegistry` on-chain (usuario verificado en Sumsub pero el webhook no llegó) | Webhooks con retry exponencial + idempotencia + reconciliación nocturna + endpoint `/admin/kyc/desync-report` para monitoreo |
| R2 | Race condition en compra simultánea de los últimos tokens de un lote (dos compradores pagan por la misma cantidad disponible) | Reserva lógica pre-pago en backend (lock de 15 minutos) + reembolso USDC automático si el mint final falla |
| R3 | Pérdida del URI Arweave antes de publicar el hash on-chain (crash entre upload y `confirmarCosecha`) | Persistir URI + hash en `legal_documents` ANTES de iniciar la preparación de la tx + backup R2 paralelo + verificación readback |
| R4 | Pérdida del hardware wallet de un firmante Safe (uno de los tres cofundadores extravía su Ledger) | Procedimiento `swapOwner` documentado + escrow notarial de las seed phrases en Bolivia y Wyoming + simulacro trimestral |
| R5 | Cambio retroactivo en interpretación regulatoria UIF/ASFI (la autoridad reinterpreta thresholds o exige nuevo formato) | Audit log append-only + Arweave snapshots permiten regenerar reportes en cualquier formato futuro. Constantes upgradeables vía governance Safe |
| R6 | `BACKEND_SIGNER_ROLE` wallet comprometida (key del backend robada por atacante) | HSM gestionado (AWS KMS o GCP KMS) — la clave nunca sale del HSM + rate limit on-chain + el Oficial de Cumplimiento puede ejecutar `pause()` inmediatamente |
| R7 | Sumsub fuera de servicio durante ventana crítica de KYC (caída del proveedor durante horas) | Cola de re-intentos + KYC manual fallback procesado por el Oficial de Cumplimiento (procedimiento documentado) |
| R8 | Discrepancia entre `kgEsperados` y `kgRealCosechado` (la cosecha real es menor a la vendida) | **Decisión pendiente:** shortfall menor al 10% → reducción pro-rata con consentimiento expreso; shortfall mayor o igual al 10% → marcar lote como FALLIDO y reembolso total. Ver conflicto C3 |
| R9 | Override `_update()` rompe integración con marketplaces estándar ERC-1155 | Documentación explícita en TyC: el token no es transferible. `setApprovalForAll` también revierte. `supportsInterface` retorna false para extensiones no soportadas |
| R10 | MiCA retracto 14 días vs entrega inmediata del token | Para B2C UE: token vive off-chain durante 14 días como `pending_withdrawal_hold`. Mint on-chain ejecutado al día 15 o tras renuncia firmada. Ver conflicto C1 |
| R11 | Pérdida de signing key del backend (HSM falla o se pierde acceso) | HSM con backup multi-región + rotación documentada vía Safe + simulacro semestral |
| R12 | Manipulación del gateway Arweave (gateway sirve archivo alterado, hash off-chain coincide pero el documento original era distinto) | Hash calculado localmente PRE-upload + verificación readback post-upload + uso de múltiples gateways (arweave.net + ar.io + gateway propio) |

---

## 13. Conflictos legales pendientes de validación

Existen tres puntos del diseño que requieren validación explícita con asesores legales especializados ANTES de iniciar la implementación de los flujos afectados.

### C1 — MiCA derecho de retracto 14 días vs entrega inmediata del token

**Tensión:** la regulación europea MiCA (en conjunto con la Directiva 2011/83/UE de derechos del consumidor) exige a los vendedores B2C otorgar al consumidor europeo el derecho de cancelar la compra sin justificación dentro de 14 días. Si el token se entrega inmediatamente al pago, podría argumentarse que el bien ya fue entregado y el derecho de retracto pierde efectividad.

**Solución propuesta:** durante los 14 días posteriores a la compra B2C UE, el "token" existe como crédito off-chain (registro en base de datos `pending_withdrawal_period`). El comprador ve en la plataforma "Tu compra está en período de retracto hasta el [fecha]". El mint en blockchain ocurre al día 15, o antes si el comprador firma electrónicamente la renuncia expresa al derecho de retracto. Para B2B UE, se incluye cláusula contractual de renuncia explícita en el contrato comercial.

**Acción requerida:** validación con **abogado europeo experto en MiCA y protección al consumidor digital** antes de implementar el flujo B2C UE. Posible coordinación con un agente legal en Frankfurt o Ámsterdam.

### C2 — Obligaciones PSAV (SRL Bolivia) vs operación de plataforma técnica (Wyoming LLC)

**Tensión:** la SRL Bolivia es la PSAV registrada ante UIF Bolivia. Como tal, es responsable de reportar mensualmente todas las operaciones de activos virtuales que custodia, intermedia o procesa. Sin embargo, la plataforma técnica corre desde Wyoming LLC, que es la entidad que técnicamente procesa los datos y custodia los USDC. Existe un riesgo de que UIF interprete que la PSAV (SRL) no está cumpliendo su rol porque "no procesa" las operaciones técnicamente.

**Solución propuesta:** la Wyoming LLC firma un Master Services Agreement con la SRL Bolivia donde se establece formalmente que la LLC procesa datos de operaciones de activos virtuales **por cuenta de la PSAV (rol de Data Processor)**. La SRL retiene el rol de Data Controller y de Sujeto Obligado ante UIF. La LLC provee a la SRL, bajo SLA contractual, toda la información necesaria para emitir los reportes mensuales y atender cualquier requerimiento de UIF. Los reportes mensuales son emitidos formalmente por la SRL (firma del Oficial de Cumplimiento boliviano).

**Acción requerida:** validación con **abogado boliviano regulatorio especializado en ASFI y UIF**. Posible consulta vinculante previa a UIF Bolivia para confirmar la estructura propuesta antes del lanzamiento.

### C3 — Política de shortfall en cosecha (`kgRealCosechado < kgVendidos`)

**Tensión:** ¿qué sucede si se vendieron tokens por 100 kg de miel y la cosecha real produjo solamente 80 kg? Los últimos compradores no podrían recibir su miel. ¿Reducción pro-rata? ¿Reembolso total a todos? ¿Política mixta?

**Solución propuesta:** se establece en el Forward Sale Agreement y se codifica en `confirmarCosecha()` una política de dos umbrales:

- **Shortfall menor al 10%:** reducción pro-rata. Cada comprador recibe el 90% de los kg comprados. El 10% restante se reembolsa en USDC. El comprador es notificado y debe aceptar la reducción pro-rata para que la operación se ejecute; en caso de negativa, se reembolsa la totalidad.
- **Shortfall mayor o igual al 10%:** el lote se marca como FALLIDO y se ejecuta reembolso total a todos los compradores.

**Acción requerida:** **decisión comercial y legal explícita** antes de implementar `confirmarCosecha`. El umbral del 10% es propuesto pero debe validarse con el equipo comercial (sensibilidad del cliente premium) y el abogado del Forward Sale Agreement. La política debe quedar redactada de forma inequívoca en el template del FSA.

---

## 14. Próximos pasos institucionales

Esta sección dirigida específicamente a la presentación ante entidades regulatorias y stakeholders bolivianos.

### 14.1 Para ASFI

**Solicitud:** consulta vinculante previa para confirmar que el modelo descrito (commodity token con FSA, sin mercado secundario, sin promesa de rendimiento) no requiere registro como Operador de Plataforma de Tokenización bajo Libro XIV, y que la operación desde Wyoming LLC (con SRL Bolivia limitada a producción y exportación) no activa la obligación de constituirse como ETF bajo D.S. 5384/2025.

**Materiales a presentar:** este documento, el template del Forward Sale Agreement, los Términos y Condiciones del servicio, la descripción técnica de los smart contracts y la arquitectura de la estructura societaria.

### 14.2 Para UIF Bolivia

**Solicitud:** registro de la SRL Bolivia como Proveedor de Servicios de Activos Virtuales (PSAV) conforme a RA UIF 19/2025. Presentación del Manual LGI/FT/FPADM, designación del Oficial de Cumplimiento titular y suplente, y demostración del cumplimiento de las obligaciones técnicas (KYC tiered, screening contra listas, reportería mensual en formato PSAV, conservación 10 años).

**Materiales a presentar:** este documento (con énfasis en la sección 9 Backend de Compliance), el Manual LGI/FT/FPADM, las hojas de vida de los Oficiales de Cumplimiento propuestos.

### 14.3 Para SENASAG

**Solicitud:** registro de la SRL Bolivia como establecimiento procesador de productos apícolas para exportación. Coordinación de la inspección inicial de los apiarios y los procedimientos de control de calidad.

**Materiales a presentar:** documentación operativa estándar requerida por SENASAG, planos de las instalaciones de la SRL, contratos con los apicultores, plan de control de calidad.

### 14.4 Para Aduana Nacional

**Solicitud:** registro de la SRL Bolivia como exportador frecuente. Confirmación del procedimiento de emisión de DUE para productos apícolas con destino Unión Europea (preferencias arancelarias SGP).

### 14.5 Para Cámara Nacional de Comercio / Cámara de Exportadores

**Presentación:** este modelo como caso de innovación exportadora boliviana, posicionamiento de marca país en RWA agrícola, oportunidades de replicación en otros commodities (café, cacao, quinua, frutas amazónicas).

### 14.6 Para potenciales inversores

**Presentación:** este documento como pieza técnico-legal demostrable. La trazabilidad criptográfica, la separación societaria y el diseño de cumplimiento configuran un activo defendible frente a due diligence de venture capital o angel investors.

### 14.7 Para apicultores y comunidades productoras

**Presentación:** charlas en formato accesible (sin tecnicismos) explicando que su miel será vendida anticipadamente a compradores europeos premium, que recibirán pagos por adelantado tras la firma del contrato, y que el sistema garantiza la trazabilidad de su producto sin que ellos deban operar tecnología compleja.

---

## 15. Glosario técnico-legal

**Activo Virtual (AV):** representación digital de valor o derechos que puede ser comerciada y transferida electrónicamente.

**Audit log:** registro detallado e inmutable de cada acción ejecutada en el sistema, con metadata de quién, cuándo y qué.

**Arweave:** red de almacenamiento descentralizado con pago único para preservación perpetua de archivos. Utilizada en este proyecto para la conservación legal de documentos.

**Backend:** sistema de software que procesa la lógica del negocio en el servidor (opuesto al frontend que ve el usuario).

**BL/AWB:** Bill of Lading (transporte marítimo) / Air Waybill (transporte aéreo). Documento emitido por el courier que certifica la recepción de la mercadería para transporte.

**Blockchain:** red distribuida donde se registran transacciones de forma criptográficamente verificable e inmutable.

**Burn (en blockchain):** acción de destruir un token transfiriéndolo a una dirección inutilizable (`address(0)`). Reduce el supply circulante.

**Commodity token:** token que representa un derecho sobre un bien físico (a diferencia de un valor mobiliario que representa un derecho financiero).

**DUE:** Declaración Única de Exportación, documento ante Aduana Nacional para autorizar salida de mercadería.

**EDD:** Enhanced Due Diligence, diligencia debida reforzada exigida en KYC tier 3 (compradores de alto volumen o empresariales).

**ERC-1155:** estándar técnico de Ethereum y EVM-compatibles para tokens multi-fungibles (un solo contrato puede representar múltiples tipos de tokens).

**FSA:** Forward Sale Agreement, contrato de venta a término donde el vendedor se compromete a entregar un bien futuro contra pago anticipado.

**Hash SHA-256:** función criptográfica que produce un identificador único de 32 bytes a partir de un archivo. Cualquier modificación del archivo produce un hash diferente.

**HMF:** hidroximetilfurfural, indicador de calidad de la miel (degradación por calor o tiempo).

**Mint (en blockchain):** acción de crear un token nuevo y asignarlo a una dirección.

**MSA:** Master Services Agreement, contrato marco de prestación de servicios entre dos entidades.

**Multi-firma (multi-sig):** wallet que requiere múltiples firmas para ejecutar transacciones (en este proyecto: 2 de 3).

**Oráculo:** sistema que aporta información del mundo real a una blockchain. En este proyecto el oráculo es humano (multi-firma Safe).

**OPT:** Operador de Plataforma de Tokenización, figura regulada por Libro XIV de propuesta ASFI.

**PII:** Personally Identifiable Information, datos personales identificables (nombre, dirección, documento).

**Polygon PoS:** sidechain de Ethereum compatible con EVM, con gas predecible y bajo.

**PSAV:** Proveedor de Servicios de Activos Virtuales, designación de RA UIF 19/2025.

**ROS:** Reporte de Operación Sospechosa, exigido por UIF cuando se detectan patrones anómalos.

**Smart contract:** programa que se ejecuta automáticamente en la blockchain cuando se cumplen condiciones predefinidas.

**Solidity:** lenguaje de programación de smart contracts en EVM.

**Sumsub:** proveedor especializado en KYC y verificación de identidad.

**Token:** unidad digital de valor representada en blockchain.

**USDC:** stablecoin emitida por Circle, respaldada 1:1 por dólares estadounidenses.

**Wallet:** software o hardware que custodia las claves privadas necesarias para operar con tokens en blockchain.

---

## 16. Referencias normativas

### Normativa boliviana

- Ley 393 (Servicios Financieros)
- Ley 1834 (Mercado de Valores)
- Ley 1489 (Exportaciones)
- Ley 470 (Almacenes Generales de Depósito)
- Ley 164 (Telecomunicaciones y TIC), artículos 74 a 79 sobre documentos electrónicos
- Resolución Directiva BCB 082/2024
- Decreto Supremo 5384 (2025)
- Decreto Supremo 5834 (2025)
- Circular ASFI 885/2025
- Resolución Administrativa UIF 19/2025
- Reglamentos SENASAG para productos apícolas exportables

### Normativa internacional

- Wyoming Digital Asset Act 2019 (HB 0070)
- Markets in Crypto-Assets Regulation MiCA (Reglamento UE 2023/1114)
- Directiva 2011/83/UE de Derechos del Consumidor
- Reglamento General de Protección de Datos GDPR (UE 2016/679)
- USA PATRIOT Act y regulaciones FinCEN (relevantes para Wyoming LLC)

### Estándares técnicos

- EIP-1155 (Ethereum Improvement Proposal): Multi Token Standard
- OpenZeppelin Contracts v5
- Foundry Foundry Book (foundry development framework)
- ISO/IEC 27001 Information Security Management (estándar de referencia para futura aplicación al ECP ASFI)
- ISO 3166-1 alpha-2 (códigos de país)

---

**Fin del documento.**

**Versión 1.0 — 16 de mayo de 2026**

**Autor:** Daniel Hidalgo Carrasco

Este documento ha sido elaborado como propuesta técnico-legal integrada para presentación ante entidades regulatorias bolivianas, asesores legales, equipo técnico, inversores y stakeholders del sector apícola exportador. Su contenido representa el diseño actual del proyecto; está sujeto a actualizaciones según evolucione el marco regulatorio boliviano y según se resuelvan los conflictos legales identificados en la Sección 13.

Para consultas o ampliaciones: contactar al autor.
