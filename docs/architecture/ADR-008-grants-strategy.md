# ADR-008: Grants strategy (Plume Foundation + Chainlink BUILD + Stellar paralelo)

**Status:** Accepted
**Date:** 2026-05-19
**Author:** Dany Hidalgo F.
**Tags:** funding, grants, plume, chainlink, stellar

---

## Context

El proyecto requiere financiamiento para cubrir desarrollo, auditoría externa, infraestructura, salarios del equipo, y costos operativos hasta alcanzar break-even o ronda de inversión externa. Los grants de fundaciones blockchain son una fuente de financiamiento no-dilutiva con valor agregado adicional (soporte técnico, co-marketing, networking).

Las opciones de grants relevantes:
- Plume Foundation Grants (milestone-based)
- Stellar Community Fund (Build Award + Matching Fund)
- Chainlink BUILD program (gratis si aprobado)
- Polygon Village (variable)
- Algorand Foundation Grants
- Arbitrum Foundation Grants
- Otros (Cicada Partners early-stage)

---

## Decision

**Aplicar a múltiples grants en paralelo (no excluyentes) con esta priorización:**

### Mes 1-2 (paralelo)
1. **Plume Foundation Grants** — target: alineado con chain primaria (ADR-001)
2. **Stellar Community Fund — Build Award** — target USD 150K (no excluyente con Plume)
3. **Chainlink BUILD program** — gratis si aprobado, requerido para Proof of Reserve sin costo (ADR-004)

### Mes 2-3
4. **Cicada Partners early-stage program** — USD 50-100K + market making support (vía Plume ecosystem)

### Mes 6-12 (post-tracción)
5. **Stellar Matching Fund** — hasta USD 500K matcheado 1:1 con lead investor (condicional a tener lead investor)

### No aplicamos a (justificado):
- **Polygon Village** — grants más chicos vs Plume + duplicación de esfuerzo
- **Algorand / Arbitrum grants** — chains descartadas (ADR-001)

---

## Alternatives considered

### Solo Plume Foundation
- ✅ Simple, foco único
- ❌ Pierde opcionalidad si Plume rechaza
- ❌ Stellar grants son más generosos por aplicación

### Solo Stellar SDF
- ✅ Grants más generosos (Build Award + Matching Fund)
- ❌ Requeriría re-stack a Soroban (ADR-001 lo descarta)
- ❌ Si SDF rechaza, sin Plan B

### Solo Chainlink BUILD
- ✅ Gratis, valor agregado (co-marketing)
- ❌ NO es un grant monetario — no cubre desarrollo

### No aplicar a grants (equity-only)
- ✅ Más rápido si tenemos lead investor desde el inicio
- ❌ Dilutivo
- ❌ Pierde valor agregado de fundaciones (soporte, comunidad)

### Aplicar a todos sin priorización
- ❌ Esfuerzo administrativo alto (cada grant requiere aplicación específica)
- ❌ Dispersión de foco

---

## Consequences

### Positive

- **Diversificación de fuentes:** si Plume rechaza, Stellar puede aprobar; si Stellar rechaza, Cicada puede aprobar.
- **No-dilutivo:** grants no requieren ceder equity.
- **Valor agregado:** soporte técnico, co-marketing, networking con cada fundación.
- **Validación externa:** un grant aprobado es señal positiva para futuros inversores.
- **Alineación de incentivos:** las fundaciones quieren que el proyecto tenga éxito en su chain.

### Negative

- **Esfuerzo administrativo:** cada aplicación requiere customización (pitch deck, milestones, propuesta técnica).
- **Time-to-cash variable:** review processes pueden tomar 2-8 semanas por fundación.
- **Compromisos de marketing:** algunos grants requieren mencionar la chain en materiales.
- **Posible conflicto de intereses** si dos fundaciones compiten por exclusividad (mitigación: no firmar exclusividad sin negociar).

### Neutral

- **Reportes periódicos:** la mayoría de los grants requiere reportes mensuales o trimestrales de progreso.

---

## Implementation notes

### Plume Foundation Grants (prioridad #1)

**Estructura recomendada:** milestone-based.

Milestones propuestos:
1. **MVP del spot token + primera bodega de miel** (mes 3) — desbloquea tranche inicial
2. **Primera transacción internacional B2B** (mes 6) — segundo tranche
3. **Lanzamiento del forward token** (mes 9) — tercer tranche
4. **Primer exportador recurrente** (mes 12) — tranche final

**Target:** variable según milestone, target total razonable USD 100-250K.

**Aplicación:**
- Pitch deck con foco en RWA agrícola + LATAM + impact metrics
- Demo técnica en Plume Testnet (post fase 1)
- Roadmap alineado con primitives Plume (Arc, Nexus, SkyLink)

### Stellar Community Fund — Build Award (paralelo)

**Target:** USD 150K (Build Award estándar).

**Pitch angle:** "Primera plataforma de tokenización agro-export desde Bolivia con estructura tranched senior/junior. Emerging markets + financial inclusion."

**Precedentes LATAM citables:** Amber, Bank2Bit, Emigro.

**Compromiso:** aunque chain primaria es Plume, podemos hacer mirror/demo en Stellar Soroban como caso de uso secundario (sin re-stack completo).

### Chainlink BUILD program (continuo)

**Aplicar apenas testnet funcione (fase 1-2).**

**Justificación:**
- Caso de uso (RWA tokenización + Proof of Reserve) encaja exactamente con target
- Sin BUILD: USD 50-200/mes en LINK para PoR
- Con BUILD: gratis + soporte técnico + co-marketing

**Compromiso:** integrar Chainlink PoR desde MVP (ADR-004).

### Cicada Partners early-stage (mes 2-3)

**Target:** USD 50-100K + market making support.

**Valor adicional:** resuelve problema futuro de liquidez secundaria si decidimos abrir mercado secundario (fase 2+).

**Vía:** integración con ecosistema Plume.

### Stellar Matching Fund (mes 6-12)

**Target:** hasta USD 500K matched 1:1.

**Condición:** requiere lead investor (QED u otro) que ponga la otra mitad.

**Timing:** solo cuando tengamos tracción demostrable (primer lote vendido + redención exitosa + métricas).

---

## Risk mitigation

- **Rechazo de Plume Foundation:** Plan B = aceptar Stellar grant + reconsiderar stack (decisión separada con ADR nuevo)
- **Rechazo de Chainlink BUILD:** Plan B = absorber costo LINK (~USD 50-200/mes) en operación
- **Exclusividad demandada por fundación:** rechazar exclusividad como condición; si insisten, decidir caso por caso con análisis CBA

---

## References

- ARQUITECTURA-TECNICA-MVP.md §4.7 (plan de grants asociado a chains)
- ADR-001 (multi-chain strategy)
- ADR-004 (oracle design — Chainlink PoR)
- Plume Foundation Grants: https://plumenetwork.xyz/
- Stellar Community Fund: https://communityfund.stellar.org/
- Chainlink BUILD: https://chain.link/build
- Cicada Partners: https://cicadapartners.xyz/
