# ADR-009: Escrow total post-cosecha (modelo de pago)

**Status:** Accepted
**Date:** 2026-05-19 (Iteration #2)
**Author:** Daniel Hidalgo Carrasco
**Tags:** smart-contracts, escrow, refund-policy, h-01

---

## Context

El audit profundo de `AssetVault.sol` (Iteration #1) identificó el finding **H-01**: el modelo original transfería el monto neto (80-85%) al productor SRL en `comprar()`, dejando solo la reserva técnica (15-20%) disponible para reembolso si el lote fallaba. Esto significaba que un comprador europeo que pagara USD 1,000 podía recuperar máximo USD 150-200 ante una falla de cosecha.

Esto era **incompatible con**:
- Forward Sale Agreements clásicos (el vendedor cobra al entregar)
- Directiva 2011/83/UE de protección al consumidor (B2C europeo)
- MiCA derecho de retracto 14 días
- Expectativa razonable de compradores premium

El audit propuso 3 opciones (recuperación off-chain, TyC documentando reembolso parcial, fondo de garantía con 5% extra). La decisión del producto requirió input del usuario.

---

## Decision

**Adoptar Opción A: Escrow total post-cosecha.**

- En `comprar()`: el USDC del comprador queda **íntegramente retenido en el contrato** (NO se transfiere al productor). Se contabiliza en dos campos:
  - `lote.reservaTecnicaUSDC` (15-20%)
  - `lote.montoNetoPendiente` (80-85%) — campo nuevo
- En `confirmarCosecha()`: **se libera automáticamente** `lote.montoNetoPendiente` al productor SRL. La reserva técnica queda pendiente.
- En `liberarReservaTecnica()`: el productor llama manualmente para cobrar el 15-20% restante (permitido desde COSECHADO, ver ADR derivado).
- En `reembolsarLoteFallido()`: el pool de reembolso = `montoNetoPendiente + (reservaTecnicaUSDC - reservaTecnicaLiberada)`. Si el lote falla en PREVENTA (pre-cosecha), reembolso = 100% del pago original.

---

## Alternatives considered

### B) Recuperación off-chain del productor
Mantener pago en `comprar()` pero agregar función `recuperarFondosProductor()` callable por `COMPLIANCE_OFFICER_ROLE` con allowance previo del productor.

**Descartada:** depende de cooperación del productor (allowance) o demanda legal off-chain. No garantiza reembolso 100% on-chain.

### C) Fondo de garantía con 5% adicional
Cobrar 5% extra al comprador, depositado en pool separado que cubre fallas.

**Descartada:** encarece el producto sin razón inherente, cobertura limitada al pool, complejidad de distribución.

---

## Consequences

### Positive

- **Reembolso 100% garantizado on-chain** si el lote falla en PREVENTA (estado donde todo el USDC sigue en escrow).
- **Modelo institucional estándar** (BlackRock BUIDL, Centrifuge, Forward Sale Agreements clásicos).
- **Defensible legalmente** ante MiCA, UE consumer law, UCC.
- **Sin dependencias off-chain frágiles** para garantizar el reembolso.
- **El productor tiene incentivo correcto:** cobra cuando produce, no cuando vende promesa.

### Negative

- **Productor no cobra anticipo en `comprar()`** — debe gestionar capital de trabajo aparte (puede usar el monto neto liberado al confirmar primera cosecha como working capital para la siguiente).
- **Falla post-cosecha (clima post-cosecha, robo en almacén) queda parcialmente cubierta**: si el productor ya cobró el monto neto en `confirmarCosecha`, ese capital no se puede recuperar on-chain. Mitigación: combinado con M-05 (restricción de `marcarFallido` a estados pre-almacén), se reduce significativamente el caso.
- **USDC inmovilizado en el contrato durante PREVENTA** — capital ocioso desde el punto de vista del productor. Aceptable porque ese capital pertenece moralmente al comprador hasta entrega.

### Neutral

- Cambio de signature en `comprar()` mínimo (sin parámetros nuevos).
- Eventos extendidos: nuevo `MontoNetoLiberado` emitido en `confirmarCosecha`.
- Interface `IAssetVault` actualizada con campo `montoNetoPendiente` en `LoteMiel`.

---

## Implementation notes

### Cambios al contrato `AssetVault.sol`

1. **Struct `LoteMiel`** agrega campo `uint256 montoNetoPendiente`.
2. **`comprar()`** NO ejecuta `usdc.safeTransfer(lote.productorSRL, montoNeto)`. En su lugar: `lote.montoNetoPendiente += montoNeto`.
3. **`confirmarCosecha()`** ejecuta `usdc.safeTransfer(lote.productorSRL, lote.montoNetoPendiente)` y resetea `lote.montoNetoPendiente = 0`. Emite evento `MontoNetoLiberado`.
4. **`reembolsarLoteFallido()`** computa `totalDisponible = montoNetoPendiente + (reservaTecnicaUSDC - reservaTecnicaLiberada)`.

### Casos de uso resultantes

| Estado al fallar | Pool de reembolso | Cobertura |
|---|---|---|
| **PREVENTA** | 100% del USDC (escrow total intacto) | 100% del pago original |
| **COSECHADO** (post-cosecha, montoNeto liberado) | Solo reserva técnica (15-20%) | Parcial — caso operacional raro |
| **COSECHADO** post-`liberarReservaTecnica` | 0 (todo entregado) | 0% on-chain — requiere flujo off-chain |
| **ALMACENADO+** | `marcarFallido` bloqueado (M-05) | N/A |

### Roadmap futuro

- **"Tokens forward" pre-cosecha (fase 2+):** modelo donde el usuario confía y compra antes de que la cosecha ocurra. Requiere diseño de garantías distinto (seguro agrícola, multi-firma de cosecha, etc.). Documentado como feature roadmap, no implementado en MVP.

---

## References

- `docs/security-reviews/audit-AssetVault-deep-2026-05-19.md` (finding H-01 detallado)
- `docs/ITERATION-LOG.md` (Iteration #2)
- ADR-003 (4 contratos inmutables → ahora 3 activos + LabRegistry standalone)
- ADR-010 (simplificación de estados sin QualityAttestation)
