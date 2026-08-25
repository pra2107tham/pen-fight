# Pen Fight

The desk game: flick your pen, knock the other one off the table. Built in
Flutter, with real 2D physics and 2–5 player online play over Supabase
Realtime.

## Playing

- **Pass & Play** — 2 to 5 pens on one device, with a hand-over screen
  between turns.
- **Vs Computer** — three difficulties. Ruthless searches ~700 candidate
  shots plus your best reply, and wins about 90% of the time.
- **Play Online** — the host opens a table and shares a four-letter code.

Every shot is taken in two stages: pick **where on your pen** to strike with
the slider, then **drag anywhere** on the table to aim and set power. Where
you hit changes the outcome — a centre strike drives the pen straight, a tip
strike spins it.

## Running it

```bash
flutter pub get
flutter run -d chrome
```

Pass & Play and Vs Computer work with no further setup.

### Online play

Online needs a Supabase project (the free tier is plenty).

1. Create a project at [supabase.com](https://supabase.com).
2. Run `supabase/schema.sql` then `supabase/002_multiplayer.sql` in the SQL
   editor.
3. Copy `supabase.example.json` to `supabase.json` and fill in your Project
   URL and **anon** key from Project Settings → API. (`supabase.json` is
   gitignored — never commit real keys.)

```bash
flutter run -d chrome --dart-define-from-file=supabase.json
```

The home screen shows an orange notice while online is unconfigured; it
disappears once the keys are picked up.

## Deploying to Vercel

The web build is static, so Vercel serves it directly.

1. Import the repo at [vercel.com/new](https://vercel.com/new). `vercel.json`
   supplies the build command and output directory.
2. Add two environment variables — **Settings → Environment Variables**:
   - `SUPABASE_URL`
   - `SUPABASE_ANON_KEY`
3. Deploy.

Without those variables the site still builds and plays offline; only online
tables are disabled. The build script fetches its own Flutter SDK, so the
first deploy takes a few minutes.

`vercel.json` also sets caching: hashed files under `/assets/` are immutable
and cached for a year, while `index.html`, the service worker, and
`version.json` are marked `no-cache` so players never get stuck on a stale
build. Deep links are rewritten to `index.html`, since routing happens
client-side.

The anon key is designed to be public — it is safe in a client bundle,
provided row-level security is on. The schema enables RLS on `rooms`; see the
comments in `supabase/schema.sql` for what the policies do and do not protect.

## Tests

```bash
flutter test
```

Covers the physics (determinism, collisions, friction), turn order across
2–5 players, netcode payloads, room lifecycle, and the AI difficulty curve —
the AI tests play hundreds of full matches to assert the win rates hold.

A screenshot harness lives in `tool/capture.dart`; it renders the battle
screen to a PNG and is not part of the suite.

## How it fits together

```
lib/
  game/sim.dart      deterministic physics — no Flutter imports
  game/ai.dart       computer opponent, searches the real sim
  net/room.dart      Supabase channel: presence, flicks, reconnect
  net/session.dart   remembers the active match so you can rejoin
  screens/           home, lobbies, battle, win
```

The sim is deterministic by construction, which is what the netcode rests on:
the player taking a shot broadcasts their input *and* their settled result,
and the peer replays the input for identical animation before snapping to the
authoritative state.
