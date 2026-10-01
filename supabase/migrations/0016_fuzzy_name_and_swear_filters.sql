-- =============================================================================
-- 0016 — name and swear filters that survive misspellings (ES + EN)
--
-- The 0011/0012 filters compared words exactly, so "Alehandro" passed for
-- "Alejandro" and "verguiza" for "verga". Now every word goes through:
--
--   1. text_canon(): lower case, no accents, leetspeak undone (4→a, 3→e,
--      1→i, 0→o, $→s...), separators turned into spaces and runs of single
--      letters joined back (v.e.r.g.a, v-e-r-g-a, v e r g a → verga), while
--      "Alexandro-Kun" stays two words.
--   2. word_key(): a phonetic key that makes spellings that sound alike
--      equal: j/x/soft g → h, soft c/z → s, qu/k/hard c → k, ll → y, v → b,
--      ph → f, repeated letters once. So alejandro, alehandro, alexandro and
--      4lej4ndro all become "alehandro".
--   3. Matching on those keys:
--        * exact key → name / banned word;
--        * a banned word's stem plus a typical suffix (verg+isa, put+ita,
--          pendej+aso) → banned word;
--        * near miss (Levenshtein, fuzzystrmatch): names of 5+ letters at
--          distance 1 (2 from 9 letters); banned words of 8+ letters at 1;
--        * diminutives of a name (Alejito, Danielito, Pepito, Juanillo).
--      None of this applies to a word in common_words: the 50,000 most
--      frequent Spanish and English words, minus the names, surnames and
--      banned words themselves (supabase/seed/common_words.txt, loaded by
--      supabase/seed/load_common_words.sql,
--      built by tool/build_common_words.py). That is what keeps "mucho",
--      "haber", "water", "golfo", "vergüenza" or "witch" from tripping the
--      fuzzy rules: they only fire on words that are rare or made up, which
--      is exactly where the tricks live.
--   4. Full names: two capitalised words in a row ("Daniel Bola", "Sahonero
--      Ampuero") where at least one is not a common word, or "Nombre
--      Apellido" with a known surname, count as naming someone even when the
--      first name is not on any list. Places made of common words ("Buenos
--      Aires", "Nueva York") do not.
--
-- What the results do is unchanged: names hold a story for review (0011),
-- banned words refuse stories, messages and group names (0002/0005/0011).
-- The English names and insults are new; English names that are everyday
-- words (will, mark, rose, grace, hope, may...) are left out on purpose.
--
-- Run after 0015. Safe to re-run. Then run supabase/seed/load_common_words.sql.
-- =============================================================================

create extension if not exists fuzzystrmatch with schema extensions;

-- -----------------------------------------------------------------------------
-- 1–2. Canonical text and phonetic key.
-- -----------------------------------------------------------------------------
create or replace function public.text_canon(p_text text)
returns text language sql immutable as $fn$
  select regexp_replace(
           regexp_replace(
             translate(
               lower(coalesce(p_text, '')),
               'áéíóúüàèìòùâêîôûäëïöñç4@31!|0$578',
               'aeiouuaeiouaeiouaeioncaaeiiiosstb'
             ),
             '[.\-_*·''´`~^]+', ' ', 'g'),
           '\m([a-z])\s+(?=[a-z]\M)', '\1', 'g');
$fn$;

create or replace function public.text_words(p_text text)
returns text[] language sql immutable as $fn$
  select coalesce(array_agg(distinct w), '{}')
  from regexp_split_to_table(public.text_canon(p_text), '[^a-z]+') as w
  where w <> '';
$fn$;

create or replace function public.word_key(p_word text)
returns text language plpgsql immutable as $fn$
declare
  w text := regexp_replace(coalesce(p_word, ''), '(.)\1+', '\1', 'g');
begin
  w := replace(w, 'ph', 'f');
  w := regexp_replace(w, 'g([ei])', 'h\1', 'g');   -- soft g: gente, ger
  w := regexp_replace(w, 'c([ei])', 's\1', 'g');   -- soft c: cielo
  w := regexp_replace(w, 'qu([ei])', 'k\1', 'g');
  w := regexp_replace(w, 'gu([ei])', 'g\1', 'g');  -- hard gu: guerra
  w := replace(w, 'ch', '9');
  w := translate(w, 'cq', 'kk');
  w := replace(w, '9', 'ch');
  w := replace(w, 'll', 'y');
  w := translate(w, 'jxzv', 'hhsb');
  w := regexp_replace(w, 'y(?![aeiou])', 'i', 'g');
  return regexp_replace(w, '(.)\1+', '\1', 'g');
end;
$fn$;

-- -----------------------------------------------------------------------------
-- 3. Lists, keyed.
-- -----------------------------------------------------------------------------
create table if not exists public.common_words (
  word text primary key  -- canonical form (text_canon), a-z only
);
alter table public.common_words enable row level security;

create table if not exists public.person_surnames (
  name text primary key
);
alter table public.person_surnames enable row level security;

alter table public.person_names
  add column if not exists key text generated always as (public.word_key(name)) stored;
create index if not exists person_names_key_idx on public.person_names (key);

alter table public.banned_words
  add column if not exists key text generated always as (public.word_key(word)) stored;
create index if not exists banned_words_key_idx on public.banned_words (key);

-- English first names (US/UK most common). Names that are ordinary words are
-- deliberately absent.
insert into public.person_names (name)
select unnest(string_to_array(
  'aaron,abigail,adam,aiden,alan,albert,alexander,alexis,alice,amy,andrew,'
  'anna,anthony,arthur,ashley,ava,barbara,betty,beverly,bobby,bradley,'
  'brandon,brian,brittany,bryan,carl,carolyn,catherine,charles,charlotte,'
  'cheryl,chloe,christina,christine,christopher,cynthia,danielle,deborah,'
  'debra,denise,dennis,diane,donald,donna,dorothy,douglas,edward,elijah,'
  'elizabeth,ella,emily,eric,ethan,frances,gary,george,gerald,gregory,'
  'hannah,harold,heather,helen,henry,isabella,jackson,jacob,jacqueline,'
  'james,janet,janice,jason,jeffrey,jeremy,jesse,joan,john,johnny,joseph,'
  'joshua,judith,judy,julie,justin,katherine,kathleen,kathryn,kayla,keith,'
  'kelly,kenneth,kimberly,kyle,larry,lauren,lawrence,liam,linda,lisa,'
  'logan,lori,margaret,marilyn,mary,matthew,megan,mia,michael,michelle,'
  'nancy,natalie,nathan,nicholas,nicole,noah,pamela,patrick,paul,peter,'
  'philip,rachel,rebecca,richard,robert,roger,ronald,russell,ruth,ryan,'
  'samantha,scott,sean,sharon,shirley,sophia,sophie,stephanie,stephen,'
  'steven,susan,terry,theresa,thomas,timothy,tyler,vincent,walter,willie,'
  'zachary',
  ','
))
on conflict do nothing;

-- English insults and slurs aimed at people. Everyday swearing used as
-- punctuation (fuck, shit, damn...) stays out, as in 0012.
insert into public.banned_words (word)
select unnest(string_to_array(
  'asshole,bastard,beaner,bitch,chink,cocksucker,cunt,dickhead,douchebag,'
  'fag,faggot,gook,motherfucker,nigga,nigger,retard,retarded,shemale,'
  'skank,slut,spic,tranny,twat,wetback,whore',
  ','
))
on conflict do nothing;

-- Frequent surnames (Spain, Mexico, Bolivia, US/UK) that are not ordinary
-- words. Surnames like Blanco, Cruz, Santos or King are left out.
insert into public.person_surnames (name)
select unnest(string_to_array(
  'acosta,aguilar,aguirre,alexander,allen,alonso,alvarez,ampuero,anderson,'
  'apaza,arce,arias,avila,barnes,bennett,brooks,bryant,butler,caballero,'
  'cabrera,calvo,camacho,campbell,cardenas,carmona,carrasco,castro,'
  'cervantes,chavez,choque,cole,coleman,collins,colque,condori,contreras,'
  'cooper,copa,cortes,crespo,cuevas,davis,delgado,diaz,dominguez,duran,'
  'edwards,ellis,espinoza,estrada,evans,fernandez,ferrer,figueroa,fisher,'
  'flores,ford,foster,gallego,garcia,garrido,gibson,gimenez,gomez,'
  'gonzales,gonzalez,graham,gray,griffin,guerrero,gutierres,gutierrez,'
  'guzman,hamilton,harris,harrison,hayes,henderson,hernandez,herrera,'
  'herrero,hidalgo,howard,huanca,hughes,ibanez,ibarra,iglesias,james,'
  'jenkins,jimenez,johnson,jones,jordan,lewis,limachi,lopez,lozano,'
  'maldonado,mamani,marin,marquez,marshall,martinez,mcdonald,medina,'
  'mendez,mendoza,mercado,miranda,mitchell,molina,montero,morales,morgan,'
  'morris,munoz,myers,navarro,nieto,nunez,ochoa,orozco,ortega,ortiz,owens,'
  'paredes,pascual,patterson,peralta,perez,perry,peterson,phillips,ponce,'
  'powell,price,prieto,quispe,ramirez,reed,reynolds,richardson,rios,'
  'roberts,robinson,rodriguez,rogers,rojas,roman,romero,rosales,ross,ruiz,'
  'russell,saez,sahonero,salazar,salinas,sanchez,sanders,sandoval,santana,'
  'sanz,serrano,silva,simmons,smith,soria,stewart,suarez,sullivan,'
  'thompson,ticona,torres,trujillo,valdez,vargas,vazquez,velasco,'
  'velazquez,vidal,villca,wallace,ward,washington,watson,west,williams,'
  'wilson,woods,zambrana,zamora',
  ','
))
on conflict do nothing;

-- Stems: the key without its final vowel, for keys of 5+ letters, plus "put"
-- (puta/puto are too short to stem safely by rule).
create or replace view public.banned_stems as
  select distinct
         case when right(key, 1) in ('a', 'e', 'o') then left(key, -1) else key end as stem
  from public.banned_words
  where length(key) >= 5
  union
  select 'put';

revoke all on public.banned_stems from public, anon, authenticated;

-- Suffixes that turn an insult into another form of the same insult.
create or replace function public.insult_suffixes()
returns text[] language sql immutable as $fn$
  select array['s','as','os','es','ita','ito','itas','itos','isa','isas',
               'aso','asa','asos','asas','ote','ota','ona','ones','ero','era',
               'eros','eras','ada','adas','iyo','iya'];
$fn$;

create or replace function public.contains_banned_word(p_text text)
returns boolean language sql stable security definer
set search_path = public, extensions as $fn$
  select exists (
    select 1
    from (
      select w, public.word_key(w) as k
      from unnest(public.text_words(p_text)) as w
      where not exists (select 1 from public.common_words c where c.word = w)
    ) t
    where exists (
            select 1 from public.banned_words b
            where t.k in (b.key, b.key || 's', b.key || 'es')
          )
       or exists (
            select 1 from public.banned_stems s
            where t.k like s.stem || '%'
              and substr(t.k, length(s.stem) + 1) = any (public.insult_suffixes())
          )
       or (length(t.k) >= 8 and exists (
            select 1 from public.banned_words b
            where length(b.key) >= 8
              and abs(length(b.key) - length(t.k)) <= 1
              and levenshtein(b.key, t.k) <= 1
          ))
  );
$fn$;

-- -----------------------------------------------------------------------------
-- 4. Two capitalised words in a row.
-- -----------------------------------------------------------------------------
create or replace function public.mentions_full_name(p_text text)
returns boolean language plpgsql stable security definer
set search_path = public as $fn$
declare
  v_raw         text;
  v_word        text;
  v_canon       text;
  v_cap         boolean;
  v_common      boolean;
  v_surname     boolean;
  v_start       boolean := true;   -- next word starts a sentence
  v_prev_cap    boolean := false;
  v_prev_start  boolean := false;
  v_prev_common boolean := false;
begin
  foreach v_raw in array regexp_split_to_array(
    regexp_replace(coalesce(p_text, ''), '\n', ' . ', 'g'), '\s+')
  loop
    if v_raw ~ '^[¿¡]' then
      v_start := true;
    end if;
    v_word := regexp_replace(v_raw, '^[^[:alpha:]]+|[^[:alpha:]]+$', '', 'g');
    if v_word = '' then
      if v_raw ~ '[.!?:;]' then v_start := true; end if;
      v_prev_cap := false;
      continue;
    end if;

    v_canon   := public.text_canon(v_word);
    v_cap     := v_word ~ '^[[:upper:]][[:lower:]]';
    v_common  := exists (select 1 from public.common_words where word = v_canon);
    v_surname := exists (select 1 from public.person_surnames where name = v_canon);

    if v_cap and not v_start and v_prev_cap and (
         -- "Daniel Bola", "Sahonero Ampuero": one of the two is not a word.
         (not v_prev_start and not (v_common and v_prev_common))
         -- First name + known surname, even at the start of a sentence.
      or v_surname
         -- Both made-up at the start of a sentence: still a name.
      or (v_prev_start and not v_common and not v_prev_common)
    ) then
      return true;
    end if;

    v_prev_cap    := v_cap;
    v_prev_start  := v_start;
    v_prev_common := v_common;
    v_start       := v_raw ~ '[.!?:;]$';
    if v_raw ~ '[,)"»]$' then v_prev_cap := false; end if;
  end loop;
  return false;
end;
$fn$;

create or replace function public.contains_person_name(p_text text)
returns boolean language sql stable security definer
set search_path = public, extensions as $fn$
  select exists (
    select 1
    from (
      select w, public.word_key(w) as k
      from unnest(public.text_words(p_text)) as w
      where not exists (select 1 from public.common_words c where c.word = w)
    ) t
    where exists (select 1 from public.person_names n where n.key = t.k)
       or (length(t.k) >= 5 and exists (
            select 1 from public.person_names n
            where length(n.key) >= 5
              and abs(length(n.key) - length(t.k)) <= 2
              and levenshtein(n.key, t.k) <= case when length(t.k) >= 9 then 2 else 1 end
          ))
       -- Diminutives: Alejito, Danielito, Pepito, Juanillo -> the name.
       or exists (
            select 1
            from public.person_names n,
                 lateral (
                   select substring(t.k from
                     '^(.{3,}?)(?:s?ito|s?ita|sitos|itos|itas|iyo|iya|in)$') as stem
                 ) d
            where d.stem is not null and n.key like d.stem || '%'
          )
  )
  or public.mentions_full_name(p_text);
$fn$;

revoke all on function public.contains_person_name(text) from public, anon, authenticated;
revoke all on function public.contains_banned_word(text) from public, anon, authenticated;
revoke all on function public.mentions_full_name(text) from public, anon, authenticated;

-- Test versions used while tuning this migration.
drop function if exists public.contains_banned_word_v2(text);
drop function if exists public.contains_person_name_v2(text);
drop function if exists public.mentions_full_name_v2(text);
