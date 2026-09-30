-- 0014 — Block IPs at the API door.
--
-- PostgREST runs public.check_request() before every REST/RPC request
-- (pgrst.db_pre_request). A request whose client IP (cf-connecting-ip, else
-- the first x-forwarded-for) falls in public.blocked_ips is rejected whole:
-- no reads, no writes. Entries may be single addresses or ranges (1.2.3.0/24).
--
-- Not covered: Supabase Auth (sign-up) and Realtime do not go through
-- PostgREST. Account creation is throttled by the Auth rate limits and the
-- Turnstile CAPTCHA instead.
--
--   insert into public.blocked_ips (ip, reason) values ('1.2.3.4', 'why');
--   delete from public.blocked_ips where ip = '1.2.3.4';
--
-- Beware of shared IPs (a home, a university, mobile carrier NAT): blocking
-- one blocks everybody behind it.

create table if not exists public.blocked_ips (
  ip         inet primary key,
  reason     text,
  created_at timestamptz not null default now()
);
alter table public.blocked_ips enable row level security;
revoke all on public.blocked_ips from anon, authenticated;

create or replace function public.check_request()
returns void
language plpgsql security definer set search_path = public as $fn$
declare
  v_headers json := nullif(current_setting('request.headers', true), '')::json;
  v_raw     text;
  v_ip      inet;
begin
  if v_headers is null then
    return;
  end if;
  v_raw := coalesce(
    v_headers ->> 'cf-connecting-ip',
    split_part(v_headers ->> 'x-forwarded-for', ',', 1),
    v_headers ->> 'x-real-ip'
  );
  begin
    v_ip := trim(v_raw)::inet;
  exception when others then
    return;
  end;
  -- `>>=`: an entry may be a single address or a range (e.g. 1.2.3.0/24).
  if v_ip is not null and exists (select 1 from public.blocked_ips where ip >>= v_ip) then
    raise exception 'blocked' using errcode = 'P0001', hint = 'ip_blocked';
  end if;
end;
$fn$;

grant execute on function public.check_request() to anon, authenticated;

alter role authenticator set pgrst.db_pre_request = 'public.check_request';
notify pgrst, 'reload config';
