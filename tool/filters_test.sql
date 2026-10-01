-- Regression test for the name and insult filters (0016). Run it in the SQL
-- Editor after touching person_names, banned_words, common_words or the
-- filter functions. Expected: aciertos = total, fallos = null.
--   BAD  → contains_banned_word() must be true (story/message refused)
--   NAME → contains_person_name() must be true (story held for review)
--   OK   → neither may fire
with t(esperado, texto) as (values
 ('BAD','Mi jefe es un verguiza'),('BAD','v e r g a para todos'),('BAD','eres un p.u.t.o'),
 ('BAD','v-e-r-g-a'),('BAD','que putita la vecina'),('BAD','pendejazo de primera'),
 ('BAD','gilipoyas'),('BAD','maric0n'),('BAD','h1jueputa'),('BAD','eres un subnormalito'),
 ('BAD','what a b1tch'),('BAD','you f4ggot'),('BAD','such a whoreee'),
 ('BAD','motherfuckers everywhere'),('BAD','retarded kid'),
 ('BAD','Alejito ya deja subir mas chismes de estos de berguiza'),
 ('NAME','Alehandro es tonto'),('NAME','el alexandro de clase'),('NAME','4lej4ndro me debe dinero'),
 ('NAME','ayer vi a Alegandro'),('NAME','Ayer en la uni vi a Daniel Bola Martínez con su novia'),
 ('NAME','conocí a Pepito Pérez en el bar'),('NAME','Sahonero Ampuero no paga'),
 ('NAME','I saw Jessika at the party'),('NAME','my boss Michael is cheating'),
 ('NAME','Mi vecino Cristhian'),('NAME','Alexandro-Kun es de chochobomba'),
 ('NAME','Alejito ya deja subir mas chismes'),('NAME','el danielito de mi clase'),('NAME','Juanillo se fue'),
 ('OK','Qué vergüenza pasé en la boda de mi prima'),
 ('OK','Mi hermano dice que hoy no vamos al cine, qué mierda de día.'),
 ('OK','Ayer fui a Buenos Aires y luego a Nueva York'),('OK','El golfo de México estaba precioso'),
 ('OK','Tengo huevos y negra la camiseta'),('OK','La computadora de la disputa'),
 ('OK','Me puse rojo de la vergüenza en el examen'),('OK','There is a witch in the water'),
 ('OK','My sister met someone at the Walmart yesterday'),('OK','I put the rewards in the travel bag'),
 ('OK','Mucho haber todas serio'),('OK','Mi novio me dejó por mensaje y luego volvió llorando'),
 ('OK','En mi trabajo hay un compañero que se come mi comida'),('OK','El Real Madrid perdió ayer'),
 ('OK','Viajé a Niger y a Mongolia'),('OK','¿Sabías que mi tía se casó otra vez?'),
 ('OK','Un poquito de café y un ratito de siesta'),('OK','Me compré un bolsito y un cafecito'),
 ('OK','We went camping in the mountains'),('OK','No sé, pero me da cosa contarlo... mi ex volvió.'),
 ('OK','Mi perrito se comió el sofá'),('OK','Fui a la playa con mis amigas del cole')
)
select count(*) filter (where acierta) as aciertos, count(*) as total,
       string_agg(case when not acierta then esperado || ': ' || texto end, ' | ') as fallos
from (
  select esperado, texto,
         case esperado
           when 'BAD'  then public.contains_banned_word(texto)
           when 'NAME' then public.contains_person_name(texto)
           else not (public.contains_banned_word(texto) or public.contains_person_name(texto))
         end as acierta
  from t
) x;
