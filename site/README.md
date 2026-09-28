# site/ — la web de Chismosa

Web estática (HTML + CSS a mano) publicada en **GitHub Pages** en
`https://chismosa-app.github.io` (organización `chismosa-app`, repo
`chismosa-app.github.io`). Hace que los enlaces de Chismosa se puedan tocar en
WhatsApp, Instagram, TikTok y cualquier otro sitio.

| Ruta | Qué es |
|---|---|
| `/` | Landing (`index.html`). |
| `/privacidad.html` | Política de privacidad. Su URL va en la ficha de Play y en Data Safety. |
| `/s/<id>` | Historia compartida. Con la app instalada, Android abre su hilo directamente (App Links). Sin ella, `404.html` ofrece Google Play. |
| `/g/<código>` | Invitación a un grupo. Igual, y la página enseña el código para copiarlo. |
| `/.well-known/assetlinks.json` | Lo que Android comprueba para abrir la app sin preguntar. |

GitHub Pages no tiene reescrituras: `/s/…` y `/g/…` no existen como archivos, así
que GitHub sirve `404.html`, que lee la ruta y pinta la página correcta (y manda
a `/` cualquier otra ruta). `.nojekyll` hace falta para que GitHub publique la
carpeta `.well-known` (Jekyll ignora las carpetas que empiezan por punto).

El host está en tres sitios y tiene que coincidir: `lib/core/config/links_config.dart`,
el intent-filter `autoVerify` de `AndroidManifest.xml` y este README.

## Publicar o actualizar

El repo `chismosa-app.github.io` contiene **solo** el contenido de esta carpeta, en
la raíz. Se publica desde la rama `main`, carpeta `/` (Settings → Pages).
Para actualizar: copiar esta carpeta encima y hacer push.

## assetlinks.json

Lleva las huellas SHA-256 de la clave de **debug** de este ordenador y de la
clave de **subida** (`android/upload-keystore.jks`), para probar los enlaces con
builds locales. Antes de publicar hay que **añadir** la de **Play App Signing**
(Play Console → Probar y publicar → Configuración → Integridad de la app →
Firma de apps → «Certificado de la clave de firma de apps», SHA-256), que es la
que firma lo que instala la gente desde Google Play.

Comprobar que Android lo acepta, con el móvil conectado:

```
adb shell pm verify-app-links --re-verify com.alejandrosahonero.chismosa
adb shell pm get-app-links com.alejandrosahonero.chismosa
```
