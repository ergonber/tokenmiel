# CLAUDE.md — apps/web (frontend Next.js 15)

> Reglas obligatorias para cualquier agente que trabaje con el frontend. Scope acotado: SOLO archivos en `apps/web/` (excepto lectura de ABIs en `packages/abis/`, tipos en `packages/shared/`, componentes UI en `packages/ui/`).

---

## 1. Scope

**Lo que SÍ podés tocar:**
- `apps/web/src/**` — código frontend
- `apps/web/tests/**` — tests
- `apps/web/public/**` — assets estáticos
- `apps/web/package.json`, `apps/web/next.config.ts`, `apps/web/tsconfig.json`, `apps/web/tailwind.config.ts`
- `packages/ui/src/**` — componentes shadcn/ui compartidos
- `packages/shared/src/**` — tipos / schemas compartidos

**Lo que NO podés tocar:**
- `packages/contracts/**` — smart contracts (otra área)
- `apps/api/**` — backend (otra área)
- `packages/db/**` — DB schemas

**Solo lectura permitida en:**
- `packages/abis/src/**` — ABIs generados (NO editar manualmente)

---

## 2. Stack

| Componente | Tecnología | Versión |
|---|---|---|
| Framework | Next.js | 15.x (App Router) |
| Lenguaje | TypeScript | 5.x |
| Estilos | TailwindCSS | 4.x |
| Componentes UI | shadcn/ui (Radix-based) | latest |
| Cliente Web3 | wagmi | 2.x |
| Cliente Ethereum | viem | 2.x |
| Wallet UI | RainbowKit | latest |
| Wallet protocol | WalletConnect | v2 |
| Forms | React Hook Form + Zod resolver | latest |
| State global | Zustand (cuando necesario) | latest |
| Data fetching | TanStack Query (integrado wagmi) | latest |
| i18n | next-intl | latest |
| Auth | Clerk | latest |
| Animations | Framer Motion (opcional) | latest |

---

## 3. Multi-chain (Plume + Polygon)

**Plume Network es la chain primaria.** Polygon es secundaria desde fase 6+. El frontend debe soportar ambas:

```typescript
// packages/shared/src/config/chains.ts (referencia)
export const supportedChains = [plume, polygon] as const;
export const defaultChain = plume;
```

**wagmi config:**
- Ambas chains configuradas en `wagmi.config.ts`
- Chain switcher en UI (RainbowKit nativo)
- Detección de chain en transacciones críticas
- Mensaje claro al usuario si está en chain incorrecta

---

## 4. Wallets soportadas

- MetaMask
- Coinbase Wallet
- WalletConnect v2 (cubre Rainbow, Trust, Rabby)
- Safe Wallet (B2B importadores con multi-sig propio)
- Ledger (direct via RainbowKit)
- Trezor (direct via RainbowKit)
- **Plume Smart Wallets** (account abstraction nativa de Plume)

---

## 5. Internacionalización (i18n)

- **Idiomas MVP obligatorios:** español (`es`), inglés (`en`)
- **Fase 2:** alemán (`de`), italiano (`it`), francés (`fr`)
- **NUNCA strings hardcoded en JSX** — usar `next-intl` con keys
- **Locale por defecto:** `es` (mercado primario LATAM/Bolivia + España)
- **URL prefix:** `/es/...`, `/en/...` (locale routing)

---

## 6. Estructura de áreas (App Router con route groups)

```
apps/web/src/app/
├── [locale]/              # i18n routing
│   ├── (marketing)/       # landing público
│   │   ├── page.tsx
│   │   ├── about/
│   │   ├── faq/
│   │   └── terms/
│   ├── (catalog)/         # catálogo público de lotes
│   │   ├── lots/
│   │   │   ├── page.tsx
│   │   │   └── [id]/
│   │   └── assets/
│   ├── (auth)/            # auth flows (Clerk)
│   │   ├── sign-in/
│   │   ├── sign-up/
│   │   └── kyc/
│   ├── (account)/         # panel del usuario
│   │   ├── dashboard/
│   │   ├── lots/
│   │   ├── redemptions/
│   │   └── settings/
│   └── (admin)/           # panel administrativo (requiere admin role + 2FA)
│       ├── lots/
│       ├── identity/
│       ├── quality/
│       ├── oracle/
│       ├── documents/
│       └── audit/
└── api/                   # route handlers Next.js (proxies a apps/api)
```

---

## 7. Archivos críticos a leer ANTES de cualquier cambio

1. `/Users/firrton/Desktop/tokenización/CLAUDE.md` (raíz)
2. **Este archivo**
3. **`ARQUITECTURA-TECNICA-MVP.md`** secciones 14 (frontend), 22 (módulos), 23 (flujos críticos)
4. **`packages/abis/src/*`** para ABIs y types contratos
5. **`packages/shared/src/*`** para tipos compartidos
6. **`packages/ui/src/*`** para componentes existentes
7. **ADRs relevantes:** ADR-006 (monorepo), ADR-001 (multi-chain)

---

## 8. Reglas obligatorias

### 8.1 Server Components vs Client Components
- **Default: Server Components.** Solo agregar `"use client"` cuando estrictamente necesario.
- Web3 hooks (wagmi) requieren client components — encapsular en componentes hoja.
- Data fetching server-side donde aplique (mejor SEO, mejor perf inicial).

### 8.2 Forms
- React Hook Form + Zod resolver — siempre
- Schemas Zod en `packages/shared/src/schemas/` reutilizables (mismos que backend valida)
- Inline validation con errors estructurados

### 8.3 Accessibility
- **WCAG AA obligatorio**
- Semantic HTML (NO `div soup`)
- ARIA labels donde corresponda
- Keyboard navigation funcional
- Color contrast ≥ 4.5:1 (texto), ≥ 3:1 (UI)
- Focus visible
- Skip links donde aplique

### 8.4 Performance
- Images con `next/image` (NO `<img>`)
- Fonts con `next/font` (NO link CDN)
- Lazy load para componentes pesados
- Suspense boundaries adecuados
- Bundle size monitoreado (`next-bundle-analyzer`)

### 8.5 SEO (vista pública)
- Metadata API de Next.js 15
- Open Graph + Twitter Cards
- Sitemap.xml generado
- robots.txt
- Structured data (Schema.org) para lotes (Product, etc.)

### 8.6 State management
- **Server state:** TanStack Query (integrado wagmi)
- **Local state:** `useState`, `useReducer`
- **Global state:** Zustand SOLO si necesario (auth ya viene de Clerk, web3 ya viene de wagmi)
- **NUNCA** Redux para MVP

### 8.7 Auth
- Clerk middleware en `middleware.ts`
- Protected routes via Clerk
- **Admin routes requieren 2FA obligatorio** (Clerk config)
- Wallet connection NO reemplaza auth — son ortogonales

---

## 9. Comandos comunes

```bash
# Setup
pnpm install

# Dev
pnpm dev                                # localhost:3000

# Build
pnpm build
pnpm start                              # production server

# Tests
pnpm test                               # Vitest unit
pnpm test:e2e                           # Playwright E2E
pnpm test:a11y                          # accessibility checks

# Lint / type-check
pnpm lint
pnpm type-check

# Storybook (si aplica para packages/ui)
pnpm storybook
```

---

## 10. Lo que NO debe hacer en esta área

- ❌ Usar `localStorage` para datos sensibles (PII, KYC, JWTs) — riesgo regulatorio
- ❌ Almacenar PII en cookies sin cifrar
- ❌ Exponer endpoints admin sin Clerk + 2FA
- ❌ Usar `dangerouslySetInnerHTML` con datos no sanitizados
- ❌ Desactivar TypeScript strict mode
- ❌ Strings hardcoded en JSX (siempre via `next-intl`)
- ❌ Usar `<img>` (usar `next/image`)
- ❌ Usar `<a>` para internal nav (usar `next/link`)
- ❌ Acceder directo a smart contracts sin wagmi/viem
- ❌ Hacer fetch sin TanStack Query (queries) o sin viem (writes)
- ❌ Bloquear UI con loading sync — siempre suspense/loading states
- ❌ Modificar componentes en `packages/ui/` para necesidades específicas de web (crear wrapper local en su lugar)
- ❌ Importar de `apps/api/` (eso es backend, otra área)
- ❌ Importar de `packages/contracts/` (eso es smart contracts, otra área)
- ❌ Permitir compra sin verificar `canMint` en IdentityRegistry on-chain
- ❌ Mostrar precios sin disclaimer si están en USDC (clarificar conversión)
- ❌ Permitir input de cantidades sin validación de stock disponible

---

## 11. Patrones obligatorios

### 11.1 Web3 reads
```tsx
'use client';
import { useReadContract } from 'wagmi';
import { assetVaultAbi, assetVaultAddress } from '@miel/abis';

export function LotInfo({ lotId }: { lotId: bigint }) {
  const { data: lot } = useReadContract({
    address: assetVaultAddress[chainId],
    abi: assetVaultAbi,
    functionName: 'lotes',
    args: [lotId],
  });
  // ...
}
```

### 11.2 Web3 writes
```tsx
'use client';
import { useWriteContract } from 'wagmi';

export function BuyButton() {
  const { writeContract, isPending } = useWriteContract();
  // ...
}
```

### 11.3 Forms con Zod
```tsx
const formSchema = z.object({
  cantidad: z.number().int().positive(),
  shippingAddress: z.string().min(10),
});
type FormData = z.infer<typeof formSchema>;

const form = useForm<FormData>({
  resolver: zodResolver(formSchema),
});
```

### 11.4 Server Component fetch
```tsx
async function LotsPage() {
  const lots = await fetchLots();  // server-side fetch
  return <LotList lots={lots} />;
}
```

---

## 12. Workflow loop dentro del área

Cada cambio en `apps/web/`:

1. **Build:**
   - Componente / página / hook implementado
   - i18n strings agregados a archivos de locale
2. **Test:**
   - Vitest unit pasan
   - Playwright E2E pasan (si aplica)
   - Accessibility check (`pnpm test:a11y`)
3. **Document:**
   - README de área si componente complejo
   - Storybook si componente reusable
4. **Review:**
   - `pnpm lint` sin errores
   - `pnpm type-check` sin errores
   - Visual review (idealmente Chromatic / Percy)

---

**Última actualización:** 2026-05-19
**Aplicabilidad:** todos los archivos bajo `apps/web/**`
