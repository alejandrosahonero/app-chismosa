-- =============================================================================
-- 0012 — the banned-words list, matched as whole words
--
-- The table existed since 0001 but was empty, so the filter caught nothing.
-- It also matched substrings (ilike '%word%'), which would have refused
-- "disputa" or "computadora" the moment "puta" went in. Now a word matches
-- only as a whole word (with an optional plural), accents and case ignored.
--
-- What goes in: insults and slurs aimed at people (sexuality, race, disability,
-- appearance). What stays out on purpose: everyday swearing used as
-- punctuation (mierda, joder, coño, carajo, hostia, pinche...), and words
-- that are also ordinary nouns (perra, cerdo, foca, basura). Refusing
-- "qué mierda de día" would make the app unusable for the stories it exists
-- for, and it harms nobody.
--
-- Private groups can turn the filter off (allow_swearing, 0011).
--
-- Run after 0011. Safe to re-run.
-- =============================================================================

create or replace function public.contains_banned_word(p_text text)
returns boolean language sql stable security definer set search_path = public as $fn$
  select exists (
    select 1
    from regexp_split_to_table(public.fold_accents(p_text), '[^a-zñ]+') as w(word)
    join public.banned_words b
      on w.word in (b.word, b.word || 's', b.word || 'es')
  );
$fn$;

-- Sexuality and gender, race and origin, disability and illness, insults.
insert into public.banned_words (word)
select unnest(string_to_array(
  'maricon,marica,mariquita,joto,jotito,bollera,tortillera,travelo,'
  'sarasa,mariposon,'
  'negrata,sudaca,panchito,moraco,'
  'subnormal,retrasado,retrasada,mongolo,mongola,mongolico,mongolica,'
  'sidoso,sidosa,'
  'puta,puto,zorra,guarra,golfa,'
  'gilipollas,imbecil,'
  'cabron,cabrona,capullo,capulla,pendejo,pendeja,huevon,huevona,'
  'cojudo,cojuda,malparido,malparida,hijueputa,'
  'mamon,mamona,culero,culera,verga,chinga,chingada,'
  'chingado,desgraciado,desgraciada,bastardo,bastarda,escoria',
  ','
))
on conflict do nothing;
