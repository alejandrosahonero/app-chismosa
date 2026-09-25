-- =============================================================================
-- 0005 — groups
--
-- 0001 to 0003 left groups half built, and with two leaks:
--
--   1. `groups` was readable row by row, and the row carries owner_id — a global
--      account id, handed to every member. join_group_by_code() returned the
--      same row. Cross that with a card and anonymity inside a group of six
--      friends is gone.
--   2. A group story was private only in the deck. join_thread() and
--      story_detail() took any story id, so a link or a leaked id opened a
--      group's conversation to the whole world.
--
-- Everything a client does with a group now goes through the functions below,
-- none of which ever returns an account id. No member cap, by product decision;
-- every other protection applies — expiring and rotatable invites, reports,
-- blocks, the daily limit and the word filter, which are the same triggers as
-- for the worldwide deck.
--
-- Run after 0004. Safe to re-run.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- No more direct access. Creating, joining, leaving, deleting: all RPCs.
-- -----------------------------------------------------------------------------
revoke all on public.groups        from anon, authenticated;
revoke all on public.group_members from anon, authenticated;

drop policy if exists groups_select_member   on public.groups;
drop policy if exists groups_insert_own      on public.groups;
drop policy if exists groups_update_owner    on public.groups;
drop policy if exists groups_delete_owner    on public.groups;
drop policy if exists group_members_select_own on public.group_members;
drop policy if exists group_members_leave      on public.group_members;

-- The old signature returned the whole row, owner_id included.
drop function if exists public.join_group_by_code(text);
drop function if exists public.group_summary(uuid);

-- Whether the caller may see a story at all: worldwide stories are for everyone,
-- a group's only for its members.
create or replace function public.can_see_story(p_story uuid)
returns boolean
language sql stable security definer set search_path = public as $fn$
  select exists (
    select 1 from public.stories s
    where s.id = p_story
      and not s.hidden
      and (
        s.group_id is null
        or exists (
          select 1 from public.group_members gm
          where gm.group_id = s.group_id and gm.user_id = auth.uid()
        )
      )
  );
$fn$;

-- -----------------------------------------------------------------------------
-- The caller's groups, in one query. The invite code is shown to every member:
-- a group of friends grows by friends passing it on, and only the owner can
-- kill it (rotate_invite).
-- -----------------------------------------------------------------------------
create or replace function public.my_groups()
returns table (
  id                uuid,
  name              text,
  member_count      int,
  is_owner          boolean,
  invite_code       text,
  invite_expires_at timestamptz,
  joined_at         timestamptz
)
language sql stable security definer set search_path = public as $fn$
  select g.id, g.name,
         (select count(*)::int from public.group_members m where m.group_id = g.id),
         g.owner_id = auth.uid(),
         g.invite_code,
         g.invite_expires_at,
         me.joined_at
  from public.group_members me
  join public.groups g on g.id = me.group_id
  where me.user_id = auth.uid()
  order by me.joined_at desc;
$fn$;

-- Creates the group and makes the creator its first member, in one step: a
-- group its owner is not in would be invisible to them.
create or replace function public.create_group(p_name text)
returns uuid
language plpgsql security definer set search_path = public as $fn$
declare
  v_uid uuid := auth.uid();
  v_id  uuid;
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
  -- A cap per creator, not per group: without it one script fills the table.
  if (select count(*) from public.groups where owner_id = v_uid) >= 20 then
    raise exception 'too_many_groups' using errcode = 'P0001';
  end if;

  insert into public.groups (name, owner_id) values (v_name, v_uid)
    returning id into v_id;
  insert into public.group_members (group_id, user_id) values (v_id, v_uid);
  return v_id;
end;
$fn$;

-- Returns the group id and name only.
create or replace function public.join_group_by_code(p_code text)
returns table (id uuid, name text)
language plpgsql security definer set search_path = public as $fn$
declare
  v_group public.groups;
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
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

  insert into public.group_members (group_id, user_id)
  values (v_group.id, v_uid)
  on conflict do nothing;

  return query select v_group.id, v_group.name;
end;
$fn$;

-- Leaving. The owner cannot leave — they delete — so a group never ends up
-- with nobody able to rotate a leaked invite.
create or replace function public.leave_group(p_group uuid)
returns void
language plpgsql security definer set search_path = public as $fn$
begin
  if exists (select 1 from public.groups where id = p_group and owner_id = auth.uid()) then
    raise exception 'owner_cannot_leave' using errcode = 'P0001';
  end if;
  delete from public.group_members
    where group_id = p_group and user_id = auth.uid();
end;
$fn$;

-- Deleting takes the group's stories and threads with it (on delete cascade).
create or replace function public.delete_group(p_group uuid)
returns void
language plpgsql security definer set search_path = public as $fn$
begin
  delete from public.groups where id = p_group and owner_id = auth.uid();
  if not found then
    raise exception 'not_the_owner' using errcode = 'P0001';
  end if;
end;
$fn$;

-- -----------------------------------------------------------------------------
-- Close the side doors into a group's stories.
-- -----------------------------------------------------------------------------
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

  if not public.can_see_story(p_story) then
    raise exception 'story_unavailable' using errcode = 'P0001';
  end if;

  select * into v_row from public.thread_members
    where story_id = p_story and user_id = v_uid;
  if found then
    return v_row;
  end if;

  insert into public.thread_members (story_id, user_id, alias)
  values (p_story, v_uid, public.assign_thread_alias(p_story, v_uid))
  returning * into v_row;

  return v_row;
end;
$fn$;

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
  where s.id = p_story and public.can_see_story(s.id);
$fn$;

-- Leaving a group ends access to its conversations too, not just its deck.
create or replace function public.after_group_leave()
returns trigger language plpgsql security definer set search_path = public as $fn$
begin
  delete from public.thread_members tm
    using public.stories s
    where tm.story_id = s.id
      and s.group_id = old.group_id
      and tm.user_id = old.user_id;
  return old;
end;
$fn$;

drop trigger if exists group_members_after_delete on public.group_members;
create trigger group_members_after_delete
  after delete on public.group_members
  for each row execute function public.after_group_leave();

-- -----------------------------------------------------------------------------
-- Grants. Same pattern as 0003: nothing is callable until named here.
-- -----------------------------------------------------------------------------
revoke execute on function
  public.can_see_story(uuid),
  public.after_group_leave(),
  public.my_groups(),
  public.create_group(text),
  public.join_group_by_code(text),
  public.leave_group(uuid),
  public.delete_group(uuid)
from public, anon, authenticated;

grant execute on function
  public.my_groups(),
  public.create_group(text),
  public.join_group_by_code(text),
  public.leave_group(uuid),
  public.delete_group(uuid)
to authenticated;
