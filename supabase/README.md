# Backend de Chismosa

Supabase, plan gratuito, sin tarjeta. Este directorio es la fuente de verdad del
esquema: **nada se toca a mano en el dashboard**, porque un cambio hecho ahí no
tiene diff, no tiene historial y no se puede volver a aplicar en otro proyecto.

## Por qué Supabase y no Firebase

Desplegar Cloud Functions exige el plan Blaze, que pide tarjeta. Sin funciones no
hay moderación automática, ni límite de publicación fiable, ni envío de push, y
entonces ya no es gratis. El plan gratuito de Supabase incluye Edge Functions y,
sobre todo, Postgres con RLS: el límite de una publicación al día, el ocultar por
reportes y los bloqueos son reglas del servidor, no promesas del cliente.

El techo real del plan gratuito son **200 conexiones Realtime simultáneas**. Por
eso solo se suscribe el hilo que está abierto en pantalla; el mazo son consultas
normales.

## Puesta en marcha

1. Crear un proyecto en [supabase.com](https://supabase.com) (gratis).
2. **Authentication → Providers → Anonymous sign-ins: activar.**
3. **Authentication → Providers → Email: desactivar "Confirm email".**
   El código de recuperación convierte la cuenta anónima en una cuenta con
   correo y contraseña derivados; el dominio (`chismosa.invalid`) no existe a
   propósito y nunca va a recibir un mensaje de confirmación.
4. SQL Editor → ejecutar en orden:
   - `migrations/0001_initial.sql`
   - `migrations/0002_logic.sql`
   - `migrations/0003_rls.sql`
   - `migrations/0004_moderation.sql`
5. Settings → API → copiar *Project URL* y la clave *publishable* en
   `lib/core/config/backend_config.dart`.

Con la config vacía la app compila y funciona en modo sin conexión, así que el
paso 5 se puede dejar para el final.

## Lo que hace el esquema y que no se ve leyendo las tablas

- **El `user_id` global nunca sale del servidor.** Un mensaje apunta a la
  *pertenencia al hilo* (`thread_members.id`), no a la cuenta, y ni `feed()` ni
  `story_detail()` devuelven `author_id`. Si eso se rompiera, en un grupo de seis
  amigos bastaría cruzar el mazo con la lista de miembros para ponerle nombre a
  cada chisme.
- **Los alias son por hilo y únicos dentro de él.** La misma persona es un
  personaje distinto en cada conversación.
- **Las cartas vistas no se guardan aquí.** Una fila por (usuario, historia)
  crece como usuarios × catálogo y se comería los 500 MB del plan gratuito; la
  lista vive en el móvil y al `feed()` solo se le manda la cola como pista.
- **La moderación no tiene cola ni panel.** Tres reportes ocultan; tres
  contenidos ocultos banean. Nadie revisa nada.
- **`post_credits` no es escribible por el cliente.** Un crédito que el móvil
  puede fabricar es un límite que no existe: los concede la verificación
  *server-side* de AdMob contra una Edge Function.

## Mantenimiento

`close_stale_threads()` cierra los hilos sin actividad en 14 días. Programarla
una vez al día con pg_cron:

```sql
select cron.schedule('close-stale-threads', '0 4 * * *', $$select public.close_stale_threads()$$);
```

## Anuncio recompensado (publicar una historia más)

El crédito lo escribe la Edge Function `functions/admob-ssv` cuando Google la llama con un recibo firmado. La app solo lo lee: un crédito que el móvil pudiera concederse no sería un límite.

1. Instalar la CLI de Supabase y enlazar el proyecto:
   ```bash
   npx supabase login
   npx supabase link --project-ref sbeyvzhtvmzcalflqajv
   ```
2. Desplegar (sin JWT: quien llama es Google, que no tiene sesión; lo autentica la firma):
   ```bash
   npx supabase functions deploy admob-ssv --no-verify-jwt
   ```
3. AdMob → crear una unidad **Recompensado** → *Verificación del lado del servidor* → URL:
   `https://sbeyvzhtvmzcalflqajv.supabase.co/functions/v1/admob-ssv`
4. Poner el id de esa unidad en `_prodRewarded` (`lib/core/config/ad_config.dart`).

La unidad de prueba de Google no tiene callback, así que en debug el vídeo se ve pero **no llega crédito**. Para probar el circuito entero: la unidad real con tu móvil en `AdConfig.testDeviceIds`.

## Pendiente

- Edge Function que envía push por FCM al llegar un mensaje a un hilo.
- Validar el token de compra de Play antes de fiarse de `profiles.is_premium`.
- Rellenar `banned_words`. Está vacía a propósito: una lista mal elegida bloquea
  conversaciones legítimas, y el filtro real es el umbral de reportes.
