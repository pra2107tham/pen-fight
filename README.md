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

`vercel.json` also sets caching: files under `/assets/` are cached for a year,
while `index.html`, `flutter_bootstrap.js`, the service worker and
`version.json` are marked `no-cache` so players never get stuck on a stale
build. Deep links are rewritten to `index.html`, since routing happens
client-side.

The build script passes two flags worth knowing about:

- `--wasm` compiles the app to WebAssembly and renders with skwasm. It is
  both smaller over the wire (~2.35 MB gzipped against ~2.87 MB) and markedly
  faster at running the physics. A dart2js + CanvasKit build is emitted
  alongside it and `flutter.js` picks that automatically on browsers without
  WasmGC, so nothing is lost.
- `--no-web-resources-cdn` serves CanvasKit and skwasm from the deployment
  rather than `gstatic.com`: no second DNS lookup and TLS handshake before
  the renderer can start downloading, and the game still works on networks
  that block Google's CDN.

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

## Performance

The game loop is built around not doing work. Worth knowing before changing it:

- `sim.dart`'s `step()` runs on raw doubles rather than `Vec2` values, because
  the AI calls it millions of times per turn and the allocations dominated
  everything else. Keep the arithmetic in the order it is written — the
  netcode's determinism rests on both clients computing identical results.
- Ruthless looks a ply ahead only down a shortlist of the best candidate
  shots, not all 700. The lookahead only ever subtracts, so a shot that lost
  on its own merits cannot be rescued by it.
- Playing a flick back must not call `setState`. The pens repaint from a
  notifier, and the rest of the screen rebuilds only when the meters, a
  knockout or the danger band actually change.
- The paper background and the table's grid each live behind a
  `RepaintBoundary`. Without one they share a layer with the game and get
  re-recorded on every frame of play.

`tool/bench.dart` measures the sim and the AI. Run it through dart2js rather
than on the VM — the game ships as JavaScript, and allocation costs far more
there:

```bash
dart compile js -O2 -o /tmp/bench.js tool/bench.dart && node /tmp/bench.js
```

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
