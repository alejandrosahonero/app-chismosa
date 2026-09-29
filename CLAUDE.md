# CLAUDE.md — Guía del proyecto para agentes de IA

> **Contexto obligatorio.** Este repositorio es **Chismosa**, una app Android de historias anónimas en formato mazo deslizable estilo Tinder: cada carta es un chisme corto que alguien del mundo ha subido; deslizar hacia arriba te mete en el hilo de conversación de esa historia. Freemium: AdMob + un pago único premium.
>
> El proyecto nació como *Ajá: Datos Curiosos Raros*. De aquello quedan el motor del mazo (`core/widgets/deck`) y la monetización. Los objetivos y rangos se borraron: en una app de historias no aportaban nada. El catálogo de datos, los favoritos y la pregunta del día se borraron.
>
> La fuente de verdad arquitectónica es `GUIA_ESTANDAR_FLUTTER_ANDROID.md` (documento del usuario, fuera del repo). Este archivo explica **qué** hay, **cómo** funciona y **por qué**. Ante un conflicto, manda la guía estándar. El backend está documentado en `supabase/README.md`.

---

## 0. Reglas no negociables

1. **Stack fijo:** Flutter stable, Dart 3.x, target **Android**. iOS no se implementa salvo orden explícita.
2. **Nunca fijar versiones de paquetes de memoria.** `flutter pub add <paquete>`.
3. **Ninguna dependencia nueva sin justificación** de peso e impacto en el arranque, escrita en el `pubspec.yaml`.
4. **Herramientas totalmente gratuitas.** Nada que exija tarjeta o plan de pago (por eso Supabase free y no Firebase Blaze; FCM sí, que es gratis).
5. **Idioma:** código y comentarios en **inglés**; UI en **español + inglés** (`.arb`).
6. **Antes de cerrar cualquier tarea:**
   ```bash
   dart format lib test && flutter analyze && flutter test
   ```
   `flutter analyze` debe terminar con *No issues found!*.
7. **Prohibido:** `print`, `setState` en widgets con lógica no trivial, `FutureBuilder` anidado, `ListView(children: [...])` con colecciones dinámicas.
8. **`const` siempre que sea posible.**

### 0.1 Anonimato — la regla que manda sobre todas

**El id global de una cuenta (`auth.uid()`, `author_id`, `user_id`, `owner_id`) no llega nunca a un cliente que no sea su dueño.** Ni en una carta, ni en un mensaje, ni en un grupo. Todo lo que el cliente lee de otros pasa por funciones `security definer` que eligen columnas a mano, y las tablas con ids ajenos están cerradas a `anon`/`authenticated`.

Consecuencias que parecen raras y son a propósito:

- Un mensaje de Realtime trae `member_id`, no una cuenta; el alias se resuelve con `thread_aliases()`.
- El alias es **distinto en cada hilo**. El mismo alias en dos hilos permite seguir a una persona.
- **Bloquear** se hace nombrando una historia o un mensaje (`block_story_author`, `block_message_author`); el servidor resuelve la cuenta. Por eso no hay lista de bloqueados, solo un número y «desbloquear a todos».
- Un grupo muestra **cuántos** miembros tiene, nunca quiénes.

Si una feature nueva necesita saber quién es quién en el cliente, la feature está mal planteada.

### 0.2 Nadie localizable

Además de no revelar cuentas, **no se deja publicar lo que convierte una historia en acoso a una persona real**: teléfonos, emails, @usuarios y enlaces se rechazan en servidor (`contains_personal_data`, 0007) en historias, mensajes y nombres de grupo. Los nombres propios no se pueden filtrar con una expresión regular; para eso están las normas, los reportes y la bienvenida. Todas las apps anónimas que cerraron (Secret, Yik Yak, Whisper) cerraron por esto. No relajar el filtro sin sustituirlo por algo mejor.

### 0.3 Secretos

- En la app solo va la **publishable key** de Supabase (`core/config/backend_config.dart`).
- La `service_role` key, la cuenta de servicio de Firebase y `PUSH_SECRET` viven **solo** como secretos de las Edge Functions. Nunca en el repo, nunca en la app.
- La cadena de conexión directa a Postgres no se escribe en ningún fichero.

### 0.4 Identidad — inmutable tras publicar

| Cosa | Valor |
|---|---|
| Paquete Dart | `chismosa` |
| `applicationId` / `namespace` / paquete Kotlin | `com.alejandrosahonero.chismosa` |
| `android:label` | `Chismosa` |
| Deep link | `chismosa://app/...` (el host es relleno: go_router solo ve el path) |
| Producto IAP | `premium_remove_ads` |
| Seed color | `0xFFC026D3` |

---

## 1. Arquitectura

**Clean Architecture simplificada de 3 capas + feature-first.**

```
lib/
├── main.dart / bootstrap.dart / app.dart
├── core/
│   ├── config/        # AppConfig, AdConfig, BillingConfig, BackendConfig
│   ├── routing/       # go_router: rutas, nombres, navigator key
│   ├── theme/ extensions/ utils/ errors/
│   └── widgets/
│       ├── deck/      # SwipeDeck genérico (DeckCard, umbrales, progreso, tarjeta de anuncio)
│       └── ...        # BaseScreen, ConfirmDialog, EmptyState, ErrorView...
├── features/
│   ├── stories/       # el mazo, escribir, normas
│   ├── threads/       # hilos en vivo (hoja sobre el mazo + historial)
│   ├── groups/        # mazos privados por invitación
│   ├── settings/      # ajustes, cuenta y código de recuperación, idiomas
│   └── premium/       # paywall
├── services/
│   ├── backend/       # cliente Supabase + sessionEpoch
│   ├── identity/      # cuenta anónima + código de recuperación
│   ├── moderation/    # bloquear
│   ├── push/          # FCM
│   ├── locale/        # país del dispositivo + idiomas del mazo
│   ├── ads/ billing/ review/ storage/
└── l10n/
supabase/
├── migrations/        # 0001…0010, se ejecutan en orden en el SQL Editor
└── functions/         # admob-ssv, thread-push (Deno)
```

**Regla de dependencia:** `presentation` → `domain` → `data`. Cada feature es autocontenida y borrable. **No crear carpetas vacías.**

**Las reglas viven en Postgres, no en la app.** Límite diario, filtro de palabras, baneo, ocultar por reportes, pertenencia a grupos, cierre de hilos inactivos: todo son triggers y funciones. El cliente repite algún límite solo para avisar antes; un límite que solo aplica el cliente es un límite que no existe. Los errores llegan como texto (`raise exception 'daily_limit_reached'`) y cada repositorio los traduce a un enum (`StoryFailure`, `GroupFailure`).

---

## 2. Gestión de estado — Riverpod 3

| Necesidad | Provider |
|---|---|
| Servicio / dependencia | `Provider` |
| Estado síncrono mutable | `NotifierProvider` |
| Estado asíncrono mutable | `AsyncNotifierProvider` |
| Lectura asíncrona de solo lectura | `FutureProvider(..., isAutoDispose: true)` |

- **Escritos a mano, sin `riverpod_generator`**: sus versiones de `analyzer` chocan con las de `flutter_test` y `pub` no resuelve. Cuando se pueda, migrar a `@riverpod`.
- **Sin families.** Lo que depende de un parámetro va en un notifier con estado (`feedQueryProvider`, `threadControllerProvider`).
- **Los repositorios son `null` mientras no hay cliente** (el backend arranca después del primer frame) y todas las pantallas lo toleran.
- **`sessionEpochProvider`**: todos los repositorios lo observan. Al restaurar otra cuenta con su código se incrementa, y todo lo construido sobre la cuenta anterior se tira y se reconstruye.
- `ref.read` en callbacks, `ref.watch` solo en `build`, `select` para observar solo lo que se pinta.

---

## 3. El mazo (`features/stories` + `core/widgets/deck`)

| Gesto | Efecto |
|---|---|
| **Derecha** | Me gusta. La carta se va. |
| **Izquierda** | Pasar. |
| **Abajo** | **Compartir** la historia como imagen 1080x1920 (`StoryShareImage`) con enlace https a su hilo. La carta se queda. Exige recorrido: nunca por un pulgar que resbala. Las historias de un grupo no se comparten fuera. |
| **Arriba** | **Entrar al hilo.** La carta se queda; la hoja del hilo sube siguiendo al dedo. |
| **⋮ en la carta de arriba** | Reportar / bloquear a quien lo escribió. En un menú y no en un gesto: reportar no puede pasar porque se escape el pulgar. |

Los botones inferiores repiten los gestos y **no son decorativos**: una interfaz solo de arrastre es inutilizable con lector de pantalla.

- `SwipeDeck` es genérico (`DeckCard`), **solo posee el gesto** y notifica hacia arriba. `dismissOn` dice qué direcciones consumen la carta; `DeckThresholds` cuánto hay que recorrer. El estado del mazo vive en `StoriesDeckController` y se testea sin animaciones.
- `DeckSwipeProgress` (un `ValueNotifier`, no `setState`: cambia cada frame) alimenta los botones que crecen, las insignias y el asomo de la hoja del hilo.
- **La hoja del hilo es un solo movimiento continuo**: mientras se arrastra, el arrastre escribe directamente en el `AnimationController` (asoma hasta el 45 %); al confirmar, `animateTo(1)` sigue desde donde lo dejó el dedo.
- **Ranking «hot»**: likes por hora con decaimiento (estilo Hacker News), calculado en `feed()`. Alternativa «nuevas».
- **Cada carta se reparte una vez.** Las vistas se guardan en el dispositivo (`SeenStoriesStore`) y la cola se envía como pista al servidor; no hay tabla de vistas en Postgres (usuarios × historias se comería los 500 MB del plan gratis).
- **El mazo nunca muestra al autor sus propias historias.**
- **El mazo arranca en el país del móvil.** Cuando se acaba, la pantalla de fin ofrece primero «Ampliar a todo el mundo». Lanzamiento en España, México y Bolivia: mejor cuarenta historias del propio país que las mismas cuarenta repartidas en tres.
- Filtros en una fila de chips: **qué mazo** (mundo o grupo), «Me gustaron» (el único modo que vuelve a repartir cartas ya vistas; ignora país, categoría e idioma), orden, mi país, categoría. Categorías genéricas más «cualquiera». Idiomas del mazo en Ajustes; el país sale del dispositivo, nunca de GPS.
- **No reintroducir un indicador de «cuánto queda».** El anillo del objetivo cuenta hacia arriba y no dice nada del mazo.

### 3.1 Escribir

- 20–600 caracteres, solo texto, una categoría.
- **Tres historias al día** (`cfg('stories_per_day')`). Más con un anuncio recompensado (§5) o sin límite con premium. La pantalla dice cuántas quedan (`publish_status()`).
- Se publica **en el mazo en el que estabas**: desde un grupo, solo lo ve el grupo, y la pantalla lo avisa.
- Normas de la comunidad en `/rules`, enlazadas desde escribir y desde Ajustes.

---

## 4. Hilos, grupos, moderación, push

**Hilos (`features/threads`).** Entrar es unirse: no hay botón «unirse». Alias asignado por el servidor, único dentro del hilo, distinto en cada hilo. Realtime con **un canal por hilo abierto** (el plan gratis da 200 conexiones simultáneas; no abrir canales para hilos que no están en pantalla). Envío optimista: el mensaje se pinta como pendiente y se quita si falla. Los hilos inactivos se cierran solos. `/threads` es el único sitio donde una historia se puede volver a encontrar.

**Grupos (`features/groups`).** Un grupo es otro mazo, privado. Se entra con un código de invitación (12 hex) que caduca a los 7 días y que el creador puede **renovar** para matar un enlace filtrado. Sin límite de miembros; todas las demás protecciones aplican. El creador no puede salir, solo borrar (siempre hay alguien que puede renovar). Salir de un grupo quita también el acceso a sus hilos. `join_thread`/`story_detail` comprueban la pertenencia: una historia de grupo no se abre con su id desde fuera. **Un enlace de invitación nunca une a nadie sin un toque.**

**Moderación: mínima a propósito.** Reportar (con motivo) y bloquear. Tres reportes ocultan el contenido solo; tres contenidos ocultos banean la cuenta. **Excepción: «Señala a alguien»** oculta al instante (máximo 5 usos por persona y día), avisa al autor por push de que está en revisión, y **requiere una revisión humana diaria** con `tool/moderation.sql` (`review_content`). Si nadie revisa, el aviso al autor es mentira.

**Push (`services/push` + `functions/thread-push`).** Un trigger manda el id de cada mensaje por `pg_net` a la Edge Function, que decide a quién avisar: no al autor, no a quien silenció el hilo, nada entre personas bloqueadas, y **un aviso por hilo hasta que se abre**. La app solo registra el token (`register_device`, que mueve el token a la cuenta que usa el móvil ahora), abre el hilo al tocar, y en primer plano enseña un snackbar salvo que ya estés en ese hilo.

**`POST_NOTIFICATIONS` se pide una sola vez, justo después del primer mensaje del usuario en un hilo**, o desde la fila de Ajustes. Nunca al arrancar: Android enseña ese diálogo una vez y recuerda el «no».

**Capítulos.** Una historia se puede continuar desde «Mis historias» (una continuación por historia: una saga es una línea). La parte nueva va al mismo grupo que la anterior, lleva la píldora «Parte N» y avisa por push a quien entró en el hilo de la parte anterior. En el hilo hay enlaces a la parte anterior y a la siguiente.

**Bienvenida (`features/welcome`).** Qué es, los gestos, las normas, 16+ y aceptación explícita. El router redirige ahí mientras `welcome_done` sea falso: no se llega a nada sin haber aceptado, tampoco por deep link.

---

## 5. Cuenta anónima

- Auth anónima de Supabase. Sin email ni contraseña.
- Una cuenta por persona. El secreto se deriva de un **código de recuperación** (`CHM-XXXX-…`, 120 bits) guardado en el directorio de soporte, que Auto Backup restaura al reinstalar.
- **Un móvil a la vez; varios con Premium** (`0009`, `InstallClaim`). Cada instalación tiene un id aleatorio en preferencias. Al arrancar, al volver al primer plano y al recuperar una cuenta, `claim_install` dice si este móvil puede usarla; si otro la tiene y no es premium, el router lleva a `/moved`, que ofrece **traerla aquí (gratis, el otro móvil la pierde)** o Premium para usarla en los dos. Mover la cuenta nunca se cobra: un móvil perdido no puede dejar a nadie sin su cuenta. Si no se puede preguntar al servidor, se deja pasar.
- **Borrar mi cuenta** (Ajustes, lo exige Google Play): `delete_my_account()` borra la fila de `auth.users` y todo cae en cascada; el móvil sigue con una cuenta nueva y vacía (la app no tiene estado «sin sesión»). El secreto local solo se borra si el servidor confirmó.
- **Recuperar una cuenta con su código es Premium.** Sin Premium, el diálogo lleva al paywall («Ya lo compré» trae la compra al móvil nuevo con la misma cuenta de Google). La pantalla `/moved` (otro móvil tiene la cuenta) sigue siendo gratis.
- El código solo se enseña en Ajustes, detrás de un toque. Restaurar otra cuenta incrementa `sessionEpoch` y re-registra el token de push.

---

## 6. Monetización

- **Tarjeta de anuncio dentro del mazo** = formato principal (`adCardEveryNCards` = 6, nunca menos de 5; el mazo no termina en un anuncio). El `AdWidget` se monta **solo en `depth == 0`**; la petición sale una carta antes. Etiqueta «Publicidad» siempre visible.
- **Banner en línea arriba del mazo, nunca abajo**: abajo está el gesto y sería el clic accidental de manual.
- **Interstitial apagado en el lanzamiento** (`AppConfig.interstitialsEnabled = false`): un anuncio a pantalla completa en mitad de una confesión espanta. Reactivar solo con la retención D7 medida; el pacing (9 acciones y 3 min) sigue en el código.
- **Rewarded solo para publicar una historia más.** El crédito lo concede el servidor (`functions/admob-ssv`, verificación SSV con firma ECDSA de Google, idempotente por `transaction_id`). La app nunca concede nada; espera al crédito consultando `publish_status()`. La unidad de prueba de Google no llama a la URL: en debug el crédito no llega.
- **Premium (`premium_remove_ads`, pago único)**: sin anuncios y sin límite de publicación. **Lo decide Google a través del servidor**: cada compra y cada restauración pasan por `functions/verify-purchase` (API de Play Developer), que es lo único que puede escribir `profiles.is_premium`. Si el servidor no responde al comprar, premium provisional; el token cacheado se reverifica en cada arranque, que es como un reembolso acaba quitándolo. Reglas y tests en `premium_controller.dart` / `premium_controller_test.dart`. Protocolo de prueba obligatorio antes de lanzar en `supabase/README.md`.
- **Historias «de la casa»** (`profiles.is_house`, `tool/seed_house_stories.sql`): diez en el lanzamiento, con la píldora «De la casa». Nunca inventar historias y hacerlas pasar por usuarios.
- **Enlaces https** (`LinksConfig`, `site/`): `/s/<id>` y `/g/<código>` en `chismosa-app.github.io`, verificados con App Links. `chismosa://` queda solo como respaldo interno: no se puede tocar en WhatsApp.
- **Usuarios**: `tool/stats.sql` (cuentas, activos 24 h / 7 d / 30 d por `last_seen_at`, por país).
- IDs de prueba en debug, producción en release (`AppConfig.useProductionAds == kReleaseMode`). Un ID vacío desactiva el formato. **Nunca IDs de producción en debug.**
- UMP antes del primer anuncio; «Opciones de privacidad» en Ajustes cuando UMP lo exige. «Restaurar compras» visible en Ajustes y en el paywall. `completePurchase()` siempre.

---

## 7. Pantalla principal

**Mínima a propósito** (feedback de testers: «saturada de botones»). App bar: menú hamburguesa (`core/widgets/app_drawer.dart`: escribir, mis historias, mis hilos, grupos, premium, normas, ajustes) y el nombre. Encima del mazo, como mucho tres chips: el grupo abierto (con ✕ para volver al mundo), «Me gustaron» y «Filtros» (hoja con orden, país y categoría; el chip cuenta los activos). Debajo, tres botones: pasar, hilo, me gusta. Compartir está en el gesto hacia abajo y en el ⋮ de la carta. **Agitar** el móvil devuelve la última carta pasada (`ShakeDetector`). Las historias largas se cortan con «Ver más», que abre el hilo: nada se desplaza dentro de la carta.

---

## 8. Navegación y arranque

- Rutas en `core/routing`, **nunca un path literal en una pantalla**. `rootNavigatorKey` para código fuera del árbol (push, anuncios, compras).
- Antes de `runApp`: solo `ensureInitialized`, `SharedPreferences` y el registro (perezoso) de las licencias OFL de las fuentes. **Primer frame < 2 s en gama media.**
- Después del primer frame, cada paso con su `try/catch`: backend + sesión + locale → push → premium (y su espejo en el perfil) → anuncios.
- `main.dart` no contiene lógica.

---

## 9. Reseñas, tema, Android

- `in_app_review` con guardas (5 acciones de valor, 3 días de instalación, 120 días entre peticiones). Se pide **solo al entrar a un hilo**.
- **Marca: «Rojo sangre»**, elegida por el dueño tras varias rondas de maquetas (`core/theme/app_colors.dart`): Granate `#4A0000` (cabecera en ambos temas, bienvenida, imagen de compartir, fondo del icono), Sangre `#880808` (primario, me gusta, comilla, píldoras), Tinta `#1E0B0B`, Hueso `#F4EFEA` (fondo), Papel `#FFFFFF` (tarjeta), Polvo `#C9A9A0`. En oscuro el primario sube a `#FF6B63`, porque Sangre no se lee sobre casi negro. **Sin color dinámico** (Material You). Logo «la burbuja cómplice» en hueso sobre granate; maestro en `brand/logo.svg`. No volver a paletas crema + coral + lima: los usuarios la señalaron como «hecha por IA».
- **Tipografía:** Onest (todo lo que se lee) y Bricolage Grotesque (títulos, bienvenida, imagen de compartir), empaquetadas en `assets/fonts` con sus licencias OFL. `AppFonts` en `app_theme.dart`. Nunca `google_fonts` en tiempo de ejecución: el primer frame no espera a la red.
- `tool/screenshots/screenshots_test.dart` pinta las pantallas principales con fuentes reales (`flutter test tool/screenshots/screenshots_test.dart --update-goldens`). Mirarlas tras cualquier cambio visual: así se encontró el FAB tapando el botón de «Me gusta».
- `AppSpacing`/`AppRadius`, nada de paddings a pelo. Toda pantalla sobre `BaseScreen`.
- `compileSdk = 37`, `minSdk = 24`, R8 + shrink en release. Firma desde `key.properties` (git-ignored). Sin flavors ni `--dart-define`.
- `google-services.json` está en el repo: solo lleva identificadores públicos del proyecto Firebase, no secretos.
- Revisar el manifiesto fusionado tras cada cambio de dependencias.

---

## 10. Comandos

```bash
flutter run
dart format lib test && flutter analyze && flutter test
flutter build appbundle --release --obfuscate --split-debug-info=build/symbols/1.0.0
```

Guardar `build/symbols/<versión>` fuera del repo.

---

## 11. Pendiente

**Pasos a mano en el backend**: lista en `supabase/README.md` → «Pendiente».

**Antes de publicar:**
1. ~~IDs de AdMob~~: app «Chismosa» (`ca-app-pub-4073049276319773~8299493462`) con banner, intersticial y recompensada (SSV verificada contra `admob-ssv`); `site/app-ads.txt` publicado. Falta vincular la app de AdMob a la ficha de Play cuando esté publicada.
2. Validar el token de compra de Play en servidor antes de fiarse de `is_premium`.
3. Iconos adaptativos y splash nativo.
4. ~~Crash reporting~~: **Sentry** integrado con su DSN (`core/config/crash_config.dart`, reenviado desde `AppLogger.error`, solo en release). Nunca Crashlytics.
5. Política de privacidad: `site/privacidad.html` → `https://chismosa-app.github.io/privacidad.html`. Contacto: `chismosa.app@gmail.com`. Borrar la cuenta: Ajustes → «Borrar mi cuenta» (`delete_my_account`, 0010; todo cae en cascada desde `auth.users`) o por email. Data Safety: **contenido generado por usuarios**, ID de publicidad, token de push; clasificación de contenido con UGC y moderación declarada.
6. App Links `https` en GitHub Pages (`chismosa-app.github.io`, `site/README.md`): falta publicar y añadir la huella de Play App Signing a `assetlinks.json`.
7. Testing cerrado (12 testers / 14 días) → producción con rollout escalonado.
8. Firma: `android/upload-keystore.jks` + `android/key.properties` (git-ignored). **Copia de seguridad de los dos** fuera del ordenador: sin ellos no se pueden subir actualizaciones sin pasar por el soporte de Google.

**Producto:** capítulos (historias en varias partes), al final.

---

## 12. Definición de «hecho» para una release

- [ ] `flutter analyze` limpio, `dart format` aplicado, tests pasando.
- [ ] Probado en dispositivo físico de gama baja en **release** (R8).
- [ ] Gestos del mazo con `textScaleFactor` alto y pantalla pequeña.
- [ ] Hilo con dos móviles: mensajes en vivo, push con la app cerrada y abierta, silenciar, bloquear.
- [ ] Grupo: crear, invitar, unirse por código y por enlace, renovar, salir, borrar.
- [ ] Límite diario, anuncio recompensado con la unidad real, premium y restaurar.
- [ ] Reinstalar y comprobar que la cuenta vuelve; restaurar con el código en otro móvil.
- [ ] Sin IDs de prueba de AdMob ni logs de debug en producción; `versionCode` incrementado; símbolos archivados.
