-- =============================================================================
-- 0004 — Blocking without names, rewarded post credits, publish quota status.
--
-- Run after 0001–0003. Idempotent: safe to run twice.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Blocks go through RPCs only.
--
-- 0003 let a client select and insert `blocks` rows directly. Both were wrong
-- for the same reason: a row carries `blocked_id`, which is a global account id.
-- To insert one the client would have to KNOW that id — and the whole schema is
-- built so it never does. Reading one back would hand it out.
--
-- So a block names the thing the reader can actually see — a message, a story —
-- and the server resolves the account behind it. The reader never learns who
-- they blocked, only that that voice is gone.
-- -----------------------------------------------------------------------------
revoke all on public.blocks from anon, authenticated;
drop policy if exists blocks_own on public.blocks;
drop policy if exists blocks_insert_own on public.blocks;
drop policy if exists blocks_delete_own on public.blocks;

create or replace function public.block_user_internal(p_target uuid)
returns void language plpgsql security definer set search_path = public as $fn$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = 'P0001';
  end if;
  -- Blocking yourself is a no-op rather than an error: from the outside the
  -- reader cannot tell which messages are theirs under another alias, and an
  -- error here would tell them.
  if p_target is null or p_target = v_uid then
    return;
  end if;
  insert into public.blocks (blocker_id, blocked_id)
  values (v_uid, p_target)
  on conflict do nothing;
end;
$fn$;

-- Blocks whoever wrote a message. Only from inside the thread: the caller has
-- to be a member of the conversation the message belongs to.
create or replace function public.block_message_author(p_message uuid)
returns void language plpgsql security definer set search_path = public as $fn$
declare
  v_target uuid;
begin
  select tm.user_id into v_target
  from public.messages m
  join public.thread_members tm on tm.id = m.member_id
  where m.id = p_message
    and exists (
      select 1 from public.thread_members me
      where me.story_id = m.story_id and me.user_id = auth.uid()
    );

  perform public.block_user_internal(v_target);
end;
$fn$;

-- Blocks whoever wrote a story. Their other stories leave the deck and their
-- messages leave every thread (`feed()` and `thread_messages()` already filter
-- on `blocks`).
create or replace function public.block_story_author(p_story uuid)
returns void language plpgsql security definer set search_path = public as $fn$
declare
  v_target uuid;
begin
  select author_id into v_target from public.stories where id = p_story;
  perform public.block_user_internal(v_target);
end;
$fn$;

-- How many people this reader has blocked. A number and nothing else: a list
-- would have to describe each entry somehow, and there is no description of a
-- blocked account that is not a way to identify it.
create or replace function public.blocked_count()
returns int language sql stable security definer set search_path = public as $fn$
  select count(*)::int from public.blocks where blocker_id = auth.uid();
$fn$;

-- Undoes every block at once. All-or-nothing is the only undo possible when
-- the entries cannot be told apart.
create or replace function public.clear_blocks()
returns int language plpgsql security definer set search_path = public as $fn$
declare
  v_count int;
begin
  delete from public.blocks where blocker_id = auth.uid();
  get diagnostics v_count = row_count;
  return v_count;
end;
$fn$;

-- -----------------------------------------------------------------------------
-- Publish quota, as the compose screen needs to show it.
-- -----------------------------------------------------------------------------
create or replace function public.publish_status()
returns table (
  posted_today int,
  daily_limit  int,
  credits      int,
  is_premium   boolean
)
language sql stable security definer set search_path = public as $fn$
  select
    (select count(*)::int from public.stories
      where author_id = auth.uid()
        and created_at >= date_trunc('day', now() at time zone 'utc')),
    public.cfg('stories_per_day'),
    coalesce((select c.credits from public.post_credits c
               where c.user_id = auth.uid()), 0),
    coalesce((select p.is_premium from public.profiles p
               where p.id = auth.uid()), false);
$fn$;

-- -----------------------------------------------------------------------------
-- Rewarded ads.
--
-- The credit is granted by an Edge Function that receives AdMob's server-side
-- verification callback and checks Google's signature. Never by the app: a
-- credit the phone can mint is a limit that does not exist.
--
-- `transaction_id` is the primary key because AdMob retries the callback until
-- it gets a 200, and a retried callback must not pay twice.
-- -----------------------------------------------------------------------------
create table if not exists public.ad_rewards (
  transaction_id text primary key,
  user_id        uuid not null references public.profiles(id) on delete cascade,
  granted_at     timestamptz not null default now()
);

alter table public.ad_rewards enable row level security;
revoke all on public.ad_rewards from anon, authenticated;

-- Callable by the service role only (see the grants below). Returns whether
-- this call actually granted something, so the function can log duplicates.
create or replace function public.grant_post_credit(p_user uuid, p_transaction text)
returns boolean language plpgsql security definer set search_path = public as $fn$
begin
  if not exists (select 1 from public.profiles where id = p_user) then
    return false;
  end if;

  insert into public.ad_rewards (transaction_id, user_id)
  values (p_transaction, p_user)
  on conflict (transaction_id) do nothing;
  if not found then
    return false;
  end if;

  insert into public.post_credits (user_id, credits)
  values (p_user, 1)
  on conflict (user_id) do update set credits = public.post_credits.credits + 1;
  return true;
end;
$fn$;

-- -----------------------------------------------------------------------------
-- Grants. Same shape as 0003: nothing is executable by default, then a named
-- list for the app and one function for the server.
-- -----------------------------------------------------------------------------
revoke execute on function
  public.block_user_internal(uuid),
  public.block_message_author(uuid),
  public.block_story_author(uuid),
  public.blocked_count(),
  public.clear_blocks(),
  public.publish_status(),
  public.grant_post_credit(uuid, text)
from public, anon, authenticated;

grant execute on function
  public.block_message_author(uuid),
  public.block_story_author(uuid),
  public.blocked_count(),
  public.clear_blocks(),
  public.publish_status()
to authenticated;

grant execute on function public.grant_post_credit(uuid, text) to service_role;
grant execute on function public.block_user_internal(uuid) to service_role;
