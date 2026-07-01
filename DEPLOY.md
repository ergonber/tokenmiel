# Deploy en Vercel - Guía paso a paso

Este documento explica cómo desplegar el proyecto Firtton en Vercel.

## Estructura del deploy

El proyecto se despliega en **dos partes separadas** en Vercel:

1. **Frontend** (`apps/web`) - Next.js app
2. **Backend** (`apps/api`) - API en Vercel Functions

## Prerrequisitos

- Cuenta en [Vercel](https://vercel.com)
- Repositorio en GitHub ya subido
- Node.js 18+ y pnpm instalados localmente

## Paso 1: Configurar variables de entorno

### Backend (apps/api)

En Vercel, crear un nuevo proyecto para el backend o usar el mismo proyecto con múltiples directorios:

**Variables de entorno requeridas:**
```
NODE_ENV=production
CHAIN_ID=98867  # o 98866 para mainnet
PLUME_RPC_URL=https://your-plume-rpc-url.com
LOG_LEVEL=info
```

**Variables opcionales (para producción completa):**
```
DATABASE_URL=postgresql://...
REDIS_URL=redis://...
BACKEND_SIGNER_KMS_KEY_ID=projects/...
GCP_KMS_LOCATION=us-east1
PLUME_RPC_URL_FALLBACK_DRPC=
PLUME_RPC_URL_FALLBACK_THIRDWEB=
```

### Frontend (apps/web)

**Variables de entorno requeridas:**
```
NEXT_PUBLIC_API_BASE_URL=https://tu-backend.vercel.app
```

> ⚠️ **Importante**: Reemplazar `https://tu-backend.vercel.app` con la URL real del backend desplegado.

## Paso 2: Deploy del Backend

### Opción A: Backend como proyecto separado

1. En Vercel, **Importar nuevo proyecto**
2. Seleccionar el repositorio de GitHub
3. Configurar:
   - **Root Directory**: `apps/api`
   - **Build Command**: (dejar vacío, Vercel detecta automáticamente)
   - **Output Directory**: (dejar vacío)
4. Agregar las variables de entorno del backend
5. Deploy

### Opción B: Backend en el mismo proyecto (monorepo)

1. En Vercel, **Importar proyecto**
2. Configurar:
   - **Root Directory**: `apps/api`
   - Vercel detectará `vercel.json` automáticamente
3. Agregar variables de entorno
4. Deploy

La URL del backend será algo como: `https://firtton-api.vercel.app`

## Paso 3: Deploy del Frontend

1. En Vercel, **Importar nuevo proyecto** (o agregar al existente)
2. Configurar:
   - **Root Directory**: `apps/web`
   - **Build Command**: `pnpm build` (auto-detectado)
   - **Output Directory**: `.next` (auto-detectado)
3. Agregar variable de entorno:
   ```
   NEXT_PUBLIC_API_BASE_URL=https://tu-backend.vercel.app
   ```
4. Deploy

La URL del frontend será algo como: `https://firtton.vercel.app`

## Paso 4: Configurar rewrites (si es necesario)

Si el frontend y backend están en el mismo dominio, actualizar `apps/web/next.config.ts`:

```typescript
const nextConfig: NextConfig = {
  async rewrites() {
    const apiBaseUrl = process.env.NEXT_PUBLIC_API_BASE_URL ?? 'http://127.0.0.1:3001';

    return [
      {
        source: '/api/:path*',
        destination: `${apiBaseUrl}/:path*`,
      },
    ];
  },
};
```

Esto ya está configurado en el proyecto actual.

## Paso 5: Verificar el deploy

1. Abrir la URL del frontend
2. Verificar que el panel "Estado del backend" muestre "Conectado"
3. Verificar que se muestren los contratos: AssetVault, IdentityRegistry, RedemptionManager
4. Probar los endpoints directamente:
   - `https://tu-backend.vercel.app/health`
   - `https://tu-backend.vercel.app/status/summary`

## Solución de problemas

### Backend no se conecta

- Verificar que `NEXT_PUBLIC_API_BASE_URL` apunte a la URL correcta del backend
- Verificar que el backend tenga las variables de entorno configuradas
- Verificar los logs de Vercel para errores de runtime

### Error de CORS

El backend ya tiene CORS configurado en `apps/api/src/shared/middleware.ts`. Si hay problemas, verificar que el dominio del frontend esté permitido.

### Timeout en Vercel Functions

El `maxDuration` está configurado en 30 segundos en `apps/api/vercel.json`. Si necesitas más tiempo, actualizar este valor (máximo 60s en plan gratuito).

### Error de chain bootstrap

Verificar que:
- `CHAIN_ID` sea correcto (98867 para testnet, 98866 para mainnet)
- `PLUME_RPC_URL` sea accesible desde Vercel
- Los contratos estén desplegados en la chain especificada

## Notas importantes

1. **Vercel Functions tiene límites**:
   - Duración máxima: 60s (plan gratuito: 10s)
   - Memoria: 1024 MB
   - Cold starts: ~1-2 segundos

2. **El backend usa Hono** que es compatible con Vercel Functions

3. **Variables de entorno**:
   - Nunca commitear archivos `.env`
   - Usar `.env.example` como documentación
   - Configurar variables en el dashboard de Vercel

4. **Monorepo**:
   - Vercel detecta automáticamente pnpm workspaces
   - Asegurarse de que `pnpm-lock.yaml` esté en el root

## Próximos pasos

- [ ] Configurar dominio custom (opcional)
- [ ] Configurar preview deployments para PRs
- [ ] Agregar monitoring y alertas
- [ ] Configurar CI/CD automático