-- =============================================================================
-- Revisar lo reportado como "señala a alguien". Pegar en el SQL Editor.
--
-- Esas historias y mensajes se ocultan en cuanto alguien los reporta con ese
-- motivo, y el autor recibe un aviso de que están "en revisión". Esta es esa
-- revisión: alguien tiene que hacerla, idealmente una vez al día. Si no se
-- hace, el aviso que recibió el autor sería mentira.
-- =============================================================================

-- review_reason = 'auto_name': historias que el servidor retuvo solas porque
-- contienen un nombre de pila común (0011). Si el nombre no es de una persona
-- real o no le hace daño, restaurar; si señala a alguien, dejarla oculta.

-- 1. Qué está esperando decisión, lo más antiguo primero.
select * from public.pending_reviews;

-- 2. Decidir, una fila cada vez. Copiar el id de la consulta de arriba.
--
--    Señala de verdad a una persona → se queda oculta y cuenta como falta
--    (tres faltas banean la cuenta):
--      select public.review_content('story', '<id>', false);
--
--    No señala a nadie → vuelve a estar visible y el autor recibe un aviso:
--      select public.review_content('story', '<id>', true);
--
--    Para mensajes, lo mismo con 'message' en lugar de 'story'.

-- 3. Quién abusa del botón: personas con muchos "señala a alguien" en la
--    última semana que acabaron restauradas. No se castiga automáticamente;
--    sirve para decidir a mano.
select r.reporter_id, count(*) as reportes, count(*) filter (
         where s.review_status = 'restored'
       ) as restaurados
from public.reports r
left join public.stories s on s.id = r.target_id and r.target_type = 'story'
where r.reason = 'names_someone' and r.created_at > now() - interval '7 days'
group by 1
having count(*) >= 3
order by restaurados desc;
