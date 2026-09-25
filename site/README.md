# site/ — la web de los enlaces

Web estática mínima que hace que los enlaces de Chismosa se puedan tocar en
WhatsApp, Instagram, TikTok y cualquier otro sitio:

| Ruta | Qué es |
|---|---|
| `/s/<id>` | Historia compartida. Con la app instalada, Android abre su hilo directamente (App Links). Sin ella, `open.html` ofrece Google Play. |
| `/g/<código>` | Invitación a un grupo. Igual, y la página enseña el código para copiarlo. |
| `/.well-known/assetlinks.json` | Lo que Android comprueba para abrir la app sin preguntar. |

## Publicarla gratis (Cloudflare Pages)

1. Cloudflare → Workers & Pages → Create → Pages → **Upload assets**.
2. Nombre del proyecto: **`chismosa`** (así el dominio es `chismosa.pages.dev`).
   Si está cogido, elige otro y cambia el host en tres sitios:
   `lib/core/config/links_config.dart`, `AndroidManifest.xml` (intent-filter
   `autoVerify`) y este README.
3. Sube el contenido de esta carpeta. `_redirects` y `_headers` son de
   Cloudflare; `404.html` hace lo mismo que `_redirects` si algún día se
   publica en GitHub Pages.

## Antes de publicar la app

`assetlinks.json` lleva ahora la huella SHA-256 de la clave de **debug** de
este ordenador, para poder probar los enlaces ya. Añade la de **Play App
Signing** (Play Console → Configuración → Integridad de la app → Firma de apps
→ «Certificado de la clave de firma de apps», SHA-256) en lugar de
`REEMPLAZAR_CON_SHA256_DE_PLAY_APP_SIGNING`, y vuelve a subir la carpeta.

Comprobar que Android lo acepta, con el móvil conectado:

```
adb shell pm verify-app-links --re-verify com.alejandrosahonero.chismosa
adb shell pm get-app-links com.alejandrosahonero.chismosa
```
