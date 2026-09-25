-- =============================================================================
-- 0007 — personal data filter, chapters, the author's own stories
--
-- 1. Personal data filter. Every anonymous app that died (Secret, Yik Yak,
--    Whisper) died of the same thing: anonymity used to point at a real,
--    findable person. Names cannot be caught by a regex; phone numbers,
--    e-mails, @handles and links can, and they are the step that turns a
--    story into harassment ("this is her Instagram"). Refused at insert, on
--    stories, messages and group names, with its own error so the app can say
--    exactly why.
--
-- 2. Chapters. A story can be continued by its author: part 2 points at part 1
--    (parent_id), one continuation per story, so a saga is a straight line.
--    Everyone who entered the thread of the previous part hears about the new
--    one (thread-push, `continuation`).
--
-- 3. my_stories(): the author's own stories with their numbers. Writers are
--    the supply of this app, and "how did mine do?" is the reason they write
--    a second one.
--
-- Run after 0006. Safe to re-run.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Personal data.
-- -----------------------------------------------------------------------------
create or replace function public.contains_personal_data(p_text text)
returns boolean language sql immutable as $fn$
  select
    -- A phone number: nine or more digits once spaces, dots, dashes and
    -- brackets are gone. "Tengo 25 años" survives; "612 34 56 78" does not.
    regexp_replace(coalesce(p_text, ''), '[\s.\-()/]', '', 'g') ~ '\d{9,}'
    -- An e-mail.
    or p_text ~* '[a-z0-9._%+\-]+@[a-z0-9.\-]+\.[a-z]{2,}'
    -- A handle: @ followed by something that looks like a username.
    or p_text ~* '(^|[^a-z0-9])@[a-z0-9_.]{3,}'
    -- A link.
    or p_text ~* '(https?://|www\.|\m[a-z0-9\-]+\.(com|es|net|org|io|me|ly|gg|tv|link|app|mx|ar|co|cl|pe)\M)';
$fn$;

create or replace function public.before_insert_personal_data()
returns trigger language plpgsql security definer set search_path = public as $fn$
begin
  if public.contains_personal_data(
       case tg_table_name when 'groups' then new.name else new.body end
     ) then
    raise exception 'personal_data' using errcode = 'P0001';
  end if;
  return new;
end;
$fn$;

drop trigger if exists stories_personal_data on public.stories;
create trigger stories_personal_data
  before insert on public.stories
  for each row execute function public.before_insert_personal_data();

drop trigger if exists messages_personal_data on public.messages;
create trigger messages_personal_data
  before insert on public.messages
  for each row execute function public.before_insert_personal_data();

drop trigger if exists groups_personal_data on public.groups;
create trigger groups_personal_data
  before insert or update of name on public.groups
  for each row execute function public.before_insert_personal_data();

-- -----------------------------------------------------------------------------
-- 2. Chapters.
-- -----------------------------------------------------------------------------
alter table public.stories
  add column if not exists parent_id uuid references public.stories(id) on delete set null,
  add column if not exists chapter   smallint not null default 1;

-- One continuation per story: a saga is a line, not a tree.
create unique index if not exists stories_parent_unique
  on public.stories (parent_id) where parent_id is not null;

create or replace function public.before_story_chapter()
returns trigger language plpgsql security definer set search_path = public as $fn$
declare
  v_parent public.stories;
begin
  if new.parent_id is null then
    new.chapter := 1;
    return new;
  end if;

  select * into v_parent from public.stories where id = new.parent_id;
  if not found
     or v_parent.author_id <> new.author_id
     or v_parent.hidden
     or v_parent.group_id is distinct from new.group_id then
    raise exception 'invalid_parent' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.stories where parent_id = new.parent_id) then
    raise exception 'already_continued' using errcode = 'P0001';
  end if;
  if v_parent.chapter >= 20 then
    raise exception 'too_many_chapters' using errcode = 'P0001';
  end if;

  new.chapter := v_parent.chapter + 1;
  return new;
end;
$fn$;

-- Named to sort before stories_before_insert: the chapter is settled before the
-- quota is spent, so a refused continuation costs nothing.
drop trigger if exists stories_a_chapter on public.stories;
create trigger stories_a_chapter
  before insert on public.stories
  for each row execute function public.before_story_chapter();

-- Tell the readers of the previous part. Same pg_net route as messages.
create or replace function public.after_story_continuation_push()
returns trigger language plpgsql security definer set search_path = public as $fn$
declare
  v_url    text;
  v_secret text;
begin
  if new.parent_id is null then
    return new;
  end if;
  select decrypted_secret into v_url
    from vault.decrypted_secrets where name = 'push_function_url';
  select decrypted_secret into v_secret
    from vault.decrypted_secrets where name = 'push_secret';
  if v_url is null or v_secret is null then
    return new;
  end if;

  perform net.http_post(
    url     := v_url,
    body    := jsonb_build_object('continuation_id', new.id),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-push-secret', v_secret
    )
  );
  return new;
exception when others then
  return new;
end;
$fn$;

drop trigger if exists stories_after_insert_push on public.stories;
create trigger stories_after_insert_push
  after insert on public.stories
  for each row execute function public.after_story_continuation_push();

-- feed() and story_detail() gain chapter and parent_id. The return type
-- changes, so they are dropped and recreated (grants re-issued below).
drop function if exists public.feed(uuid, text, text[], text, text, uuid[], int);
create function public.feed(
  p_group    uuid   default null,
  p_category text   default null,
  p_langs    text[] default null,
  p_country  text   default null,
  p_sort     text   default 'hot',
  p_exclude  uuid[] default '{}',
  p_limit    int    default 30
) returns table (
  id             uuid,
  body           text,
  category       text,
  country_code   text,
  lang           text,
  created_at     timestamptz,
  likes_count    int,
  messages_count int,
  closed_at      timestamptz,
  liked          boolean,
  joined         boolean,
  chapter        smallint,
  parent_id      uuid
)
language sql stable security definer set search_path = public as $fn$
  select
    s.id, s.body, s.category, s.country_code, s.lang, s.created_at,
    s.likes_count, s.messages_count, s.closed_at,
    exists (select 1 from public.story_likes l
             where l.story_id = s.id and l.user_id = auth.uid()) as liked,
    exists (select 1 from public.thread_members tm
             where tm.story_id = s.id and tm.user_id = auth.uid()) as joined,
    s.chapter, s.parent_id
  from public.stories s
  join public.profiles a on a.id = s.author_id
  where not s.hidden
    and not a.is_banned
    and s.author_id <> auth.uid()
    and s.group_id is not distinct from p_group
    and (
      p_group is null or exists (
        select 1 from public.group_members gm
        where gm.group_id = p_group and gm.user_id = auth.uid()
      )
    )
    and (p_category is null or p_category = 'cualquiera' or s.category = p_category)
    and (p_langs is null or s.lang = any (p_langs))
    and (p_country is null or s.country_code = p_country)
    and s.id <> all (coalesce(p_exclude, '{}'::uuid[]))
    and not exists (
      select 1 from public.blocks b
      where b.blocker_id = auth.uid() and b.blocked_id = s.author_id
    )
  order by
    case when p_sort = 'new' then extract(epoch from s.created_at) end desc nulls last,
    case when p_sort = 'hot' then
      s.likes_count / power(extract(epoch from (now() - s.created_at)) / 3600.0 + 2, 1.5)
    end desc nulls last,
    s.created_at desc
  limit least(coalesce(p_limit, 30), 50);
$fn$;

drop function if exists public.story_detail(uuid);
create function public.story_detail(p_story uuid)
returns table (
  id             uuid,
  body           text,
  category       text,
  country_code   text,
  lang           text,
  created_at     timestamptz,
  likes_count    int,
  messages_count int,
  closed_at      timestamptz,
  liked          boolean,
  joined         boolean,
  is_mine        boolean,
  chapter        smallint,
  parent_id      uuid,
  next_id        uuid
)
language sql stable security definer set search_path = public as $fn$
  select
    s.id, s.body, s.category, s.country_code, s.lang, s.created_at,
    s.likes_count, s.messages_count, s.closed_at,
    exists (select 1 from public.story_likes l
             where l.story_id = s.id and l.user_id = auth.uid()),
    exists (select 1 from public.thread_members tm
             where tm.story_id = s.id and tm.user_id = auth.uid()),
    s.author_id = auth.uid(),
    s.chapter, s.parent_id,
    (select n.id from public.stories n where n.parent_id = s.id and not n.hidden)
  from public.stories s
  where s.id = p_story and public.can_see_story(s.id);
$fn$;

-- -----------------------------------------------------------------------------
-- 3. The author's side.
-- -----------------------------------------------------------------------------
create or replace function public.my_stories(p_limit int default 100)
returns table (
  id             uuid,
  body           text,
  created_at     timestamptz,
  likes_count    int,
  messages_count int,
  hidden         boolean,
  chapter        smallint,
  group_id       uuid,
  has_next       boolean
)
language sql stable security definer set search_path = public as $fn$
  select s.id, s.body, s.created_at, s.likes_count, s.messages_count,
         s.hidden, s.chapter, s.group_id,
         exists (select 1 from public.stories n where n.parent_id = s.id)
  from public.stories s
  where s.author_id = auth.uid()
  order by s.created_at desc
  limit least(coalesce(p_limit, 100), 200);
$fn$;

-- my_threads() says which thread is under the reader's own story.
drop function if exists public.my_threads(int);
create function public.my_threads(p_limit int default 50)
returns table (
  story_id        uuid,
  body            text,
  alias           text,
  muted           boolean,
  messages_count  int,
  last_read_at    timestamptz,
  unread_count    int,
  last_message_at timestamptz,
  is_mine         boolean
)
language sql stable security definer set search_path = public as $fn$
  select
    s.id,
    s.body,
    tm.alias,
    tm.muted,
    s.messages_count,
    tm.last_read_at,
    (select count(*)::int from public.messages m
      where m.story_id = s.id and not m.hidden and m.created_at > tm.last_read_at)
      as unread_count,
    (select max(m.created_at) from public.messages m where m.story_id = s.id)
      as last_message_at,
    s.author_id = auth.uid()
  from public.thread_members tm
  join public.stories s on s.id = tm.story_id
  where tm.user_id = auth.uid() and not s.hidden
  order by last_message_at desc nulls last, tm.joined_at desc
  limit least(coalesce(p_limit, 50), 100);
$fn$;

-- -----------------------------------------------------------------------------
-- Grants.
-- -----------------------------------------------------------------------------
revoke execute on function
  public.contains_personal_data(text),
  public.before_insert_personal_data(),
  public.before_story_chapter(),
  public.after_story_continuation_push(),
  public.feed(uuid, text, text[], text, text, uuid[], int),
  public.story_detail(uuid),
  public.my_stories(int),
  public.my_threads(int)
from public, anon, authenticated;

grant execute on function
  public.feed(uuid, text, text[], text, text, uuid[], int),
  public.story_detail(uuid),
  public.my_stories(int),
  public.my_threads(int)
to authenticated;
