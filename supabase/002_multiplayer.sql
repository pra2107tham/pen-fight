-- Pen Fight — 2 to 5 players per table.
-- Paste into the Supabase SQL editor and run once, after schema.sql.

-- How many seats the host opened the table with.
alter table public.rooms
  add column if not exists capacity int not null default 2;

-- Everyone who has joined, in seat order. The host holds seat 0 and is
-- tracked by host_id, so this list covers seats 1..capacity-1.
alter table public.rooms
  add column if not exists guests jsonb not null default '[]'::jsonb;

-- Keep capacity within what the game can actually deal.
alter table public.rooms
  drop constraint if exists rooms_capacity_range;
alter table public.rooms
  add constraint rooms_capacity_range check (capacity between 2 and 5);
