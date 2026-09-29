-- =============================================================================
-- 0011 — names held for review, group rules
--
-- 1. Names. The first testers' stories named real people with full names and
--    their supposed sexuality, which is exactly what killed Yik Yak. A regex
--    cannot tell a name from a word, so this does not refuse anything: a story
--    that contains a common first name is published *hidden*, pending review
--    (review_status = 'pending', review_reason = 'auto_name'), and goes through
--    the same review_content() as "señala a alguien" (tool/moderation.sql).
--    Phones, e-mails, handles and links are still refused outright (0007).
--
--    Ambiguous names that are also everyday words (Rosa, Luz, Mercedes, Pilar,
--    Ángel...) are left out of the list on purpose: holding every story that
--    says "rosa" would make review impossible.
--
-- 2. Group rules. A private group of friends can turn off two rules:
--      allow_names    — names are not held for review;
--      allow_swearing — the banned-words filter does not apply.
--    Personal data, the report / block system and everything illegal apply
--    everywhere, always. The worldwide deck always has every rule on.
--    Rules are chosen when the group is created and can only be tightened
--    afterwards, so nobody who joined a strict group finds it relaxed.
--
-- Run after 0010. Safe to re-run.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Names.
-- -----------------------------------------------------------------------------
create table if not exists public.person_names (
  name text primary key  -- lower case, no accents
);
alter table public.person_names enable row level security;
-- Server side only. No grants.

insert into public.person_names (name)
select unnest(string_to_array(
  -- Spain, Mexico, Bolivia: common first names and nicknames, lower case,
  -- without accents. Ambiguous words (rosa, luz, sol, paz, mar, pilar, cruz,
  -- reyes, santos, blanca, clara, victoria, esperanza, angel, mercedes,
  -- leo ("I read"), simon ("yes" in Mexico), dolores, gloria, milagros...)
  -- deliberately absent.
  'alejandro,alejandra,alex,ale,adrian,adriana,agustin,agustina,aitana,alba,'
  'alberto,alfonso,alfredo,alicia,alvaro,amanda,ana,andrea,andres,angela,'
  'angelica,antonio,antonia,ariadna,armando,arturo,aurora,axel,beatriz,bea,'
  'benjamin,bernardo,berta,brenda,bruno,camila,carla,carlos,carlitos,carmen,'
  'carolina,catalina,cecilia,cesar,christian,cristian,cristina,claudia,'
  'daniel,dani,daniela,dario,david,diana,diego,eduardo,edu,elena,'
  'eliana,elias,elisa,elsa,emilio,emilia,emma,enrique,erick,erik,ernesto,'
  'esteban,estefania,eugenia,eva,evelyn,fabian,fabiola,federico,felipe,'
  'fernando,fer,fernanda,francisco,fran,frida,gabriel,gabriela,gabi,gael,'
  'gerardo,german,gilberto,gisela,gonzalo,guadalupe,lupe,lupita,'
  'guillermo,memo,gustavo,hector,hugo,ignacio,nacho,ines,irene,isaac,isabel,'
  'isabela,ismael,ivan,ivonne,jaime,javier,javi,jazmin,jennifer,jesus,chucho,'
  'jimena,joaquin,jonathan,jordi,jorge,jose,pepe,josefina,juan,juanito,juana,'
  'juanjo,julia,julian,julio,karen,karina,kevin,laura,leonardo,leticia,'
  'liliana,lorena,lorenzo,lucas,lucia,luciana,luis,luisa,lucho,manuel,manolo,'
  'manu,marcela,marcelo,marco,marcos,maria,mari,mariana,mariano,'
  'maribel,marina,mario,marisol,marta,martha,martin,mateo,matias,mauricio,'
  'maximiliano,max,melissa,miguel,miriam,monica,natalia,nati,nerea,'
  'nicolas,nico,noelia,nuria,oliver,olivia,omar,oscar,pablo,paola,patricia,'
  'paty,paula,pedro,paco,rafael,rafa,ramiro,ramon,raquel,raul,rebeca,regina,'
  'renata,ricardo,roberto,rocio,rodrigo,rogelio,rolando,ruben,samuel,sandra,'
  'santiago,santi,sara,sarah,sebastian,sergio,silvia,sofia,sonia,'
  'susana,tania,teresa,tere,tomas,valentina,valeria,vanesa,vanessa,veronica,'
  'vicente,victor,ximena,yolanda,zoe,toño,conchi,nando,'
  'kike,quique,chema,charly,fede,guille,jaume,marc,pau,oriol,unai,iker,'
  'aimar,izan,hugo,thiago,dylan,brayan,jhonny,wilmer,wilson,edwin,freddy,'
  'grover,limbert,marcelino,ximena,yessica,jessica,mayra,wendy,araceli,'
  'jiahe',
  ','
))
on conflict do nothing;

-- Accents off and lower case, without the unaccent extension.
create or replace function public.fold_accents(p_text text)
returns text language sql immutable as $fn$
  select translate(lower(coalesce(p_text, '')), 'áéíóúüàèìòùâêîôû', 'aeiouuaeiouaeiou');
$fn$;

create or replace function public.contains_person_name(p_text text)
returns boolean language sql stable security definer set search_path = public as $fn$
  select exists (
    select 1
    from regexp_split_to_table(public.fold_accents(p_text), '[^a-zñ]+') as w(word)
    join public.person_names n on n.name = w.word
  );
$fn$;

-- -----------------------------------------------------------------------------
-- 2. Group rules.
-- -----------------------------------------------------------------------------
alter table public.groups
  add column if not exists allow_names    boolean not null default false,
  add column if not exists allow_swearing boolean not null default false;

-- The rules that apply to a story or message published into p_group (null is
-- the worldwide deck: everything on).
create or replace function public.group_allows(p_group uuid, p_rule text)
returns boolean language sql stable security definer set search_path = public as $fn$
  select case
    when p_group is null then false
    when p_rule = 'names'    then coalesce((select allow_names    from public.groups where id = p_group), false)
    when p_rule = 'swearing' then coalesce((select allow_swearing from public.groups where id = p_group), false)
    else false
  end;
$fn$;

-- Stories: the banned-words filter respects the group, and a name holds the
-- story for review instead of refusing it.
create or replace function public.before_story_insert()
returns trigger language plpgsql security definer set search_path = public as $fn$
declare
  v_premium boolean;
  v_banned  boolean;
  v_today   int;
begin
  select is_premium, is_banned into v_premium, v_banned
  from public.profiles where id = new.author_id;

  if v_banned then
    raise exception 'account_banned' using errcode = 'P0001';
  end if;

  if not public.group_allows(new.group_id, 'swearing')
     and public.contains_banned_word(new.body) then
    raise exception 'blocked_content' using errcode = 'P0001';
  end if;

  if new.group_id is not null and not exists (
    select 1 from public.group_members
    where group_id = new.group_id and user_id = new.author_id
  ) then
    raise exception 'not_a_group_member' using errcode = 'P0001';
  end if;

  -- Premium buys unlimited publishing; everyone else gets the daily allowance
  -- plus whatever rewarded ads have granted. The day is UTC.
  if not coalesce(v_premium, false) then
    select count(*) into v_today
    from public.stories
    where author_id = new.author_id
      and created_at >= date_trunc('day', now() at time zone 'utc');

    if v_today >= public.cfg('stories_per_day') then
      update public.post_credits
        set credits = credits - 1
        where user_id = new.author_id and credits > 0;
      if not found then
        raise exception 'daily_limit_reached' using errcode = 'P0001';
      end if;
    end if;
  end if;

  -- Published, but nobody sees it until a person has looked.
  if not public.group_allows(new.group_id, 'names')
     and public.contains_person_name(new.body) then
    new.hidden        := true;
    new.review_status := 'pending';
    new.review_reason := 'auto_name';
  end if;

  return new;
end;
$fn$;

-- Messages: only the banned-words filter changes. Names in a thread stay a
-- matter for "señala a alguien": holding every message for review would stop
-- the conversation.
create or replace function public.before_message_insert()
returns trigger language plpgsql security definer set search_path = public as $fn$
declare
  v_author uuid;
  v_story  uuid;
  v_recent int;
  v_closed timestamptz;
  v_group  uuid;
begin
  select user_id, story_id into v_author, v_story
  from public.thread_members where id = new.member_id;

  if v_author is null or v_story <> new.story_id then
    raise exception 'not_in_thread' using errcode = 'P0001';
  end if;

  if exists (select 1 from public.profiles where id = v_author and is_banned) then
    raise exception 'account_banned' using errcode = 'P0001';
  end if;

  select closed_at, group_id into v_closed, v_group
    from public.stories where id = new.story_id;
  if v_closed is not null then
    raise exception 'thread_closed' using errcode = 'P0001';
  end if;

  if not public.group_allows(v_group, 'swearing')
     and public.contains_banned_word(new.body) then
    raise exception 'blocked_content' using errcode = 'P0001';
  end if;

  -- Counted across every thread, not per thread: a flooder just opens a second
  -- conversation otherwise.
  select count(*) into v_recent
  from public.messages m
  join public.thread_members tm on tm.id = m.member_id
  where tm.user_id = v_author and m.created_at > now() - interval '1 minute';
  if v_recent >= public.cfg('messages_per_minute') then
    raise exception 'too_fast' using errcode = 'P0001';
  end if;

  return new;
end;
$fn$;

-- "Señala a alguien" in a group that allows names is an ordinary report: it
-- still counts towards the threshold, it just does not hide anything at once.
create or replace function public.after_report_names_someone()
returns trigger language plpgsql security definer set search_path = public as $fn$
declare
  v_used  int;
  v_group uuid;
begin
  if new.reason is distinct from 'names_someone' then
    return new;
  end if;

  if new.target_type = 'story' then
    select group_id into v_group from public.stories where id = new.target_id;
  else
    select s.group_id into v_group
      from public.messages m join public.stories s on s.id = m.story_id
      where m.id = new.target_id;
  end if;
  if public.group_allows(v_group, 'names') then
    return new;
  end if;

  select count(*) into v_used
  from public.reports
  where reporter_id = new.reporter_id
    and reason = 'names_someone'
    and created_at > now() - interval '1 day';
  if v_used > public.cfg('names_reports_per_day') then
    return new;
  end if;

  if new.target_type = 'story' then
    update public.stories
      set hidden = true, review_status = 'pending', review_reason = 'names_someone'
      where id = new.target_id and not hidden and review_status is null;
    if found then
      perform public.push_event(jsonb_build_object('hidden_story_id', new.target_id));
    end if;
  else
    update public.messages
      set hidden = true, review_status = 'pending', review_reason = 'names_someone'
      where id = new.target_id and not hidden and review_status is null;
  end if;
  return new;
end;
$fn$;

-- create_group with its rules. The old one-argument version is dropped so a
-- stale app cannot create a group while skipping the choice.
drop function if exists public.create_group(text);
create or replace function public.create_group(
  p_name           text,
  p_allow_names    boolean default false,
  p_allow_swearing boolean default false
)
returns uuid
language plpgsql security definer set search_path = public as $fn$
declare
  v_uid  uuid := auth.uid();
  v_id   uuid;
  v_name text := btrim(coalesce(p_name, ''));
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = 'P0001';
  end if;
  if char_length(v_name) not between 2 and 40 then
    raise exception 'invalid_name' using errcode = 'P0001';
  end if;
  if public.contains_banned_word(v_name) then
    raise exception 'blocked_content' using errcode = 'P0001';
  end if;
  if (select count(*) from public.groups where owner_id = v_uid) >= 20 then
    raise exception 'too_many_groups' using errcode = 'P0001';
  end if;

  insert into public.groups (name, owner_id, allow_names, allow_swearing)
    values (v_name, v_uid, coalesce(p_allow_names, false), coalesce(p_allow_swearing, false))
    returning id into v_id;
  insert into public.group_members (group_id, user_id) values (v_id, v_uid);
  return v_id;
end;
$fn$;

-- Tighten only: a rule can be switched back on, never off.
create or replace function public.tighten_group_rules(
  p_group          uuid,
  p_allow_names    boolean,
  p_allow_swearing boolean
)
returns void
language plpgsql security definer set search_path = public as $fn$
begin
  update public.groups
    set allow_names    = allow_names    and coalesce(p_allow_names, false),
        allow_swearing = allow_swearing and coalesce(p_allow_swearing, false)
    where id = p_group and owner_id = auth.uid();
  if not found then
    raise exception 'not_the_owner' using errcode = 'P0001';
  end if;
end;
$fn$;

-- What an invite leads to, before joining: the name, how many are in it, and
-- which rules are off. Joining still takes a separate tap.
create or replace function public.invite_preview(p_code text)
returns table (name text, member_count int, allow_names boolean, allow_swearing boolean)
language plpgsql stable security definer set search_path = public as $fn$
declare
  v_group public.groups;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = 'P0001';
  end if;
  select * into v_group from public.groups
    where invite_code = lower(btrim(coalesce(p_code, '')));
  if not found then
    raise exception 'invalid_invite' using errcode = 'P0001';
  end if;
  if v_group.invite_expires_at < now() then
    raise exception 'expired_invite' using errcode = 'P0001';
  end if;
  return query
    select v_group.name,
           (select count(*)::int from public.group_members m where m.group_id = v_group.id),
           v_group.allow_names,
           v_group.allow_swearing;
end;
$fn$;

-- my_groups() with the rules.
drop function if exists public.my_groups();
create or replace function public.my_groups()
returns table (
  id                uuid,
  name              text,
  member_count      int,
  is_owner          boolean,
  invite_code       text,
  invite_expires_at timestamptz,
  joined_at         timestamptz,
  allow_names       boolean,
  allow_swearing    boolean
)
language sql stable security definer set search_path = public as $fn$
  select g.id, g.name,
         (select count(*)::int from public.group_members m where m.group_id = g.id),
         g.owner_id = auth.uid(),
         g.invite_code,
         g.invite_expires_at,
         me.joined_at,
         g.allow_names,
         g.allow_swearing
  from public.group_members me
  join public.groups g on g.id = me.group_id
  where me.user_id = auth.uid()
  order by me.joined_at desc;
$fn$;

revoke all on function public.contains_person_name(text) from public, anon, authenticated;
revoke all on function public.group_allows(uuid, text) from public, anon, authenticated;
revoke all on function
  public.create_group(text, boolean, boolean),
  public.tighten_group_rules(uuid, boolean, boolean),
  public.invite_preview(text),
  public.my_groups()
from public, anon;
grant execute on function
  public.create_group(text, boolean, boolean),
  public.tighten_group_rules(uuid, boolean, boolean),
  public.invite_preview(text),
  public.my_groups()
to authenticated;
