-- =============================================================================
-- 0009 — one phone at a time, several with premium
--
-- An account (the recovery code) can be used on one install at a time. Moving
-- it to another phone is always free — a lost or broken phone must never hold
-- somebody's account hostage — but the phone it leaves stops being able to use
-- it. Using it on several phones AT ONCE is a premium benefit.
--
-- An "install" is a random id the app keeps in its preferences: a reinstall
-- restored by Auto Backup keeps it, a new phone does not.
--
-- Enforced by the app through claim_install(): a modified client could skip
-- the check and share an account for free. That is acceptable — the worst case
-- is one free premium perk — and it is what keeps this possible without paid
-- infrastructure.
--
-- Run after 0008. Safe to re-run.
-- =============================================================================

alter table public.profiles
  add column if not exists active_install uuid;

-- 'ok'    → this install may use the account (and is now its active one, unless
--           the account is premium, where any number may).
-- 'moved' → another install holds it. Call again with p_take = true to bring
--           the account here; the other install then gets 'moved'.
create or replace function public.claim_install(p_install uuid, p_take boolean default false)
returns text
language plpgsql security definer set search_path = public as $fn$
declare
  v_active  uuid;
  v_premium boolean;
begin
  if auth.uid() is null or p_install is null then
    raise exception 'not_authenticated' using errcode = 'P0001';
  end if;

  select active_install, is_premium into v_active, v_premium
  from public.profiles where id = auth.uid()
  for update;

  if coalesce(v_premium, false) then
    update public.profiles set active_install = p_install where id = auth.uid();
    return 'ok';
  end if;

  if v_active is null or v_active = p_install or coalesce(p_take, false) then
    update public.profiles set active_install = p_install where id = auth.uid();
    return 'ok';
  end if;

  return 'moved';
end;
$fn$;

revoke execute on function public.claim_install(uuid, boolean) from public, anon, authenticated;
grant execute on function public.claim_install(uuid, boolean) to authenticated;
