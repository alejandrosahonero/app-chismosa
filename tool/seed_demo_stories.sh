#!/usr/bin/env bash
#
# Siembra el mazo con historias de ejemplo.
#
# El mazo arranca vacío y `feed()` nunca devuelve las historias propias, así que
# una instalación recién hecha no tiene nada que enseñar hasta que publique
# **otra** persona. Este script crea esa otra persona: una cuenta anónima por
# historia, exactamente como haría la app.
#
# Una cuenta por historia y no una para las tres: `before_story_insert` permite
# una publicación al día por autor, y saltárselo desde aquí sería sembrar el
# mazo con una regla distinta de la que corre en producción.
#
# Uso:
#   tool/seed_demo_stories.sh [project-url] [publishable-key]
#
# Sin argumentos toma los valores de lib/core/config/backend_config.dart.
#
# Ejecutarlo dos veces publica las mismas historias otra vez con autores nuevos.
# Para limpiar, en el SQL Editor:
#   delete from public.stories where body like '%(demo)%';
set -euo pipefail

URL="${1:-}"
KEY="${2:-}"

config="$(dirname "$0")/../lib/core/config/backend_config.dart"
URL="${URL:-$(grep -oE 'https://[a-z0-9]+\.supabase\.co' "$config" | head -1)}"
KEY="${KEY:-$(grep -oE 'sb_publishable_[A-Za-z0-9_-]+' "$config" | head -1)}"

if [[ -z "$URL" || -z "$KEY" ]]; then
  echo "Falta la URL del proyecto o la clave publishable." >&2
  exit 1
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Las historias van en ficheros y no en argumentos de curl a propósito: en
# Windows los argumentos de un proceso pasan por la codificación ANSI del
# sistema, que destroza los acentos y hace que PostgREST responda
# "Empty or invalid json". Un fichero viaja como los bytes que es.
cat >"$work/1.json" <<'JSON'
{
  "body": "Mi vecina lleva tres semanas recogiendo un paquete que no es suyo. Lo sé porque el repartidor se equivoca de puerta siempre y yo firmo por medio edificio. Ayer la escuché contarle a otra vecina que le habían regalado una freidora de aire. Todavía no sé cómo decirle que la freidora era mía. (demo)",
  "category": "vecinos",
  "country_code": "ES",
  "lang": "es"
}
JSON

cat >"$work/2.json" <<'JSON'
{
  "body": "En mi trabajo hay un grupo de chat del que nadie habla en voz alta y en el que estamos todos menos el jefe. Llevo dos años ahí dentro. La semana pasada me ascendieron y ahora, técnicamente, dirijo a la mitad del grupo. Nadie ha dicho nada. Yo tampoco. (demo)",
  "category": "trabajo",
  "country_code": "MX",
  "lang": "es"
}
JSON

cat >"$work/3.json" <<'JSON'
{
  "body": "Cuando murió mi abuela encontramos en su armario una caja con cartas de un hombre que no era mi abuelo. Están fechadas a lo largo de cuarenta años, incluidos los que estuvo casada. Mi madre las leyó una noche entera y por la mañana dijo que eran de una amiga. No sabe que yo también las leí. (demo)",
  "category": "familia",
  "country_code": "VE",
  "lang": "es"
}
JSON

for n in 1 2 3; do
  session="$(curl -sS -X POST "$URL/auth/v1/signup" \
    -H "apikey: $KEY" -H "Content-Type: application/json" -d '{}')"

  token="$(printf '%s' "$session" | grep -oE '"access_token":"[^"]+"' | cut -d'"' -f4)"
  uid="$(printf '%s' "$session" | grep -oE '"id":"[0-9a-f-]{36}"' | head -1 | cut -d'"' -f4)"

  if [[ -z "$token" || -z "$uid" ]]; then
    echo "No se pudo crear la cuenta anónima $n." >&2
    exit 1
  fi

  # La política de RLS de `stories` exige author_id = auth.uid(), así que el id
  # tiene que viajar en la fila aunque el servidor ya sepa quién llama.
  sed "1s|^{|{\n  \"author_id\": \"$uid\",|" "$work/$n.json" >"$work/$n.body.json"

  response="$(curl -sS -X POST "$URL/rest/v1/stories" \
    -H "apikey: $KEY" \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    -H "Prefer: return=representation" \
    --data-binary "@$work/$n.body.json")"

  if [[ "$response" != *'"id"'* ]]; then
    echo "Historia $n rechazada: $response" >&2
    exit 1
  fi
  printf 'Historia %s publicada: %s\n' "$n" \
    "$(printf '%s' "$response" | grep -oE '"id":"[^"]+"' | head -1 | cut -d'"' -f4)"
done

echo "Listo."
