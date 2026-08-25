-- Pen Fight — room persistence.
-- Paste this whole file into the Supabase SQL editor and run it once.
--
-- Rooms are ephemeral: they exist so a code can be validated before joining
-- and so a refresh can rejoin the same seat. They expire after 2 hours.

create table if not exists public.rooms (
  code        text primary key,
  host_id     text not null,
  guest_id    text,
  -- 'waiting' until both seats are filled, then 'playing', then 'done'.
  status      text not null default 'waiting',
  -- Latest settled pen snapshot + whose turn it is, so a reconnecting
  -- player can resume mid-match instead of restarting.
  state       jsonb,
  turn        int not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  expires_at  timestamptz not null default now() + interval '2 hours'
);

-- Join validation reads by code (the primary key). Expiry sweeps read by
-- expires_at, so index that.
create index if not exists rooms_expires_at_idx on public.rooms (expires_at);

alter table public.rooms enable row level security;

-- This is a casual party game with no accounts: anon holds the whole API
-- surface. Guessing a live 4-letter code is the only way to reach a room,
-- and a room carries no personal data — just pen positions and ink.
-- Tighten this (per-user auth, host-only updates) if rooms ever hold
-- anything worth protecting.
drop policy if exists "anon reads rooms" on public.rooms;
create policy "anon reads rooms"
  on public.rooms for select
  to anon
  using (expires_at > now());

drop policy if exists "anon creates rooms" on public.rooms;
create policy "anon creates rooms"
  on public.rooms for insert
  to anon
  with check (expires_at > now());

drop policy if exists "anon updates live rooms" on public.rooms;
create policy "anon updates live rooms"
  on public.rooms for update
  to anon
  using (expires_at > now());

-- Housekeeping: drop expired rooms whenever a new one is created, so the
-- table cannot grow without bound. Cheap because of the index above, and it
-- avoids needing pg_cron.
create or replace function public.sweep_expired_rooms()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.rooms where expires_at < now();
  return new;
end;
$$;

drop trigger if exists sweep_expired_rooms_trigger on public.rooms;
create trigger sweep_expired_rooms_trigger
  after insert on public.rooms
  for each statement
  execute function public.sweep_expired_rooms();
