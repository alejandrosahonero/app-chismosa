-- =============================================================================
-- Chismosa — aliases, counters, automatic moderation and the feed.
--
-- Everything the client is not allowed to be trusted with lives here: counters,
-- the daily publishing limit, alias uniqueness, hiding and banning. The client
-- calls RPCs; it never writes a counter.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Per-thread aliases.
--
-- Feminine nouns and adjectives so the pairing always agrees in Spanish, and
-- because the brand is "Chismosa". 24 x 20 = 480 combinations: plenty for a
-- thread, and the loop guarantees uniqueness inside one anyway.
-- -----------------------------------------------------------------------------
create or replace function public.assign_thread_alias(p_story uuid, p_user uuid)
returns text language plpgsql security definer set search_path = public as $fn$
declare
  nouns text[] := array[
    'Vecina','Sombra','Paloma','Lechuza','Máscara','Cortina','Ventana','Farola',
    'Portera','Cámara','Antena','Grieta','Escalera','Azotea','Terraza','Cafetera',
    'Libreta','Almohada','Persiana','Maceta','Linterna','Brújula','Campana','Cerradura'];
  adjs text[] := array[
    'Curiosa','Discreta','Nocturna','Inquieta','Silenciosa','Impaciente','Serena',
    'Traviesa','Distraída','Perpleja','Sincera','Errante','Insomne','Testaruda',
    'Risueña','Astuta','Tímida','Valiente','Despistada','Sospechosa'];
  n_count int := array_length(nouns, 1);
  a_count int := array_length(adjs, 1);
  seed bigint;
  candidate text;
  i int;
begin
  -- Derived from (story, user) so the same person is a different character in
  -- every thread and cannot be followed across them.
  seed := abs(('x' || substr(md5(p_story::text || p_user::text), 1, 8))::bit(32)::bigint);

  for i in 0 .. (n_count * a_count - 1) loop
    candidate := nouns[1 + ((seed + i) % n_count)] || ' ' ||
                 adjs[1 + (((seed + i) / n_count) % a_count)];
    if not exists (
      select 1 from public.thread_members
      where story_id = p_story and alias = candidate
    ) then
      return candidate;
    end if;
  end loop;

  -- 480 people in one thread. Unlikely, but a collision here would be a crash.
  return nouns[1 + (seed % n_count)] || ' ' || (1000 + floor(random() * 9000))::int::text;
end;
$fn$;

-- -----------------------------------------------------------------------------
-- Banned words. Substring match on purpose: crude, cheap, and it only has to
-- catch the obvious. Real moderation is the report threshold below.
-- -----------------------------------------------------------------------------
create or replace function public.contains_banned_word(p_text text)
returns boolean language sql stable security definer set search_path = public as $fn$
  select exists (
    select 1 from public.banned_words w
    where p_text ilike '%' || w.word || '%'
  );
$fn$;

-- -----------------------------------------------------------------------------
-- stories: publishing guard.
--
-- Runs BEFORE insert so a rejected story never exists. The daily allowance is
-- checked here rather than in a policy because it has to consume a credit
-- atomically in the same statement.
-- -----------------------------------------------------------------------------
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

  if public.contains_banned_word(new.body) then
    raise exception 'blocked_content' using errcode = 'P0001';
  end if;

  if new.group_id is not null and not exists (
    select 1 from public.group_members
    where group_id = new.group_id and user_id = new.author_id
  ) then
    raise exception 'not_a_group_member' using errcode = 'P0001';
  end if;

  -- Premium buys unlimited publishing; everyone else gets one a day plus
  -- whatever rewarded ads have granted. The day is UTC: without a server there
  -- is no way to trust a device clock, and a limit that resets when you change
  -- the timezone is not a limit.
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

  return new;
end;
$fn$;

drop trigger if exists stories_before_insert on public.stories;
create trigger stories_before_insert
  before insert on public.stories
  for each row execute function public.before_story_insert();

-- The author is the first member of their own thread, so replies to them have
-- somewhere to land and the story shows up in their history.
create or replace function public.after_story_insert()
returns trigger language plpgsql security definer set search_path = public as $fn$
begin
  insert into public.thread_members (story_id, user_id, alias)
  values (new.id, new.author_id, public.assign_thread_alias(new.id, new.author_id))
  on conflict do nothing;
  return new;
end;
$fn$;

drop trigger if exists stories_after_insert on public.stories;
create trigger stories_after_insert
  after insert on public.stories
  for each row execute function public.after_story_insert();

-- -----------------------------------------------------------------------------
-- Like counter.
-- -----------------------------------------------------------------------------
create or replace function public.on_story_like()
returns trigger language plpgsql security definer set search_path = public as $fn$
begin
  if tg_op = 'INSERT' then
    update public.stories set likes_count = likes_count + 1 where id = new.story_id;
    return new;
  else
    update public.stories set likes_count = greatest(likes_count - 1, 0) where id = old.story_id;
    return old;
  end if;
end;
$fn$;

drop trigger if exists story_likes_count on public.story_likes;
create trigger story_likes_count
  after insert or delete on public.story_likes
  for each row execute function public.on_story_like();

-- -----------------------------------------------------------------------------
-- messages: flood guard + counter.
-- -----------------------------------------------------------------------------
create or replace function public.before_message_insert()
returns trigger language plpgsql security definer set search_path = public as $fn$
declare
  v_author uuid;
  v_story  uuid;
  v_recent int;
  v_closed timestamptz;
begin
  select user_id, story_id into v_author, v_story
  from public.thread_members where id = new.member_id;

  if v_author is null or v_story <> new.story_id then
    raise exception 'not_in_thread' using errcode = 'P0001';
  end if;

  if exists (select 1 from public.profiles where id = v_author and is_banned) then
    raise exception 'account_banned' using errcode = 'P0001';
  end if;

  select closed_at into v_closed from public.stories where id = new.story_id;
  if v_closed is not null then
    raise exception 'thread_closed' using errcode = 'P0001';
  end if;

  if public.contains_banned_word(new.body) then
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

drop trigger if exists messages_before_insert on public.messages;
create trigger messages_before_insert
  before insert on public.messages
  for each row execute function public.before_message_insert();

create or replace function public.after_message_insert()
returns trigger language plpgsql security definer set search_path = public as $fn$
begin
  update public.stories
    set messages_count = messages_count + 1
    where id = new.story_id;
  -- Writing counts as reading: your own message must not come back as unread.
  update public.thread_members
    set last_read_at = now()
    where id = new.member_id;
  return new;
end;
$fn$;

drop trigger if exists messages_after_insert on public.messages;
create trigger messages_after_insert
  after insert on public.messages
  for each row execute function public.after_message_insert();

-- -----------------------------------------------------------------------------
-- Automatic moderation.
--
-- A report increments a counter; at the threshold the content disappears from
-- every feed and thread. An author whose stories keep getting hidden is banned.
-- Nobody reviews anything, which is the whole design: the alternative is a
-- moderation queue this project has no intention of staffing.
-- -----------------------------------------------------------------------------
create or replace function public.after_report_insert()
returns trigger language plpgsql security definer set search_path = public as $fn$
declare
  v_count  int;
  v_author uuid;
  v_hidden int;
  v_member uuid;
begin
  if new.target_type = 'story' then
    update public.stories
      set reports_count = reports_count + 1
      where id = new.target_id
      returning reports_count, author_id into v_count, v_author;

    if v_count >= public.cfg('reports_to_hide') then
      update public.stories set hidden = true
        where id = new.target_id and not hidden;
      if not found then
        v_author := null;  -- already hidden: do not punish the same story twice
      end if;
    else
      v_author := null;
    end if;
  else
    update public.messages
      set reports_count = reports_count + 1
      where id = new.target_id
      returning reports_count, member_id into v_count, v_member;

    if v_count >= public.cfg('reports_to_hide') then
      update public.messages set hidden = true
        where id = new.target_id and not hidden;
      if found then
        -- Resolving the account happens here and only here: the reporter never
        -- learns who they reported.
        select user_id into v_author from public.thread_members where id = v_member;
      end if;
    end if;
  end if;

  -- A harasser mostly writes messages, not stories, so both count towards the
  -- same strike total.
  if v_author is not null then
    update public.profiles
      set hidden_content_count = hidden_content_count + 1
      where id = v_author
      returning hidden_content_count into v_hidden;

    if v_hidden >= public.cfg('hidden_to_ban') then
      update public.profiles set is_banned = true where id = v_author;
    end if;
  end if;

  return new;
end;
$fn$;

drop trigger if exists reports_after_insert on public.reports;
create trigger reports_after_insert
  after insert on public.reports
  for each row execute function public.after_report_insert();

-- -----------------------------------------------------------------------------
-- RPCs. The client's whole write surface for anything that needs a decision.
-- -----------------------------------------------------------------------------

-- Entering a thread IS joining it: the swipe up is the only membership gesture.
create or replace function public.join_thread(p_story uuid)
returns public.thread_members
language plpgsql security definer set search_path = public as $fn$
declare
  v_row public.thread_members;
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = 'P0001';
  end if;

  select * into v_row from public.thread_members
    where story_id = p_story and user_id = v_uid;
  if found then
    return v_row;
  end if;

  if not exists (select 1 from public.stories where id = p_story and not hidden) then
    raise exception 'story_unavailable' using errcode = 'P0001';
  end if;

  insert into public.thread_members (story_id, user_id, alias)
  values (p_story, v_uid, public.assign_thread_alias(p_story, v_uid))
  returning * into v_row;

  return v_row;
end;
$fn$;

create or replace function public.report_content(
  p_target_type text,
  p_target_id uuid,
  p_reason text default null
) returns void
language plpgsql security definer set search_path = public as $fn$
begin
  insert into public.reports (reporter_id, target_type, target_id, reason)
  values (auth.uid(), p_target_type, p_target_id, p_reason)
  on conflict (reporter_id, target_type, target_id) do nothing;
end;
$fn$;

create or replace function public.join_group_by_code(p_code text)
returns public.groups
language plpgsql security definer set search_path = public as $fn$
declare
  v_group public.groups;
  v_uid uuid := auth.uid();
begin
  select * into v_group from public.groups where invite_code = p_code;
  if not found then
    raise exception 'invalid_invite' using errcode = 'P0001';
  end if;
  if v_group.invite_expires_at < now() then
    raise exception 'expired_invite' using errcode = 'P0001';
  end if;

  insert into public.group_members (group_id, user_id)
  values (v_group.id, v_uid)
  on conflict do nothing;

  return v_group;
end;
$fn$;

-- Rotating the code is how a leaked link is killed.
create or replace function public.rotate_invite(p_group uuid)
returns text
language plpgsql security definer set search_path = public as $fn$
declare
  v_code text;
begin
  update public.groups
    set invite_code = encode(gen_random_bytes(6), 'hex'),
        invite_expires_at = now() + interval '7 days'
    where id = p_group and owner_id = auth.uid()
    returning invite_code into v_code;

  if v_code is null then
    raise exception 'not_the_owner' using errcode = 'P0001';
  end if;
  return v_code;
end;
$fn$;

-- -----------------------------------------------------------------------------
-- The deck.
--
-- "Hot" is likes per hour with a decay, Hacker News style: a story from this
-- morning with 20 likes beats one from last week with 200. Without the decay
-- the first stories ever published own the feed forever.
--
-- p_exclude is the tail of the device's seen list. It is a hint, not the source
-- of truth: the client filters the page again, so a long history costs nothing
-- on the wire.
-- -----------------------------------------------------------------------------
-- The column list is explicit and `author_id` is NOT in it. Handing the global
-- account id out with every card would let anyone cross-reference the deck with
-- a group's member list and put a name to a story. Nothing outside this schema
-- ever needs to know who wrote a card.
create or replace function public.feed(
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
  joined         boolean
)
language sql stable security definer set search_path = public as $fn$
  select
    s.id, s.body, s.category, s.country_code, s.lang, s.created_at,
    s.likes_count, s.messages_count, s.closed_at,
    exists (select 1 from public.story_likes l
             where l.story_id = s.id and l.user_id = auth.uid()) as liked,
    exists (select 1 from public.thread_members tm
             where tm.story_id = s.id and tm.user_id = auth.uid()) as joined
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

-- One page of a thread, oldest last. Returns the alias and nothing that could
-- identify an account — not even the membership id of other people.
-- Aliases of everyone in a thread, keyed by membership id. This is how a
-- Realtime message row (which carries only member_id) gets a name on screen.
create or replace function public.thread_aliases(p_story uuid)
returns table (member_id uuid, alias text, is_author boolean)
language sql stable security definer set search_path = public as $fn$
  select tm.id, tm.alias, tm.user_id = s.author_id
  from public.thread_members tm
  join public.stories s on s.id = tm.story_id
  where tm.story_id = p_story
    and exists (
      select 1 from public.thread_members me
      where me.story_id = p_story and me.user_id = auth.uid()
    );
$fn$;

-- Header of a thread, without the author's account id.
create or replace function public.story_detail(p_story uuid)
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
  is_mine        boolean
)
language sql stable security definer set search_path = public as $fn$
  select
    s.id, s.body, s.category, s.country_code, s.lang, s.created_at,
    s.likes_count, s.messages_count, s.closed_at,
    exists (select 1 from public.story_likes l
             where l.story_id = s.id and l.user_id = auth.uid()),
    exists (select 1 from public.thread_members tm
             where tm.story_id = s.id and tm.user_id = auth.uid()),
    s.author_id = auth.uid()
  from public.stories s
  where s.id = p_story and not s.hidden;
$fn$;

create or replace function public.thread_messages(
  p_story  uuid,
  p_before timestamptz default null,
  p_limit  int default 50
) returns table (
  id         uuid,
  alias      text,
  body       text,
  created_at timestamptz,
  is_mine    boolean,
  is_author  boolean
)
language sql stable security definer set search_path = public as $fn$
  select
    m.id,
    tm.alias,
    m.body,
    m.created_at,
    tm.user_id = auth.uid() as is_mine,
    tm.user_id = s.author_id as is_author
  from public.messages m
  join public.thread_members tm on tm.id = m.member_id
  join public.stories s on s.id = m.story_id
  where m.story_id = p_story
    and not m.hidden
    and (p_before is null or m.created_at < p_before)
    -- Reading a thread requires having joined it: the swipe up is the door.
    and exists (
      select 1 from public.thread_members me
      where me.story_id = p_story and me.user_id = auth.uid()
    )
    and not exists (
      select 1 from public.blocks b
      where b.blocker_id = auth.uid() and b.blocked_id = tm.user_id
    )
  order by m.created_at desc
  limit least(coalesce(p_limit, 50), 100);
$fn$;

-- Threads the user has joined, newest activity first. This is the history
-- screen in one query.
create or replace function public.my_threads(p_limit int default 50)
returns table (
  story_id       uuid,
  body           text,
  alias          text,
  muted          boolean,
  messages_count int,
  last_read_at   timestamptz,
  unread_count   int,
  last_message_at timestamptz
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
      as last_message_at
  from public.thread_members tm
  join public.stories s on s.id = tm.story_id
  where tm.user_id = auth.uid() and not s.hidden
  order by last_message_at desc nulls last, tm.joined_at desc
  limit least(coalesce(p_limit, 50), 100);
$fn$;
