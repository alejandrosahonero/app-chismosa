-- =============================================================================
-- ¿Cuánta gente usa Chismosa? Pegar en el SQL Editor de Supabase.
--
-- "Registrado" aquí es "instaló la app y abrió al menos una vez": cada
-- instalación crea su cuenta anónima al arrancar. Una reinstalación que
-- restaura la cuenta NO cuenta doble.
--
-- La actividad sale de profiles.last_seen_at (0008), que la app actualiza en
-- cada apertura. Antes de la 0008 no existe, así que los activos empiezan a
-- contar desde ese día.
--
-- Para descargas e instalaciones "oficiales", la fuente es Play Console
-- (Estadísticas); para la tasa de retención, Play Console → Adquisición de
-- usuarios → Retención.
-- =============================================================================

select
  (select count(*) from public.profiles where not is_house)                        as cuentas_totales,
  (select count(*) from public.profiles
     where not is_house and last_seen_at > now() - interval '1 day')              as activos_24h,
  (select count(*) from public.profiles
     where not is_house and last_seen_at > now() - interval '7 days')             as activos_7d,
  (select count(*) from public.profiles
     where not is_house and last_seen_at > now() - interval '30 days')            as activos_30d,
  (select count(*) from public.profiles where is_premium and not is_house)          as premium,
  (select count(*) from public.profiles where is_banned)                            as baneados;

-- Por país (el del móvil de cada cuenta).
select coalesce(country_code, '??') as pais,
       count(*) as cuentas,
       count(*) filter (where last_seen_at > now() - interval '7 days') as activos_7d
from public.profiles
where not is_house
group by 1
order by 2 desc;

-- Contenido de los últimos 7 días: lo que indica si el mazo se llena solo.
select
  (select count(*) from public.stories s join public.profiles p on p.id = s.author_id
     where not p.is_house and s.created_at > now() - interval '7 days')           as historias_7d,
  (select count(distinct s.author_id) from public.stories s
     join public.profiles p on p.id = s.author_id
     where not p.is_house and s.created_at > now() - interval '7 days')           as escritores_7d,
  (select count(*) from public.messages where created_at > now() - interval '7 days') as mensajes_7d,
  (select count(*) from public.stories
     where hidden and created_at > now() - interval '7 days')                     as ocultadas_7d;

-- Altas por día (últimos 30 días).
select date_trunc('day', u.created_at)::date as dia, count(*) as altas
from auth.users u
join public.profiles p on p.id = u.id
where not p.is_house and u.created_at > now() - interval '30 days'
group by 1
order by 1 desc;
