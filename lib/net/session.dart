import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The match this device is currently in, remembered across reloads so the
/// app can offer "rejoin" instead of stranding the player.
///
/// Like [PlayerIdentity], storage is best-effort: if it is unavailable the
/// game still plays, you just lose the rejoin prompt.
class ActiveSession {
  final String code;
  final bool isHost;
  final DateTime joinedAt;

  const ActiveSession({
    required this.code,
    required this.isHost,
    required this.joinedAt,
  });

  /// Sessions older than this are stale — the room itself has expired.
  static const maxAge = Duration(hours: 2);

  bool get isStale => DateTime.now().difference(joinedAt) > maxAge;

  Map<String, dynamic> toJson() => {
        'code': code,
        'isHost': isHost,
        'joinedAt': joinedAt.toIso8601String(),
      };

  static ActiveSession? _fromJson(Map<String, dynamic> j) {
    final code = j['code'] as String?;
    final at = DateTime.tryParse(j['joinedAt'] as String? ?? '');
    if (code == null || code.length != 4 || at == null) return null;
    return ActiveSession(
      code: code,
      isHost: j['isHost'] as bool? ?? false,
      joinedAt: at,
    );
  }

  static const _key = 'penfight_active_session';

  static Future<void> save(String code, {required bool isHost}) async {
    final s = ActiveSession(
      code: code,
      isHost: isHost,
      joinedAt: DateTime.now(),
    );
    try {
      final prefs = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 3));
      await prefs.setString(_key, jsonEncode(s.toJson()));
    } catch (e) {
      debugPrint('Pen Fight: could not save session ($e)');
    }
  }

  /// The session to offer rejoining, or null if there is none worth resuming.
  static Future<ActiveSession?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 3));
      final raw = prefs.getString(_key);
      if (raw == null) return null;

      final s = _fromJson(jsonDecode(raw) as Map<String, dynamic>);
      if (s == null || s.isStale) {
        await clear();
        return null;
      }
      return s;
    } catch (e) {
      debugPrint('Pen Fight: could not read session ($e)');
      return null;
    }
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 3));
      await prefs.remove(_key);
    } catch (_) {
      // Nothing to do — a stale entry is filtered out by isStale on read.
    }
  }
}
