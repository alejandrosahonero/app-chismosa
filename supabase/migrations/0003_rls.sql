-- =============================================================================
-- Chismosa — row level security.
--
-- The rule behind every policy below: a client may read its own rows, and
-- everything else it needs comes from a security-definer RPC that returns
-- columns chosen by hand. The global account id (`profiles.id`, `author_id`,
-- `thread_members.user_id`) must never reach a device other than its owner's —
-- that single leak is what would turn "anonymous" into "pseudonymous", and in a
-- group of six friends that is the same as named.
-- =============================================================================

alter table public.profiles       enable row level security;
alter table public.stories        enable row level security;
alter table public.story_likes    enable row level security;
alter table public.thread_members enable row level security;
alter table public.messages       enable row level security;
alter table public.reports        enable row level security;
alter table public.blocks         enable row level security;
alter table public.groups         enable row level security;
alter table public.group_members  enable row level security;
alter table public.post_credits   enable row level security;
alter table public.devices        enable row level security;
alter table public.banned_words   enable row level security;

-- Supabase grants the API roles broad privileges on public by default. Take
-- them back and hand out only what the policies below are meant to allow.
revoke all on all tables in schema public from anon, authenticated;

-- -----------------------------------------------------------------------------
-- profiles
-- -----------------------------------------------------------------------------
grant select on public.profiles to authenticated;
-- Column list, not `grant update`: is_banned and hidden_content_count are the
-- moderation record, and an account that can clear its own strikes has none.
grant update (country_code, languages, is_premium) on public.profiles to authenticated;

create policy profiles_select_own on public.profiles
  for select to authenticated using (id = auth.uid());
create policy profiles_update_own on public.profiles
  for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

-- -----------------------------------------------------------------------------
-- stories
--
-- No direct SELECT: the deck goes through feed() and a thread header through
-- story_detail(), both of which omit author_id. The only readable rows are your
-- own, where there is nothing to protect.
-- -----------------------------------------------------------------------------
grant select, insert, delete on public.stories to authenticated;

create policy stories_select_own on public.stories
  for select to authenticated using (author_id = auth.uid());
create policy stories_insert_own on public.stories
  for insert to authenticated with check (author_id = auth.uid());
create policy stories_delete_own on public.stories
  for delete to authenticated using (author_id = auth.uid());

-- -----------------------------------------------------------------------------
-- story_likes
-- -----------------------------------------------------------------------------
grant select, insert, delete on public.story_likes to authenticated;

create policy likes_own on public.story_likes
  for select to authenticated using (user_id = auth.uid());
create policy likes_insert_own on public.story_likes
  for insert to authenticated with check (user_id = auth.uid());
create policy likes_delete_own on public.story_likes
  for delete to authenticated using (user_id = auth.uid());

-- -----------------------------------------------------------------------------
-- thread_members
--
-- Own rows only. Other people's aliases come from thread_aliases(), which
-- returns the membership id and never the account behind it. Joining is
-- join_thread(): the alias has to be unique inside the thread, so the client
-- cannot pick it.
-- -----------------------------------------------------------------------------
grant select on public.thread_members to authenticated;
grant update (muted, last_read_at) on public.thread_members to authenticated;

create policy members_select_own on public.thread_members
  for select to authenticated using (user_id = auth.uid());
create policy members_update_own on public.thread_members
  for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

-- -----------------------------------------------------------------------------
-- messages
--
-- Readable by anyone who joined the thread, because Realtime ships these rows
-- as they are. That is safe precisely because a row carries member_id and not
-- an account id.
-- -----------------------------------------------------------------------------
grant select, insert, delete on public.messages to authenticated;

create policy messages_select_thread on public.messages
  for select to authenticated using (
    not hidden
    and exists (
      select 1 from public.thread_members me
      where me.story_id = messages.story_id and me.user_id = auth.uid()
    )
  );
create policy messages_insert_own on public.messages
  for insert to authenticated with check (
    member_id in (select id from public.thread_members where user_id = auth.uid())
  );
create policy messages_delete_own on public.messages
  for delete to authenticated using (
    member_id in (select id from public.thread_members where user_id = auth.uid())
  );

-- Keep the counter honest when someone deletes their own message.
create or replace function public.after_message_delete()
returns trigger language plpgsql security definer set search_path = public as $fn$
begin
  update public.stories
    set messages_count = greatest(messages_count - 1, 0)
    where id = old.story_id;
  return old;
end;
$fn$;

drop trigger if exists messages_after_delete on public.messages;
create trigger messages_after_delete
  after delete on public.messages
  for each row execute function public.after_message_delete();

-- -----------------------------------------------------------------------------
-- reports — write-only, and only through report_content(). No policy grants
-- SELECT: knowing who reported you is how retaliation starts.
-- -----------------------------------------------------------------------------
-- (no grants at all: the RPC is security definer)

-- -----------------------------------------------------------------------------
-- blocks
-- -----------------------------------------------------------------------------
grant select, insert, delete on public.blocks to authenticated;

create policy blocks_own on public.blocks
  for select to authenticated using (blocker_id = auth.uid());
create policy blocks_insert_own on public.blocks
  for insert to authenticated with check (blocker_id = auth.uid());
create policy blocks_delete_own on public.blocks
  for delete to authenticated using (blocker_id = auth.uid());

-- -----------------------------------------------------------------------------
-- groups — joining is join_group_by_code(); the invite code is never guessable
-- and never listed.
-- -----------------------------------------------------------------------------
grant select, insert on public.groups to authenticated;
grant update (name) on public.groups to authenticated;
grant delete on public.groups to authenticated;

create policy groups_select_member on public.groups
  for select to authenticated using (
    owner_id = auth.uid()
    or exists (
      select 1 from public.group_members gm
      where gm.group_id = groups.id and gm.user_id = auth.uid()
    )
  );
create policy groups_insert_own on public.groups
  for insert to authenticated with check (owner_id = auth.uid());
create policy groups_update_owner on public.groups
  for update to authenticated using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy groups_delete_owner on public.groups
  for delete to authenticated using (owner_id = auth.uid());

-- Own membership only. A member list with account ids in it is the one thing
-- that would break anonymity inside a group of friends; the member count comes
-- from group_summary() instead.
grant select, delete on public.group_members to authenticated;

create policy group_members_select_own on public.group_members
  for select to authenticated using (user_id = auth.uid());
create policy group_members_leave on public.group_members
  for delete to authenticated using (user_id = auth.uid());

create or replace function public.group_summary(p_group uuid)
returns table (id uuid, name text, member_count int, is_owner boolean, invite_code text)
language sql stable security definer set search_path = public as $fn$
  select g.id, g.name,
         (select count(*)::int from public.group_members m where m.group_id = g.id),
         g.owner_id = auth.uid(),
         g.invite_code
  from public.groups g
  where g.id = p_group
    and exists (
      select 1 from public.group_members gm
      where gm.group_id = g.id and gm.user_id = auth.uid()
    );
$fn$;

-- -----------------------------------------------------------------------------
-- post_credits — readable so the UI can say "te queda 1 publicación", never
-- writable: the AdMob server-side callback is the only thing that grants one.
-- -----------------------------------------------------------------------------
grant select on public.post_credits to authenticated;

create policy credits_select_own on public.post_credits
  for select to authenticated using (user_id = auth.uid());

-- -----------------------------------------------------------------------------
-- devices — FCM tokens.
-- -----------------------------------------------------------------------------
grant select, insert, update, delete on public.devices to authenticated;

create policy devices_own on public.devices
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

-- -----------------------------------------------------------------------------
-- banned_words — server side only. No grants.
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- Functions the client is allowed to call.
-- -----------------------------------------------------------------------------
-- Postgres grants EXECUTE to PUBLIC on every new function, so revoking from
-- anon/authenticated alone would change nothing. Close the door first, then
-- open it by name.
revoke execute on all functions in schema public from public, anon, authenticated;
grant execute on all functions in schema public to service_role;

grant execute on function
  public.feed(uuid, text, text[], text, text, uuid[], int),
  public.story_detail(uuid),
  public.my_threads(int),
  public.thread_messages(uuid, timestamptz, int),
  public.thread_aliases(uuid),
  public.join_thread(uuid),
  public.report_content(text, uuid, text),
  public.join_group_by_code(text),
  public.rotate_invite(uuid),
  public.group_summary(uuid)
to authenticated;

-- Everything not on that list — assign_thread_alias, contains_banned_word, cfg,
-- close_stale_threads and every trigger function — stays unreachable from a
-- device by virtue of the blanket revoke above.

-- -----------------------------------------------------------------------------
-- Housekeeping. Call from pg_cron (or an edge function) once a day.
-- A thread nobody has written in for a fortnight is over; leaving it open just
-- fills the history screen with conversations that never move again.
-- -----------------------------------------------------------------------------
create or replace function public.close_stale_threads()
returns int language sql security definer set search_path = public as $fn$
  with closed as (
    update public.stories s
      set closed_at = now()
      where s.closed_at is null
        and coalesce(
          (select max(m.created_at) from public.messages m where m.story_id = s.id),
          s.created_at
        ) < now() - interval '14 days'
      returning 1
  )
  select count(*)::int from closed;
$fn$;
revoke execute on function public.close_stale_threads() from public, anon, authenticated;
grant execute on function public.close_stale_threads() to service_role;

-- -----------------------------------------------------------------------------
-- Realtime. Only `messages` is published: the deck reads with plain queries, so
-- the 200 concurrent connections of the free plan are spent on people who
-- actually have a thread open rather than on everyone holding the app.
-- -----------------------------------------------------------------------------
alter publication supabase_realtime add table public.messages;
