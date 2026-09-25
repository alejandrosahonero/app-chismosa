-- =============================================================================
-- Las 10 historias "de la casa" del lanzamiento (España, México, Bolivia).
--
-- Se ejecuta UNA vez en el SQL Editor de Supabase, después de las migraciones
-- 0001 a 0008. Es idempotente: si ya existen, no duplica nada.
--
-- Qué hace:
--   1. Borra las tres historias demo del principio (llevan "(demo)" y se hacían
--      pasar por usuarios) y la historia basura de las pruebas.
--   2. Crea la cuenta de la casa (anónima, sin email) y la marca is_house.
--      Premium para que el límite diario no la frene.
--   3. Publica diez historias, repartidas en los últimos tres días para que el
--      orden "populares" no las apile. Las dos últimas son una serie (parte 1 y
--      parte 2), para que el lanzamiento enseñe los capítulos desde el día uno.
--
-- En la app se ven con la píldora "De la casa". Nunca se hacen pasar por
-- historias de usuarios.
-- =============================================================================

-- 1. Limpieza.
delete from public.stories where body like '%(demo)%';
delete from public.stories where id = '90f59fbc-8423-4e0d-b84d-b82e5d641de8';

do $$
declare
  v_house uuid := '00000000-0000-4000-8000-0000000c4a5a';
  v_part1 uuid;
begin
  -- 2. La cuenta de la casa. handle_new_user() (0001) crea su perfil.
  insert into auth.users (
    id, instance_id, aud, role, is_anonymous,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at
  ) values (
    v_house, '00000000-0000-0000-0000-000000000000', 'authenticated',
    'authenticated', true,
    '{"provider":"anonymous","providers":["anonymous"]}'::jsonb, '{}'::jsonb,
    now(), now()
  ) on conflict (id) do nothing;

  update public.profiles
    set is_house = true, is_premium = true, languages = '{es}'
    where id = v_house;

  if exists (select 1 from public.stories where author_id = v_house) then
    raise notice 'Las historias de la casa ya estaban publicadas.';
    return;
  end if;

  -- 3. Las historias.
  insert into public.stories (author_id, body, category, lang, country_code, created_at) values
  (v_house, 'En mi oficina alguien se come los yogures de la nevera desde hace un año. Hoy dejé uno con una nota: «Sé quién eres». Ha desaparecido igual. Y la nota ha vuelto a mi mesa con una respuesta: «Y yo sé lo que cobras».',
   'trabajo', 'es', 'ES', now() - interval '70 hours'),
  (v_house, 'El vecino del tercero ensaya con la batería todos los domingos a las diez. Hicimos junta, carta y hasta una colecta para insonorizarle el piso. Hoy me he enterado de que la batería es de la presidenta de la comunidad. Ella toca los martes.',
   'vecinos', 'es', 'ES', now() - interval '64 hours'),
  (v_house, 'Llevo seis meses quedando con alguien que conocí en una app. Ayer, en la boda de mi prima, lo vi sentado en la mesa de los novios. Es el hermano del novio. Y está casado. Con la otra dama de honor.',
   'amor', 'es', 'ES', now() - interval '52 hours'),
  (v_house, 'Mi madre lleva toda la vida diciendo que la receta de las croquetas es secreta, de la bisabuela. Ayer encontré la bolsa en el fondo del congelador. Las compra hechas. La familia lleva veinte años peleándose por una herencia de supermercado.',
   'familia', 'es', 'ES', now() - interval '30 hours'),
  (v_house, 'Mi tía organizó una tanda con toda la familia y la primera en cobrar fue ella. Van tres meses y dice que el banco le «retuvo» el dinero. Ayer subió fotos en la playa. Con sombrero nuevo.',
   'dinero', 'es', 'MX', now() - interval '60 hours'),
  (v_house, 'Mi mejor amiga me pidió que le guardara un secreto: se va a vivir a otra ciudad y todavía no quiere que nadie lo sepa. Hoy supe que a cada una de nuestras amigas le dijo una ciudad distinta. Creo que quiere averiguar quién habla.',
   'amistad', 'es', 'MX', now() - interval '40 hours'),
  (v_house, 'En la universidad un profe pone el mismo examen desde hace años. Lo sabemos todos y él sabe que lo sabemos. Este semestre cambió una sola pregunta: «¿Quién te pasó el examen?». Media clase la dejó en blanco.',
   'escuela', 'es', 'MX', now() - interval '20 hours'),
  (v_house, 'En mi barrio la señora de la tienda sabe todo antes que nadie: quién se casa, quién se separa, quién debe. Un día le pregunté cómo lo hace. «Hijita, la gente viene por pan y se queda a confesarse». Hoy me contó lo tuyo.',
   'vecinos', 'es', 'BO', now() - interval '56 hours');

  insert into public.stories (author_id, body, category, lang, country_code, created_at)
  values (v_house, 'Entré a trabajar a una oficina pública hace un mes. El primer día me dieron un escritorio con un cajón cerrado con llave y me dijeron que nunca lo abriera. Hoy encontré la llave pegada debajo de la silla. Sigue mañana.',
          'trabajo', 'es', 'BO', now() - interval '34 hours')
  returning id into v_part1;

  -- Parte 2: el trigger de capítulos (0007) le pone chapter = 2.
  insert into public.stories (author_id, body, category, lang, country_code, parent_id, created_at)
  values (v_house, 'Abrí el cajón. Había un cuaderno con los cumpleaños de todos los de la oficina, qué regalo le gusta a cada uno y quién no se habla con quién. Lo llevaba la persona que tenía mi puesto antes. Ahora entiendo por qué todos me traen café.',
          'trabajo', 'es', 'BO', v_part1, now() - interval '10 hours');
end $$;

-- Comprobación: deberían salir 10 filas, dos de ellas con chapter 1 y 2.
select s.country_code, s.chapter, left(s.body, 60) as inicio
from public.stories s join public.profiles p on p.id = s.author_id
where p.is_house
order by s.created_at;
