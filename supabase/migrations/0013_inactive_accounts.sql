-- 0013 — Inactive accounts: disable after 30 days, delete 90 days later.
--
-- Why: sign-up is anonymous and free, so abandoned and scripted accounts pile
-- up forever. This keeps the database (500 MB on the free plan) and the deck
-- clean without anyone reviewing it.
--
--   * 30 days without opening the app (profiles.last_seen_at, written by
--     touch_session on every app open; created_at when never set) → the
--     account is DISABLED: profiles.disabled_at is set and feed() stops dealing
--     its stories. Nothing is deleted.
--   * Coming back reactivates it: touch_session clears disabled_at. A real
--     person who just took a break loses nothing.
--   * 90 more days disabled (120 days away in total) → the account is DELETED
--     (auth.users, and everything cascades, exactly like delete_my_account).
--   * Never touched: house accounts, and Premium accounts are never deleted (a
--     paid purchase is not garbage); they can still be disabled while away.
--
-- Runs every night from pg_cron (04:30 UTC, after close-stale-threads).

alter table public.profiles
  add column if not exists disabled_at timestamptz;

create index if not exists profiles_disabled_idx
  on public.profiles (disabled_at) where disabled_at is not null;

-- Coming back reactivates.
create or replace function public.touch_session()
returns void
language sql security definer set search_path = public as $fn$
  update public.profiles
     set last_seen_at = now(), disabled_at = null
   where id = auth.uid();
$fn$;

create or replace function public.expire_inactive_accounts(
  p_disable_after interval default interval '30 days',
  p_delete_after  interval default interval '90 days'
)
returns table (disabled integer, deleted integer)
language plpgsql security definer set search_path = public as $fn$
declare
  v_disabled integer;
  v_deleted  integer;
begin
  update public.profiles
     set disabled_at = now()
   where disabled_at is null
     and not is_house
     and coalesce(last_seen_at, created_at) < now() - p_disable_after;
  get diagnostics v_disabled = row_count;

  delete from auth.users u
   using public.profiles p
   where p.id = u.id
     and p.disabled_at < now() - p_delete_after
     and not p.is_house
     and not p.is_premium;
  get diagnostics v_deleted = row_count;

  return query select v_disabled, v_deleted;
end;
$fn$;

revoke execute on function public.expire_inactive_accounts(interval, interval)
  from public, anon, authenticated;

-- feed(): disabled authors are dealt like banned ones (not at all). Patched in
-- place so the rest of the function, owned by earlier migrations, is untouched.
do $do$
declare
  v_def text;
begin
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p
  where p.pronamespace = 'public'::regnamespace and p.proname = 'feed';

  if v_def is null or position('not a.is_banned' in v_def) = 0 then
    raise exception 'feed() has no "not a.is_banned" filter to extend';
  end if;
  if position('a.disabled_at is null' in v_def) = 0 then
    execute replace(v_def, 'not a.is_banned',
                    'not a.is_banned and a.disabled_at is null');
  end if;
end;
$do$;

select cron.unschedule('expire-inactive-accounts')
where exists (select 1 from cron.job where jobname = 'expire-inactive-accounts');

select cron.schedule(
  'expire-inactive-accounts',
  '30 4 * * *',
  'select public.expire_inactive_accounts()'
);
