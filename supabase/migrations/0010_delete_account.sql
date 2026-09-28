-- =============================================================================
-- 0010 — "Borrar mi cuenta"
--
-- Google Play requires apps that create accounts to let people delete them
-- from inside the app. Deleting the auth.users row is enough: profiles cascades
-- from it, and every table with a user id cascades from profiles (stories and
-- therefore their threads and messages, likes, thread memberships, groups the
-- person owns, group memberships, reports filed, blocks either way, devices,
-- credits, purchases).
--
-- The house account cannot delete itself: its stories are the launch deck.
--
-- Run after 0009. Safe to re-run.
-- =============================================================================

create or replace function public.delete_my_account()
returns void
language plpgsql security definer set search_path = public as $fn$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.profiles where id = v_uid and is_house) then
    raise exception 'house_account' using errcode = 'P0001';
  end if;

  delete from auth.users where id = v_uid;
end;
$fn$;

revoke execute on function public.delete_my_account() from public, anon, authenticated;
grant execute on function public.delete_my_account() to authenticated;
