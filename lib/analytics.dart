import 'package:flutter/foundation.dart';

import 'analytics_stub.dart' if (dart.library.js_interop) 'analytics_web.dart'
    as impl;

/// Product analytics, wired to Vercel Web Analytics on the web build.
///
/// Flutter renders to a canvas and never changes the URL, so Vercel would
/// otherwise only ever see one page view per visitor. These events report
/// what people actually reach — which modes get played, whether online games
/// find a second player, how matches end.
///
/// Everything here is best-effort and silent: analytics must never be able to
/// break the game. Off the web it compiles to no-ops, so the APK and the test
/// suite carry none of it.
class Analytics {
  const Analytics._();

  /// A screen the player opened.
  static void screen(String name) => _send('screen', {'screen': name});

  /// A match started. [mode] is local / online / computer.
  static void matchStarted(String mode, {required int players}) =>
      _send('match_started', {'mode': mode, 'players': players});

  /// A match finished. [outcome] is win / loss / forfeit.
  static void matchEnded(
    String mode, {
    required String outcome,
    required int turns,
  }) =>
      _send('match_ended', {
        'mode': mode,
        'outcome': outcome,
        'turns': turns,
      });

  /// Someone tried to join an online table. [result] is ok, or why it failed.
  static void joinAttempt(String result) =>
      _send('join_attempt', {'result': result});

  static void _send(String name, Map<String, Object?> props) {
    // Debug runs would otherwise pollute real numbers.
    if (kDebugMode) return;
    impl.track(name, props);
  }
}
