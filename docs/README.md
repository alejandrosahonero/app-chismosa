# Catálogo remoto de Ajá

Este directorio se publica con **GitHub Pages**. `facts.json` es el catálogo que la
app descarga para añadir, corregir o retirar preguntas **sin publicar una versión
nueva en Play**.

No borres este README: GitHub Pages sirve la carpeta entera, y `facts.json` es el
único fichero que la app lee.

## Cómo se fusiona

La app arranca con las preguntas que van dentro del APK y le suma este fichero:

| En `facts.json` | Efecto |
|---|---|
| Un `id` que **ya existe** | Reemplaza esa pregunta **en su sitio** |
| Un `id` **nuevo** | Se añade al final del mazo |
| Un id dentro de `removed` | Esa pregunta desaparece |

Reglas que la app aplica sola, y conviene conocer:

- Una entrada mal formada **se descarta y las demás siguen**. Un error tuyo no deja
  a nadie sin app, pero tampoco publica esa pregunta.
- Un fichero que dejaría el catálogo vacío **se ignora entero**.
- Si `version` es menor que la que el móvil ya tiene, se rechaza.
- Los cambios se ven **en el siguiente arranque**, no al instante: cambiar el mazo
  mientras alguien lo está leyendo le movería las cartas.

## Añadir preguntas: paso a paso

1. **Edita `docs/facts.json`.** Añade las entradas nuevas dentro de `"facts"`.
   Copia el formato exacto de `assets/data/facts.json` — los campos son los mismos.
   Usa un `id` que no exista ya, en minúsculas y sin acentos.

2. **Mantén el intercalado por categoría.** El mazo no baraja en la primera vuelta:
   el orden del fichero es el orden que ve el usuario. Alterna `cuerpo`, `ciencia`,
   `historia`, `lenguaje` en vez de meter quince seguidas de la misma.

3. **Valida antes de subir:**

   ```bash
   python3 tool/build_remote_catalog.py --check
   ```

   Comprueba las mismas reglas que aplica la app: categorías válidas, los dos
   idiomas en cada texto, ids duplicados, fuentes vacías. Si falla, dice qué
   entrada y por qué.

4. **Sube la versión y publica:**

   ```bash
   python3 tool/build_remote_catalog.py --bump
   git add docs/facts.json
   git commit -m "Contenido: N preguntas nuevas"
   git push
   ```

   `--bump` incrementa `version`. **Si no la subes, los móviles que ya tengan una
   copia no verán el cambio.**

5. Un minuto después está en el CDN. Cierra y abre la app para verlo.

## Corregir una pregunta que ya está publicada

Copia la entrada entera desde `assets/data/facts.json` a `docs/facts.json`,
**con el mismo `id`**, y corrige lo que haga falta. Reemplaza a la de dentro del
APK sin moverla de sitio.

## Retirar un dato falso

Añade su `id` a `"removed"` y sube la versión. Es lo más urgente que sabe hacer
este sistema: las 85 preguntas del APK llevan fuente verificada, pero una fuente puede caerse o corregirse, y cuando
una resulte falsa hay que poder matarla hoy.

```json
{ "version": 4, "facts": [], "removed": ["huellas-koala"] }
```

## Activarlo (una sola vez)

1. GitHub → Settings → Pages → Source: rama `main`, carpeta `/docs`.
2. Copia la URL resultante en `RemoteCatalogConfig.url`
   (`lib/core/config/remote_catalog_config.dart`):

   ```dart
   static const String url =
       'https://<usuario>.github.io/<repo>/facts.json';
   ```

3. Publica **una** versión de la app con esa URL dentro. A partir de ahí, todo el
   contenido nuevo viaja por aquí.

Mientras la URL esté vacía la app funciona con normalidad, solo con las preguntas
del APK.
