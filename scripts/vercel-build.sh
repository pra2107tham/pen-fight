#!/usr/bin/env bash
#
# Vercel build for Pen Fight.
#
# Vercel's image has no Flutter SDK, so fetch a pinned version and build the
# web bundle with it. Supabase credentials come from Vercel environment
# variables — they are never committed.
set -euo pipefail

FLUTTER_VERSION="${FLUTTER_VERSION:-3.38.4}"
FLUTTER_DIR="${PWD}/.flutter-sdk"

if [ ! -x "${FLUTTER_DIR}/bin/flutter" ]; then
  echo "==> Fetching Flutter ${FLUTTER_VERSION}"
  git clone --depth 1 --branch "${FLUTTER_VERSION}" \
    https://github.com/flutter/flutter.git "${FLUTTER_DIR}"
fi

export PATH="${FLUTTER_DIR}/bin:${PATH}"
# The clone is disposable build scratch, not a repo anyone will push from.
git config --global --add safe.directory "${FLUTTER_DIR}" || true

flutter --version
flutter pub get

# Online play needs Supabase. Without the vars the app still builds and runs —
# it just falls back to Pass & Play and vs Computer, and says so on screen.
DEFINES=()
if [ -n "${SUPABASE_URL:-}" ] && [ -n "${SUPABASE_ANON_KEY:-}" ]; then
  echo "==> Building with Supabase online play enabled"
  DEFINES+=("--dart-define=SUPABASE_URL=${SUPABASE_URL}")
  DEFINES+=("--dart-define=SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY}")
else
  echo "==> SUPABASE_URL / SUPABASE_ANON_KEY not set — online play disabled"
fi

# --wasm compiles the app to WebAssembly and renders with skwasm. It is both
# smaller over the wire and markedly faster at running the physics than the
# JavaScript build. A dart2js + CanvasKit build is emitted alongside it and
# flutter.js picks that one automatically on browsers without WasmGC, so
# nothing is dropped — see build/web/flutter_bootstrap.js.
#
# --no-web-resources-cdn serves CanvasKit and skwasm from this deployment
# instead of gstatic.com. Same origin means no extra DNS lookup and TLS
# handshake before the renderer can even start downloading, and the site keeps
# working on networks that block Google's CDN. The service worker versions
# those files by content hash, so a Flutter upgrade still invalidates them.
flutter build web --release --wasm --no-web-resources-cdn \
  "${DEFINES[@]+"${DEFINES[@]}"}"

echo "==> Built build/web"
