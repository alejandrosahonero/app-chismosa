# Chismosa

App Android de historias anónimas en formato mazo deslizable. Cada carta es un chisme corto que alguien del mundo ha contado; deslizas a la derecha si te gusta, a la izquierda o abajo para pasar, y **hacia arriba para entrar en su hilo** y comentarlo con más gente, cada uno con un alias distinto en cada hilo.

> **Para agentes de IA y para cualquiera que toque el código: leer [`CLAUDE.md`](CLAUDE.md) primero.** El backend está en [`supabase/README.md`](supabase/README.md).

---

## Qué hace

| Área | Qué hay |
|---|---|
| Mazo | Historias de todo el mundo, orden «hot» (likes por hora) o «nuevas», filtros por país, categoría e idioma |
| Hilos | Conversación en vivo detrás de cada historia (Supabase Realtime), alias por hilo, historial de tus hilos |
| Grupos | Mazos privados por código de invitación que caduca y se puede renovar |
| Publicar | Una historia al día; otra más viendo un anuncio (verificado en servidor); sin límite con premium |
| Anonimato | Cuenta anónima sin email; el id de cuenta nunca llega a otro cliente; código de recuperación |
| Moderación | Reportar y bloquear; lo reportado de sobra se oculta solo |
| Push | Aviso de mensajes nuevos en tus hilos (FCM), uno por hilo hasta que lo abres |
| Progreso | Objetivo diario de hilos + seis rangos |
| Monetización | AdMob (tarjeta de anuncio en el mazo, banner, interstitial con pacing, recompensado) + pago único premium |
| Plataforma | Flutter, Riverpod 3, go_router, Material 3 claro/oscuro, español e inglés |

Todo sobre herramientas gratuitas: Supabase plan free (Postgres, Auth, Realtime, Edge Functions) y Firebase solo para Cloud Messaging.

---

## Arrancar

```bash
flutter pub get
flutter run
```

Sin más: la URL y la clave pública de Supabase están en `lib/core/config/backend_config.dart` y los anuncios usan los IDs de prueba de Google en debug. Para montar el backend desde cero, seguir [`supabase/README.md`](supabase/README.md).

## Calidad

```bash
dart format lib test && flutter analyze && flutter test
```

## Release

```bash
flutter build appbundle --release --obfuscate --split-debug-info=build/symbols/1.0.0
```

Antes de publicar, la lista de [`CLAUDE.md` §11](CLAUDE.md).

---

## Estructura

```
lib/
├── core/        # config, tema, rutas, widgets base, motor del mazo
├── features/    # stories, threads, groups, goals, settings, premium
├── services/    # backend, identity, moderation, push, locale, ads, billing, review, storage
└── l10n/        # app_es.arb, app_en.arb
supabase/
├── migrations/  # esquema, lógica y seguridad (RLS), en orden
└── functions/   # admob-ssv, thread-push
tool/
└── seed_demo_stories.sh
```
