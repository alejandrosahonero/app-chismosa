-- =============================================================================
-- 0006 — push notifications for new thread messages
--
-- Flow: a message is inserted → a trigger posts its id to the Edge Function
-- `thread-push` through pg_net → the function works out who should hear about
-- it and sends through FCM.
--
-- The trigger only forwards an id. Deciding the recipients happens in the
-- function, with the service role, because it needs to read other people's
-- memberships and devices — exactly what no client may ever read.
--
-- One notification per thread until it is read: a member who has been told
-- about a thread is not told again until they open it (last_notified_at vs
-- last_read_at). A lively thread would otherwise buzz a phone forty times in an
-- evening, and the first thing people do with an app like that is mute it.
--
-- Prerequisites (once, in the SQL Editor — see supabase/README.md):
--   select vault.create_secret('https://<ref>.supabase.co/functions/v1/thread-push', 'push_function_url');
--   select vault.create_secret('<a long random string>', 'push_secret');
-- and the same random string as the function's PUSH_SECRET. Without the two
-- secrets the trigger does nothing, so messages keep working either way.
--
-- Run after 0005. Safe to re-run.
-- =============================================================================

create extension if not exists pg_net with schema extensions;

alter table public.thread_members
  add column if not exists last_notified_at timestamptz;

-- -----------------------------------------------------------------------------
-- devices — through register_device() only. A token belongs to a phone, not to
-- an account: after a recovery-code restore the same token must move to the
-- restored account, and a row policy cannot hand a row from one user to
-- another.
-- -----------------------------------------------------------------------------
revoke all on public.devices from anon, authenticated;
drop policy if exists devices_own on public.devices;

create or replace function public.register_device(p_token text)
returns void
language plpgsql security definer set search_path = public as $fn$
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = 'P0001';
  end if;
  if char_length(coalesce(p_token, '')) not between 20 and 4096 then
    raise exception 'invalid_token' using errcode = 'P0001';
  end if;

  insert into public.devices (fcm_token, user_id, updated_at)
  values (p_token, auth.uid(), now())
  on conflict (fcm_token) do update
    set user_id = excluded.user_id, updated_at = now();
end;
$fn$;

-- -----------------------------------------------------------------------------
-- The trigger. Fire and forget: pg_net queues the request and returns at once,
-- so a slow or dead function never slows down sending a message.
-- -----------------------------------------------------------------------------
create or replace function public.after_message_push()
returns trigger language plpgsql security definer set search_path = public as $fn$
declare
  v_url    text;
  v_secret text;
begin
  select decrypted_secret into v_url
    from vault.decrypted_secrets where name = 'push_function_url';
  select decrypted_secret into v_secret
    from vault.decrypted_secrets where name = 'push_secret';
  if v_url is null or v_secret is null then
    return new;
  end if;

  perform net.http_post(
    url     := v_url,
    body    := jsonb_build_object('message_id', new.id),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-push-secret', v_secret
    )
  );
  return new;
exception when others then
  -- Never let a notification problem refuse a message.
  return new;
end;
$fn$;

drop trigger if exists messages_after_insert_push on public.messages;
create trigger messages_after_insert_push
  after insert on public.messages
  for each row execute function public.after_message_push();

-- -----------------------------------------------------------------------------
-- Grants.
-- -----------------------------------------------------------------------------
revoke execute on function
  public.register_device(text),
  public.after_message_push()
from public, anon, authenticated;

grant execute on function public.register_device(text) to authenticated;
