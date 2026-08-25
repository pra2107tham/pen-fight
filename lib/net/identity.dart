import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// A stable id for this device, persisted across reloads.
///
/// Without it a refresh would look like a brand-new third player and be
/// turned away from your own seat. With it, rejoining is recognised as the
/// same person coming back.
///
/// Persistence is a nicety, never a gate: if storage is unavailable — private
/// browsing, a platform channel that has not registered yet — we fall back to
/// a session-scoped id. Losing resume-on-refresh is a far smaller failure than
/// being unable to start a game at all.
class PlayerIdentity {
  static const _key = 'penfight_player_id';
  static String? _cached;

  static Future<String> mine() async {
    final cached = _cached;
    if (cached != null) return cached;

    // Generate up front so every failure path still returns a usable id.
    final fallback = const Uuid().v4();

    try {
      final prefs = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 3));
      var id = prefs.getString(_key);
      if (id == null || id.isEmpty) {
        id = fallback;
        await prefs.setString(_key, id);
      }
      return _cached = id;
    } catch (e) {
      // Catches MissingPluginException, storage denials, and the timeout.
      debugPrint('Pen Fight: identity storage unavailable ($e); '
          'using a session-only id.');
      return _cached = fallback;
    }
  }
}
