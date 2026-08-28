-- =============================================================================
-- Chismosa — initial schema
--
-- Paste this whole file into the Supabase SQL editor (or run it with the CLI).
--
-- Design notes that are NOT obvious from the DDL:
--
-- * Moderation is entirely automatic. There is no console, no queue and no
--   human in the loop: reports increment a counter, a trigger hides the content
--   at the threshold, and an author whose content keeps getting hidden is
--   banned by another trigger. That is the minimum Play requires for user
--   generated content and the maximum this project wants to operate.
--
-- * "Seen" cards are NOT stored here. One row per (user, story) grows as
--   users x catalogue and would eat the 500 MB free tier on its own; the deck
--   keeps the list on the device exactly like the inherited one did, and the
--   feed only receives the most recent ids as an exclusion hint.
--
-- * Aliases are stored per thread, not derived on the fly, because they have to
--   be UNIQUE inside a thread: two "Loro Discreto" in the same conversation
--   makes it unreadable. Across threads the same person gets unrelated aliases,
--   which is the whole point.
-- =============================================================================

create extension if not exists pgcrypto;

-- -----------------------------------------------------------------------------
-- Tunables. A function rather than a table so policies can inline them and
-- there is nothing to keep in sync.
-- -----------------------------------------------------------------------------
create or replace function public.cfg(key text)
returns int language sql immutable as $fn$
  select case key
    when 'reports_to_hide'     then 3   -- reports that hide a story or message
    when 'hidden_to_ban'       then 3   -- hidden stories that ban the author
    when 'stories_per_day'     then 1   -- free daily allowance (see post_credits)
    when 'messages_per_minute' then 20  -- flood guard inside a thread
    else null
  end;
$fn$;

-- -----------------------------------------------------------------------------
-- profiles — one row per anonymous account, created by the trigger on
-- auth.users. The client never inserts here.
-- -----------------------------------------------------------------------------
create table if not exists public.profiles (
  id                 uuid primary key references auth.users(id) on delete cascade,
  -- Two letter code inferred from the device locale. No GPS, no permission, and
  -- deliberately no city: a city plus an anonymous story is a doxxing kit.
  country_code       text check (country_code ~ '^[A-Z]{2}$'),
  -- Languages the user wants in the deck. Seeded from the country, editable.
  languages          text[] not null default '{}',
  -- Trusted from the client for now. Validating the Play purchase token needs
  -- the Play Developer API from an edge function; until that lands a determined
  -- user can grant themselves unlimited posting. Acceptable: the worst case is
  -- more stories, and every one of them still goes through moderation.
  is_premium           boolean not null default false,
  is_banned            boolean not null default false,
  -- Stories and messages of this author that crossed the report threshold.
  hidden_content_count int not null default 0,
  created_at           timestamptz not null default now()
);

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $fn$
begin
  insert into public.profiles (id) values (new.id) on conflict do nothing;
  return new;
end;
$fn$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- -----------------------------------------------------------------------------
-- groups — a private deck. A story with group_id set never reaches the global
-- feed, and vice versa.
-- -----------------------------------------------------------------------------
create table if not exists public.groups (
  id                uuid primary key default gen_random_uuid(),
  name              text not null check (char_length(name) between 2 and 40),
  owner_id          uuid not null references public.profiles(id) on delete cascade,
  -- Short, shareable and revocable: rotating this column kills every link that
  -- ever escaped. No member cap, by product decision.
  invite_code       text not null unique default encode(gen_random_bytes(6), 'hex'),
  invite_expires_at timestamptz not null default now() + interval '7 days',
  created_at        timestamptz not null default now()
);

create table if not exists public.group_members (
  group_id  uuid not null references public.groups(id) on delete cascade,
  user_id   uuid not null references public.profiles(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);
create index if not exists group_members_user_idx on public.group_members (user_id);

-- -----------------------------------------------------------------------------
-- stories — one card in the deck.
-- -----------------------------------------------------------------------------
create table if not exists public.stories (
  id             uuid primary key default gen_random_uuid(),
  author_id      uuid not null references public.profiles(id) on delete cascade,
  group_id       uuid references public.groups(id) on delete cascade,
  body           text not null check (char_length(body) between 20 and 600),
  -- Generic on purpose, plus a catch-all. A taxonomy nobody fits into just
  -- pushes everything into "other".
  category       text not null default 'cualquiera'
                 check (category in ('cualquiera','amor','familia','trabajo',
                                     'amistad','escuela','vecinos','dinero')),
  country_code   text check (country_code ~ '^[A-Z]{2}$'),
  lang           text not null check (char_length(lang) = 2),
  created_at     timestamptz not null default now(),
  likes_count    int not null default 0,
  messages_count int not null default 0,
  reports_count  int not null default 0,
  hidden         boolean not null default false,
  -- Threads that go quiet stop accepting messages. A feed full of dead chats
  -- reads as an abandoned app.
  closed_at      timestamptz
);
create index if not exists stories_feed_idx   on public.stories (created_at desc) where not hidden;
create index if not exists stories_group_idx  on public.stories (group_id, created_at desc) where not hidden;
create index if not exists stories_author_idx on public.stories (author_id, created_at desc);

create table if not exists public.story_likes (
  story_id   uuid not null references public.stories(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (story_id, user_id)
);

-- -----------------------------------------------------------------------------
-- threads — there is no thread table: every story IS its thread. Membership is
-- what the user's history is built from.
-- -----------------------------------------------------------------------------
-- The surrogate `id` is the point of this table, not bookkeeping. Messages
-- reference the MEMBERSHIP, never the account: that way a message row can be
-- handed to every participant of a thread — and to Realtime, which ships rows
-- verbatim — without the global user id ever leaving the server. Two messages
-- by the same person in two different threads are unlinkable by design.
create table if not exists public.thread_members (
  id           uuid primary key default gen_random_uuid(),
  story_id     uuid not null references public.stories(id) on delete cascade,
  user_id      uuid not null references public.profiles(id) on delete cascade,
  alias        text not null,
  joined_at    timestamptz not null default now(),
  last_read_at timestamptz not null default now(),
  muted        boolean not null default false,
  unique (story_id, user_id),
  unique (story_id, alias)
);
create index if not exists thread_members_user_idx on public.thread_members (user_id, joined_at desc);

create table if not exists public.messages (
  id            uuid primary key default gen_random_uuid(),
  story_id      uuid not null references public.stories(id) on delete cascade,
  member_id     uuid not null references public.thread_members(id) on delete cascade,
  body          text not null check (char_length(body) between 1 and 500),
  created_at    timestamptz not null default now(),
  reports_count int not null default 0,
  hidden        boolean not null default false
);
create index if not exists messages_story_idx  on public.messages (story_id, created_at);
create index if not exists messages_member_idx on public.messages (member_id);

-- -----------------------------------------------------------------------------
-- Moderation and abuse control.
-- -----------------------------------------------------------------------------
create table if not exists public.reports (
  id          uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  target_type text not null check (target_type in ('story','message')),
  target_id   uuid not null,
  reason      text check (char_length(reason) <= 200),
  created_at  timestamptz not null default now(),
  -- One report per person per thing: otherwise one angry user hides anything.
  unique (reporter_id, target_type, target_id)
);

create table if not exists public.blocks (
  blocker_id uuid not null references public.profiles(id) on delete cascade,
  blocked_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);

create table if not exists public.banned_words (
  word text primary key
);

-- Extra publishing slots, granted ONLY by the AdMob server-side verification
-- callback hitting an edge function. Never writable from the client: a credit
-- the client can mint is a limit that does not exist.
create table if not exists public.post_credits (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  credits int not null default 0 check (credits >= 0)
);

create table if not exists public.devices (
  fcm_token  text primary key,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  platform   text not null default 'android',
  updated_at timestamptz not null default now()
);
create index if not exists devices_user_idx on public.devices (user_id);
