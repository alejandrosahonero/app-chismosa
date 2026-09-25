-- =============================================================================
-- 0008 — launch decisions
--
-- 1. Three stories a day instead of one. At launch there are too few stories,
--    not too few readers, and the writer is the one who was being rationed.
-- 2. "De la casa": stories written by the team are marked as such, never
--    passed off as users' (profiles.is_house).
-- 3. Activity: profiles.last_seen_at, touched on every app open, so daily and
--    monthly active users can be counted (tool/stats.sql).
-- 4. "Me gustaron": feed(p_liked => true) deals the stories the reader liked.
-- 5. "Señala a alguien": a report with that reason hides the story or message
--    at once, pending review, and tells the author why. Reviewed by hand with
--    review_content() (tool/moderation.sql). One person can use this reason at
--    most five times a day, so it cannot be used to wipe the deck.
-- 6. Premium is granted by the server only. The client can no longer write
--    profiles.is_premium; the Edge Function verify-purchase checks the token
--    with Google Play and sets it.
--
-- Run after 0007. Safe to re-run.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Limits.
-- -----------------------------------------------------------------------------
create or replace function public.cfg(key text)
returns int language sql immutable as $fn$
  select case key
    when 'reports_to_hide'      then 3   -- reports that hide a story or message
    when 'hidden_to_ban'        then 3   -- hidden stories that ban the author
    when 'stories_per_day'      then 3   -- free daily allowance (see post_credits)
    when 'messages_per_minute'  then 20  -- flood guard inside a thread
    when 'names_reports_per_day' then 5  -- "señala a alguien" reports per person
    else null
  end;
$fn$;

-- -----------------------------------------------------------------------------
-- 2 & 3. Profile columns.
-- -----------------------------------------------------------------------------
alter table public.profiles
  add column if not exists is_house     boolean not null default false,
  add column if not exists last_seen_at timestamptz;

create index if not exists profiles_last_seen_idx on public.profiles (last_seen_at);

-- Premium is no longer the client's to write.
revoke update on public.profiles from authenticated;
grant update (country_code, languages) on public.profiles to authenticated;

create or replace function public.touch_session()
returns void
language sql security definer set search_path = public as $fn$
  update public.profiles set last_seen_at = now() where id = auth.uid();
$fn$;

-- -----------------------------------------------------------------------------
-- 5. Review of "señala a alguien".
-- -----------------------------------------------------------------------------
alter table public.stories
  add column if not exists review_status text
    check (review_status in ('pending','restored','removed')),
  add column if not exists review_reason text;
alter table public.messages
  add column if not exists review_status text
    check (review_status in ('pending','restored','removed')),
  add column if not exists review_reason text;

-- One pg_net call for every push the database sends. Does nothing until the
-- two Vault secrets from 0006 exist.
create or replace function public.push_event(p_body jsonb)
returns void
language plpgsql security definer set search_path = public as $fn$
declare
  v_url    text;
  v_secret text;
begin
  select decrypted_secret into v_url
    from vault.decrypted_secrets where name = 'push_function_url';
  select decrypted_secret into v_secret
    from vault.decrypted_secrets where name = 'push_secret';
  if v_url is null or v_secret is null then
    return;
  end if;
  perform net.http_post(
    url     := v_url,
    body    := p_body,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-push-secret', v_secret
    )
  );
exception when others then
  return;
end;
$fn$;

create or replace function public.after_report_names_someone()
returns trigger language plpgsql security definer set search_path = public as $fn$
declare
  v_used int;
begin
  if new.reason is distinct from 'names_someone' then
    return new;
  end if;

  select count(*) into v_used
  from public.reports
  where reporter_id = new.reporter_id
    and reason = 'names_someone'
    and created_at > now() - interval '1 day';
  -- Over the daily allowance it stays an ordinary report: it still counts
  -- towards the threshold, it just does not hide anything on its own.
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

drop trigger if exists reports_names_someone on public.reports;
create trigger reports_names_someone
  after insert on public.reports
  for each row execute function public.after_report_names_someone();

-- The review, run by a person from the SQL Editor (service role only).
--   restore = true  → visible again, reports reset, author told.
--   restore = false → stays hidden and counts as a strike towards a ban.
create or replace function public.review_content(
  p_type    text,
  p_id      uuid,
  p_restore boolean
) returns void
language plpgsql security definer set search_path = public as $fn$
declare
  v_author uuid;
  v_hidden int;
begin
  if p_type = 'story' then
    update public.stories
      set hidden = not p_restore,
          reports_count = case when p_restore then 0 else reports_count end,
          review_status = case when p_restore then 'restored' else 'removed' end
      where id = p_id and review_status = 'pending'
      returning author_id into v_author;
    if v_author is not null and p_restore then
      perform public.push_event(jsonb_build_object('restored_story_id', p_id));
    end if;
  else
    update public.messages m
      set hidden = not p_restore,
          reports_count = case when p_restore then 0 else m.reports_count end,
          review_status = case when p_restore then 'restored' else 'removed' end
      from public.thread_members tm
      where m.id = p_id and m.review_status = 'pending' and tm.id = m.member_id
      returning tm.user_id into v_author;
  end if;

  if v_author is not null and not p_restore then
    update public.profiles
      set hidden_content_count = hidden_content_count + 1
      where id = v_author
      returning hidden_content_count into v_hidden;
    if v_hidden >= public.cfg('hidden_to_ban') then
      update public.profiles set is_banned = true where id = v_author;
    end if;
  end if;
end;
$fn$;

-- What is waiting for a decision, oldest first.
create or replace view public.pending_reviews as
  select 'story'::text as type, s.id, s.body, s.review_reason, s.reports_count, s.created_at
  from public.stories s where s.review_status = 'pending'
  union all
  select 'message', m.id, m.body, m.review_reason, m.reports_count, m.created_at
  from public.messages m where m.review_status = 'pending'
  order by created_at;
revoke all on public.pending_reviews from anon, authenticated;

-- -----------------------------------------------------------------------------
-- 6. Purchases, verified by the Edge Function verify-purchase.
-- -----------------------------------------------------------------------------
create table if not exists public.purchases (
  purchase_token text primary key,
  user_id        uuid not null references public.profiles(id) on delete cascade,
  product_id     text not null,
  -- 0 purchased, 1 cancelled/refunded, 2 pending — Play's purchaseState.
  state          smallint not null,
  order_id       text,
  verified_at    timestamptz not null default now()
);
alter table public.purchases enable row level security;
revoke all on public.purchases from anon, authenticated;

-- Called by verify-purchase only. A token belongs to one account at a time:
-- restoring on a new install moves it, and the old account loses premium,
-- the same way a push token follows the phone.
create or replace function public.apply_purchase(
  p_user    uuid,
  p_token   text,
  p_product text,
  p_state   smallint,
  p_order   text
) returns boolean
language plpgsql security definer set search_path = public as $fn$
declare
  v_previous uuid;
begin
  select user_id into v_previous from public.purchases where purchase_token = p_token;

  insert into public.purchases (purchase_token, user_id, product_id, state, order_id, verified_at)
  values (p_token, p_user, p_product, p_state, p_order, now())
  on conflict (purchase_token) do update
    set user_id = excluded.user_id, state = excluded.state,
        order_id = excluded.order_id, verified_at = now();

  if v_previous is not null and v_previous <> p_user then
    update public.profiles set is_premium = exists (
      select 1 from public.purchases where user_id = v_previous and state = 0
    ) where id = v_previous;
  end if;

  update public.profiles set is_premium = exists (
    select 1 from public.purchases where user_id = p_user and state = 0
  ) where id = p_user;

  return exists (select 1 from public.purchases where user_id = p_user and state = 0);
end;
$fn$;

-- -----------------------------------------------------------------------------
-- 4 & 2. feed() with "me gustaron" and the house flag; story_detail and
-- my_stories with what the app now shows.
-- -----------------------------------------------------------------------------
drop function if exists public.feed(uuid, text, text[], text, text, uuid[], int);
create function public.feed(
  p_group    uuid    default null,
  p_category text    default null,
  p_langs    text[]  default null,
  p_country  text    default null,
  p_sort     text    default 'hot',
  p_exclude  uuid[]  default '{}',
  p_limit    int     default 30,
  p_liked    boolean default false
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
  parent_id      uuid,
  is_house       boolean
)
language sql stable security definer set search_path = public as $fn$
  select
    s.id, s.body, s.category, s.country_code, s.lang, s.created_at,
    s.likes_count, s.messages_count, s.closed_at,
    (l.user_id is not null) as liked,
    exists (select 1 from public.thread_members tm
             where tm.story_id = s.id and tm.user_id = auth.uid()) as joined,
    s.chapter, s.parent_id, a.is_house
  from public.stories s
  join public.profiles a on a.id = s.author_id
  left join public.story_likes l on l.story_id = s.id and l.user_id = auth.uid()
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
    -- "Me gustaron" re-reads stories on purpose, so the seen list does not
    -- apply to it.
    and (
      (coalesce(p_liked, false) and l.user_id is not null)
      or (not coalesce(p_liked, false)
          and s.id <> all (coalesce(p_exclude, '{}'::uuid[])))
    )
    and not exists (
      select 1 from public.blocks b
      where b.blocker_id = auth.uid() and b.blocked_id = s.author_id
    )
  order by
    case when coalesce(p_liked, false) then extract(epoch from l.created_at) end desc nulls last,
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
  next_id        uuid,
  is_house       boolean
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
    (select n.id from public.stories n where n.parent_id = s.id and not n.hidden),
    a.is_house
  from public.stories s
  join public.profiles a on a.id = s.author_id
  where s.id = p_story and public.can_see_story(s.id);
$fn$;

drop function if exists public.my_stories(int);
create function public.my_stories(p_limit int default 100)
returns table (
  id             uuid,
  body           text,
  created_at     timestamptz,
  likes_count    int,
  messages_count int,
  hidden         boolean,
  chapter        smallint,
  group_id       uuid,
  has_next       boolean,
  review_status  text,
  review_reason  text
)
language sql stable security definer set search_path = public as $fn$
  select s.id, s.body, s.created_at, s.likes_count, s.messages_count,
         s.hidden, s.chapter, s.group_id,
         exists (select 1 from public.stories n where n.parent_id = s.id),
         s.review_status, s.review_reason
  from public.stories s
  where s.author_id = auth.uid()
  order by s.created_at desc
  limit least(coalesce(p_limit, 100), 200);
$fn$;

-- -----------------------------------------------------------------------------
-- Grants.
-- -----------------------------------------------------------------------------
revoke execute on function
  public.touch_session(),
  public.push_event(jsonb),
  public.after_report_names_someone(),
  public.review_content(text, uuid, boolean),
  public.apply_purchase(uuid, text, text, smallint, text),
  public.feed(uuid, text, text[], text, text, uuid[], int, boolean),
  public.story_detail(uuid),
  public.my_stories(int)
from public, anon, authenticated;

grant execute on function
  public.touch_session(),
  public.feed(uuid, text, text[], text, text, uuid[], int, boolean),
  public.story_detail(uuid),
  public.my_stories(int)
to authenticated;
