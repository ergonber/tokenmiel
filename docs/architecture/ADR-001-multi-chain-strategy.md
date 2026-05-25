# ADR-001: Multi-chain strategy (Plume primaria + Polygon secundaria)

**Status:** Accepted
**Date:** 2026-05-19
**Author:** Daniel Hidalgo Carrasco
**Tags:** blockchain, infrastructure, plume, polygon

---

## Context

El proyecto necesita una blockchain pública para emitir tokens ERC-1155 que representen lotes de commodities agrícolas tokenizados. La decisión de chain impacta:

- Talento dev disponible (EVM vs no-EVM)
- Pool de auditores experimentados
- Primitives nativas para RWA (KYC integrado, asset issuance)
- Costo de gas y latencia
- Reconocimiento institucional (compradores B2B premium)
- Acceso a grants (Plume Foundation, Stellar SDF, Polygon Village, etc.)
- Fiat on-ramps disponibles

Cuatro chains fueron evaluadas como candidatas serias: Plume Network, Polygon PoS, Arbitrum One, Algorand, Stellar.

---

## Decision

**Adoptar estrategia multi-chain progresiva:**

1. **Chain primaria (fases 1–7 del MVP): Plume Network** (L2 EVM-compatible diseñada 100% para RWA, mainnet activa desde 2024).
2. **Chain secundaria (fase 8+): Polygon PoS** (track record en RWA agrícola LATAM con AgroToken y Mercado Bitcoin).
3. **Sincronización cross-chain:** Plume SkyLink primario, Chainlink CCIP como alternativa.

**Modelo de mirror, no bridge bidireccional:** el token "vive" en Plume. En Polygon hay un mirror del estado del lote (mismo `loteId`, mismos `kg` disponibles, mismos hashes) que permite consulta y verificación pero no transferencia. Esto evita la complejidad y riesgos de bridge bidireccional de tokens.

---

## Alternatives considered

### Polygon PoS único
- ✅ Máximo pool de auditores y talento dev
- ✅ Precedente directo en RWA agrícola LATAM (AgroToken, Mercado Bitcoin)
- ❌ Sin primitives RWA built-in (todo custom)
- ❌ Sin grants específicos para RWA

### Stellar (con Soroban)
- ✅ Asset issuance nativo, authorization flags integrados
- ✅ SDF Grants generosos (USD 150K Build Award, USD 500K Matching Fund)
- ❌ Re-stack completo a Rust/Soroban (4–8 semanas equipo)
- ❌ Pool de auditores Soroban muy pequeño

### Algorand
- ✅ ASA nativo con compliance built-in (freeze, clawback)
- ✅ Algorand Foundation Grants generosos
- ❌ PyTeal/TEAL no-EVM (curva 2–4 semanas)
- ❌ Pool de auditores menor

### Arbitrum One
- ✅ EVM, gas barato, maturity alta
- ❌ Foco DeFi, no RWA agrícola
- ❌ Sin primitives RWA built-in

### Ethereum mainnet
- ❌ Gas prohibitivo para volumen MVP

### Plume único (sin Polygon)
- ✅ Más simple operacionalmente
- ❌ Sin redundancia ante riesgo de chain joven
- ❌ Pierde reconocimiento institucional de Polygon

---

## Consequences

### Positive

- **Plume primero** acelera time-to-market: primitives `Plume Arc` (KYC), `Plume Nexus` (oracle data), `Plume SkyLink` (cross-chain) reducen significativamente código custom.
- **EVM compatible:** mantenemos stack Solidity + OpenZeppelin v5 + Foundry. No re-stack.
- **Multi-chain en fase 8** da redundancia ante riesgo de Plume (chain joven, sequencer centralizado, pool de auditores Plume-specific menor).
- **Reconocimiento institucional de Polygon** disponible cuando se necesite (importadores europeos institucionales tradicionales).
- **Aplicación a Plume Foundation Grants** alineada con producto.

### Negative

- **Doble deployment + doble auditoría** en fase 8 (Polygon agrega ~USD 4-10K adicionales).
- **Complejidad operacional cross-chain** para mantener estado consistente.
- **Plume es joven (2024):** pool de auditores Plume-specific reducido (mitigado: auditores EVM genéricos pueden auditar contratos Solidity estándar).
- **Sequencer centralizado** en Plume (mitigado: idéntico a la mayoría de L2 hoy).

### Neutral

- Liquidez USDC en Plume es menor que en Polygon, pero suficiente para MVP volume.
- Documentación y comunidad dev de Plume más chica que Polygon (mitigado: equipo conoce Solidity, no necesita docs Plume-specific extensos).

---

## Implementation notes

### Plume (fase 1–7)
- USDC nativo de Plume (address por confirmar en mainnet)
- RPC: Plume RPC oficial + provider redundante
- Indexer: Goldsky subgraph para Plume
- Explorer: Plume Explorer
- Multi-sig Safe (Gnosis) 2-de-3 en Plume

### Polygon (fase 8+)
- USDC Circle nativo: `0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359`
- RPC: Alchemy (primario) + Infura (fallback)
- Indexer: Goldsky subgraph para Polygon
- Explorer: PolygonScan
- Multi-sig Safe (Gnosis) 2-de-3 en Polygon — mismos 3 firmantes que Plume

### Cross-chain (fase 8)
- **Opción A primaria:** Plume SkyLink — primitive nativo de Plume
- **Opción B alternativa:** Chainlink CCIP — protocolo cross-chain genérico (relevante si ya integramos Chainlink para PoR, ver ADR-004)
- **Modelo:** mirror de estado, NO bridge de tokens
- **Reconciliación:** job nightly que detecta discrepancias entre chains

### Configuración wagmi (frontend)
```typescript
export const supportedChains = [plume, polygon] as const;
export const defaultChain = plume;
```

---

## References

- `ARQUITECTURA-TECNICA-MVP.md` §4 (decisión técnica #1: red blockchain)
- ADR-002 (ERC-1155 token standard)
- ADR-003 (4 contratos inmutables)
- ADR-004 (oracle design)
- AgroToken (Argentina) — https://agrotoken.io/
- Mercado Bitcoin (Brasil) — RWA agrícola sobre Polygon
- Plume Network docs — primitives Arc/Nexus/SkyLink
