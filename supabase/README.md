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
   - `migrations/0005_groups.sql`
   - `migrations/0006_push.sql`
   - `migrations/0007_safety_and_chapters.sql`
   - `migrations/0008_launch.sql`
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

## Notificaciones push (mensajes nuevos en tus hilos)

Un trigger manda el id de cada mensaje nuevo a la Edge Function `thread-push`
(por `pg_net`), y la función decide a quién avisar y envía por FCM. Gratis: FCM
no cobra y la función cabe de sobra en el plan free.

1. Firebase Console → Configuración del proyecto → Cuentas de servicio →
   **Generar nueva clave privada**. Descarga un JSON. **No lo metas en el repo.**
2. Inventa un secreto largo (por ejemplo `openssl rand -hex 32`).
3. SQL Editor:
   ```sql
   select vault.create_secret('https://sbeyvzhtvmzcalflqajv.supabase.co/functions/v1/thread-push', 'push_function_url');
   select vault.create_secret('<el secreto>', 'push_secret');
   ```
4. Terminal (fuera del repo, con el JSON en una sola línea dentro de un fichero
   `.env` temporal: `FCM_SERVICE_ACCOUNT=<json>`):
   ```
   npx supabase secrets set PUSH_SECRET=<el secreto>
   npx supabase secrets set --env-file ruta/al/.env
   npx supabase functions deploy thread-push --no-verify-jwt
   ```
   Borra el `.env` después.

Sin los dos secretos del Vault el trigger no hace nada y los mensajes siguen
funcionando igual.

Reglas: un aviso por hilo hasta que lo abras (no cuarenta en una noche), nunca
a quien escribió, nunca a quien lo tiene silenciado, y nada entre personas que
se han bloqueado. El permiso de notificaciones se pide una sola vez, justo
después de tu primer mensaje en un hilo.

## Compras premium verificadas (`verify-purchase`)

Premium solo lo concede el servidor: la app manda el token de compra a
`verify-purchase`, que lo comprueba con la API de Google Play y actualiza
`profiles.is_premium` (la app ya no puede escribir esa columna). Pasos, todos
gratis, en la cabecera de `functions/verify-purchase/index.ts`. Resumen:

1. Play Console → Configuración → Acceso a la API → vincular un proyecto de
   Google Cloud.
2. En ese proyecto: cuenta de servicio + clave JSON.
3. Play Console → Usuarios y permisos → invitar el email de la cuenta de
   servicio con «Ver información de la app» y «Ver datos financieros» (puede
   tardar hasta 24 h en aplicarse).
4. `npx supabase secrets set --env-file <.env con PLAY_SERVICE_ACCOUNT=<json>>`
5. `npx supabase functions deploy verify-purchase` (con verificación de JWT).

**Probarlo antes de lanzar, sin excepción** (con una cuenta de «tester con
licencia» en Play Console, que compra sin pagar):

- [ ] Comprar → la app quita anuncios y `select is_premium from profiles` da `true`.
- [ ] Publicar más de 3 historias en un día con esa cuenta.
- [ ] Desinstalar, reinstalar, restaurar la cuenta con el código → sigue premium.
- [ ] «Restaurar compras» en Ajustes funciona en una cuenta nueva del mismo Google.
- [ ] Reembolsar la compra de prueba en Play Console → al abrir la app, deja de ser premium.
- [ ] Sin conexión en el momento de comprar → premium provisional, y se confirma al volver la red.

## Pendiente

### Pasos a mano todavía sin hacer

- [ ] Ejecutar en el SQL Editor, en orden: `0004_moderation.sql`,
      `0005_groups.sql`, `0006_push.sql`, `0007_safety_and_chapters.sql`,
      `0008_launch.sql`, `0009_devices_premium.sql`, `0010_delete_account.sql`, `0011_names_and_group_rules.sql`.
- [ ] Después, `tool/seed_house_stories.sql` (borra las demo y la historia
      basura, publica las 10 de la casa).
- [ ] Desplegar las Edge Functions: `admob-ssv`, `thread-push` y
      `verify-purchase` (`npx supabase login`,
      `npx supabase link --project-ref sbeyvzhtvmzcalflqajv`, y un
      `npx supabase functions deploy <nombre>` por cada una; `admob-ssv` y
      `thread-push` con `--no-verify-jwt`).
- [ ] Secretos: los de push (sección de arriba) y `PLAY_SERVICE_ACCOUNT`.
- [x] Crear la unidad recompensada en AdMob con SSV apuntando a
      `https://sbeyvzhtvmzcalflqajv.supabase.co/functions/v1/admob-ssv` y poner
      su id en `_prodRewarded` (`lib/core/config/ad_config.dart`).
- [ ] Publicar `site/` en GitHub Pages como `chismosa-app.github.io` y añadir
      la huella de Play App Signing a `assetlinks.json` (ver `site/README.md`).
- [ ] Rotar la contraseña de Postgres.
- [ ] Activar `pg_cron` (cierra los hilos inactivos).
- [ ] Revisar a diario `tool/moderation.sql` una vez haya usuarios.

### Por construir

- Rellenar `banned_words`. Está vacía a propósito: una lista mal elegida bloquea
  conversaciones legítimas, y el filtro real es el umbral de reportes.
- Notificaciones en tiempo real de Play (Pub/Sub) para enterarse de un
  reembolso al momento; hoy se detecta en el siguiente arranque de la app.
