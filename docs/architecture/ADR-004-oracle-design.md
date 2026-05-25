# ADR-004: Oracle design (Safe multi-firma + Chainlink Proof of Reserve)

**Status:** Accepted
**Date:** 2026-05-19
**Author:** Dany Hidalgo F.
**Tags:** smart-contracts, oracle, safe, chainlink, proof-of-reserve

---

## Context

El sistema requiere "oráculos" en sentido amplio para varias funciones:

1. **Confirmación de eventos físicos** (cosecha realizada, lote almacenado, exportación confirmada): decisiones humanas basadas en documentos físicos.
2. **Verificación pública de reservas físicas** (kg de miel en almacén): para credibilidad institucional con compradores B2B premium.
3. **Confirmación de calidad** (palinología, NMR): pilar separado del oráculo de calidad (ver ADR-005).
4. **Cross-chain messaging** (Plume↔Polygon en fase 8): para mirror de estado.

Las opciones evaluadas: Safe multi-firma humano, Chainlink (productos varios), oráculo centralizado custom, híbridos.

---

## Decision

**Oráculo dual:**

1. **Safe (Gnosis Safe) multi-firma 2-de-3** para confirmación de hitos productivos.
2. **Chainlink Proof of Reserve** para verificación de reservas físicas.
3. **Aplicación al Chainlink BUILD program** para acceso gratis a servicios Chainlink + co-marketing.

**Productos Chainlink NO usados en MVP:**
- Chainlink Price Feeds (no requerimos precio dinámico — el precio se fija al mint)
- Chainlink VRF (no hay randomness)
- Chainlink Automation (backend cron cubre el caso)
- Chainlink Functions (evaluable en fase 2 para integración directa con APIs de labs)

**Productos Chainlink reservados para fase 8:**
- Chainlink CCIP (alternativa a Plume SkyLink para cross-chain messaging)

---

## Alternatives considered

### v1.0 (descartar Chainlink completamente)
- ✅ Más simple, menos dependencias
- ❌ Sin Proof of Reserve público — pierde credibilidad institucional B2B
- → **Decisión revertida en v2.0** porque el otro agente trajo punto válido sobre PoR

### Chainlink Automation para liberación de reserva técnica
- ✅ Ejecución automática on-chain post-cosecha
- ❌ Backend cron es más simple, sin LINK costs ni dependencia
- → Mantenido como backend job, no Chainlink

### Chainlink Functions para sync Sumsub → IdentityRegistry
- ✅ Llamadas Web2 desde contratos de forma "trustless"
- ❌ Webhook directo es más simple, sin latencia ni LINK costs
- → Mantenido como webhook backend, no Chainlink Functions

### Oráculo centralizado custom
- ❌ Punto de falla único
- ❌ Confianza en una entidad — no defensible institucionalmente

### API3 / Pyth / Tellor / Witnet
- ❌ Menor adopción institucional que Chainlink
- ❌ No tienen producto PoR equivalente

---

## Consequences

### Positive

- **Decisiones humanas auditables:** cada confirmación de hito tiene firmantes identificables.
- **Defensible legalmente:** representantes legales de la entidad emisora firmando.
- **Sin dependencias externas para hitos críticos.**
- **PoR público verificable:** comprador institucional puede verificar reservas físicas on-chain.
- **Chainlink BUILD program:** si aprobados, costo de PoR = cero.
- **Co-marketing con Chainlink:** legitimidad adicional.

### Negative

- **Disponibilidad de firmantes:** requiere 2 de 3 disponibles para cada confirmación.
- **Pérdida de hardware wallets:** si se pierden 2 de 3, sistema bloqueado (mitigado con escrow notarial de seeds).
- **Costo LINK** si no entramos al BUILD program (~USD 50-200/mes estimado para PoR).
- **Latencia** de updates PoR (depende de frecuencia configurada — típicamente 24h).

### Neutral

- **Audit trail completo:** cada acción Safe queda registrada con tx hash + firmantes en eventos on-chain + PostgreSQL.

---

## Implementation notes

### Safe multi-firma 2-de-3

**Firmantes:**
- 3 cofundadores/operadores con direcciones documentadas y declaradas
- Cada uno con hardware wallet (Ledger Nano X o Trezor Model T)
- Direcciones registradas en `ORACLE_ROLE` de los contratos

**Threshold:** 2 de 3 (cualquier 2 firmas autorizan la transacción)

**Hardware:**
- Ledger Nano X (recomendado) o Trezor Model T
- Backup de seeds en escrow notarial físico (Bolivia + Wyoming)
- Drill trimestral de rotación de firmantes

**Dashboard custom en panel admin:**
1. Upload de documentos
2. Cálculo automático de hash SHA-256
3. Generación de transacción pre-firmada (calldata + Safe SDK)
4. Notificación a 3 firmantes via Slack DM + email
5. Cada firmante revisa, conecta hardware wallet, firma
6. Al alcanzar 2 firmas, tx se ejecuta on-chain automáticamente

**Audit trail:**
- Eventos on-chain: `LoteComprado`, `CosechaConfirmada`, `AlmacenamientoConfirmado`, `LoteFallido`, `RedencionCompletada`
- Tabla `safe_transactions` en PostgreSQL con metadata completa

### Chainlink Proof of Reserve

**Función:** verificación pública de reservas físicas (kg en almacén).

**Flujo:**
1. Almacén certificado reporta balance periódicamente (firmado)
2. Nodos Chainlink consultan el reporte (vía API del almacén o adapter custom)
3. Publican resultado on-chain de forma firmada y verificable
4. Cualquier comprador puede verificar en explorer

**Frecuencia:** updates diarios o por evento (configurable)

**Aplicación al BUILD program:**
- Aplicar apenas testnet esté funcionando (fase 1-2)
- Caso de uso (RWA tokenización + PoR) encaja con target del programa
- Si aprobado: costo cero + soporte técnico + co-marketing

**Costo estimado sin BUILD program:**
- ~USD 50-200/mes en LINK tokens (proporcional a frecuencia de updates)

---

## Plan de escalamiento

**Fase 8+ (multi-chain):**
- Chainlink CCIP como alternativa a Plume SkyLink para cross-chain messaging
- Decisión final entre ambos basada en evaluación técnica en fase 7

**Post-MVP:**
- Chainlink Automation: solo si las operaciones automáticas crecen significativamente
- Chainlink Functions: solo si necesitamos llamar APIs Web2 directamente desde contratos

---

## References

- ARQUITECTURA-TECNICA-MVP.md §7 (decisión técnica #4: oráculos y Chainlink)
- ADR-003 (4 contratos inmutables)
- ADR-005 (LabRegistry, oráculo de calidad — separado)
- Safe (Gnosis Safe): https://docs.safe.global/
- Chainlink Proof of Reserve: https://chain.link/proof-of-reserve
- Chainlink BUILD program: https://chain.link/build
