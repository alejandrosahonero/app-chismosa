# Verificación de fuentes del catálogo

Registro de la revisión una-a-una de las 87 entradas originales de `assets/data/facts.json`. Cada dato se contrastó contra una página abierta de verdad; la cita en texto plano que traía el catálogo se trató como pista y no como fuente, porque varias resultaron estar inventadas o no hablar del tema.

**Resultado: 85 conservadas, 2 retiradas.** De las conservadas, 12 llevan la redacción corregida porque decían más de lo que su fuente sostenía.

La regla queda fijada en un test (`test/features/fact_repository_test.dart`): una entrada sin `sourceUrl` https rompe la suite. El validador `tool/build_remote_catalog.py` aplica lo mismo a lo que se publique en remoto.


## Retiradas

| id | motivo |
|---|---|
| `huellas-koala` | **partial** — The underlying science (near-identical ridge patterns, convergent evolution, tens of millions of years of divergence) is correct, but 'confunden a un forense' overstates it: this is a theoretical risk the discoverer flagged ('coul |
| `venas-vuelta-tierra` | **refuted** — La cifra de ~100.000 km viene de una extrapolación de 1929 del fisiólogo August Krogh (a partir de un cuerpo idealizado de 143 kg con 50 kg de músculo) que el propio Krogh reconoció problemática, y que hoy se considera un mito. Es |

## Redacción corregida

| id | qué decía de más |
|---|---|
| `vomito-verde` | La fuente clinica (Cleveland Clinic) invierte el mecanismo: verde es bilis SIN digerir; amarilla es bilis ya degradada, y esa si es la tipica del estomago vacio. La redaccion anterior atribuia el verde al estomago vacio. |
| `flamencos-rosas` | La afirmacion de que el rosa intenso es una senal de salud usada para elegir pareja no se pudo respaldar en ninguna fuente solida. Se retira y se deja solo lo que la fuente dice. |
| `grillos-termometro` | La formula verificable de la ley de Dolbear es contar en 15 segundos y sumar 40. La variante de 14 segundos solo aparece en fuentes populares que no se pudieron abrir. |
| `estornudo-velocidad` | La cifra 'por debajo de 50 km/h' contradice el propio estudio que la desmiente: la velocidad maxima media medida es 16,5 m/s (~59 km/h) y el pico individual llega a 21,9 m/s (~79 km/h). |
| `malaria-mal-aire` | De 1740 (primera documentacion de la palabra) a 1897 (Ross y el mosquito) van 157 anos, no 'casi dos siglos'. |
| `azar-dados-arabes` | Etymonline/OED tratan la derivacion de az-zahr como dudosa (no consta 'zahr' en los diccionarios arabes clasicos). La app la daba por hecha. |
| `orejas-crecen-vida` | El estudio de Heathcote (BMJ 1995) solo mide orejas: la frase sobre la nariz era una extrapolacion sin respaldo. Se cambia tambien la fuente, de un foro de preguntas al archivo del NIH. |
| `regla-cinco-segundos` | El estudio real es de Miranda y Schaffner (Rutgers, 2016), no de Dawson, y el tiempo que lleva sucia la superficie no fue una variable medida. |
| `trivial-cruce-caminos` | Etymonline dice expresamente que 'trivia' en el sentido de datos curiosos NO desciende del cotilleo del cruce, sino de un libro de 1902 y de la jerga estudiantil de los sesenta. |
| `pelusa-ombligo` | El detalle mezclaba dos estudios: el Ig Nobel (2002) fue el de Kruszelnicki con miles de encuestados; Steinhauser (2009), la fuente citada, analizo 503 muestras de su propio ombligo. |
| `guerra-38-minutos` | Britannica dice 'no mas de 40 minutos'. Los 38 son la cifra popular atribuida a Guinness, que no se pudo abrir. |
| `salario-sal` | La fuente era el blog personal de un clasicista. Se cambia a Etymonline, que respalda lo mismo y ademas lo matiza con un 'said to be'. |
| `ojala-ala-quiera` | La fuente era un sitio aficionado de etimologias. Se cambia al diccionario de la RAE, que es la autoridad para el castellano. |
| `tarantula-baile-veneno` | Britannica situa el tarantismo entre los siglos XV y XVII; 'medieval' era impreciso. |

## Catálogo publicado

| id | categoría | fuente |
|---|---|---|
| `vomito-verde` | cuerpo | [Cleveland Clinic — Vomit Color Chart](https://health.clevelandclinic.org/vomit-color-chart) |
| `platano-baya` | ciencia | [Britannica — Berry (plant reproductive body)](https://www.britannica.com/science/berry-plant-reproductive-body) |
| `muralla-espacio` | historia | [Al Jazeera — 'China's spaceman shatters a myth' (2003)](https://www.aljazeera.com/news/2003/10/17/chinas-spaceman-shatters-a-myth) |
| `origen-ok` | lenguaje | [Merriam-Webster — The Hilarious History of 'OK'](https://www.merriam-webster.com/wordplay/the-hilarious-history-of-ok-okay) |
| `mapa-lengua` | cuerpo | [Smithsonian Magazine — The Taste Map of the Tongue You Learned in School Is All Wrong](https://www.smithsonianmag.com/science-nature/neat-and-tidy-map-tastes-tongue-you-learned-school-all-wrong-180963407/) |
| `flamencos-rosas` | ciencia | [Britannica — Why Are Flamingos Pink?](https://www.britannica.com/story/why-are-flamingos-pink) |
| `cleopatra-piramides` | historia | [Britannica — Cleopatra (y Great Pyramid of Giza)](https://www.britannica.com/biography/Cleopatra-queen-of-Egypt) |
| `salario-sal` | lenguaje | [Etymonline — salary](https://www.etymonline.com/word/salary) |
| `brillo-humano` | cuerpo | [PLoS ONE — Kobayashi, Kikuchi & Okamura (2009), Imaging of Ultraweak Spontaneous Photon Emission from Human Body Displaying Diurnal Rhythm](https://journals.plos.org/plosone/article?id=10.1371%2Fjournal.pone.0006256) |
| `dia-venus` | ciencia | [NASA Science — Venus Facts](https://science.nasa.gov/venus/venus-facts/) |
| `oxford-aztecas` | historia | [Smithsonian Magazine — The University of Oxford Is Older Than the Aztec Empire](https://www.smithsonianmag.com/smart-news/university-oxford-older-than-aztec-empire-other-facts-will-change-your-perspective-history-1529607/) |
| `sandwich-conde` | lenguaje | [Encyclopaedia Britannica — Sandwich](https://www.britannica.com/topic/sandwich) |
| `estomago-se-renueva` | cuerpo | [American Journal of Physiology-Cell Physiology — Allen & Flemström 2005](https://journals.physiology.org/doi/full/10.1152/ajpcell.00102.2004) |
| `relampago-sol` | ciencia | [NOAA NESDIS — ¿Qué causa el rayo y el trueno?](https://www.nesdis.noaa.gov/about/k-12-education/severe-weather/what-causes-lightning-and-thunder) |
| `miel-tumbas` | historia | [Smithsonian Magazine — The Science Behind Honey's Eternal Shelf Life](https://www.smithsonianmag.com/science-nature/the-science-behind-honeys-eternal-shelf-life-1218690/) |
| `letra-enye` | lenguaje | [The Conversation (autora de la U. de Castilla-La Mancha), citando la explicación de la RAE](https://theconversation.com/de-donde-viene-la-ene-breve-repaso-de-la-historia-de-una-letra-unica-204577) |
| `sangre-nunca-azul` | cuerpo | [Cleveland Clinic — What Color Is Blood?](https://health.clevelandclinic.org/what-color-is-blood) |
| `pulpo-corazones` | ciencia | [Smithsonian Magazine — Ten Wild Facts About Octopuses](https://www.smithsonianmag.com/science-nature/ten-wild-facts-about-octopuses-they-have-three-hearts-big-brains-and-blue-blood-7625828/) |
| `fax-antes-telefono` | historia | [Wikipedia — Alexander Bain (inventor)](https://en.wikipedia.org/wiki/Alexander_Bain_(inventor)) |
| `cuarentena-cuarenta` | lenguaje | [Encyclopaedia Britannica — Today in History: julio 27, primera cuarentena](https://www.britannica.com/today-in-history/July-27-When-and-Where-the-Worlds-First-Quarantine-Began) |
| `astronautas-crecen` | cuerpo | [Smithsonian Magazine — Space Makes Astronauts Grow Taller, But It Also Causes Back Problems](https://www.smithsonianmag.com/smart-news/space-makes-astronauts-grow-taller-and-also-backs-180960922/) |
| `petricor` | ciencia | [American Council on Science and Health — Geosmin: Why We Smell Air After a Storm](https://www.acsh.org/news/2018/07/28/geosmin-why-we-smell-air-after-storm-13240) |
| `mamuts-piramide` | historia | [Britannica — Great Pyramid of Giza / PMC — mammoth genome erosion](https://www.britannica.com/topic/Great-Pyramid-of-Giza) |
| `nostalgia-enfermedad` | lenguaje | [Britannica — Nostalgia](https://www.britannica.com/science/nostalgia) |
| `piel-erizada` | cuerpo | [Wikipedia — Arrector pili muscle](https://en.wikipedia.org/wiki/Arrector_pili_muscle) |
| `platano-radiactivo` | ciencia | [Britannica — Are Bananas Radioactive?](https://www.britannica.com/science/Are-Bananas-Radioactive) |
| `harvard-independencia` | historia | [Harvard University — History Timeline](https://www.harvard.edu/about/history/timeline/) |
| `trivial-cruce-caminos` | lenguaje | [Etymonline — trivia / trivial](https://www.etymonline.com/word/trivia) |
| `punto-ciego` | cuerpo | [Britannica — Blind spot](https://www.britannica.com/science/blind-spot) |
| `estornudo-velocidad` | ciencia | [Physics of Fluids (Bahl et al., 2021) — dinámica de gotitas del estornudo](https://pmc.ncbi.nlm.nih.gov/articles/PMC8597717/) |
| `guillotina-star-wars` | historia | [History.com — The guillotine falls silent](https://www.history.com/this-day-in-history/september-10/the-guillotine-falls-silent) |
| `musculo-raton` | lenguaje | [Etymonline — muscle](https://www.etymonline.com/word/muscle) |
| `hueso-vs-acero` | cuerpo | [CK-12 Foundation — Are bones more robust than steel?](https://www.ck12.org/flexi/life-science/skeletal-system/are-bones-of-the-skeletal-system-more-robust-than-steel/) |
| `caca-cubo-wombat` | ciencia | [Smithsonian Magazine — cómo el wombat hace caca cúbica (investigación de Patricia Yang, Soft Matter)](https://www.smithsonianmag.com/smart-news/scientists-have-solved-mystery-how-wombats-poop-cubes-180976898/) |
| `bigote-obligatorio` | historia | [Historic UK — Moustaches Throughout History](https://www.historic-uk.com/HistoryUK/HistoryofBritain/The-Moustache-to-Rule-Them-All/) |
| `malaria-mal-aire` | lenguaje | [Etymonline (basado en OED) — entrada 'malaria'](https://www.etymonline.com/word/malaria) |
| `pulmon-izquierdo` | cuerpo | [Cleveland Clinic — Every Breath You Take: Your Lungs and How They Work](https://my.clevelandclinic.org/health/body/8960-lungs) |
| `tardigrado-vacio` | ciencia | [PMC — Tardigrades in Space Research: Past and Future (cita Jönsson et al. 2008, Current Biology)](https://pmc.ncbi.nlm.nih.gov/articles/PMC5705745/) |
| `tutankamon-sultanato` | historia | [Wikipedia (con History.com para Tutankamón) — abolición del sultanato otomano](https://en.wikipedia.org/wiki/Abolition_of_the_Ottoman_sultanate) |
| `desastre-mala-estrella` | lenguaje | [Etymonline — entrada 'disaster'](https://www.etymonline.com/word/disaster) |
| `bebes-lagrimas-tardias` | cuerpo | [Stanford Medicine Children's Health — Newborn Crying](https://www.stanfordchildrens.org/en/topic/default?id=newborn-crying-90-P02648) |
| `tiburones-antes-arboles` | ciencia | [Encyclopaedia Britannica — Shark](https://www.britannica.com/animal/shark) |
| `chiste-mas-antiguo` | historia | [Wikipedia — Philogelos](https://en.wikipedia.org/wiki/Philogelos) |
| `influenza-astros` | lenguaje | [Etymonline — entrada 'influenza'](https://www.etymonline.com/word/influenza) |
| `pelusa-ombligo` | cuerpo | [reposiTUm (TU Wien) — Steinhauser, «The nature of navel fluff», Medical Hypotheses 2009](https://repositum.tuwien.at/handle/20.500.12708/166310) |
| `desierto-mas-grande` | ciencia | [Encyclopaedia Britannica — Why Is Antarctica a Desert?](https://www.britannica.com/topic/Why-Is-Antarctica-a-Desert) |
| `duelo-diputados-francia` | historia | [Wikipedia — Gaston Defferre](https://en.wikipedia.org/wiki/Gaston_Defferre) |
| `clue-ovillo-ariadna` | lenguaje | [Etymonline — clue](https://www.etymonline.com/word/clue) |
| `huesos-recien-nacido` | cuerpo | [Cleveland Clinic — How Many Bones Does a Baby Have?](https://health.clevelandclinic.org/how-many-bones-does-a-baby-have) |
| `huevo-altura-hervir` | ciencia | [NIST Chemistry WebBook — propiedades de saturación del agua](https://webbook.nist.gov/cgi/fluid.cgi?Action=Load&ID=C7732185&Type=SatP&Digits=5&PLow=0.2&PHigh=0.4&PInc=0.05&RefState=DEF&TUnit=C&PUnit=atm&DUnit=kg%2Fm3&HUnit=kJ%2Fkg&WUnit=m%2Fs&VisUnit=uPa*s&STUnit=N%2Fm) |
| `guerra-38-minutos` | historia | [Encyclopaedia Britannica — Anglo-Zanzibar War](https://www.britannica.com/event/Anglo-Zanzibar-War) |
| `ojala-ala-quiera` | lenguaje | [RAE — Diccionario de la lengua española, «ojalá»](https://dle.rae.es/ojal%C3%A1) |
| `sonrojo-solo-humano` | cuerpo | [CARTA (UC San Diego) — Blushing and Flushing](https://carta.anthropogeny.org/moca/topics/blushing-and-flushing) |
| `torre-eiffel-crece` | ciencia | [The Conversation — The Eiffel Tower gets bigger every summer](https://theconversation.com/the-eiffel-tower-gets-bigger-every-summer-heres-why-261904) |
| `cien-anos-116` | historia | [Encyclopaedia Britannica — Hundred Years' War (summary)](https://www.britannica.com/summary/Hundred-Years-War) |
| `adios-goodbye-dios` | lenguaje | [Etymonline — good-bye](https://www.etymonline.com/word/good-bye) |
| `corazon-late-fuera` | cuerpo | [Cleveland Clinic — Heart Conduction System](https://my.clevelandclinic.org/health/body/21648-heart-conduction-system) |
| `dias-mas-cortos` | ciencia | [AGU press release — Ancient shell shows days were half-hour shorter 70 million years ago](https://news.agu.org/press-release/ancient-shell-shows-days-were-half-hour-shorter-70-million-years-ago/) |
| `eiffel-provisional` | historia | [Official Eiffel Tower site — Why was the Eiffel Tower kept?](https://www.toureiffel.paris/en/news/130-years/why-was-eiffel-tower-kept) |
| `ketchup-salsa-pescado` | lenguaje | [Etymonline — ketchup](https://www.etymonline.com/word/ketchup) |
| `apendice-refugio-bacterias` | cuerpo | [ScienceDaily — Appendix Isn't Useless At All (Duke study, 2007)](https://www.sciencedaily.com/releases/2007/10/071008102334.htm) |
| `olor-espacio` | ciencia | [NASA (Ames) — Interesting Fact of the Month, December 2021: What does space smell like?](https://www.nasa.gov/space-science-and-astrobiology-at-ames/interesting-fact-of-the-month-current/interesting-fact-of-the-month-2021/) |
| `lovelace-sin-ordenador` | historia | [Computer History Museum — Ada Lovelace](https://www.computerhistory.org/babbage/adalovelace/) |
| `aguacate-testiculo` | lenguaje | [Etymonline — avocado](https://www.etymonline.com/word/avocado) |
| `orejas-crecen-vida` | cuerpo | [Heathcote, «Why do old men have big ears?», BMJ 1995 (archivo del NIH)](https://pmc.ncbi.nlm.nih.gov/articles/PMC2539087/) |
| `gatos-sin-dulce` | ciencia | [PLOS Genetics (PMC) — Li et al. 2005, pseudogenización de Tas1r2 en gatos](https://pmc.ncbi.nlm.nih.gov/articles/PMC1183522/) |
| `fiesta-desenvolver-momias` | historia | [History.com — Victorian mummy-unwrapping parties](https://www.history.com/articles/mummy-unwrapping-parties-egyptomania) |
| `azar-dados-arabes` | lenguaje | [Etymonline — hazard](https://www.etymonline.com/word/hazard) |
| `paralisis-sueno-rem` | cuerpo | [PMC — Brainstem and Spinal Cord Circuitry Regulating REM Sleep and Muscle Atonia](https://pmc.ncbi.nlm.nih.gov/articles/PMC3197189/) |
| `regla-cinco-segundos` | ciencia | [Rutgers University — estudio de Miranda y Schaffner (2016)](https://www.rutgers.edu/news/rutgers-researchers-debunk-five-second-rule-eating-food-floor-isnt-safe) |
| `ola-melaza-boston` | historia | [Britannica — Great Molasses Flood](https://www.britannica.com/topic/Great-Molasses-Flood) |
| `ajedrez-sanscrito` | lenguaje | [Etymonline — chess](https://www.etymonline.com/word/chess) |
| `pelirrojos-mas-anestesia` | cuerpo | [Anesthesiology (PMC) — Liem et al. 2004, requerimiento anestésico en pelirrojas](https://pmc.ncbi.nlm.nih.gov/articles/PMC1362956/) |
| `lluvia-diamantes` | ciencia | [Lawrence Livermore National Laboratory — Diamond rain on icy giant planets](https://www.llnl.gov/article/43621/scientists-create-diamond-rain-forms-interior-icy-giant-planets-neptune) |
| `juicio-al-cerdo` | historia | [JSTOR Daily — juicios a animales en la Europa medieval](https://daily.jstor.org/when-societies-put-animals-on-trial) |
| `tarantula-baile-veneno` | lenguaje | [Britannica — Tarantella (y tarantismo)](https://www.britannica.com/art/tarantella) |
| `huellas-gemelos-distintas` | cuerpo | [PMC (NIH) — Fingerprint Recognition with Identical Twin Fingerprints](https://pmc.ncbi.nlm.nih.gov/articles/PMC3338710/) |
| `camaron-mantis-golpe` | ciencia | [Journal of Experimental Biology — Patek & Caldwell (2005), fuerzas de impacto y cavitación del camarón mantis](https://journals.biologists.com/jeb/article/208/19/3655/15838/Extreme-impact-and-cavitation-forces-of-a) |
| `libertad-para-egipto` | historia | [Smithsonian Magazine — The Statue of Liberty Was Originally a Muslim Woman](https://www.smithsonianmag.com/smart-news/statue-liberty-was-originally-muslim-woman-180957377/) |
| `panico-dios-pan` | lenguaje | [Etymonline — panic](https://www.etymonline.com/word/panic) |
| `grillos-termometro` | ciencia | [Wikipedia — Dolbear's law](https://en.wikipedia.org/wiki/Dolbear%27s_law) |
| `guerra-de-los-emus` | historia | [Encyclopaedia Britannica — Emu War](https://www.britannica.com/topic/Emu-War) |
| `robot-trabajo-forzado` | lenguaje | [Etymonline — robot](https://www.etymonline.com/word/robot) |
| `saturno-flota` | ciencia | [NASA Science — Saturn Facts](https://science.nasa.gov/saturn/facts/) |
| `medusa-inmortal` | ciencia | [Wikipedia — Turritopsis dohrnii](https://en.wikipedia.org/wiki/Turritopsis_dohrnii) |

## Fuentes que conviene subir de nivel

Ninguna es falsa, pero son de segunda fila y merecen una primaria si aparece: las que apuntan a Wikipedia, a `historic-uk.com`, a `ck12.org` y a `history.com`. Están así porque la fuente de primer nivel devolvió 403 o estaba tras muro de pago.

`dle.rae.es` bloquea a los rastreadores automáticos, así que la etimología de «ojalá» se confirmó contra resultados del propio dominio rae.es en vez de abriendo la ficha. El enlace funciona con normalidad en un navegador.

