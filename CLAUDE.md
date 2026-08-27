# CLAUDE.md — Guía del proyecto para agentes de IA

> **Contexto obligatorio.** Este repositorio es **Ajá: Datos Curiosos Raros**, una app Android de datos curiosos en formato mazo deslizable estilo Tinder, con monetización freemium (AdMob + IAP "quitar anuncios").
>
> Nació de una plantilla base de Flutter; queda de ella toda la infraestructura (`core/`, `services/`), pero las features de demostración ya no existen. La fuente de verdad arquitectónica es `GUIA_ESTANDAR_FLUTTER_ANDROID.md` (documento del usuario, fuera del repo). Este archivo explica **qué** hay implementado, **cómo** funciona y **por qué** se decidió así. Ante cualquier duda o conflicto, manda la guía estándar.

---

## 0. Reglas no negociables

1. **Stack fijo:** Flutter stable, Dart 3.x, target **Android**. iOS no se implementa salvo orden explícita.
2. **Nunca fijar versiones de paquetes de memoria.** Usar `flutter pub add <paquete>` para que pub resuelva la última estable compatible.
3. **Ninguna dependencia nueva sin justificación** de peso e impacto en el arranque, escrita en el `pubspec.yaml`.
4. **Idioma:** código y comentarios en **inglés**; UI en **español + inglés** (archivos `.arb`). El **contenido** (preguntas y respuestas) no vive en los `.arb`, sino en `assets/data/facts.json`, con los dos idiomas dentro de cada entrada.
5. **Antes de cerrar cualquier tarea**, en este orden:
   ```bash
   dart format lib test && flutter analyze && flutter test
   ```
   `flutter analyze` debe terminar con *No issues found!*.
6. **Prohibido:** `print`, `setState` en widgets con lógica no trivial, `FutureBuilder` anidado, JSON pesado en el isolate principal, imágenes sin `cacheWidth`/`cacheHeight`, `ListView(children: [...])` con colecciones dinámicas.
7. **`const` siempre que sea posible.**

### 0.1 Identidad — inmutable tras publicar

| Cosa | Valor |
|---|---|
| Paquete Dart (`pubspec.yaml`) | `aja` |
| `applicationId` / `namespace` | `com.alejandrosahonero.aja` |
| Paquete Kotlin | `com.alejandrosahonero.aja` |
| `android:label` | `Ajá` |
| Deep link | `aja://` |
| Producto IAP | `premium_remove_ads` |
| Seed color | `0xFFC026D3` |

`applicationId` y el ID del producto IAP **no se pueden cambiar** después de la primera publicación sin perder las compras existentes.

---

## 1. Arquitectura

**Clean Architecture simplificada de 3 capas + feature-first.**

```
lib/
├── main.dart                 # solo llama a bootstrap(); sin lógica
├── bootstrap.dart            # init asíncrono dentro de runZonedGuarded
├── app.dart                  # MaterialApp.router (tema + rutas + l10n)
├── core/
│   ├── config/               # AppConfig, AdConfig, BillingConfig
│   ├── theme/                # colores, spacing, ThemeData, ThemeModeController
│   ├── routing/              # go_router: rutas y navigator key
│   ├── errors/               # AppException sellada
│   ├── extensions/           # BuildContextX (theme, l10n, snackbars)
│   ├── utils/                # AppLogger
│   └── widgets/              # BaseScreen, AdaptiveBannerAd, SectionCard,
│                             # EmptyState, ErrorView, AppLoader
├── features/
│   ├── facts/                # ← la app entera (mazo + favoritos)
│   │   ├── data/             # FactRepository (asset + overlay remoto),
│   │   │                     # RemoteCatalogService, FactShareService
│   │   ├── domain/           # Fact, FactCategory, DeckItem, buildDeck()
│   │   └── presentation/     # providers / screens / widgets
│   ├── goals/                # objetivo diario + rangos
│   │   ├── domain/           # DailyGoal, Rank, GoalsState, GoalEvent
│   │   └── presentation/     # GoalsController, anillo, pantalla, diálogo
│   ├── settings/presentation/
│   └── premium/presentation/ # paywall + diálogo de función bloqueada
├── services/
│   ├── ads/                  # AdsService + ConsentService (UMP) + providers
│   ├── billing/              # PremiumService + PremiumController + estado
│   ├── notifications/        # DailyQuestionService (pregunta del día) + providers
│   ├── review/               # ReviewService + providers
│   └── storage/              # KeyValueStore (prefs) + SecureStore + providers
└── l10n/                     # app_es.arb (plantilla) + app_en.arb
```

**Regla de dependencia:** `presentation` → `domain` → `data`. `domain` no conoce a nadie.
`facts/` y `goals/` son las únicas features con `domain/`, porque son las únicas con lógica de negocio real (composición del mazo y progreso; derivación del objetivo del día y umbrales de rango). `settings/` y `premium/` son triviales y solo tienen `presentation/`. **No crear carpetas vacías.**

**Cada feature es autocontenida y borrable.** Si un helper solo lo usa una feature, vive dentro de esa feature, nunca en `core/utils/`.

---

## 2. Gestión de estado — Riverpod

Estándar único: **Riverpod 3** (`flutter_riverpod`).

| Necesidad | Provider a usar |
|---|---|
| Servicio / dependencia | `Provider` |
| Estado síncrono mutable | `NotifierProvider` |
| Estado asíncrono mutable | `AsyncNotifierProvider` |
| Lectura asíncrona de solo lectura | `FutureProvider` (con `isAutoDispose: true`) |

Convenciones aplicadas en el repo:

- **Estados de UI con `sealed class`**, nunca booleanos sueltos. Ver `services/billing/premium_state.dart` (`PurchaseFlow`) y `features/facts/domain/deck_item.dart` (`DeckItem` → `FactItem` / `AdItem`). La dimensión carga/error la aporta `AsyncValue`.
- **`ref.read` dentro de callbacks; `ref.watch` solo en `build`.** Ejemplo: `AdsService` recibe `isPremium: () => ref.read(isPremiumProvider)`.
- **`select` para observar solo lo que se pinta.**
- **`autoDispose`**: en Riverpod 3 se activa con `isAutoDispose: true`. Los providers de servicios (`adsServiceProvider`, `premiumControllerProvider`, `routerProvider`, `factRepositoryProvider`) son **keepAlive a propósito** y cada uno lleva el comentario que lo justifica (anuncios precargados, suscripción al `purchaseStream`, pila de navegación, catálogo parseado).

### ⚠️ Desviación conocida: sin `riverpod_generator` / `riverpod_lint`

La guía pide codegen con `build_runner`. **No se pudo instalar**: `riverpod_generator` y `riverpod_lint` exigen versiones de `analyzer` incompatibles con las que `flutter_test` fija (`matcher` / `test_api`), y `pub` no resuelve.

Por eso **los providers están escritos a mano** con la API declarativa de Riverpod 3, que es equivalente y totalmente soportada. Cuando el ecosistema se actualice:

```bash
flutter pub add dev:build_runner dev:riverpod_generator dev:riverpod_lint dev:custom_lint
```

y migrar los providers a `@riverpod`. Añadir entonces `custom_lint` al `analysis_options.yaml`.

---

## 3. El mazo (feature `facts`)

### 3.1 Interacción

Una pila de tarjetas, una detrás de otra. Solo la de arriba responde al dedo.

| Gesto | Efecto |
|---|---|
| **Deslizar a la derecha** | La tarjeta **se voltea** y enseña la respuesta. Vuelve al centro, no se descarta. |
| **Deslizar a la izquierda** | La tarjeta **sale volando** y sube la siguiente. |
| **Deslizar hacia arriba** | **Guarda la tarjeta** en favoritos (premium, ver §3.7). También vuelve al centro: guardar no es motivo para dejar de leerla. |
| **Deslizar hacia abajo** | **Comparte la pregunta** como imagen 1080x1920 (§3.4). Gratis para todos. También vuelve al centro. |
| **Tocar la tarjeta** | Igual que deslizar a la derecha (voltear). |
| **Botones inferiores** | "Siguiente", "Compartir la pregunta", "Guardar" y "Ver respuesta". **No son decorativos**: una interfaz solo-arrastre es inutilizable con lector de pantalla y la penaliza el escaneo de accesibilidad de Play. No borrarlos. |

El eje dominante decide la acción: un arrastre de 200 px hacia arriba y 60 px a la izquierda es un guardado, no un descarte.

**Filtro de categoría: fila de chips** (`_CategoryChips`), arriba del todo y por encima del banner. Sustituye al `PopupMenuButton` que vivía en la barra superior: los chips cuestan alto que era de la tarjeta, pero enseñan las categorías sin abrir nada y cambiar de una es un toque en vez de tres. Siguen visibles en la pantalla de "te has quedado sin preguntas", que es justo donde cambiar de categoría es lo más útil que puede hacer el usuario. Volver a tocar el chip ya seleccionado **no** limpia el filtro: en una fila de filtros un toque significa "enséñame este".

`SwipeDeck` (`features/facts/presentation/widgets/swipe_deck.dart`) **solo posee el gesto**. Notifica hacia arriba y repinta a partir de `items`/`index`. El estado del mazo — posición, volteo — vive en `DeckController`, y por eso se puede testear sin animaciones.

Umbrales en `AppConfig`: `deckSwipeThreshold` (28 % del ancho), `deckSwipeUpThreshold` (16 % del alto) y `deckSwipeDownThreshold` (26 % del alto). `deckSwipeVelocity` (700 px/s) confirma el gesto sin recorrer la distancia — **salvo hacia abajo**, que además exige haber viajado: comparte eje con guardar y abre una hoja modal encima de la app.

**Feedback en vivo del arrastre.** `SwipeDeck` publica un `DeckSwipeProgress` (dirección + 0→1) en un `ValueNotifier`. Lo leen dos cosas, y por eso no pueden contradecirse:

- El **botón** correspondiente crece hasta 1,4x, se rellena con su tinte y sube de elevación. Solo uno a la vez: manda el eje dominante.
- Una **insignia** sobre la tarjeta, en el borde **opuesto** al gesto — skip a la derecha, voltear a la izquierda, guardar abajo, compartir arriba. El borde hacia el que se va la tarjeta se sale de pantalla y escondería el icono justo cuando confirma la acción.

La misma función decide qué se ilumina y qué se dispara al soltar. Durante el rebote la dirección se congela: `Curves.easeOutBack` se pasa del centro y el signo del arrastre se invierte unos frames, lo que sin eso haría parpadear el botón contrario al final de cada gesto.

Un `ValueNotifier` y no `setState` a propósito: cambia en cada frame de cada arrastre y solo deben repintarse los cuatro botones, no la pantalla.

El volteo es un `rotateY` con perspectiva (`setEntry(3, 2, 0.0012)`); a mitad de la animación se cambia la cara y se des-espeja la trasera con otro `rotateY(pi)`. Va dentro de un `RepaintBoundary` para no repintar las tarjetas de debajo.

### 3.2 Contenido

`assets/data/facts.json`: una entrada por tarjeta con `question` / `answer` / `detail` en `es` y `en`, más `category` y `source`.

- **Cada dato lleva fuente, y la fuente es un enlace que se abrió.** Las 85 entradas se verificaron una a una contra una página real: `sourceUrl` es ese enlace permanente y la app lo pinta como enlace clicable bajo la respuesta (`FactSourceLink`). Un "dato curioso" falso viral se convierte en reseñas de 1 estrella y en burla pública, así que la regla es dura: **una entrada sin URL comprobada no entra**, y hay un test (`fact_repository_test.dart`) que lo impide.
- **La cita de texto plano no vale como verificación.** El catálogo se escribió con ayuda de IA y varias de aquellas citas resultaron ser inventadas o no decir lo que se afirmaba: existía el organismo, existía la revista, pero la página no hablaba del tema. Si añades contenido con IA, la cita que produzca es una **pista**, no una fuente: hay que abrir la página.
- El contenido está localizado **en el asset**, no en los `.arb`, porque traducir o ampliar el catálogo no debe exigir una versión nueva — y porque ese mismo JSON vendrá luego de Firebase Remote Config o Firestore.
- `FactCategory` es un enum cerrado: una categoría desconocida en el JSON **revienta al parsear**, no pinta un chip vacío en producción.
- El parseo corre en un isolate aparte (`compute`) y se cachea en `FactRepository` durante toda la vida del proceso.
- **El orden del fichero es el orden que ve el usuario**: no hay barajado en ninguna parte. Por eso el catálogo va **intercalado por categoría** (cuerpo, ciencia, historia, lenguaje, y vuelta a empezar) en vez de agrupado: con el filtro en «Todas», un bloque de veinte tarjetas seguidas de la misma categoría se lee como si la app se hubiera quedado atascada. Al añadir contenido, mantener el intercalado.

### 3.3 Composición del mazo

`buildDeck(facts, withAds:)` intercala las tarjetas de anuncio:

- Un `AdItem` cada `AppConfig.adCardEveryNCards` (6) tarjetas de contenido. **Nunca bajar de 5.**
- **El mazo jamás termina en un anuncio**: cerrar la sesión con una tarjeta de publicidad se lee como un muro de pago.
- `withAds: false` si el usuario es premium → el mazo no reserva ni un hueco.

El progreso se persiste como **el conjunto de ids ya leídos** (`deck_seen_ids`), uno solo para toda la app, y el mazo contiene **únicamente cartas sin leer**: la de arriba es siempre el índice 0.

Guardar ids y no un índice resuelve dos cosas a la vez. Los huecos de anuncio se desplazan al comprar premium, y un índice guardado apuntaría a otra tarjeta. Y sobre todo: **los chips son cuatro vistas de un mismo catálogo, no cuatro mazos**. Un contador solo significa algo contra un orden concreto, así que con uno por filtro (`deck_facts_seen_<categoría>`, como estaba antes) terminarte «Ciencia» y pasar a «Todas» te repartía esas mismas cartas otra vez. Repartir una carta que el usuario acaba de leer es lo único que este mazo no puede hacer.

La lista viaja en `shared_preferences`, que se carga entera al arrancar (§10): con 533 entradas son unos diez kilobytes. Los ids de datos que un catálogo remoto haya retirado dejan de coincidir con nada y son inofensivos.

**«Reiniciar deck» solo revive las cartas del filtro activo.** Pulsarlo bajo el chip de «Ciencia» es pedir más ciencia, no ofrecerse a releer la historia que se terminó la semana pasada.

**La pantalla de fin de mazo** (`DeckExhaustedView`) es la única sin nada que deslizar, y ofrece tres salidas en orden decreciente de lo que devuelven:

1. **«Reiniciar deck»** — rebaraja y vuelve a empezar. Rebarajar y no rebobinar: quien llega al final y pulsa reiniciar está pidiendo más, y darle las mismas 85 cartas en el mismo orden es responderle que no. La semilla se persiste (`deck_shuffle_seed_<categoría>`) para que el orden nuevo sobreviva a cerrar la app y para que comprar premium a mitad de mazo no rebaraje las cartas bajo el usuario. La **primera** vuelta a una categoría siempre es el orden curado del fichero (semilla 0): barajar la primera sesión tira el único control editorial que hay sobre qué pregunta se encuentra primero.
2. **«Aportar»** — formulario de pregunta + respuesta + fuente opcional (§3.5).
3. **«Pedir más»** — ráfaga de corazones estilo Instagram y un contador. Es el único botón que no hace nada verificable para el usuario, y por eso justamente tenía que ser el que mejor sienta pulsar.

**El avance dentro del mazo no se enseña.** No hay barra ni contador «7/23»: la promesa del producto es un mazo que no se acaba, y un indicador que va vaciándose convierte la sesión en una tarea con final. El progreso se guarda para saber por dónde retomar, nada más. **No reintroducir un indicador de cuánto queda.**

> El anillo del objetivo diario (§3.8) **no es esto**, y conviene no confundirlos al leer código ajeno. Aquel cuenta hacia **arriba**, hacia un número que se reinicia mañana, y no dice absolutamente nada sobre cuántas cartas quedan en el catálogo. Lo que está prohibido es la cuenta atrás, no la idea de mostrar un número.

### 3.4 Compartir — imagen para historias

Deslizar hacia abajo (o el botón) renderiza la pregunta como PNG de **1080x1920** y la entrega a la hoja del sistema (`share_plus`). Es el tamaño nativo de una historia de Instagram, un Reel y un TikTok: se publica sin recorte ni recodificación.

- **Solo va la pregunta, nunca la respuesta.** La respuesta es el motivo para instalar la app; un post que la regala es un post que nadie tiene por qué seguir.
- **Gratis para todos**, a diferencia de favoritos. Una tarjeta compartida es la instalación más barata que va a tener esta app: ponerla tras el muro de pago sería cobrar por el marketing.
- Se pinta sobre un `Canvas` (`FactStoryImage`), **no** rasterizando un widget: tiene que medir 1080x1920 exactos sea cual sea el tamaño, la densidad y el tema del móvil, y un `RepaintBoundary` te da los píxeles del dispositivo.
- Todo lo legible vive dentro del **área segura**: las tres superficies pintan su propia interfaz sobre las franjas superior e inferior del lienzo.
- La tarjeta es de **tamaño fijo y la pregunta se encoge** para caber, no al revés: el marco constante es lo que hace que un feed de estas se lea como una serie. Pasado el mínimo (34 pt) corta la cola en vez de desbordar.
- La paleta sale de `AppColors.seed` y está **fijada al esquema claro**: rebrandear la app rebrandea lo compartido, y un post cuyo fondo cambia con el tema del lector parece de dos cuentas distintas.
- Un guardia impide que dos deslizamientos seguidos encolen dos hojas.

> **Al escribir tests:** el render pasa por el motor gráfico, así que **se cuelga bajo el reloj falso de `testWidgets`**. Hace falta un `test` normal o envolverlo en `tester.runAsync`.

### 3.5 Aportaciones de usuarios y «pedir más»

**Dónde van los datos: un web app de Google Apps Script que escribe en una hoja de cálculo.** La app no tiene backend y no va a criar uno por un buzón de sugerencias. Frente a Firestore (que significa `firebase_core` + `cloud_firestore`, un `google-services.json`, varios MB de AAB y trabajo en cada arranque en frío) esto es **una petición POST y cero SDK**; es gratis y ya está en la cuenta de Google del desarrollador; y la bandeja de entrada es una hoja de cálculo, que es justo la herramienta para ordenar, filtrar y marcar una sugerencia como «ya publicada». Si algún día entra Firestore para el catálogo (está en la hoja de ruta), mover esto es un fichero y un servicio.

Las instrucciones de montaje y el código del script están en `core/config/contribution_config.dart`.

- **Nada se pierde por no haber red.** Todo se escribe en disco *antes* de intentar enviarse: la red es una optimización, nunca lo que decide si la acción del usuario contó. Con `ContributionConfig.endpoint` vacío la app sigue funcionando igual y va acumulando en la bandeja local; la primera build con URL real vacía el atraso.
- **Los toques de «pedir más» se cuentan en local y viajan agregados.** El botón está para machacarlo: veinte toques son una petición con un número, no veinte peticiones.
- **La carga no lleva ningún identificador.** Ni ad id, ni install id, ni modelo de móvil. Es una decisión de producto: mantiene la declaración del Data Safety en «contenido de usuario, opcional, no vinculado a la identidad».
- **El endpoint es público y sin autenticar**, que está bien para un buzón de sugerencias y mal para cualquier otra cosa. Hay límite de longitud y un mínimo de 30 s entre envíos, pero **cada fila es texto no fiable**: no pegar nunca una aportación en el catálogo sin leerla.

> **Antes de publicar:** activar esto obliga a declarar contenido de usuario en el formulario de Data Safety y a mencionarlo en la política de privacidad.

### 3.6 Catálogo remoto — añadir preguntas sin publicar versión

**Un JSON estático en GitHub Pages, no Firebase.** El problema es estrecho: publicar más preguntas sin pasar por revisión. Remote Config y Firestore lo resuelven, y los dos cuestan `firebase_core` más un segundo SDK, un `google-services.json`, varios MB de AAB y trabajo en cada arranque en frío. Un fichero en un CDN cuesta **una petición GET y cero dependencias**, y como vive en un repo de git cada publicación de contenido es un commit con su diff y su historial — que es justo lo que quiere un catálogo curado a mano.

**Tres capas, y la red solo puede sumar:**

1. `assets/data/facts.json` dentro del APK. Es el suelo: instantáneo, offline, no puede fallar.
2. La última descarga buena, cacheada en disco (`getApplicationSupportDirectory`, no en prefs: las prefs se cargan enteras al arrancar).
3. La descarga de fondo, después del primer frame.

`mergeCatalogues` funde 1 y 2 al arrancar: **mismo id reemplaza en su sitio**, los ids de `removed` desaparecen, los ids nuevos se añaden al final.

**Que se pueda borrar un dato en remoto es la razón de tener esto desde el día uno**: el catálogo está verificado (§3.2), pero una fuente puede caerse, corregirse o resultar peor de lo que parecía, y entonces hay que poder matar la entrada hoy, no en la siguiente release.

**La descarga nunca se espera desde la UI y se aplica en el arranque siguiente.** Cambiar el catálogo a mitad de sesión movería las cartas que el usuario está leyendo. Se descarga, se valida, se escribe en disco, y la próxima vez que abra la app está.

**Ningún fallo de red puede dejar al usuario con menos preguntas de las que trae el APK.** Sin conexión, 404, cuerpo truncado o JSON corrupto acaban todos igual: se usa lo que ya había. El parser remoto es **tolerante a propósito**, al revés que el del asset: una categoría desconocida en el asset es un bug de compilación y debe reventar, pero el mismo error servido por red reventaría todas las copias instaladas a la vez, así que la entrada mala se descarta, se cuenta y el resto se conserva. Un remoto que dejara el catálogo vacío se ignora entero.

`If-None-Match` con el ETag guardado: un catálogo que no ha cambiado cuesta un 304 y cero parseo. Y una versión menor que la cacheada se rechaza, para que una copia rancia del CDN no haga rollback del contenido.

Configuración y pasos de publicación en `core/config/remote_catalog_config.dart`. El fichero se valida con `python3 tool/build_remote_catalog.py --check` **antes** de subirlo: comprueba las mismas reglas que aplica el parser de Dart, así que un error se ve ahí y no en cien mil móviles.

### 3.7 Favoritos — función de pago

Guardar tarjetas está detrás del **mismo pago único `premium_remove_ads`**. No hay un segundo producto: añadir SKUs multiplica el soporte y las combinaciones de entitlement que hay que probar.

- `favoritesProvider` guarda **ids**, no copias de las tarjetas: si un dato se reescribe en una actualización de contenido, el favorito sigue siendo correcto. Los ids que ya no existen en el catálogo se descartan en silencio.
- `canUseFavoritesProvider` está separado de `isPremiumProvider` aunque hoy devuelva lo mismo, para que desacoplarlo más adelante sea una línea.
- **La comprobación del entitlement vive en la UI**, no en `FavoritesController`. La rama del "no" tiene que abrir el paywall y eso necesita un `BuildContext`; duplicar la comprobación en el controller solo haría que las dos copias se separaran.
- Un usuario sin premium **sí puede hacer el gesto**: es así como descubre que la función existe. Sale un diálogo que explica qué desbloquea, con un "Ahora no" a un toque. **No saltar directamente al paywall**: secuestrar la pantalla tras un deslizamiento que pudo ser accidental se lee como una trampa.
- Los ids guardados **no se borran nunca** al perder el entitlement. Un reembolso o una reinstalación no deben destruir la lista; la pantalla se bloquea, los datos siguen ahí.

> **Ojo en Play Console:** la ficha del producto `premium_remove_ads` tiene que mencionar los favoritos. Vender "quitar anuncios" y usarlo además para desbloquear una función es motivo de reembolso y de reseña negativa si el usuario no lo sabía al pagar.

### 3.8 Objetivo diario y rangos

Dos sistemas encadenados: **cada día pide un número de datos**, y **cumplirlo da puntos que suben de rango**. Es lo único de la app que da una razón para volver mañana en concreto, en vez de "algún día".

**«Aprender» un dato es voltear la tarjeta y leer la respuesta.** No descartarla. Contar descartes llenaría el objetivo con todo lo que un usuario impaciente pasó sin mirar, y el anillo le diría que ha aprendido quince cosas que no ha leído. Es el mismo momento del que cuelga la petición de reseña (§7), por la misma razón: es lo único que el usuario viene a hacer aquí.

**El mismo dato solo cuenta una vez al día.** Voltear una tarjeta adelante y atrás no rellena nada. Pero un dato que vuelve a salir mañana **sí** cuenta otra vez: si no, un usuario veterano que ha rebarajado el mazo se quedaría con un objetivo imposible.

**El objetivo es función de la fecha y de nada más** (`DailyGoal.targetFor`). No hay servidor, así que lo único que impide re-tirar el dado de un objetivo incómodo es que cerrar y abrir la app no pueda cambiar la respuesta. De ahí que no se guarde: se recalcula.

- Los tamaños salen de `DailyGoal.sizes` (8, 10, 12, 15) y se reparten **en bloques de cuatro días barajados**, así que cada tamaño sale exactamente una vez cada cuatro días en lugar de "a menudo". Dos días seguidos nunca repiten número, y eso se garantiza mirando solo el bloque anterior — el arreglo intercambia las posiciones 0 y 1 y **nunca toca la última**, que es lo que impide que resolver un bloque exija resolver toda la historia hacia atrás.
- El **día de la instalación siempre es el más corto**. Una primera sesión que acaba en objetivo cumplido es lo que vende el sistema entero; abrir una instalación recién hecha con un 15 es jugarse a cara o cruz que eso ocurra.
- `epochDayOf` convierte la fecha **local** a UTC antes de numerarla. Usar la marca de tiempo local directamente hace que el índice avance algo distinto de uno al cambiar la hora en una zona UTC±0, y eso reparte el mismo día dos veces o se salta uno.

**El día paga lo que pidió**: cumplir un objetivo de 15 son 15 puntos; uno de 8, ocho. Es justo sin necesidad de inventarse una constante. Y **paga una sola vez**: seguir leyendo después suma datos al contador pero no más puntos.

**Rangos** (`Rank`): Curioso · Preguntón · Sabelotodo · Erudito · Enciclopedia · Oráculo, en 0 / 60 / 180 / 400 / 800 / 1400 puntos. Con una media de ~11 puntos por día perfecto, el segundo cae dentro de la primera semana — pronto para demostrar que el sistema funciona — y el último más allá de cien días cumplidos, que es donde debe estar un rango final. La barra de la pantalla de progreso mide **desde el suelo del rango actual**, no desde cero: una barra única para toda la escalera se pasaría semanas sin moverse.

**Dónde se ve.** Un anillo en la **barra superior** del mazo, con el icono del rango dentro. Ahí y no sobre las tarjetas: el mazo ya cede alto a los chips y al banner, y esto sería lo tercero en pedirle una franja. Al tocarlo se abre `/progress`, que es donde vive la explicación completa, la escalera entera y el estado del día.

**El aviso está graduado por lo que vale interrumpir:**

| Qué pasa | Qué sale |
|---|---|
| Se cumple el objetivo | Un `SnackBar`. Pasa todos los días y un modal acabaría siendo lo que el usuario aprende a cerrar. |
| Se sube de rango | Un diálogo. Pasa seis veces en la vida de la app, y es el único premio que tienen los puntos. |

**El día se cierra desde el reloj, no desde memoria.** `registerLearned` relee el día guardado en cada escritura, así que una app abierta desde antes de medianoche se pone al día con la primera tarjeta que se voltee; `refresh()` existe para el caso de volver del segundo plano sin haber tocado nada todavía. Los contadores de ayer no se borran hasta la siguiente escritura, pero **nunca se leen**: la comparación con el reloj los enmascara, y por eso un `awarded` viejo no puede pagar el objetivo de hoy.

**Es gratis y no toca la monetización.** Ni el objetivo ni los rangos miran `isPremiumProvider`. Poner detrás del muro de pago la única mecánica de retención que tiene la app sería cobrar por el motivo de volver.

> Lo obvio que falta y que **no** está implementado: la **racha** (días consecutivos cumpliendo). Es la pieza que multiplicaría esto y la notificación diaria, y encaja sin tocar nada de lo de arriba — un contador más y una condición en `registerLearned`. No se ha metido porque no se pidió.

---

## 4. Monetización

### 4.1 Modelo económico

- Núcleo gratuito completo y usable (apps de "funcionalidad mínima" se retiran).
- **Tarjeta de anuncio dentro del mazo = formato principal.** Se desliza igual que el contenido.
- **Interstitial = secundario**, cada ~9 tarjetas y nunca antes de 3 min desde el anterior.
- **Sin rewarded.** El uso es pasivo: no hay nada que desbloquear que justifique un vídeo. `AdsService` ya no tiene ese formato — **no reintroducirlo** sin una razón de producto nueva.
- **IAP no consumible "quitar anuncios"** = conversión principal. Desbloquea además los favoritos (§3.7), así que tiene dos puntos de venta: la tarjeta de anuncio sin relleno y el intento de guardar una tarjeta.

### 4.2 AdMob (`google_mobile_ads`)

**IDs.** `core/config/ad_config.dart` mantiene dos juegos: los **IDs oficiales de prueba de Google** y los de producción (vacíos hasta que existan). La selección es automática:

```dart
AppConfig.useProductionAds  // == kReleaseMode
```

Un ID vacío **desactiva** ese formato en vez de romper. **Nunca** usar IDs de producción en debug: es causa directa de baneo por tráfico inválido.

Hay **una sola unidad de banner** y sirve tanto al banner adaptativo anclado como al rectángulo 300x250 de la tarjeta de anuncio: una unidad de banner sirve cualquier tamaño de banner, y una segunda solo partiría los informes en dos.

El App ID de prueba también está declarado en `android/app/src/main/AndroidManifest.xml`
(`ca-app-pub-3940256099942544~3347511713`).

**`AdsService` (`services/ads/ads_service.dart`)** — punto único de entrada:

| Regla | Dónde |
|---|---|
| Premium nunca ve anuncios | `adsEnabled` (getter del servicio, **no** en cada pantalla) |
| Consentimiento antes del primer anuncio | `initialize()` llama a `ConsentService.gatherConsent()` |
| Interstitial cada N acciones **y** con intervalo mínimo | `registerActionAndMaybeShowInterstitial()` |
| Caducidad ~1 h de anuncios full screen | `_isExpired()` + `AppConfig.fullScreenAdTtl` |
| Reintentos con backoff exponencial (4s, 8s, 16s, 32s, máx. 4) | `_scheduleRetry()` |
| Nunca bloquear al usuario por falta de inventario | devuelve `AdShowResult.notReady`; la UI degrada |

**Pacing del interstitial:** deben cumplirse **las dos** condiciones —
`AppConfig.interstitialEveryNActions` (9) **y** `AppConfig.minIntervalBetweenInterstitials` (3 min).
Una "acción de valor" aquí es **una tarjeta descartada**. Como las tarjetas se consumen rápido, el que manda en la práctica es el suelo de 3 minutos. No añadir atajos que salten el pacing.

**Tarjeta de anuncio (`AdDeckCard`).** Dos reglas que no se relajan:

1. **Pedir el creativo y pintarlo son dos cosas distintas, y solo la segunda es una impresión.** El `AdWidget` se monta **únicamente en `depth == 0`**: las tarjetas que esperan detrás están tapadas al 95 %, y pintar un anuncio que nadie puede ver es justo lo que AdMob cuenta como impresión inválida. Esta regla no se relaja.
2. **La petición sale una tarjeta antes** (`AppConfig.deckAdPreloadDepth`, hoy 1). Pedirla solo al llegar arriba es lo que hacía que el anuncio apareciera tarde, después de un parpadeo del argumento de "quitar anuncios". Precargando, llegar arriba es un repintado y no una ida y vuelta a la red. Subir esa profundidad es pedir creativos que quizá nadie vea, así que se queda en 1.
3. Mientras la petición está en vuelo la tarjeta **reserva el hueco vacío**, no enseña el argumento de pago. Ese argumento significa "no entró nada" —sin consentimiento, sin inventario, sin unidad configurada— y sacarlo durante una carga que va a funcionar es como la tarjeta acaba cambiando de opinión delante del usuario.
4. La etiqueta **"Publicidad" siempre visible**. Un anuncio mimetizado sin etiqueta es un rechazo por *deceptive ads*.

`SwipeDeck` pasa al `builder` la **profundidad** de cada tarjeta, no un booleano "es la de arriba": una tarjeta puede necesitar empezar a trabajar antes de ser alcanzable, y eso no cabe en un `bool`.

Si no entra ningún creativo (sin consentimiento, sin inventario, sin unidad configurada) la tarjeta cae a un argumento discreto de "quitar anuncios" en vez de un rectángulo en blanco: mantiene el ritmo del mazo y coloca el paywall justo detrás de un momento de valor.

> **Pendiente:** el plan original pedía un *native ad* real. Requiere una `NativeAdFactory` en Kotlin más su layout XML. Lo que hay ahora es un 300x250 dentro del mismo `DeckCardShell` que el contenido — cero código nativo y misma sensación. Migrar solo si el eCPM lo justifica.

**Banner.** `AdaptiveBannerAd` es el único sitio donde vive la política de colocación. Tiene dos modos:

- `anchored: true` (por defecto): lo coloca `BaseScreen` **debajo** del contenido, nunca superpuesto. Hoy no lo activa ninguna pantalla — `SettingsScreen`, `PaywallScreen` y `FavoritesScreen` van con `showBanner: false`.
- `anchored: false`: **en línea, dentro del layout**. Es el que usa el mazo, entre los chips de categoría y las tarjetas.

**El banner del mazo va arriba, nunca abajo.** El mazo es una superficie que se arrastra en cuatro direcciones, y un banner anclado al borde inferior bajo ese gesto es el ejemplo de manual del clic accidental. Colocado sobre las tarjetas el dedo no lo pisa nunca al salir de un deslizamiento. **No moverlo abajo.**

Si no entra creativo, o el usuario es premium, el widget no ocupa nada (`SizedBox.shrink`): la tarjeta recupera el espacio en vez de dejar una franja gris. En pantallas pequeñas el banner y los chips comen alto que era de la tarjeta; el mazo va en un `Expanded` y cede, pero conviene revisarlo con `textScaleFactor` alto (§14).

**Consentimiento (UMP).** `services/ads/consent_service.dart` usa el UMP SDK que ya incluye `google_mobile_ads` (sin dependencia extra):
`requestConsentInfoUpdate` → `loadAndShowConsentFormIfRequired` → `canRequestAds()`.
En Ajustes hay una fila **"Opciones de privacidad"** que reabre el formulario, visible solo cuando `getPrivacyOptionsRequirementStatus() == required`.

**Mediación:** no activarla en el lanzamiento. A partir de ~10k usuarios activos, 2–3 redes.

### 4.3 IAP (`in_app_purchase`)

- Producto **gestionado no consumible**: `premium_remove_ads` (`core/config/billing_config.dart`). Debe existir y estar **activo** en Play Console y requiere una versión subida a un canal de pruebas.
- `PremiumService` = plomería del store; `PremiumController` (`AsyncNotifier`) = estado.
- **`purchaseStream` se escucha desde el arranque**, no desde el paywall: una compra puede completarse fuera de la sesión.
- **`completePurchase()` siempre**, incluso en compras rechazadas o con error: si no, Google reembolsa automáticamente a los 3 días.
- Entitlement cacheado en `flutter_secure_storage` + `restorePurchases()` al arrancar para verificar contra el store. Nunca confiar solo en un flag de `shared_preferences`.
- **Botón "Restaurar compras" obligatorio y visible** en Ajustes (y también en el paywall). Su ausencia es motivo de rechazo.
- Verificación local del token (app sin backend). Con servidor: validar contra la Google Play Developer API en `PremiumService.isValidPurchase`.
- **Paywall tras un momento de valor**, nunca en el primer arranque. Puntos de entrada: el intento de guardar una tarjeta, la pantalla de guardadas bloqueada, la tarjeta de anuncio sin relleno, fila en Ajustes, deep link `aja://premium`.

### 4.4 Política

- **Data Safety form** debe declarar exactamente lo que recogen AdMob y los SDKs (ID de publicidad, datos de uso). Declaración incompleta = rechazo.
- El permiso `com.google.android.gms.permission.AD_ID` está declarado explícitamente en el manifiesto para que no se olvide en el formulario.
- Si la app se dirige a menores: poner `AdConfig.isChildDirected = true` y aplicar Families Policy. **Ojo**: parte del contenido es de cuerpo humano; revisar el content rating antes de marcar público infantil.

---

## 5. Permisos

La app pide **uno solo en tiempo de ejecución**: `POST_NOTIFICATIONS`, para la pregunta del día (§6). El resto del manifiesto son permisos de instalación: `INTERNET`, `ACCESS_NETWORK_STATE`, `AD_ID` y `RECEIVE_BOOT_COMPLETED`.

**`POST_NOTIFICATIONS` se pide desde el interruptor de Ajustes y desde ningún otro sitio.** Android enseña ese diálogo **una vez** y recuerda la negativa para siempre: gastarlo al arrancar, antes de que el usuario sepa siquiera qué hace la app, es como se mata una función de retención antes de publicarla. El interruptor *es* el consentimiento — al tocarlo ya ha dicho que la quiere.

**`RECEIVE_BOOT_COMPLETED`** existe porque Android tira todas las alarmas pendientes al reiniciar y al actualizar la app. Sin él, la cola de dos semanas se pierde en el primer reinicio.

**Deliberadamente NO se declaran `SCHEDULE_EXACT_ALARM` ni `USE_EXACT_ALARM`.** Las notificaciones se programan inexactas (`AndroidScheduleMode.inexactAllowWhileIdle`), que es todo lo que necesita un recordatorio diario. Las alarmas exactas las revisa Play caso por caso y habría que justificarlas; un recordatorio que llega cinco minutos tarde sigue siendo un recordatorio. **No cambiar a exactas** sin una razón de producto nueva.

`permission_handler` **sigue sin estar** y no hace falta: `flutter_local_notifications` trae su propio `requestNotificationsPermission()`. Una dependencia menos.

`flutter_local_notifications` inyecta además `VIBRATE` en el manifiesto fusionado. Revisar el fusionado tras cada cambio de dependencias.

---

## 6. Pregunta del día (notificación diaria)

El motor de retención: sin ella, una app de datos curiosos es una app de una sola sesión.

**Notificaciones locales, no push.** No hay backend y esto no justifica criar uno. Cada notificación se encola en el dispositivo con su pregunta ya elegida, así que funciona sin red y no cuesta nada mantener. El precio, y hay que saberlo: la cola solo llega a `AppConfig.dailyQuestionDaysAhead` (14) días y se rellena **cada vez que se abre la app**. Un usuario que no la abra en dos semanas deja de recibir recordatorios hasta que vuelva. Es un intercambio aceptable a cambio de cero servidores; si algún día entra FCM, esto se sustituye sin tocar la UI.

La pregunta se elige **al azar** entre todo el catálogo, barajado sin semilla: dos semanas seguidas no deben repartir las mismas catorce preguntas.

Hora fija a las **20:00 locales** (`AppConfig.dailyQuestionHour`). Es contenido de curiosidad ociosa: por la mañana compite con el trabajo y después de cenar no compite con nada. La zona horaria se resuelve con `flutter_timezone`; sin eso todo se programaría en UTC y «las 20:00» caerían a la hora que tocase según el desfase del usuario.

### Al tocar la notificación: la carta se traslada, no se salta

`DeckController._hoist` es la pieza importante y la única con lógica real aquí. Saltar el índice hasta donde esté esa carta **se saltaría en silencio todo lo que hay entre la posición actual y ella**. En vez de eso, la carta se **saca** del mazo y se **suelta en la posición de lectura**, y las cartas entre las que estaba cierran el hueco. Lo que iba a salir después sigue saliendo después, un puesto más tarde.

Tres casos que el código cubre y que conviene no romper:

- **Carta ya leída:** no está en el mazo, porque el mazo solo lleva cartas sin leer. Se saca del catálogo filtrado y se pone arriba para esta sesión; descartarla vuelve a marcarla leída, que no cambia nada.
- **Mazo ya agotado:** la carta aterriza arriba y el mazo vuelve a estar agotado justo después. Un recordatorio que toca alguien que ya se lo ha leído todo tiene que funcionar igual.
- **Id desconocido o filtrado por los chips:** el mazo se deja exactamente como estaba, sin adivinar qué quería el usuario. Por eso `openFactFromNotification` **limpia el filtro de categoría** antes de fijar la carta: la pregunta del día sale de todo el catálogo, y un usuario parado en «Historia» tocaría una de ciencia y no vería nada.

El «pin» vive en `pinnedFactProvider` y **no se persiste**: pertenece a una sesión. Uno que sobreviviera a un reinicio seguiría tirando de la misma carta días después.

---

## 7. Reseñas in-app (`in_app_review`)

`services/review/review_service.dart`. Google limita el diálogo silenciosamente: si se gasta la cuota en un mal momento, el usuario no lo vuelve a ver en meses. Por eso hay tres guardas (`AppConfig`):

- `reviewMinSuccessfulActions` = 5 acciones de valor completadas.
- `reviewMinAppAge` = 3 días desde la instalación.
- `reviewMinInterval` = 120 días entre solicitudes.

En Ajá el **momento de valor es voltear una tarjeta para leer la respuesta**: es lo único que el usuario viene a hacer. `requestReviewAfterSuccess()` se llama solo desde ahí (`DeckScreen._reveal`), nunca al arrancar, nunca tras un error, nunca desde Ajustes.
Para el botón explícito "Valorar la aplicación" de Ajustes se usa `openStoreListing()`, que no consume la cuota del diálogo nativo.

---

## 8. Tema y diseño (Material 3)

- Un **único seed color** (`AppColors.seed = 0xFFC026D3`) genera los esquemas claro y oscuro con `ColorScheme.fromSeed`.
- `AppTheme.light([scheme])` / `AppTheme.dark([scheme])` aceptan un `ColorScheme` externo: si algún día se quiere Material You, se inyecta ahí sin tocar el resto del tema.
- Colores semánticos (success/warning) vía `ThemeExtension<AppSemanticColors>`, accesibles con `context.semanticColors`.
- **Tokens de espaciado y radios** en `AppSpacing` / `AppRadius`. Prohibido escribir paddings a pelo.
- `ThemeModeController` persiste claro/oscuro/sistema en `shared_preferences` de forma **síncrona** (las prefs ya están cargadas en `bootstrap`), así el primer frame no parpadea con el brillo equivocado.
- Widgets base: `BaseScreen`, `SectionCard`, `AppLoader`, `EmptyState`, `ErrorView`, `AdaptiveBannerAd`.
- Todas las tarjetas del mazo — contenido y anuncio — comparten `DeckCardShell`. Ahí es donde se cambia la forma de una tarjeta, no en cada widget.

**Toda pantalla nueva debe construirse sobre `BaseScreen`**, no sobre un `Scaffold` pelado.

---

## 9. Navegación (`go_router`)

- Rutas declarativas en `core/routing/app_router.dart`, constantes en `app_routes.dart`. **Nunca escribir un path literal en una pantalla.**
- Navegación por nombre: `context.goNamed(AppRoutes.settingsName)`.
- `rootNavigatorKey` disponible para código fuera del árbol (callbacks de anuncios, stream de compras) en vez de guardar un `BuildContext` obsoleto.
- Deep links activos desde el día 1: esquema `aja://` en el manifiesto + `flutter_deeplinking_enabled`. App Links (`https`, `autoVerify`) están comentados: activarlos requiere publicar `assetlinks.json` en el dominio.
- `errorBuilder` → `RouteErrorScreen`, para que un deep link de campaña obsoleto no crashee.

---

## 10. Arranque (`bootstrap.dart`)

Objetivo: **primer frame < 2 s en gama media**.

Antes de `runApp` solo se permite:
1. `WidgetsFlutterBinding.ensureInitialized()`
2. cargar `SharedPreferences` (unos ms, y evita parpadeos de tema/contadores)

El catálogo **no** se carga aquí: `factsProvider` lo pide desde la pantalla y el mazo enseña `AppLoader` mientras tanto.

Todo lo demás arranca **después del primer frame** (`addPostFrameCallback`), en este orden y con `try/catch` individual:
1. `premiumControllerProvider` — el entitlement debe conocerse **antes** de pedir anuncios.
2. `AdsService.initialize()` (RequestConfiguration → consentimiento → `MobileAds.initialize()` → precarga).
3. `adsInitializedProvider.markInitialized()`.
4. `DailyQuestionService.initialize()` — engancha los toques, atiende la notificación que pueda haber arrancado la app y rellena la cola de 14 días. **No pide permiso ninguno**: eso es exclusivo del interruptor de Ajustes (§5).

Todo va dentro de `runZonedGuarded`, con `FlutterError.onError` y `PlatformDispatcher.instance.onError` enrutados a `AppLogger`.

`main.dart` no contiene lógica. **No añadir nada ahí.**

---

## 11. Configuración Android

`android/app/build.gradle.kts`:

- `compileSdk = 37` — lo exige `flutter_secure_storage 11`. No bajarlo.
- `minSdk = 24`, `targetSdk = flutter.targetSdkVersion`.
- `applicationId = com.alejandrosahonero.aja` — **no se puede cambiar nunca** tras publicar.
- Release: `isMinifyEnabled = true`, `isShrinkResources = true`, `proguard-rules.pro`.
- **Firma:** lee `android/key.properties` (git-ignored). Si no existe, cae a la firma de debug para no romper builds locales. Antes de publicar, verificar que `key.properties` existe y que el AAB **no** va firmado con debug.
- **Sin product flavors ni entornos.** `flutter run` y `flutter build` funcionan sin `--flavor` ni `--dart-define`. No reintroducirlos.
- El nombre visible se declara directamente en `AndroidManifest.xml` (`android:label`), no como `resValue`: AGP 9 desactiva la build feature `resValues` por defecto.

---

## 12. Comandos

```bash
# Desarrollo
flutter run

# Calidad (obligatorio antes de cerrar una tarea)
dart format lib test && flutter analyze && flutter test

# Release para Play (AAB, ofuscado, símbolos archivados por versión)
flutter clean && flutter pub get
flutter build appbundle --release \
  --obfuscate --split-debug-info=build/symbols/1.0.0

# Auditoría de tamaño (objetivo: AAB < 15 MB)
flutter build appbundle --release --analyze-size
```

**Guardar `build/symbols/<versión>` fuera del repo.** Sin esos símbolos los crashes son ilegibles.

---

## 13. Pendiente antes de publicar

1. ~~Verificar a mano las entradas de `assets/data/facts.json` y rellenar `sourceUrl`.~~ **Hecho.** Las 87 se comprobaron una a una contra una página abierta; se retiraron 2 (una refutada, otra sin fuente aceptable) y se corrigió la redacción de 12 que decían más de lo que su fuente sostenía. Quedan **85**, todas con enlace. Lo que sí queda pendiente: repasar las que se apoyan en fuentes de segunda fila (Wikipedia, `historic-uk.com`, `ck12.org`) y subirlas a una primaria si aparece.
2. `core/config/ad_config.dart`: rellenar `_prodBanner` y `_prodInterstitial`.
3. `AndroidManifest.xml`: sustituir el App ID de prueba de AdMob por el de producción.
4. Iconos adaptativos (`flutter_launcher_icons`) y splash nativo (`flutter_native_splash`) — necesitan assets reales.
5. Crash reporting (Crashlytics o Sentry) — **obligatorio desde la v1**. Enganchar en `AppLogger.error` y en `bootstrap`.
6. Política de privacidad publicada en una URL accesible (obligatoria por usar AdMob).
7. Data Safety form, content rating (IARC), público objetivo, declaración "contiene anuncios".
8. Testing interno → closed testing (**12 testers / 14 días** para cuentas personales creadas después de nov-2023) → producción con rollout escalonado 10–20 %.
9. Vigilar Android Vitals: crash rate > 1,09 % o ANR > 0,47 % penalizan la visibilidad → parar el rollout.

### Features del plan original todavía sin implementar

- **Widget de pantalla de inicio** con la pregunta del día.

---

## 14. Definición de "hecho" para cada release

- [ ] `flutter analyze` sin issues y `dart format` aplicado.
- [ ] Tests pasando.
- [ ] Probado en dispositivo físico de gama baja en **modo release** (R8 rompe cosas que en debug funcionan).
- [ ] El gesto del mazo probado con `textScaleFactor` alto y en pantalla pequeña.
- [ ] Objetivo diario probado **cruzando la medianoche** con la app abierta: el contador se reinicia con la primera tarjeta del día nuevo y los puntos de ayer siguen ahí.
- [ ] Pregunta del día probada **en dispositivo físico**: permiso concedido y denegado, notificación tocada con la app cerrada y con la app abierta, y la carta apareciendo arriba sin saltarse ninguna. Comprobar también que sobrevive a un reinicio.
- [ ] Sin IDs de prueba de AdMob ni logs de debug en el build de producción.
- [ ] `versionCode` incrementado.
- [ ] Símbolos de ofuscación archivados y subidos al crash reporting.
- [ ] Tamaño del AAB verificado, sin regresión.
- [ ] Compra premium y restauración probadas con cuenta de tester licenciado, comprobando que los favoritos se desbloquean con la compra y que la lista sobrevive a una reinstalación.
- [ ] Notas de la versión en todas las localizaciones.

---

## 15. Rendimiento — recordatorios al escribir código

- Listas: `ListView.builder` / `SliverList` siempre.
- El mazo monta como mucho `AppConfig.deckVisibleCards` (3) tarjetas; el resto no existe. No subirlo "por si acaso".
- Extraer widgets propios en vez de métodos `_buildX()`, para acotar rebuilds.
- `RepaintBoundary` en animaciones y elementos que se repintan solos (ya lo lleva `FactCard`).
- Imágenes: WebP para bitmaps, SVG para iconografía, `cacheWidth`/`cacheHeight` obligatorios.
- Liberar recursos en `dispose()`: controllers, streams, timers (`AdsService.disposeAds`, `AdaptiveBannerAd`, `AdDeckCard` y los `AnimationController` del mazo ya lo hacen).
- Trabajo pesado fuera del isolate principal (`compute()` / `Isolate.run()`) — el catálogo ya lo hace.
- Perfilar en **modo profile en dispositivo físico**, nunca en debug ni emulador.
