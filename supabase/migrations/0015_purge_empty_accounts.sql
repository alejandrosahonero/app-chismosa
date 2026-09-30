-- 0015 — Nightly purge of empty accounts farmed from one IP.
--
-- A script that mints anonymous accounts leaves them all behind one IP and
-- never uses them. Every night, when MORE THAN 5 accounts whose last session
-- came from the same IP are completely empty, all of those empty ones are
-- deleted (auth.users; everything cascades).
--
-- "Empty" = no story, like, thread joined, group (member or owner), report,
-- block, purchase, rewarded ad or post credit. Only accounts older than 12
-- hours (nobody is wiped in the middle of their first session). House and
-- Premium accounts are never touched. A real person caught by this lost
-- nothing: an account with no interaction is the same as a new one, and the
-- app simply creates a fresh one on the next start.
--
-- The IP is the one Supabase Auth recorded for the account's latest session
-- (auth.sessions.ip). Accounts with no session left are ignored.

create or replace function public.purge_empty_accounts_by_ip(
  p_more_than integer  default 5,
  p_min_age   interval default interval '12 hours'
)
returns integer
language plpgsql security definer set search_path = public, auth as $fn$
declare
  v_deleted integer;
begin
  with last_ip as (
    select distinct on (s.user_id) s.user_id, s.ip
    from auth.sessions s
    where s.ip is not null
    order by s.user_id, s.created_at desc
  ),
  empty as (
    select p.id, l.ip
    from public.profiles p
    join last_ip l on l.user_id = p.id
    join auth.users u on u.id = p.id
    where not p.is_house
      and not p.is_premium
      and u.created_at < now() - p_min_age
      and not exists (select 1 from public.stories       x where x.author_id   = p.id)
      and not exists (select 1 from public.story_likes   x where x.user_id     = p.id)
      and not exists (select 1 from public.thread_members x where x.user_id    = p.id)
      and not exists (select 1 from public.group_members x where x.user_id     = p.id)
      and not exists (select 1 from public.groups        x where x.owner_id    = p.id)
      and not exists (select 1 from public.reports       x where x.reporter_id = p.id)
      and not exists (select 1 from public.blocks        x where x.blocker_id  = p.id)
      and not exists (select 1 from public.purchases     x where x.user_id     = p.id)
      and not exists (select 1 from public.ad_rewards    x where x.user_id     = p.id)
      and not exists (select 1 from public.post_credits  x where x.user_id     = p.id)
  ),
  farmed as (
    select e.id
    from empty e
    where e.ip in (select ip from empty group by ip having count(*) > p_more_than)
  ),
  gone as (
    delete from auth.users u using farmed f where u.id = f.id returning u.id
  )
  select count(*) into v_deleted from gone;

  return v_deleted;
end;
$fn$;

revoke execute on function public.purge_empty_accounts_by_ip(integer, interval)
  from public, anon, authenticated;

select cron.unschedule('purge-empty-accounts-by-ip')
where exists (select 1 from cron.job where jobname = 'purge-empty-accounts-by-ip');

select cron.schedule(
  'purge-empty-accounts-by-ip',
  '0 5 * * *',
  'select public.purge_empty_accounts_by_ip()'
);
