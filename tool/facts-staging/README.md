# facts-staging — lote investigado, **sin revisar por un humano**

Nada de esto ha entrado en `assets/data/facts.json` todavía, y no debe entrar en
bloque. Son 166 entradas producidas por agentes de investigación siguiendo
`BRIEF.md`, con el protocolo de §3.2: buscar, **abrir la página**, y copiar en
`_evidence` la frase literal que sostiene la respuesta.

Lo que ya está comprobado por máquina (`tool/ingest_facts.py --check --links`):

- Esquema completo, categoría válida, ids sin colisión con el catálogo actual.
- Longitudes que caben en la tarjeta y en la imagen 1080x1920.
- `sourceUrl` https, dominio no vetado, y **la URL responde** — cero enlaces
  muertos en las 159 comprobadas.

Lo que **no** puede comprobar una máquina, y es justo donde falló el catálogo
original doce veces: **que la página diga lo que la respuesta afirma**. La URL
puede existir, el organismo puede ser real, y la página puede no hablar del tema.
Para eso está `_evidence`: se lee la frase citada junto a la respuesta y se ve de
un vistazo si la entrada dice más de lo que la fuente sostiene.

## Repaso pendiente antes de fusionar

- [ ] Leer `_evidence` de las 166 y tumbar las que se estiren más que su fuente.
- [ ] Mirar con lupa las que se apoyan en Wikipedia (es fuente de segunda fila,
      §13.1) y subirlas a una primaria donde se pueda.
- [ ] Abrir a mano las 3 de Britannica: devuelven 403 al comprobador automático,
      así que su enlace está sin verificar por máquina.
- [ ] Comprobar que ninguna repite tema con las 85 que ya existen.

## Fusionar

```bash
python3 tool/ingest_facts.py --stage tool/facts-staging --check --links
python3 tool/ingest_facts.py --stage tool/facts-staging --apply
```

`--apply` borra `_evidence` y teje las entradas en la rotación de categorías del
fichero en vez de pegar cuatro bloques al final (§3.2: un bloque largo de la misma
categoría se lee como si la app se hubiera atascado).

Para fusionar solo una parte, saca del directorio los ficheros que no quieras o
recorta los arrays.

## De dónde salió cada lote

Cuatro agentes en paralelo, uno por categoría. Los cuatro se cortaron por límite
de la API antes de llegar a las 100 que pedía el encargo; escribían por tandas, así
que lo que hay es lo investigado hasta el corte, no un lote completo.

| Fichero | Entradas | Encargo |
|---|---|---|
| `ciencia.json` | 40 | física cotidiana, diseño industrial, astronomía, probabilidad |
| `cuerpo.json` | 34 | reflejos, sentidos que mienten, mitos médicos desmentidos |
| `historia.json` | 38 | solapamientos temporales, orígenes accidentales, burocracia vigente |
| `lenguaje.json` | 54 | etimologías, signos, bulos etimológicos famosos |
