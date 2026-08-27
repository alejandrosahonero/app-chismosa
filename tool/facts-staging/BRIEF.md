# Brief — nuevas entradas para el catálogo de Ajá

Ajá es una app de datos curiosos en formato mazo. Cada tarjeta es **una pregunta**
que el usuario lee, intenta responder mentalmente, y voltea para ver la respuesta.

## Qué se busca (lo más importante de todo)

Preguntas **rarísimas**. No preguntas de trivial de bar. No "¿cuál es el animal más
rápido?". No "¿cuántos huesos tiene el cuerpo humano?". No "¿quién inventó la
bombilla?". Nada que salga en el primer resultado de "datos curiosos".

La vara de medir: **la pregunta tiene que ser algo que el lector nunca se planteó,
pero que en cuanto la lee se da cuenta de que lleva toda la vida sin cuestionar.**

Familias de preguntas que funcionan:

- **Lo cotidiano que nadie mira**: por qué el papel higiénico va perforado así, por
  qué los ascensores tienen espejo, por qué las latas de refresco tienen el fondo
  cóncavo, por qué el sonido de la cerveza al abrirse es ese.
- **Creencias falsas muy extendidas** (y qué pasa de verdad): la lengua no tiene
  mapa de sabores, la Gran Muralla no se ve desde el espacio.
- **Coincidencias históricas imposibles**: quién estaba vivo a la vez que quién,
  qué se inventó antes que qué.
- **Consecuencias absurdas de una regla técnica**: por qué el teclado está así, por
  qué los aviones tiran el combustible, por qué hay un número máximo de gente en un
  ascensor pero no en un autobús.
- **Etimologías que revientan el sentido de una palabra de uso diario.**
- **Lo que el cuerpo hace sin pedir permiso y nadie explica**: por qué se te duerme
  un pie, por qué bostezar contagia, por qué el pelo mojado se ve más oscuro.
- **Números que no cuadran con la intuición**: barajas, cumpleaños, escalas.

Familias prohibidas: récords Guinness, "el animal que...", curiosidades de
banderas, datos de países, cosas que ya son meme.

## Verificación — regla dura, sin excepciones

**Una entrada sin URL comprobada NO entra.** El catálogo entero se verificó a mano y
un dato falso viral se convierte en reseñas de una estrella.

Para cada entrada:

1. Busca con `WebSearch`.
2. **Abre la página con `WebFetch`** y comprueba que dice lo que vas a afirmar.
3. Si la página no lo sostiene, **descarta la entrada**. No la maquilles.
4. En el campo `_evidence` copia la frase literal de la página que lo sostiene.

Una cita generada de memoria **no vale**. Existe el organismo, existe la revista, y
la página no habla del tema: eso ya ha pasado en este proyecto. Hay que abrirla.

**Jerarquía de fuentes.** Preferidas: organismos oficiales (NASA, NOAA, NIH, USGS,
Cleveland Clinic, Mayo Clinic, museos nacionales, bibliotecas nacionales),
diccionarios etimológicos (etymonline, RAE, OED, Merriam-Webster), revistas
científicas y sus resúmenes, universidades, Snopes/Britannica para desmentidos.
Aceptables a regañadientes: Wikipedia (solo si no hay nada mejor).
**Prohibidas**: blogs de curiosidades, listicles, contenido agregado sin fuente,
Reddit, Quora, Pinterest, IA.

El `sourceUrl` debe ser un **enlace permanente y directo** a la página concreta, no
a la home del sitio ni a un buscador.

## Formato de salida

Un único fichero JSON, un array en la raíz, sin nada más:

```json
[
  {
    "id": "kebab-case-en-espanol",
    "category": "ciencia",
    "question": {
      "es": "¿Por qué el vómito se dibuja verde si casi nunca lo es?",
      "en": "Why is vomit always drawn green when it almost never is?"
    },
    "answer": {
      "es": "Porque a veces sí lo es: cuando lo que sube es bilis en vez de comida.",
      "en": "Because sometimes it really is: when what comes up is bile rather than food."
    },
    "detail": {
      "es": "Dos o tres frases que explican el mecanismo y rematan con lo interesante.",
      "en": "Two or three sentences explaining the mechanism, ending on the good part."
    },
    "source": "Cleveland Clinic — Vomit Color Chart",
    "sourceUrl": "https://health.clevelandclinic.org/vomit-color-chart",
    "_evidence": "Frase literal copiada de la página que sostiene la respuesta."
  }
]
```

### Reglas de los campos

- `id`: kebab-case, en español, sin acentos ni ñ, 2–4 palabras, único. Comprueba
  que no choque con `EXISTING.txt`.
- `category`: exactamente uno de `cuerpo` / `ciencia` / `historia` / `lenguaje`.
  **Un valor distinto revienta la app al parsear.** El tuyo va fijado en tu encargo.
- `question`: **siempre interrogativa**, con `¿ ?` en español. Máximo ~90
  caracteres: tiene que caber en una tarjeta y en una imagen de historia de
  Instagram. Sin spoiler de la respuesta dentro de la pregunta.
- `answer`: **una frase**, máximo ~140 caracteres. Es el golpe. Va directa al grano.
- `detail`: 2–3 frases. Aquí va el mecanismo, el matiz y el remate. Máximo ~400
  caracteres. **No repitas la respuesta literalmente**, amplíala.
- `en`: inglés natural, no traducción literal del español. Un hablante nativo tiene
  que leerlo sin notar que viene de otro idioma. Los juegos de palabras se
  reescriben, no se calcan.
- `source`: nombre legible de la fuente, formato `Organismo — Título de la página`.
- `_evidence`: la frase de la página. **Este campo se borra antes de publicar**,
  es solo para la revisión.

### Tono

Directo, seco, con gracia sin hacerse el gracioso. Nada de "¡Increíble!",
"¿Sabías que...?", "Te sorprenderá". Ni emojis. Ni signos de exclamación.
Lee `EXISTING.txt` para calibrar el tono y para no repetir temas.

## Entrega

- **Mínimo 100 entradas verificadas.** Es un suelo, no un objetivo.
- Escribe el JSON en la ruta que te indique tu encargo.
- Valídalo antes de terminar: `python3 -m json.tool <fichero> > /dev/null`.
- Informa de: cuántas entregaste, cuántas descartaste y por qué motivos.
- **Prefiero 100 entradas verificadas que 200 con la mitad inventadas.** Si no
  llegas a 100 con fuentes de verdad, entrega las que tengas y dilo.
